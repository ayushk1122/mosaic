import Foundation
import Observation

/// Visit layouts are authorized afresh. An opened board's media is fetched first; afterwards the
/// photos of boards not opened yet download quietly, so opening them later is instant.
@MainActor
@Observable
final class MosaicVisitMedia {
    /// Blurred stand-ins by file name, shown while files download.
    let previews: [String: ComposerMediaPreview]
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    /// Enough for a few boards' photos without using much data on a profile that's only glanced at.
    static let prefetchLimit = 40

    private(set) var loading: Set<UUID> = []
    private(set) var failed: Set<UUID> = []
    /// Boards whose media has been fetched at least once.
    private(set) var attempted: Set<UUID> = []
    /// Files currently downloading.
    private(set) var pendingFiles: Set<String> = []
    private let documents: [ComposerSyncDocument]
    private let mosaicID: UUID
    private let ownerID: UUID
    private let location: ComposerStorageLocation
    private let client: MosaicVisitClient

    init(documents: [ComposerSyncDocument], mosaicID: UUID, ownerID: UUID,
         location: ComposerStorageLocation, client: MosaicVisitClient) throws {
        self.documents = documents
        self.mosaicID = mosaicID
        self.ownerID = ownerID
        self.location = location
        self.client = client
        var previews: [String: ComposerMediaPreview] = [:]
        for document in documents {
            for (name, encoded) in document.body.mediaPreviews ?? [:] {
                if let preview = ComposerMediaPreview(encoded: encoded) { previews[name] = preview }
            }
        }
        self.previews = previews
        try Self.prepareCache(documents: documents, location: location)
    }

    static func location(viewerID: UUID, ownerID: UUID) -> ComposerStorageLocation {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        removeOldCaches(in: caches)
        return ComposerStorageLocation(root: caches.appendingPathComponent("Visits-v3", isDirectory: true)
            .appendingPathComponent(viewerID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(ownerID.uuidString.lowercased(), isDirectory: true))
    }

    /// v2 may hold a sticker's JPEG display copy, which shows on a solid box.
    private static var removedOldCaches = false
    private static func removeOldCaches(in caches: URL) {
        guard !removedOldCaches else { return }
        removedOldCaches = true
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("Visits-v2", isDirectory: true))
    }

    /// Files placed as stickers on a board, including inside groups.
    static func stickerFiles(in blocks: [ComposerBlock]) -> Set<String> {
        blocks.reduce(into: Set<String>()) { files, block in
            if block.kind == .sticker, let name = block.mediaFileName, !name.isEmpty { files.insert(name) }
            files.formUnion(stickerFiles(in: block.groupMembers))
        }
    }

    func boardID(_ documentID: ComposerDocumentID?) -> UUID {
        documentID.flatMap(ComposerBoardSync.uuid) ?? mosaicID
    }

    /// A manifest prevents a reused filename from displaying a different/removed cloud asset.
    static func prepareCache(documents: [ComposerSyncDocument], location: ComposerStorageLocation) throws {
        var assets: [String: String] = [:]
        for document in documents {
            for (name, rawAsset) in document.body.mediaAssets ?? [:] {
                guard ComposerAccountRestore.isSafeFileName(name), let asset = UUID(uuidString: rawAsset) else {
                    throw ComposerRestoreError.invalidMedia
                }
                let value = asset.uuidString.lowercased()
                guard assets[name] == nil || assets[name] == value else {
                    throw ComposerRestoreError.invalidMedia
                }
                assets[name] = value
            }
        }
        let fm = FileManager.default
        let manifest = location.root.appendingPathComponent("media-manifest.json")
        let previous = (try? Data(contentsOf: manifest)).flatMap {
            try? JSONDecoder().decode([String: String].self, from: $0)
        } ?? [:]
        try fm.createDirectory(at: location.mediaDirectory, withIntermediateDirectories: true)
        for file in try fm.contentsOfDirectory(at: location.mediaDirectory, includingPropertiesForKeys: nil) {
            let name = file.lastPathComponent
            if assets[name] == nil || assets[name] != previous[name] {
                try fm.removeItem(at: file)
            }
        }
        try JSONEncoder().encode(assets).write(to: manifest, options: .atomic)
    }

    /// Stops the quiet fetching, when a board opens or the visit is left. Files already saved stay.
    func pausePrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    func prefetchFinished() async {
        await prefetchTask?.value
    }

    private func startPrefetch(store: ComposerStore, token: String) {
        pausePrefetch()
        let queue = prefetchQueue()
        guard !queue.isEmpty else { return }
        let client = client, ownerID = ownerID, folder = location.mediaDirectory
        prefetchTask = Task(priority: .utility) { [weak store] in
            await withTaskGroup(of: (String, Data?).self) { group in
                var pending = queue.makeIterator()
                func next() {
                    guard !Task.isCancelled, let file = pending.next() else { return }
                    group.addTask {
                        let paths = MosaicVisitClient.objectPaths(ownerID: ownerID, assetID: file.asset,
                                                                  fileName: file.name, isSticker: file.isSticker)
                        for path in paths {
                            guard !Task.isCancelled else { return (file.name, nil) }
                            if let data = await client.download(path: path, accessToken: token, inLowDataMode: false),
                               !data.isEmpty {
                                return (file.name, data)
                            }
                        }
                        return (file.name, nil)
                    }
                }
                // Two at a time, so a board opened meanwhile isn't slowed down.
                for _ in 0..<2 { next() }
                while let (name, data) = await group.next() {
                    guard !Task.isCancelled else { group.cancelAll(); continue }
                    let target = folder.appendingPathComponent(name)
                    // A miss is fine: the board fetches it when it opens.
                    if let data, !FileManager.default.fileExists(atPath: target.path),
                       (try? data.write(to: target, options: .atomic)) != nil {
                        store?.mediaDidDownload(name)
                    }
                    next()
                }
            }
        }
    }

    /// Photos of boards not opened yet, Pursuits before their pages and nodes. Videos and GIFs
    /// are large and only fetched once their board opens.
    private func prefetchQueue() -> [(name: String, asset: String, isSticker: Bool)] {
        let rank: [ComposerSyncRole: Int] = [.mosaic: 0, .pursuit: 1, .node: 2, .page: 3]
        let order = documents.enumerated()
            .filter { !attempted.contains($0.element.id) && !loading.contains($0.element.id) }
            .sorted { (rank[$0.element.role] ?? 9, $0.offset) < (rank[$1.element.role] ?? 9, $1.offset) }
            .map(\.element)
        var queue: [(name: String, asset: String, isSticker: Bool)] = []
        var seen = Set<String>()
        for document in order {
            let stickers = Self.stickerFiles(in: document.body.blocks)
            for (name, asset) in (document.body.mediaAssets ?? [:]).sorted(by: { $0.key < $1.key })
            where seen.insert(name).inserted && Self.prefetches(name) {
                guard !FileManager.default.fileExists(atPath: location.mediaDirectory.appendingPathComponent(name).path)
                else { continue }
                queue.append((name, asset, stickers.contains(name)))
                if queue.count == Self.prefetchLimit { return queue }
            }
        }
        return queue
    }

    nonisolated static func prefetches(_ fileName: String) -> Bool {
        !["mov", "mp4", "m4v", "gif"].contains((fileName as NSString).pathExtension.lowercased())
    }

    func needsRetry(documentID: ComposerDocumentID?) {
        failed.insert(boardID(documentID))
    }

    /// Before a board's first fetch every missing file may still come; afterwards only the ones downloading.
    func waiting(for documentID: ComposerDocumentID?) -> ComposerMediaWaiting {
        let id = boardID(documentID)
        return ComposerMediaWaiting(all: !attempted.contains(id) && !failed.contains(id), files: pendingFiles)
    }

    func load(documentID: ComposerDocumentID?, store: ComposerStore, token: String) async {
        let id = boardID(documentID)
        guard !loading.contains(id), let document = documents.first(where: { $0.id == id }),
              !Task.isCancelled else { return }
        // The board being opened goes first; the quiet fetching resumes once it's done.
        pausePrefetch()
        loading.insert(id)
        failed.remove(id)
        defer {
            loading.remove(id)
            attempted.insert(id)
            if !Task.isCancelled { startPrefetch(store: store, token: token) }
        }
        let wanted = document.body.mediaAssets ?? [:]
        let missing = wanted.filter { name, _ in
            !FileManager.default.fileExists(atPath: location.mediaDirectory.appendingPathComponent(name).path)
        }
        pendingFiles.formUnion(missing.keys)
        defer { pendingFiles.subtract(missing.keys) }
        let client = client, ownerID = ownerID
        let stickers = Self.stickerFiles(in: document.body.blocks)
        await withTaskGroup(of: (String, Data?).self) { group in
            var queue = Array(missing).makeIterator()
            func next() {
                guard !Task.isCancelled, let (name, asset) = queue.next() else { return }
                let paths = MosaicVisitClient.objectPaths(ownerID: ownerID, assetID: asset, fileName: name,
                                                          isSticker: stickers.contains(name))
                group.addTask {
                    for path in paths {
                        guard !Task.isCancelled else { return (name, nil) }
                        if let data = await client.download(path: path, accessToken: token), !data.isEmpty {
                            return (name, data)
                        }
                    }
                    return (name, nil)
                }
            }
            for _ in 0..<4 { next() }
            while let (name, data) = await group.next() {
                pendingFiles.remove(name)
                guard !Task.isCancelled else { group.cancelAll(); continue }
                do {
                    guard let data else { throw ComposerRestoreError.mediaUnavailable }
                    try data.write(to: location.mediaDirectory.appendingPathComponent(name), options: .atomic)
                    store.mediaDidDownload(name)
                } catch {
                    failed.insert(id)
                }
                next()
            }
        }
    }
}

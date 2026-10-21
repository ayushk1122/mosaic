import Foundation
import Observation

/// Visit layouts are authorized afresh; media is fetched only when its board opens.
@MainActor
@Observable
final class MosaicVisitMedia {
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
        loading.insert(id)
        failed.remove(id)
        defer {
            loading.remove(id)
            attempted.insert(id)
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

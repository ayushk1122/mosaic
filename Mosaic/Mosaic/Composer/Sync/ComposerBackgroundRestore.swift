import Foundation
import Observation

/// Resumable downloads for an already usable editor. Successful files are their own checkpoint.
@MainActor
@Observable
final class ComposerBackgroundRestore {
    private(set) var isLoading = false
    var failure: String?
    /// Missing files that still have a cloud copy on the way. Any other missing file is unavailable.
    private(set) var expectedFiles: Set<String> = []
    /// Files copied back from older folders on this phone during the last run.
    private(set) var recoveredFiles: [String] = []

    static func state(at location: ComposerStorageLocation) -> ComposerSyncState? {
        guard let data = try? Data(contentsOf: location.syncStateURL) else { return nil }
        return try? JSONDecoder().decode(ComposerSyncState.self, from: data)
    }

    static func missingMedia(store: ComposerStore, state: ComposerSyncState) -> [(file: String, asset: String)] {
        // The catalog visits the landing board first, so its images get priority.
        ComposerMediaCatalog.references(snapshot: store.snapshot, mosaicID: state.mosaicID).compactMap { reference in
            guard let asset = state.mediaAssets[reference.fileName],
                  !FileManager.default.fileExists(atPath: store.mediaURL(for: reference.fileName).path)
            else { return nil }
            return (reference.fileName, asset)
        }
    }

    /// Every referenced file that is not on this phone, whether or not the cloud has a copy.
    static func missingFiles(store: ComposerStore, mosaicID: UUID) -> [String] {
        var seen = Set<String>()
        return ComposerMediaCatalog.references(snapshot: store.snapshot, mosaicID: mosaicID).compactMap { reference in
            let file = reference.fileName
            guard seen.insert(file).inserted,
                  !FileManager.default.fileExists(atPath: store.mediaURL(for: file).path)
            else { return nil }
            return file
        }
    }

    static func needsWork(store: ComposerStore) -> Bool {
        guard let state = state(at: store.location) else { return false }
        if state.pendingRestore || !missingMedia(store: store, state: state).isEmpty { return true }
        let folders = recoveryFolders(for: store.location)
        return missingFiles(store: store, mosaicID: state.mosaicID).contains { file in
            folders.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent(file).path) }
        }
    }

    /// Media folders of older copies of these boards left on the phone: folders a restore set aside,
    /// and the Documents folder used before accounts.
    static func recoveryFolders(
        for location: ComposerStorageLocation,
        shared: ComposerStorageLocation = .shared(),
        fileManager: FileManager = .default
    ) -> [URL] {
        let parent = location.root.deletingLastPathComponent()
        let siblings = (try? fileManager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
        let backups = siblings
            .filter { $0.lastPathComponent.hasPrefix(ComposerAccountRestore.backupPrefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { ComposerStorageLocation(root: $0).mediaDirectory }
        let own = location.mediaDirectory.standardizedFileURL
        return (backups + [shared.mediaDirectory]).filter { $0.standardizedFileURL != own }
    }

    /// Copies files that are missing here from the first folder that has them. Returns the names copied.
    static func recover(
        _ files: [String],
        into location: ComposerStorageLocation,
        from folders: [URL],
        fileManager: FileManager = .default
    ) -> [String] {
        var recovered: [String] = []
        for file in files where ComposerAccountRestore.isSafeFileName(file) {
            let target = location.mediaDirectory.appendingPathComponent(file)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            for folder in folders {
                let source = folder.appendingPathComponent(file)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                do {
                    try fileManager.createDirectory(at: location.mediaDirectory, withIntermediateDirectories: true)
                    try fileManager.copyItem(at: source, to: target)
                    recovered.append(file)
                    break
                } catch {
                    continue
                }
            }
        }
        return recovered
    }

    /// Marks the files that will download, before the first run starts, so they show as loading.
    func noteExpectedFiles(store: ComposerStore) {
        guard let state = Self.state(at: store.location) else { return }
        expectedFiles = Set(Self.missingMedia(store: store, state: state).map(\.file))
    }

    func run(store: ComposerStore, client: SupabaseDocumentSync, ownerID: UUID, accessToken: String) async throws {
        guard !isLoading, var state = Self.state(at: store.location) else { return }
        isLoading = true
        failure = nil
        recoveredFiles = []
        defer { isLoading = false }
        if state.pendingRestore {
            let rows = try await client.ownDocuments(ownerID: ownerID, accessToken: accessToken)
            // Missing child rows get empty boards in `finishRestoring` rather than failing every retry.
            let (remote, downloadedState) = try ComposerAccountRestore.assemble(
                rows: rows, ownerID: ownerID, mosaicID: state.mosaicID, requireComplete: false
            )
            var complete = downloadedState
            // The landing board may have been edited while the children downloaded.
            // Keep its original revision and assets, never replace it with another snapshot.
            complete.revisions.merge(state.revisions) { _, local in local }
            complete.mediaAssets.merge(state.mediaAssets) { _, local in local }
            try Task.checkCancellation()
            try store.finishRestoring(snapshot: remote, state: complete)
            state = complete
        }
        // A local copy beats a download, and is the only way back for a file that never reached the cloud.
        recoveredFiles = Self.recover(
            Self.missingFiles(store: store, mosaicID: state.mosaicID),
            into: store.location,
            from: Self.recoveryFolders(for: store.location)
        )
        recoveredFiles.forEach(store.mediaDidDownload)
        let missing = Self.missingMedia(store: store, state: state)
        expectedFiles = Set(missing.map(\.file))
        guard !missing.isEmpty else { return }
        try FileManager.default.createDirectory(at: store.location.mediaDirectory, withIntermediateDirectories: true)
        // One failed object does not hold up all the other photos and videos.
        for (file, asset) in missing {
            try Task.checkCancellation()
            guard ComposerAccountRestore.isSafeFileName(file), let assetID = UUID(uuidString: asset) else {
                throw ComposerRestoreError.invalidMedia
            }
            do {
                let data = try await client.downloadOriginal(ownerID: ownerID, assetID: assetID, accessToken: accessToken)
                try Task.checkCancellation()
                try data.write(to: store.mediaURL(for: file), options: .atomic)
                store.mediaDidDownload(file)
            } catch {
                try Task.checkCancellation()
                failure = "Some photos or videos couldn’t download. You can keep using your Mosaic."
            }
            expectedFiles.remove(file)
        }
    }
}

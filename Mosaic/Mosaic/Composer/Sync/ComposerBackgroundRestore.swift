import Foundation
import Observation

/// Resumable downloads for an already usable editor. Successful files are their own checkpoint.
@MainActor
@Observable
final class ComposerBackgroundRestore {
    private(set) var isLoading = false
    private(set) var remainingMedia = 0
    var failure: String?

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

    static func needsWork(store: ComposerStore) -> Bool {
        guard let state = state(at: store.location) else { return false }
        return state.pendingRestore || !missingMedia(store: store, state: state).isEmpty
    }

    func run(store: ComposerStore, client: SupabaseDocumentSync, ownerID: UUID, accessToken: String) async throws {
        guard !isLoading, var state = Self.state(at: store.location) else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }
        if state.pendingRestore {
            let rows = try await client.ownDocuments(ownerID: ownerID, accessToken: accessToken)
            let (remote, downloadedState) = try ComposerAccountRestore.assemble(rows: rows, ownerID: ownerID, mosaicID: state.mosaicID)
            var complete = downloadedState
            // The landing board may have been edited while the children downloaded.
            // Keep its original revision and assets, never replace it with another snapshot.
            complete.revisions.merge(state.revisions) { _, local in local }
            complete.mediaAssets.merge(state.mediaAssets) { _, local in local }
            try Task.checkCancellation()
            try store.finishRestoring(snapshot: remote, state: complete)
            state = complete
        }
        let missing = Self.missingMedia(store: store, state: state)
        remainingMedia = missing.count
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
                remainingMedia -= 1
            } catch {
                try Task.checkCancellation()
                failure = "Some photos or videos couldn’t download. You can keep using your Mosaic."
            }
        }
    }
}

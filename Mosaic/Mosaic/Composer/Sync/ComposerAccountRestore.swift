import Foundation

/// Strictly decoded owner rows. A partial or malformed board list cannot become editable data.
struct ComposerRestoredDocument: Codable, Sendable {
    var id: UUID
    var ownerID: UUID
    var parentID: UUID?
    var role: ComposerSyncRole
    var title: String
    var body: ComposerBoardBody
    var revision: Int64

    enum CodingKeys: String, CodingKey {
        case id, role, title, body, revision
        case ownerID = "owner_id"
        case parentID = "parent_id"
    }

    var document: ComposerSyncDocument {
        ComposerSyncDocument(id: id, parentID: parentID, role: role, title: title,
                             visibility: ComposerBoardSync.privateVisibility, body: body)
    }
}

enum ComposerRestoreError: Error, LocalizedError {
    case incompleteBoards
    case invalidMedia
    case mediaUnavailable
    case localChanges

    var errorDescription: String? {
        switch self {
        case .incompleteBoards:
            "Your saved Mosaic could not be loaded completely. Please try again."
        case .invalidMedia, .mediaUnavailable:
            "Some saved photos or videos could not be downloaded. Please try again."
        case .localChanges:
            "This device has unsynced edits and your account already has a saved Mosaic. Your local edits have been kept. They need to be reconciled before restoring."
        }
    }
}

/// Caches the landing board and a durable pending flag before the editor is created.
/// Established local boards remain available offline, preserving edits not uploaded yet.
@MainActor
struct ComposerAccountRestore {
    var client: SupabaseDocumentSync
    var fileManager: FileManager = .default

    static let backupPrefix = ".before-restore-"

    static func hasLocalAccount(at location: ComposerStorageLocation) -> Bool {
        guard let snapshot = try? Data(contentsOf: location.snapshotURL),
              (try? JSONDecoder().decode(ComposerSnapshot.self, from: snapshot)) != nil,
              let state = try? Data(contentsOf: location.syncStateURL),
              (try? JSONDecoder().decode(ComposerSyncState.self, from: state)) != nil
        else { return false }
        return true
    }

    func prepare(ownerID: UUID, accessToken: String, location: ComposerStorageLocation) async throws {
        guard !Self.hasLocalAccount(at: location) else { return }
        let localData = try? Data(contentsOf: location.snapshotURL)
        let local = localData.flatMap { try? JSONDecoder().decode(ComposerSnapshot.self, from: $0) }
        guard let mosaicID = try await client.ownMosaicID(accessToken: accessToken) else {
            // A genuinely new account can keep its local board and begin uploading it.
            return
        }
        if let local, !Self.isStarterBoard(local) {
            throw ComposerRestoreError.localChanges
        }
        let row = try await client.ownDocument(id: mosaicID, ownerID: ownerID, accessToken: accessToken)
        var (snapshot, state) = try Self.assemble(rows: [row], ownerID: ownerID, mosaicID: mosaicID, requireComplete: false)
        state.pendingRestore = true
        let parent = location.root.deletingLastPathComponent()
        let stage = ComposerStorageLocation(root: parent.appendingPathComponent(".restore-\(UUID().uuidString)", isDirectory: true))
        try fileManager.createDirectory(at: stage.mediaDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stage.root) }

        try JSONEncoder().encode(snapshot).write(to: stage.snapshotURL, options: .atomic)
        try JSONEncoder().encode(state).write(to: stage.syncStateURL, options: .atomic)
        try Task.checkCancellation()
        // Retain any previous local folder as a recovery copy. The landing board and pending-download marker are installed together.
        let backup = parent.appendingPathComponent(Self.backupPrefix + UUID().uuidString, isDirectory: true)
        let hadLocal = fileManager.fileExists(atPath: location.root.path)
        if hadLocal { try fileManager.moveItem(at: location.root, to: backup) }
        do {
            try fileManager.moveItem(at: stage.root, to: location.root)
        } catch {
            if hadLocal { try? fileManager.moveItem(at: backup, to: location.root) }
            throw error
        }
    }

    static func assemble(
        rows: [ComposerRestoredDocument], ownerID: UUID, mosaicID: UUID, requireComplete: Bool = true
    ) throws -> (ComposerSnapshot, ComposerSyncState) {
        let ids = Set(rows.map(\.id))
        guard ids.count == rows.count,
              rows.allSatisfy({ $0.ownerID == ownerID && $0.revision > 0 }),
              rows.filter({ $0.role == .mosaic }).map(\.id) == [mosaicID],
              let snapshot = ComposerBoardSync.assemble(mosaicID: mosaicID, documents: rows.map(\.document))
        else { throw ComposerRestoreError.incompleteBoards }
        let references = ComposerBoardSync.referencedIDs(in: snapshot)
        guard !requireComplete || references.allSatisfy({ raw in UUID(uuidString: raw).map { ids.contains($0) } ?? false }) else {
            throw ComposerRestoreError.incompleteBoards
        }
        var state = ComposerSyncState(mosaicID: mosaicID)
        for row in rows {
            let key = row.id.uuidString.lowercased()
            state.revisions[key] = row.revision
            // Recorded as already pushed, so the first push after a restore skips boards that
            // haven't changed instead of re-saving all of them, which could overwrite edits another
            // device made in the meantime. Anything edited here afterwards hashes differently and
            // is pushed as usual.
            if let hash = ComposerSyncState.contentHash(of: row.document) {
                state.pushedHashes[key] = hash
            }
            for (file, asset) in row.body.mediaAssets ?? [:] {
                guard isSafeFileName(file), let assetID = UUID(uuidString: asset) else {
                    throw ComposerRestoreError.invalidMedia
                }
                let normalized = assetID.uuidString.lowercased()
                if let existing = state.mediaAssets[file], existing != normalized {
                    throw ComposerRestoreError.invalidMedia
                }
                state.mediaAssets[file] = normalized
            }
            state.mediaPreviews.merge(row.body.mediaPreviews ?? [:]) { _, row in row }
        }
        // Unuploaded local media has no cloud asset to recover. Preserve those references as-is.
        return (snapshot, state)
    }

    static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    static func isStarterBoard(_ snapshot: ComposerSnapshot) -> Bool {
        if snapshot == .empty { return true }
        guard snapshot.mosaicTitle == "Mosaic", snapshot.mosaicTitlePlaced,
              snapshot.pursuits.isEmpty, snapshot.mosaicBlocks.count == 1,
              snapshot.mosaicBackground == nil
        else { return false }
        var heading = ComposerBlock(id: snapshot.mosaicBlocks[0].id, kind: .heading, text: "Mosaic",
                                    style: .headingDefault, position: BlockPosition(x: 0.06, y: 0.03))
        heading.text = "Mosaic"
        heading.style.fontSize = 34
        return snapshot.mosaicBlocks[0] == heading
    }
}

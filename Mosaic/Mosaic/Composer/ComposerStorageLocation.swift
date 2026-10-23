import Foundation

/// Where one set of boards, media, and sync state lives on the phone.
struct ComposerStorageLocation: Equatable, Sendable {
    var root: URL

    var snapshotURL: URL { root.appendingPathComponent("composer.json") }
    var mediaDirectory: URL { root.appendingPathComponent(Self.mediaFolderName, isDirectory: true) }
    nonisolated static let mediaFolderName = "Media"
    var syncStateURL: URL { root.appendingPathComponent("sync-state.json") }

    /// The Documents folder itself. Used before accounts, and when no account is signed in.
    static func shared(fileManager: FileManager = .default) -> ComposerStorageLocation {
        ComposerStorageLocation(root: documents(fileManager))
    }

    static func account(_ userID: UUID, fileManager: FileManager = .default) -> ComposerStorageLocation {
        ComposerStorageLocation(
            root: documents(fileManager)
                .appendingPathComponent("Accounts", isDirectory: true)
                .appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
        )
    }

    private static func documents(_ fileManager: FileManager) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

/// Boards saved before accounts had their own folders.
enum ComposerLegacyStorage {
    /// Synced boards go to the account that owns that Mosaic on the server.
    /// Boards that never synced go to the first account that has no Mosaic yet.
    static func shouldClaim(legacyMosaicID: UUID?, serverMosaicID: UUID?) -> Bool {
        if let legacyMosaicID {
            return legacyMosaicID == serverMosaicID
        }
        return serverMosaicID == nil
    }

    static func legacyMosaicID(in legacy: ComposerStorageLocation) -> UUID? {
        guard let data = try? Data(contentsOf: legacy.syncStateURL),
              let state = try? JSONDecoder().decode(ComposerSyncState.self, from: data)
        else { return nil }
        return state.mosaicID
    }

    /// An account folder holding only a board that was never edited or synced.
    static func isBlank(_ location: ComposerStorageLocation, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: location.snapshotURL.path) else { return true }
        guard !fileManager.fileExists(atPath: location.syncStateURL.path),
              let data = try? Data(contentsOf: location.snapshotURL),
              let snapshot = try? JSONDecoder().decode(ComposerSnapshot.self, from: data)
        else { return false }
        return ComposerAccountRestore.isStarterBoard(snapshot)
    }

    /// Moves the boards file, media, and sync state. An account that already has boards keeps them.
    @discardableResult
    static func claim(
        from legacy: ComposerStorageLocation,
        to target: ComposerStorageLocation,
        fileManager: FileManager = .default
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: legacy.snapshotURL.path),
              isBlank(target, fileManager: fileManager)
        else { return false }
        try fileManager.createDirectory(at: target.root, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: target.snapshotURL.path) {
            try fileManager.removeItem(at: target.snapshotURL)
        }
        try fileManager.moveItem(at: legacy.snapshotURL, to: target.snapshotURL)
        if fileManager.fileExists(atPath: legacy.mediaDirectory.path),
           !fileManager.fileExists(atPath: target.mediaDirectory.path) {
            try fileManager.moveItem(at: legacy.mediaDirectory, to: target.mediaDirectory)
        }
        if fileManager.fileExists(atPath: legacy.syncStateURL.path),
           !fileManager.fileExists(atPath: target.syncStateURL.path) {
            try fileManager.moveItem(at: legacy.syncStateURL, to: target.syncStateURL)
        }
        return true
    }

    /// Runs once per sign-in, before that account's boards open.
    static func prepare(for account: MosaicAccount, fileManager: FileManager = .default) async {
        guard let userID = account.session?.userID else { return }
        let legacy = ComposerStorageLocation.shared(fileManager: fileManager)
        let target = ComposerStorageLocation.account(userID, fileManager: fileManager)
        guard fileManager.fileExists(atPath: legacy.snapshotURL.path),
              isBlank(target, fileManager: fileManager)
        else { return }
        guard let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken()
        else { return }
        let serverMosaicID: UUID?
        do {
            serverMosaicID = try await SupabaseDocumentSync(config: config).ownMosaicID(accessToken: token)
        } catch {
            return
        }
        guard shouldClaim(legacyMosaicID: legacyMosaicID(in: legacy), serverMosaicID: serverMosaicID) else { return }
        _ = try? claim(from: legacy, to: target, fileManager: fileManager)
    }
}

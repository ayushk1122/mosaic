import Foundation

struct ComposerSyncState: Codable, Equatable, Sendable {
    var mosaicID: UUID
    var revisions: [String: Int64]
    var mediaAssets: [String: String]
    var pendingRestore: Bool

    init(mosaicID: UUID, revisions: [String: Int64] = [:], mediaAssets: [String: String] = [:], pendingRestore: Bool = false) {
        self.mosaicID = mosaicID
        self.revisions = revisions
        self.mediaAssets = mediaAssets
        self.pendingRestore = pendingRestore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mosaicID = try container.decode(UUID.self, forKey: .mosaicID)
        revisions = try container.decodeIfPresent([String: Int64].self, forKey: .revisions) ?? [:]
        mediaAssets = try container.decodeIfPresent([String: String].self, forKey: .mediaAssets) ?? [:]
        pendingRestore = try container.decodeIfPresent(Bool.self, forKey: .pendingRestore) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mosaicID, forKey: .mosaicID)
        try container.encode(revisions, forKey: .revisions)
        try container.encode(mediaAssets, forKey: .mediaAssets)
        try container.encode(pendingRestore, forKey: .pendingRestore)
    }

    static func choosingMosaicID(local: UUID?, remote: UUID?) -> UUID {
        remote ?? local ?? UUID()
    }

    /// A phone that never synced this account must not overwrite a Mosaic the server already has,
    /// and a phone synced to one Mosaic must not write into another.
    static func mayPush(local: UUID?, remote: UUID?) -> Bool {
        guard let remote else { return true }
        return local == remote
    }

    private enum CodingKeys: String, CodingKey {
        case mosaicID, revisions, mediaAssets, pendingRestore
    }
}

/// Pushes the local snapshot to Supabase after edits settle.
@MainActor
@Observable
final class ComposerRemoteSync {
    private var latest: ComposerSnapshot?
    private var wait: Task<Void, Never>?
    private var active = false
    private var again = false
    private let location: ComposerStorageLocation
    private var mediaFile: (@MainActor (String) -> URL)?

    init(location: ComposerStorageLocation = .shared()) {
        self.location = location
    }

    var canUpload: Bool { loadState()?.pendingRestore != true }

    func schedule(
        snapshot: ComposerSnapshot,
        account: MosaicAccount,
        mediaFile: @escaping @MainActor (String) -> URL
    ) {
        guard canUpload else { return }
        self.mediaFile = mediaFile
        latest = snapshot
        wait?.cancel()
        wait = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await self?.run(account: account)
        }
    }

    /// Pushes right away instead of after the usual pause, and returns once nothing is left to push.
    /// False when the last push could not reach the server or was not allowed.
    func syncNow(
        snapshot: ComposerSnapshot,
        account: MosaicAccount,
        mediaFile: @escaping @MainActor (String) -> URL
    ) async -> Bool {
        guard canUpload else { return false }
        self.mediaFile = mediaFile
        latest = snapshot
        wait?.cancel()
        await run(account: account)
        while active || latest != nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return lastPushSucceeded
    }

    @ObservationIgnored private var lastPushSucceeded = false

    private func run(account: MosaicAccount) async {
        if active {
            again = true
            return
        }
        active = true
        defer { active = false }
        guard let snapshot = latest else { return }
        latest = nil
        lastPushSucceeded = await push(snapshot, account: account)
        if again {
            again = false
            await run(account: account)
        }
    }

    private func push(_ snapshot: ComposerSnapshot, account: MosaicAccount) async -> Bool {
        guard let config = SupabaseSyncConfig.current(),
              let accessToken = await account.accessToken()
        else { return false }
        let client = SupabaseDocumentSync(config: config)
        do {
            var state = loadState()
            guard state?.pendingRestore != true else { return false }
            let remoteMosaicID = try await client.ownMosaicID(accessToken: accessToken)
            guard ComposerSyncState.mayPush(local: state?.mosaicID, remote: remoteMosaicID) else { return false }
            let mosaicID = ComposerSyncState.choosingMosaicID(local: state?.mosaicID, remote: remoteMosaicID)
            if state?.mosaicID != mosaicID {
                state = ComposerSyncState(
                    mosaicID: mosaicID,
                    revisions: state?.revisions ?? [:],
                    mediaAssets: state?.mediaAssets ?? [:]
                )
            }
            var revisions = state?.revisions ?? [:]
            var mediaAssets = state?.mediaAssets ?? [:]
            let split = ComposerBoardSync.split(snapshot: snapshot, mosaicID: mosaicID)
            let documents = ComposerMediaCatalog.stamped(split, assets: mediaAssets)
            for document in documents {
                let next = try await save(
                    client: client,
                    document: document,
                    expected: revisions[document.id.uuidString.lowercased()] ?? 0,
                    accessToken: accessToken
                )
                revisions[document.id.uuidString.lowercased()] = next
                saveState(ComposerSyncState(mosaicID: mosaicID, revisions: revisions, mediaAssets: mediaAssets))
            }
            guard let userID = account.session?.userID else { return true }
            let liveIDs = documents.map(\.id)
            if let remoteIDs = try? await client.listOwnDocumentIDs(ownerID: userID, accessToken: accessToken) {
                let dead = ComposerBoardSync.deadIDs(live: liveIDs, remote: remoteIDs, mosaicID: mosaicID)
                if !dead.isEmpty {
                    try? await client.deleteMedia(forDocumentIDs: dead, accessToken: accessToken)
                    try? await client.deleteDocuments(ids: dead, accessToken: accessToken)
                    let deadKeys = Set(dead.map { $0.uuidString.lowercased() })
                    revisions = revisions.filter { !deadKeys.contains($0.key) }
                    let liveFiles = Set(
                        ComposerMediaCatalog.references(snapshot: snapshot, mosaicID: mosaicID).map(\.fileName)
                    )
                    mediaAssets = mediaAssets.filter { liveFiles.contains($0.key) }
                    saveState(ComposerSyncState(mosaicID: mosaicID, revisions: revisions, mediaAssets: mediaAssets))
                }
            }
            guard let mediaFile else { return true }
            mediaAssets = await uploadMedia(
                references: ComposerMediaCatalog.references(snapshot: snapshot, mosaicID: mosaicID),
                assets: mediaAssets,
                ownerID: userID,
                mosaicID: mosaicID,
                revisions: revisions,
                client: client,
                accessToken: accessToken,
                mediaFile: mediaFile
            )
            let restamped = ComposerMediaCatalog.stamped(split, assets: mediaAssets)
            for (before, after) in zip(documents, restamped) where before.body.mediaAssets != after.body.mediaAssets {
                let key = after.id.uuidString.lowercased()
                let next = try await save(
                    client: client,
                    document: after,
                    expected: revisions[key] ?? 0,
                    accessToken: accessToken
                )
                revisions[key] = next
                saveState(ComposerSyncState(mosaicID: mosaicID, revisions: revisions, mediaAssets: mediaAssets))
            }
            return true
        } catch {
            return false
        }
    }

    private func uploadMedia(
        references: [ComposerMediaReference],
        assets: [String: String],
        ownerID: UUID,
        mosaicID: UUID,
        revisions: [String: Int64],
        client: SupabaseDocumentSync,
        accessToken: String,
        mediaFile: @MainActor (String) -> URL
    ) async -> [String: String] {
        var assets = assets
        let media = SupabaseMediaSync(config: client.config, session: client.session)
        for reference in references where assets[reference.fileName] == nil {
            let url = mediaFile(reference.fileName)
            guard let prepared = await ComposerMediaPreparer.prepare(fileAt: url) else { continue }
            let assetID = UUID()
            do {
                try await media.upload(
                    prepared: prepared,
                    ownerID: ownerID,
                    assetID: assetID,
                    documentID: reference.documentID,
                    accessToken: accessToken
                )
                assets[reference.fileName] = assetID.uuidString.lowercased()
                saveState(ComposerSyncState(mosaicID: mosaicID, revisions: revisions, mediaAssets: assets))
            } catch {
                continue
            }
        }
        return assets
    }

    private func save(
        client: SupabaseDocumentSync,
        document: ComposerSyncDocument,
        expected: Int64,
        accessToken: String
    ) async throws -> Int64 {
        let push = ComposerDocumentPush(document: document, expectedRevision: expected)
        do {
            return try await client.save(push: push, accessToken: accessToken)
        } catch SupabaseDocumentSyncError.revisionConflict {
            let data = try await client.readDocument(id: document.id, accessToken: accessToken)
            guard let serverRevision = SupabaseDocumentSync.optionalRevision(from: data) else {
                throw SupabaseDocumentSyncError.revisionConflict
            }
            let retry = ComposerDocumentPush(document: document, expectedRevision: serverRevision)
            return try await client.save(push: retry, accessToken: accessToken)
        } catch SupabaseDocumentSyncError.mosaicExists {
            guard let remote = try await client.ownMosaicID(accessToken: accessToken) else {
                throw SupabaseDocumentSyncError.mosaicExists
            }
            var adopted = document
            adopted.id = remote
            let retry = ComposerDocumentPush(document: adopted, expectedRevision: 0)
            return try await client.save(push: retry, accessToken: accessToken)
        }
    }

    private func loadState() -> ComposerSyncState? {
        guard let data = try? Data(contentsOf: location.syncStateURL) else { return nil }
        return try? JSONDecoder().decode(ComposerSyncState.self, from: data)
    }

    private func saveState(_ state: ComposerSyncState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: location.root, withIntermediateDirectories: true)
        try? data.write(to: location.syncStateURL, options: .atomic)
    }
}

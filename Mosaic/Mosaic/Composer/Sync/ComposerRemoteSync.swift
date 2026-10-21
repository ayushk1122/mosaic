import CryptoKit
import Foundation
import UIKit

struct ComposerSyncState: Codable, Equatable, Sendable {
    var mosaicID: UUID
    var revisions: [String: Int64]
    var mediaAssets: [String: String]
    var pendingRestore: Bool
    /// Content hash of each board as last saved, so unchanged boards are not pushed again.
    var pushedHashes: [String: String]

    init(
        mosaicID: UUID,
        revisions: [String: Int64] = [:],
        mediaAssets: [String: String] = [:],
        pendingRestore: Bool = false,
        pushedHashes: [String: String] = [:]
    ) {
        self.mosaicID = mosaicID
        self.revisions = revisions
        self.mediaAssets = mediaAssets
        self.pendingRestore = pendingRestore
        self.pushedHashes = pushedHashes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mosaicID = try container.decode(UUID.self, forKey: .mosaicID)
        revisions = try container.decodeIfPresent([String: Int64].self, forKey: .revisions) ?? [:]
        mediaAssets = try container.decodeIfPresent([String: String].self, forKey: .mediaAssets) ?? [:]
        pendingRestore = try container.decodeIfPresent(Bool.self, forKey: .pendingRestore) ?? false
        pushedHashes = try container.decodeIfPresent([String: String].self, forKey: .pushedHashes) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mosaicID, forKey: .mosaicID)
        try container.encode(revisions, forKey: .revisions)
        try container.encode(mediaAssets, forKey: .mediaAssets)
        try container.encode(pendingRestore, forKey: .pendingRestore)
        try container.encode(pushedHashes, forKey: .pushedHashes)
    }

    /// Identifies a board's saved content: title, placement, and body.
    static func contentHash(of document: ComposerSyncDocument) -> String? {
        struct Content: Encodable {
            var parentID: UUID?
            var role: ComposerSyncRole
            var title: String
            var body: ComposerBoardBody
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Content(
            parentID: document.parentID, role: document.role, title: document.title, body: document.body
        )) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
        case mosaicID, revisions, mediaAssets, pendingRestore, pushedHashes
    }
}

/// Pushes the local snapshot to Supabase after edits settle.
@MainActor
@Observable
final class ComposerRemoteSync {
    private var latest: ComposerSnapshot?
    /// Document ids held by a cut clipboard; must not be deleted as dead during sync.
    private var latestProtecting: Set<UUID> = []
    private var latestAccount: MosaicAccount?
    /// The pause before a push. Cancelling it never cancels a push that has already started.
    private var wait: Task<Void, Never>?
    private var active = false
    private var again = false
    /// Background retries left for local files that still need a cloud asset.
    private var mediaRetryBudget = 0
    /// Set when a push could not finish, so the next foreground or retry tries again.
    private var needsPush = false
    private var failureRetries = 0
    /// Files whose upload failed on several pushes in a row this session; skipped until relaunch.
    @ObservationIgnored private var uploadFailures: [String: Int] = [:]
    private let location: ComposerStorageLocation
    private var mediaFile: (@MainActor (String) -> URL)?

    init(location: ComposerStorageLocation = .shared()) {
        self.location = location
    }

    var canUpload: Bool { loadState()?.pendingRestore != true }

    /// True when this phone still has files that visitors cannot download yet.
    func hasUnmappedLocalMedia(
        snapshot: ComposerSnapshot,
        mediaFile: @escaping @MainActor (String) -> URL
    ) -> Bool {
        guard let state = loadState(), !state.pendingRestore else { return false }
        let references = ComposerMediaCatalog.references(snapshot: snapshot, mosaicID: state.mosaicID)
        return references.contains { reference in
            guard state.mediaAssets[reference.fileName] == nil,
                  (uploadFailures[reference.fileName] ?? 0) < Self.uploadAttemptLimit else { return false }
            return FileManager.default.fileExists(atPath: mediaFile(reference.fileName).path)
        }
    }

    /// A push that failed (offline, server error) is retried when the app comes back.
    var hasUnsyncedChanges: Bool { needsPush || latest != nil }

    func schedule(
        snapshot: ComposerSnapshot,
        account: MosaicAccount,
        mediaFile: @escaping @MainActor (String) -> URL,
        protectingDocumentIDs: Set<UUID> = []
    ) {
        guard canUpload else { return }
        self.mediaFile = mediaFile
        latest = snapshot
        latestProtecting = protectingDocumentIDs
        latestAccount = account
        mediaRetryBudget = 3
        failureRetries = 0
        startAfter(.milliseconds(800), account: account)
    }

    /// Sends a waiting edit now instead of after the pause; used when the app moves to the background.
    func flushNow(account: MosaicAccount) {
        guard latest != nil || needsPush, canUpload else { return }
        wait?.cancel()
        wait = nil
        let task = UIApplication.shared.beginBackgroundTask(withName: "Mosaic sync")
        Task { [weak self] in
            await self?.run(account: account)
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    /// Pushes right away instead of after the usual pause, and returns once nothing is left to push.
    /// False when the last push could not reach the server or was not allowed.
    func syncNow(
        snapshot: ComposerSnapshot,
        account: MosaicAccount,
        mediaFile: @escaping @MainActor (String) -> URL,
        protectingDocumentIDs: Set<UUID> = []
    ) async -> Bool {
        guard canUpload else { return false }
        self.mediaFile = mediaFile
        latest = snapshot
        latestProtecting = protectingDocumentIDs
        latestAccount = account
        mediaRetryBudget = 3
        wait?.cancel()
        wait = nil
        await run(account: account)
        // A push that was already running picks this snapshot up next; wait for both to finish.
        while active {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return lastPushSucceeded
    }

    @ObservationIgnored private var lastPushSucceeded = false
    @ObservationIgnored private var lastPushLeftMediaPending = false

    /// Waits, then starts a push in its own task, so a newer edit cancelling the wait never
    /// cancels an upload that is already in flight.
    private func startAfter(_ delay: Duration, account: MosaicAccount) {
        wait?.cancel()
        wait = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            Task { await self.run(account: account) }
        }
    }

    /// One push at a time. Edits that arrive during a push are pushed right after it, in the same run.
    private func run(account: MosaicAccount) async {
        if active {
            again = true
            return
        }
        active = true
        defer { active = false }
        var pushed: (snapshot: ComposerSnapshot, protecting: Set<UUID>)?
        repeat {
            again = false
            guard let snapshot = latest else { break }
            let protecting = latestProtecting
            latest = nil
            latestProtecting = []
            lastPushSucceeded = await push(snapshot, account: account, protecting: protecting)
            pushed = (snapshot, protecting)
            if !lastPushSucceeded && !lastPushLeftMediaPending {
                // Keep the snapshot so a retry or the next foreground can send it.
                if latest == nil {
                    latest = snapshot
                    latestProtecting = protecting
                }
                needsPush = true
                break
            }
            needsPush = false
        } while again || latest != nil

        if needsPush {
            scheduleFailureRetry(account: account)
        } else if lastPushLeftMediaPending, mediaRetryBudget > 0, latest == nil, let pushed {
            mediaRetryBudget -= 1
            scheduleMediaRetry(snapshot: pushed.snapshot, account: account, protecting: pushed.protecting)
        }
    }

    /// Offline or a server error: try again after 5, 15, 45, then 120 seconds while the app is open.
    private func scheduleFailureRetry(account: MosaicAccount) {
        let delays: [Duration] = [.seconds(5), .seconds(15), .seconds(45), .seconds(120)]
        guard failureRetries < delays.count else { return }
        let delay = delays[failureRetries]
        failureRetries += 1
        startAfter(delay, account: account)
    }

    /// Called when the app returns to the foreground.
    func resumeIfNeeded(account: MosaicAccount) {
        guard needsPush || latest != nil, canUpload else { return }
        failureRetries = 0
        startAfter(.milliseconds(300), account: account)
    }

    private func scheduleMediaRetry(
        snapshot: ComposerSnapshot,
        account: MosaicAccount,
        protecting: Set<UUID>
    ) {
        wait?.cancel()
        wait = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.latest == nil else { return }
            self.latest = snapshot
            self.latestProtecting = protecting
            Task { await self.run(account: account) }
        }
    }

    private static let uploadAttemptLimit = 3

    private func push(
        _ snapshot: ComposerSnapshot,
        account: MosaicAccount,
        protecting: Set<UUID>
    ) async -> Bool {
        lastPushLeftMediaPending = false
        // Captured once, so a sign-out or account switch mid-push can't mix two accounts.
        guard let config = SupabaseSyncConfig.current(),
              let userID = account.session?.userID,
              let accessToken = await account.accessToken(),
              account.session?.userID == userID
        else { return false }
        let client = SupabaseDocumentSync(config: config)
        do {
            let stored = loadState()
            guard stored?.pendingRestore != true else { return false }
            let remoteMosaicID = try await client.ownMosaicID(accessToken: accessToken)
            guard ComposerSyncState.mayPush(local: stored?.mosaicID, remote: remoteMosaicID) else { return false }
            let mosaicID = ComposerSyncState.choosingMosaicID(local: stored?.mosaicID, remote: remoteMosaicID)
            var state = stored ?? ComposerSyncState(mosaicID: mosaicID)
            if state.mosaicID != mosaicID {
                state.mosaicID = mosaicID
            }
            // Record the chosen id before the first save. If that save's reply is lost, the next push
            // still recognizes the server's Mosaic as this phone's own instead of refusing to sync.
            if stored == nil || stored?.mosaicID != mosaicID {
                saveState(state)
            }

            // Nodes and pages need a parent on the server. One held only by a cut clipboard has none
            // yet, and sending it would fail the whole push.
            let split = ComposerBoardSync.split(snapshot: snapshot, mosaicID: mosaicID).filter { document in
                document.parentID != nil || document.role == .mosaic || document.role == .pursuit
            }
            let documents = ComposerMediaCatalog.stamped(split, assets: state.mediaAssets)
            // One board the server refuses (too large, say) mustn't hold back every other board
            // and the media; it's retried with the next push.
            var anySaveFailed = false
            for document in documents {
                do {
                    try await saveIfChanged(document, state: &state, client: client, ownerID: userID, accessToken: accessToken)
                } catch {
                    if Task.isCancelled { return false }
                    anySaveFailed = true
                }
            }

            let liveIDs = Set(documents.map(\.id))
            // Deleting removed boards waits for a push where every board saved: a board whose
            // save failed may be the new home of a node, and deleting its old parent would take
            // the node's server copy with it.
            if !anySaveFailed,
               let remoteIDs = try? await client.listOwnDocumentIDs(ownerID: userID, accessToken: accessToken) {
                // Only boards this phone has synced before and has since removed. A board another
                // device created is unknown here, not dead.
                let dead = ComposerBoardSync.deadIDs(
                    live: Array(liveIDs),
                    remote: remoteIDs,
                    mosaicID: mosaicID,
                    protecting: protecting
                ).filter { state.revisions[$0.uuidString.lowercased()] != nil }
                if !dead.isEmpty {
                    try? await client.deleteMedia(forDocumentIDs: dead, accessToken: accessToken)
                    try? await client.deleteDocuments(ids: dead, accessToken: accessToken)
                    let deadKeys = Set(dead.map { $0.uuidString.lowercased() })
                    state.revisions = state.revisions.filter { !deadKeys.contains($0.key) }
                    state.pushedHashes = state.pushedHashes.filter { !deadKeys.contains($0.key) }
                    let liveFiles = Set(
                        ComposerMediaCatalog.references(snapshot: snapshot, mosaicID: mosaicID).map(\.fileName)
                    )
                    state.mediaAssets = state.mediaAssets.filter { liveFiles.contains($0.key) }
                    saveState(state)
                }
            }
            guard let mediaFile else { return !anySaveFailed }
            let references = ComposerMediaCatalog.references(snapshot: snapshot, mosaicID: mosaicID)
            state.mediaAssets = await uploadMedia(
                references: references,
                state: state,
                ownerID: userID,
                client: client,
                accessToken: accessToken,
                mediaFile: mediaFile
            )
            saveState(state)
            let restamped = ComposerMediaCatalog.stamped(split, assets: state.mediaAssets)
            for document in restamped {
                do {
                    try await saveIfChanged(document, state: &state, client: client, ownerID: userID, accessToken: accessToken)
                } catch {
                    if Task.isCancelled { return false }
                    anySaveFailed = true
                }
            }
            // Readable local files without a cloud asset are not finished syncing yet,
            // unless they have already failed too often to be retried this session.
            let unfinished = references.contains { reference in
                guard state.mediaAssets[reference.fileName] == nil,
                      (uploadFailures[reference.fileName] ?? 0) < Self.uploadAttemptLimit else { return false }
                return FileManager.default.fileExists(atPath: mediaFile(reference.fileName).path)
            }
            lastPushLeftMediaPending = unfinished
            return !unfinished && !anySaveFailed
        } catch {
            return false
        }
    }

    /// Saves one board unless its content matches what was last pushed.
    private func saveIfChanged(
        _ document: ComposerSyncDocument,
        state: inout ComposerSyncState,
        client: SupabaseDocumentSync,
        ownerID: UUID,
        accessToken: String
    ) async throws {
        let key = document.id.uuidString.lowercased()
        let hash = ComposerSyncState.contentHash(of: document)
        if let hash, state.revisions[key] != nil, state.pushedHashes[key] == hash { return }
        let next = try await save(
            client: client,
            document: document,
            expected: state.revisions[key] ?? 0,
            ownerID: ownerID,
            accessToken: accessToken
        )
        state.revisions[key] = next
        state.pushedHashes[key] = hash
        saveState(state)
    }

    private func uploadMedia(
        references: [ComposerMediaReference],
        state: ComposerSyncState,
        ownerID: UUID,
        client: SupabaseDocumentSync,
        accessToken: String,
        mediaFile: @MainActor (String) -> URL
    ) async -> [String: String] {
        var assets = state.mediaAssets
        let media = SupabaseMediaSync(config: client.config)
        // A file that can't be read or uploaded stays without an asset, so the next sync tries again,
        // and the board shows it as unavailable if it is gone from this phone.
        for reference in references where assets[reference.fileName] == nil {
            guard (uploadFailures[reference.fileName] ?? 0) < Self.uploadAttemptLimit else { continue }
            let url = mediaFile(reference.fileName)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0 else { continue }
            let payloads: [ComposerMediaUploadPayload]
            if ComposerMediaKind.isVideo(reference.fileName) {
                payloads = await ComposerMediaPreparer.prepare(fileAt: url).map { [$0] } ?? []
            } else if let data = try? Data(contentsOf: url) {
                payloads = ComposerMediaPreparer.photoPayloads(from: data)
            } else {
                payloads = []
            }
            var uploaded = false
            for prepared in payloads {
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
                    var progress = state
                    progress.mediaAssets = assets
                    saveState(progress)
                    uploaded = true
                    break
                } catch {
                    continue
                }
            }
            if uploaded {
                uploadFailures[reference.fileName] = nil
            } else {
                uploadFailures[reference.fileName, default: 0] += 1
            }
        }
        return assets
    }

    private func save(
        client: SupabaseDocumentSync,
        document: ComposerSyncDocument,
        expected: Int64,
        ownerID: UUID,
        accessToken: String
    ) async throws -> Int64 {
        let push = ComposerDocumentPush(document: document, expectedRevision: expected)
        do {
            return try await client.save(push: push, accessToken: accessToken)
        } catch SupabaseDocumentSyncError.revisionConflict {
            let server = try await client.ownDocument(id: document.id, ownerID: ownerID, accessToken: accessToken)
            // The earlier save reached the server but its reply was lost: nothing to resolve.
            if server.body == document.body, server.title == document.title {
                return server.revision
            }
            // Another device changed this board. Until the conflict banner from ADR 0003 exists,
            // this phone's version is saved, and the server's is kept on this phone so it isn't lost.
            keepConflictCopy(server)
            let retry = ComposerDocumentPush(document: document, expectedRevision: server.revision)
            return try await client.save(push: retry, accessToken: accessToken)
        }
    }

    private func keepConflictCopy(_ server: ComposerRestoredDocument) {
        let folder = location.root.appendingPathComponent("conflicts", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(server.id.uuidString.lowercased())-r\(server.revision).json"
        if let data = try? JSONEncoder().encode(server) {
            try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
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

import Foundation
import Testing
@testable import Mosaic

@MainActor
struct ComposerBoardSyncTests {
    @Test
    func splitParentsPagesToThePursuitAndLeavesTopLevelPursuitsUnparented() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let pursuitBlockID = store.addBlock(.pursuit, to: nil)
        let pursuitID = store.block(with: pursuitBlockID, in: nil)?.pursuitID
        store.addBlock(.text, to: pursuitID)
        let scrapbookID = store.addBlock(.scrapbook, to: pursuitID)
        let pageIDs = store.block(with: scrapbookID, in: pursuitID)?.scrapbookPageIDs ?? []
        #expect(pageIDs.count == 2)

        let mosaicID = UUID()
        let documents = ComposerBoardSync.split(snapshot: store.snapshot, mosaicID: mosaicID)
        let mosaic = documents.first { $0.role == .mosaic }
        let pursuit = documents.first { $0.role == .pursuit }
        let pages = documents.filter { $0.role == .page }

        #expect(mosaic?.id == mosaicID)
        #expect(mosaic?.parentID == nil)
        #expect(mosaic?.visibility == "private")
        #expect(pursuit?.parentID == nil)
        #expect(pursuit?.visibility == "private")
        #expect(pursuit?.body.blocks.contains { $0.kind == .text } == true)
        #expect(pages.count == 2)
        #expect(pages.allSatisfy { $0.parentID == pursuit?.id } == true)
        #expect(documents.allSatisfy { $0.visibility == "private" })
    }

    @Test
    func pruneAndDeadIDsDropBoardsNothingPointsAt() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let pursuitBlockID = store.addBlock(.pursuit, to: nil)
        let pursuitID = store.block(with: pursuitBlockID, in: nil)?.pursuitID
        let scrapbookID = store.addBlock(.scrapbook, to: pursuitID)
        let pageIDs = store.block(with: scrapbookID, in: pursuitID)?.scrapbookPageIDs ?? []
        #expect(pageIDs.count == 2)

        store.deleteBlock(pursuitBlockID, in: nil)
        #expect(store.snapshot.pursuits.isEmpty)
        #expect(pageIDs.allSatisfy { store.pursuit(for: $0) == nil })

        var orphaned = ComposerSnapshot.empty
        let live = ComposerDocumentID()
        let deadPage = ComposerDocumentID()
        orphaned.pursuits = [
            ComposerPursuit(id: live, title: "Gym", blocks: [], role: .pursuit),
            ComposerPursuit(id: deadPage, title: "Page 7", blocks: [], role: .page)
        ]
        orphaned.mosaicBlocks = [
            {
                var block = ComposerBlock.make(kind: .pursuit, position: BlockPosition(x: 0.2, y: 0.2))
                block.pursuitID = live
                return block
            }()
        ]
        let removed = ComposerBoardSync.pruneUnreferenced(&orphaned)
        #expect(removed == [deadPage])
        #expect(orphaned.pursuits.map(\.id) == [live])

        let mosaicID = UUID()
        let liveUUID = UUID(uuidString: live.rawValue) ?? UUID()
        let deadUUID = UUID(uuidString: deadPage.rawValue) ?? UUID()
        let dead = ComposerBoardSync.deadIDs(
            live: [mosaicID, liveUUID],
            remote: [mosaicID, liveUUID, deadUUID],
            mosaicID: mosaicID
        )
        #expect(dead == [deadUUID])

        let base = URL(string: "https://example.supabase.co")!
        let owner = UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!
        let listed = SupabaseDocumentSync.ownDocumentsURL(base: base, ownerID: owner)
        #expect(listed.absoluteString.contains("owner_id=eq.00000000-0000-0000-0000-00000000000a"))
        let deleteURL = SupabaseDocumentSync.deleteDocumentsURL(base: base, ids: [deadUUID])
        #expect(deleteURL.absoluteString.contains("id=in.(\(deadUUID.uuidString.lowercased()))"))
    }

    @Test
    func eachAccountKeepsItsOwnBoards() throws {
        let synced = UUID()
        #expect(ComposerLegacyStorage.shouldClaim(legacyMosaicID: synced, serverMosaicID: synced))
        #expect(!ComposerLegacyStorage.shouldClaim(legacyMosaicID: synced, serverMosaicID: nil))
        #expect(!ComposerLegacyStorage.shouldClaim(legacyMosaicID: synced, serverMosaicID: UUID()))
        #expect(ComposerLegacyStorage.shouldClaim(legacyMosaicID: nil, serverMosaicID: nil))
        #expect(!ComposerLegacyStorage.shouldClaim(legacyMosaicID: nil, serverMosaicID: UUID()))

        #expect(ComposerSyncState.mayPush(local: nil, remote: nil))
        #expect(ComposerSyncState.mayPush(local: synced, remote: synced))
        #expect(!ComposerSyncState.mayPush(local: nil, remote: synced))
        #expect(!ComposerSyncState.mayPush(local: UUID(), remote: synced))

        let first = UUID()
        let second = UUID()
        #expect(ComposerStorageLocation.account(first).root != ComposerStorageLocation.account(second).root)
        #expect(ComposerStorageLocation.account(first).root.path.hasSuffix("Accounts/\(first.uuidString.lowercased())"))

        let fileManager = FileManager.default
        let temp = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: temp) }
        let legacy = ComposerStorageLocation(root: temp)
        let target = ComposerStorageLocation(root: temp.appendingPathComponent("Accounts/a", isDirectory: true))
        try fileManager.createDirectory(at: legacy.mediaDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy.snapshotURL)
        try fileManager.createDirectory(at: target.root, withIntermediateDirectories: true)
        try JSONEncoder().encode(ComposerSnapshot.empty).write(to: target.snapshotURL)
        #expect(ComposerLegacyStorage.isBlank(target, fileManager: fileManager))
        try Data("jpg".utf8).write(to: legacy.mediaDirectory.appendingPathComponent("day.jpg"))
        let state = ComposerSyncState(mosaicID: synced)
        try JSONEncoder().encode(state).write(to: legacy.syncStateURL)
        #expect(ComposerLegacyStorage.legacyMosaicID(in: legacy) == synced)

        #expect(try ComposerLegacyStorage.claim(from: legacy, to: target, fileManager: fileManager))
        #expect(fileManager.fileExists(atPath: target.snapshotURL.path))
        #expect(fileManager.fileExists(atPath: target.mediaDirectory.appendingPathComponent("day.jpg").path))
        #expect(fileManager.fileExists(atPath: target.syncStateURL.path))
        #expect(!fileManager.fileExists(atPath: legacy.snapshotURL.path))
        #expect(try !ComposerLegacyStorage.claim(from: legacy, to: target, fileManager: fileManager))

        let store = ComposerStore(fileManager: fileManager, persistToDisk: true, location: target)
        #expect(store.mediaURL(for: "day.jpg") == target.mediaDirectory.appendingPathComponent("day.jpg"))
    }

    @Test
    func assembleRestoresTheBoards() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        store.addBlock(.text, to: nil)
        let pursuitBlockID = store.addBlock(.pursuit, to: nil)
        let pursuitID = store.block(with: pursuitBlockID, in: nil)?.pursuitID
        store.addBlock(.heading, to: pursuitID)

        let mosaicID = UUID()
        let documents = ComposerBoardSync.split(snapshot: store.snapshot, mosaicID: mosaicID)
        let restored = ComposerBoardSync.assemble(mosaicID: mosaicID, documents: documents)

        #expect(restored?.mosaicTitle == store.snapshot.mosaicTitle)
        #expect(restored?.mosaicBlocks.map(\.kind) == store.snapshot.mosaicBlocks.map(\.kind))
        #expect(restored?.pursuits.count == 1)
        #expect(restored?.pursuits.first?.blocks.map(\.kind) == [.heading])
    }

    @Test
    func saveBodyCarriesTheExpectedRevision() throws {
        let mosaicID = UUID()
        let document = ComposerSyncDocument(
            id: mosaicID,
            parentID: nil,
            role: .mosaic,
            title: "Mosaic",
            visibility: "private",
            body: ComposerBoardBody(
                blocks: [],
                layoutHeight: nil,
                background: nil,
                mosaicTitlePlaced: false,
                pursuitPagesBlanked: false
            )
        )
        let body = try SupabaseDocumentSync.saveBody(
            ComposerDocumentPush(document: document, expectedRevision: 4)
        )
        #expect((body["p_expected_revision"] as? NSNumber)?.int64Value == 4)
        #expect(body["p_role"] as? String == "mosaic")
        #expect(body["p_id"] as? String == mosaicID.uuidString.lowercased())
        #expect(body["p_parent_id"] is NSNull)
    }

    @Test
    func revisionParserReadsTheRpcRow() throws {
        let data = Data(#"[{"revision": 3}]"#.utf8)
        #expect(try SupabaseDocumentSync.revision(from: data) == 3)
        #expect(SupabaseDocumentSync.error(from: Data("revision conflict".utf8), status: 400) == .revisionConflict)
        #expect(SupabaseDocumentSync.mosaicID(from: Data("null".utf8)) == nil)
        #expect(
            SupabaseDocumentSync.mosaicID(from: Data(#""65c2a70f-dfb3-40a0-a76c-96a6e721fd22""#.utf8))
                == UUID(uuidString: "65C2A70F-DFB3-40A0-A76C-96A6E721FD22")
        )
    }

    @Test
    func authSessionReadsTheTokenPayload() throws {
        let userID = UUID()
        let json = """
        {"access_token":"access","refresh_token":"refresh","expires_in":3600,"user":{"id":"\(userID.uuidString)"}}
        """
        let now = Date(timeIntervalSince1970: 1_000)
        let session = try MosaicAuthResponse.session(from: Data(json.utf8), now: now)
        #expect(session.accessToken == "access")
        #expect(session.userID == userID)
        #expect(session.expiresAt == now.addingTimeInterval(3600))
        #expect(MosaicPKCE.challenge(for: "hello-verifier-hello-verifier-hello-verif") == "My6Ou2QRvR7J1v2W65mBNajT_v3bz6dH3B4oolrqrKQ")
    }

    @Test
    func remoteMosaicIDWinsWhenTheServerAlreadyHasOne() {
        let remote = UUID()
        #expect(ComposerSyncState.choosingMosaicID(local: UUID(), remote: remote) == remote)
        let local = UUID()
        #expect(ComposerSyncState.choosingMosaicID(local: local, remote: nil) == local)
    }

    @Test
    func mediaUploadKeepsADisplayCopyAndCapsVideoLength() throws {
        let wide = ComposerMediaScale.fitted(width: 4000, height: 2000, longEdge: ComposerMediaScale.displayLongEdge)
        #expect(wide.width == 2560)
        #expect(wide.height == 1280)
        let small = ComposerMediaScale.fitted(width: 300, height: 200, longEdge: ComposerMediaScale.thumbLongEdge)
        #expect(small == (width: 300, height: 200))
        #expect(ComposerMediaScale.videoMilliseconds(seconds: 3.2) == 3200)
        #expect(ComposerMediaScale.videoMilliseconds(seconds: 15) == nil)

        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let mediaID = store.addBlock(.media, to: nil)
        var media = try #require(store.block(with: mediaID, in: nil))
        media.mediaFileName = "day.jpg"
        store.updateBlock(media, in: nil)
        let groupID = store.addBlock(.group, to: nil)
        var grouped = try #require(store.block(with: groupID, in: nil))
        var inside = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0.1, y: 0.1))
        inside.mediaFileName = "inside.jpg"
        grouped.groupMembers = [inside]
        store.updateBlock(grouped, in: nil)

        let mosaicID = UUID()
        let found = ComposerMediaCatalog.references(snapshot: store.snapshot, mosaicID: mosaicID)
        #expect(found.map(\.fileName) == ["day.jpg", "inside.jpg"])
        #expect(found.allSatisfy { $0.documentID == mosaicID })

        let owner = UUID()
        let asset = UUID()
        let path = ComposerMediaCatalog.objectPath(ownerID: owner, assetID: asset, name: "original")
        #expect(path == "\(owner.uuidString.lowercased())/\(asset.uuidString.lowercased())/original")

        let documents = ComposerBoardSync.split(snapshot: store.snapshot, mosaicID: mosaicID)
        let stamped = ComposerMediaCatalog.stamped(documents, assets: ["day.jpg": asset.uuidString, "other.png": UUID().uuidString])
        #expect(stamped.first?.body.mediaAssets?.keys.contains("day.jpg") == true)
        #expect(stamped.first?.body.mediaAssets?["other.png"] == nil)

        let state = try JSONDecoder().decode(
            ComposerSyncState.self,
            from: Data(#"{"mosaicID":"00000000-0000-0000-0000-000000000001","revisions":{"a":1}}"#.utf8)
        )
        #expect(state.mediaAssets.isEmpty)
        #expect(state.revisions["a"] == 1)
    }

    @Test
    func settingsListUsesLocalTitlesAndServerPrivacy() {
        let mosaicID = UUID()
        let synced = UUID()
        let waiting = UUID()
        var snapshot = ComposerSnapshot.empty
        snapshot.mosaicTitle = "  Studio  "
        snapshot.pursuits = [
            ComposerPursuit(id: ComposerDocumentID(rawValue: synced.uuidString), title: "Golf", blocks: []),
            ComposerPursuit(id: ComposerDocumentID(rawValue: waiting.uuidString), title: "", blocks: [])
        ]
        let listed = MosaicSettingsList.rows(
            snapshot: snapshot,
            remote: [
                MosaicRemoteBoard(id: mosaicID, role: "mosaic", title: "Server", isPublic: true),
                MosaicRemoteBoard(id: synced, role: "pursuit", title: "Old", isPublic: false)
            ]
        )
        #expect(listed.mosaic?.title == "Studio")
        #expect(listed.mosaic?.isPublic == true)
        #expect(listed.mosaic?.canChange == true)
        #expect(listed.pursuits.map(\.title) == ["Golf", "Pursuit"])
        #expect(listed.pursuits.map(\.canChange) == [true, false])
        #expect(MosaicSettingsList.displayName(from: "  Ada Lovelace  ") == "Ada Lovelace")
    }

    @Test
    func usernameFollowsTheServerRule() {
        #expect(MosaicSettingsList.username(from: "  @Ada_Golf ") == "ada_golf")
        #expect(MosaicSettingsList.typedUsername("@@Ada_Golf") == "ada_golf")
        #expect(MosaicSettingsList.usernameProblems("ada_golf").isEmpty)
        #expect(MosaicSettingsList.usernameProblems("ab") == ["Use at least 3 characters."])
        #expect(MosaicSettingsList.usernameProblems(String(repeating: "a", count: 21)) == ["Use 20 characters or fewer."])
        #expect(MosaicSettingsList.usernameProblems("a-") == [
            "Use at least 3 characters.",
            "Use only letters, numbers, and underscores."
        ])
        #expect(MosaicSettingsList.usernameProblems("ada golf") == ["Use only letters, numbers, and underscores."])
        let lookup = MosaicSettingsClient.usernameURL(base: URL(string: "https://example.supabase.co")!, username: "ada_golf")
        #expect(lookup.absoluteString == "https://example.supabase.co/rest/v1/profiles?username=eq.ada_golf&select=id")
        #expect(MosaicSettingsClient.usernameError(status: 409, body: Data()) == .taken)
        #expect(MosaicSettingsClient.usernameError(status: 400, body: Data(#"{"code":"23505"}"#.utf8)) == .taken)
        #expect(MosaicSettingsClient.usernameError(status: 400, body: Data(#"{"code":"23514"}"#.utf8)) == .failed)
    }

    @Test
    func configIgnoresEmptyKeys() {
        #expect(SupabaseSyncConfig.current(bundle: Bundle(for: EmptyBundleToken.self), environment: [:]) == nil)
        let config = SupabaseSyncConfig.current(
            bundle: Bundle(for: EmptyBundleToken.self),
            environment: [
                "SUPABASE_URL": "https://example.supabase.co",
                "SUPABASE_ANON_KEY": "anon"
            ]
        )
        #expect(config?.anonKey == "anon")
        #expect(config?.url.absoluteString == "https://example.supabase.co")
    }
}

private final class EmptyBundleToken: NSObject {}

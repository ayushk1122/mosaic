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

import Foundation
import Testing

@testable import Mosaic

@MainActor
@Suite
struct ComposerSyncEdgeCaseTests {
    @Test
    func unchangedBoardsHashTheSameAndEditsDoNot() {
        let body = ComposerBoardBody(blocks: [], layoutHeight: 900, background: nil, mosaicTitlePlaced: true, pursuitPagesBlanked: nil)
        let document = ComposerSyncDocument(
            id: UUID(), parentID: nil, role: .pursuit, title: "Golf", visibility: "private", body: body
        )
        #expect(ComposerSyncState.contentHash(of: document) == ComposerSyncState.contentHash(of: document))

        var renamed = document
        renamed.title = "Golf 2"
        #expect(ComposerSyncState.contentHash(of: renamed) != ComposerSyncState.contentHash(of: document))

        var moved = document
        moved.body.layoutHeight = 1200
        #expect(ComposerSyncState.contentHash(of: moved) != ComposerSyncState.contentHash(of: document))
    }

    @Test
    func olderSyncStateDecodesWithoutHashes() throws {
        let id = UUID()
        let json = #"{"mosaicID":"\#(id.uuidString)","revisions":{"a":3},"mediaAssets":{},"pendingRestore":false}"#
        let state = try JSONDecoder().decode(ComposerSyncState.self, from: Data(json.utf8))
        #expect(state.pushedHashes.isEmpty)
        #expect(state.revisions["a"] == 3)
    }

    @Test
    func missingBoardsAreFoundWithTheRoleTheirWidgetImplies() {
        var pursuit = ComposerBlock.make(kind: .pursuit, position: BlockPosition(x: 0, y: 0))
        let pursuitID = ComposerDocumentID()
        pursuit.pursuitID = pursuitID
        var scrapbook = ComposerBlock.make(kind: .scrapbook, position: BlockPosition(x: 0, y: 0))
        let page = ComposerDocumentID()
        scrapbook.scrapbookPageIDs = [page]
        var node = ComposerBlock.make(kind: .node, position: BlockPosition(x: 0, y: 0))
        let nodeID = ComposerDocumentID()
        node.pursuitID = nodeID

        var snapshot = ComposerSnapshot.empty
        snapshot.mosaicBlocks = [pursuit]
        snapshot.pursuits = [ComposerPursuit(id: pursuitID, title: "Golf", blocks: [scrapbook, node], role: .pursuit)]

        let missing = ComposerBoardSync.missingReferences(in: snapshot)
        #expect(missing.count == 2)
        #expect(missing.contains { $0.0 == page && $0.1 == .page })
        #expect(missing.contains { $0.0 == nodeID && $0.1 == .node })
    }

    @Test
    func restoreFinishesWhenTheServerIsMissingAChildBoard() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        var widget = ComposerBlock.make(kind: .pursuit, position: BlockPosition(x: 0.2, y: 0.2))
        let missingID = ComposerDocumentID()
        widget.pursuitID = missingID
        var remote = ComposerSnapshot.empty
        remote.mosaicBlocks = [widget]
        store.replacePage([widget], in: nil)

        try store.finishRestoring(snapshot: remote, state: ComposerSyncState(mosaicID: UUID()))
        #expect(store.pursuit(for: missingID)?.role == .pursuit)
        #expect(!store.isRestoringDocuments)
    }
}

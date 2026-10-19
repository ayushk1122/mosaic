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
    func followerSearchMatchesNamesAndUsernames() {
        let person = MosaicCirclePerson(kind: .follower, personID: UUID(), username: "jose_golf", displayName: "José Ramírez")
        #expect(person.matches(""))
        #expect(person.matches("jose"))
        #expect(person.matches("RAMIREZ"))
        #expect(person.matches("@jose_g"))
        #expect(person.matches("  golf "))
        #expect(!person.matches("ada"))
    }

    @Test
    func followerFiltersSortAndNarrowTheList() throws {
        func person(_ name: String, daysAgo: Double?, iFollow: Bool) -> MosaicCirclePerson {
            var row = MosaicCirclePerson(kind: .follower, personID: UUID(), username: name, displayName: name)
            row.iFollow = iFollow
            row.followedAt = daysAgo.map { Date(timeIntervalSince1970: 1_000_000 - $0 * 86_400) }
            return row
        }
        let people = [
            person("old", daysAgo: 30, iFollow: true),
            person("new", daysAgo: 1, iFollow: false),
            person("undated", daysAgo: nil, iFollow: false),
            person("mid", daysAgo: 10, iFollow: true)
        ]
        #expect(MosaicFollowerFilter.latest.apply(to: people).map(\.username) == ["new", "mid", "old", "undated"])
        #expect(MosaicFollowerFilter.earliest.apply(to: people).map(\.username) == ["undated", "old", "mid", "new"])
        #expect(MosaicFollowerFilter.following.apply(to: people).map(\.username) == ["mid", "old"])
        #expect(MosaicFollowerFilter.notFollowing.apply(to: people).map(\.username) == ["new", "undated"])

        let json = Data(#"[{"kind":"follower","person_id":"\#(UUID().uuidString)","username":"ada","created_at":"2026-10-18T22:10:08.615722+00:00","i_follow":true}]"#.utf8)
        let parsed = try #require(try MosaicCircleClient.people(from: json).first)
        #expect(parsed.followedAt != nil)
        #expect(parsed.iFollow)
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

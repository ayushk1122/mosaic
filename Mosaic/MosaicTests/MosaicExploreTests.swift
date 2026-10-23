import CoreGraphics
import Foundation
import Testing
@testable import Mosaic

@MainActor
struct MosaicExploreTests {
    private func row(_ level: MosaicVisibilityLevel, explore: Bool = false, canChange: Bool = true) -> MosaicVisibilityRow {
        MosaicVisibilityRow(id: UUID(), title: "Golf", level: level, canChange: canChange, explore: explore)
    }

    @Test
    func onlyPublicBoardsOnAPublicMosaicCanBeShared() {
        #expect(MosaicSettingsList.canShareToExplore(row(.public), mosaicLevel: .public))
        #expect(!MosaicSettingsList.canShareToExplore(row(.public), mosaicLevel: .private), "a private Mosaic keeps its Pursuits out")
        #expect(!MosaicSettingsList.canShareToExplore(row(.private), mosaicLevel: .public))
        #expect(!MosaicSettingsList.canShareToExplore(row(.hidden), mosaicLevel: .public))
        #expect(!MosaicSettingsList.canShareToExplore(row(.public, canChange: false), mosaicLevel: .public),
                "a board not on the server yet can't be shared")
    }

    @Test
    func onlyExploreChoicesSinceTheLastSaveAreSent() {
        let shared = row(.public, explore: true)
        let kept = row(.public, explore: false)
        var saved = MosaicSettingsList.savedExplore([shared, kept])
        #expect(MosaicSettingsList.changedExplore([shared, kept], saved: saved).isEmpty)
        var turnedOff = shared
        turnedOff.explore = false
        #expect(MosaicSettingsList.changedExplore([turnedOff, kept], saved: saved).map(\.id) == [shared.id])
        saved[shared.id] = false
        #expect(MosaicSettingsList.changedExplore([turnedOff, kept], saved: saved).isEmpty)
    }

    @Test
    func rowsCarryEachBoardsExploreSharing() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let widget = store.addBlock(.pursuit, to: nil)
        let pursuit = try #require(store.block(with: widget, in: nil)?.pursuitID.flatMap(ComposerBoardSync.uuid))
        let mosaicID = UUID()
        let listed = MosaicSettingsList.rows(snapshot: store.snapshot, remote: [
            MosaicRemoteBoard(id: mosaicID, role: "mosaic", title: "Mosaic", level: .public, explore: true),
            MosaicRemoteBoard(id: pursuit, role: "pursuit", title: "Golf", level: .public, explore: false),
        ])
        #expect(listed.mosaic?.explore == true)
        #expect(listed.pursuits.first { $0.id == pursuit }?.explore == false)
    }

    @Test
    func feedRowsBecomeTilesWithTheRightCaption() throws {
        let owner = UUID(), board = UUID()
        let mosaic = try #require(MosaicExploreItem(row: [
            "document_id": board.uuidString, "role": "mosaic", "title": "Mosaic", "owner_id": owner.uuidString,
            "username": "ada", "display_name": "Ada Lovelace", "avatar_path": "a.jpg", "preview_path": "p/display",
        ]))
        #expect(mosaic.caption == "Ada Lovelace")
        #expect(mosaic.target.pursuitID == nil)
        #expect(mosaic.target.person.id == owner)

        let pursuit = try #require(MosaicExploreItem(row: [
            "document_id": board.uuidString, "role": "pursuit", "title": "Golf", "owner_id": owner.uuidString,
            "username": "ada", "display_name": NSNull(), "preview_path": "p/display",
        ]))
        #expect(pursuit.caption == "ada: Golf", "falls back to the username without a display name")
        #expect(pursuit.target.pursuitID == board, "a Pursuit tile opens on that Pursuit")
        #expect(pursuit.ownerTarget.pursuitID == nil, "its owner's picture opens their whole Mosaic")
        #expect(pursuit.ownerTarget.person.id == owner)
        #expect(pursuit.followerCount == 0, "a missing count reads as none")

        #expect(MosaicExploreItem(row: ["document_id": board.uuidString, "role": "node"]) == nil)
    }

    @Test
    func feedAsksForOnePageWithTheFilterAndSeed() async throws {
        ExploreFeedProtocol.reply = Data(#"[{"document_id":"6c1f7a4e-0b39-4a52-9d6e-0f9b1c2d3e4f","role":"pursuit","title":"Golf","owner_id":"7c1f7a4e-0b39-4a52-9d6e-0f9b1c2d3e4f","username":"ada","display_name":"Ada","avatar_path":null,"preview_path":"x/y/display","follower_count":4},{"role":"broken"}]"#.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExploreFeedProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = MosaicExploreClient(
            config: SupabaseSyncConfig(url: URL(string: "https://explore.invalid")!, anonKey: "key"),
            session: session
        )
        let page = try await client.feed(filter: .pursuits, sort: .popular, hideFollowed: true, query: "  golf ",
                                         seed: "abc", offset: 30, accessToken: "token")
        #expect(page.map(\.caption) == ["Ada: Golf"], "rows that don't parse are skipped")
        #expect(page.first?.followerCount == 4)
        let request = try #require(ExploreFeedProtocol.lastRequest)
        #expect(request.url?.path == "/rest/v1/rpc/explore_feed")
        let body = try #require(ExploreFeedProtocol.lastBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["p_kind"] as? String == "pursuits")
        #expect(body["p_seed"] as? String == "abc")
        #expect(body["p_offset"] as? Int == 30)
        #expect(body["p_limit"] as? Int == MosaicExploreClient.pageSize)
        #expect(body["p_query"] as? String == "golf", "the search is sent trimmed")
        #expect(body["p_sort"] as? String == "popular")
        #expect(body["p_hide_followed"] as? Bool == true)
        #expect(MosaicExploreClient.Sort.allCases.map(\.rawValue)
                == ["shuffle", "trending", "popular", "least_popular", "newest", "updated"], "the names the server sorts by")
    }

    @Test
    func profileCardsReadTheFollowerCountOnlyWhenGiven() throws {
        let open = try #require(try MosaicVisitClient.profile(from: Data(#"[{"user_id":"7c1f7a4e-0b39-4a52-9d6e-0f9b1c2d3e4f","username":"ada","can_view":true,"follows_mosaic":true,"follower_count":12}]"#.utf8)))
        #expect(open.followerCount == 12)
        #expect(open.followsMosaic)
        let closed = try #require(try MosaicVisitClient.profile(from: Data(#"[{"user_id":"7c1f7a4e-0b39-4a52-9d6e-0f9b1c2d3e4f","username":"ada","can_view":false,"follower_count":null}]"#.utf8)))
        #expect(closed.followerCount == nil, "a private Mosaic's count isn't shown")
    }

    @Test
    func previewsFrameTheirPiecesAtThreeByFour() {
        let board = CGSize(width: 400, height: 800)
        let empty = MosaicBoardPreviewRenderer.crop(around: nil, in: board)
        #expect(empty == CGRect(x: 0, y: 0, width: 400, height: CGFloat(400) * 4 / 3), "an empty board shows its top")

        let small = MosaicBoardPreviewRenderer.crop(around: CGRect(x: 300, y: 500, width: 60, height: 60), in: board)
        #expect(small.width == 240, "never closer than 60% of the board's width")
        #expect(small.height == 320)
        #expect(small.maxX == 400, "kept on the board")
        #expect(small.midY == 530, "a short group sits in the middle")

        let tall = MosaicBoardPreviewRenderer.crop(around: CGRect(x: 20, y: 100, width: 200, height: 700), in: board)
        #expect(tall.width == 400, "never wider than the board")
        #expect(tall.minY == 86, "tall content shows from its top, with a margin")

        let wide = MosaicBoardPreviewRenderer.crop(around: CGRect(x: 20, y: 40, width: 300, height: 100), in: board)
        #expect(wide.width == 328, "the content and a margin each side")
        #expect(wide.midX == 170)
    }

    @Test
    func previewContentIsWhatLandsOnTheBoard() {
        let frames = MosaicBoardPreviewFrames()
        #expect(frames.content(in: CGSize(width: 400, height: 800)) == nil)
        frames.rects[ComposerBlockID()] = CGRect(x: -50, y: 10, width: 100, height: 100)
        frames.rects[ComposerBlockID()] = CGRect(x: 200, y: 300, width: 100, height: 50)
        frames.rects[ComposerBlockID()] = CGRect(x: 100, y: 900, width: 100, height: 100)
        #expect(frames.content(in: CGSize(width: 400, height: 800)) == CGRect(x: 0, y: 10, width: 300, height: 340),
                "trimmed to the board, and pieces off its bottom are left out")
    }
}

private final class ExploreFeedProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var reply = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            return data
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.reply)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

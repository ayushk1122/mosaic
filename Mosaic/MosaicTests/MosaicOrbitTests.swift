import CoreGraphics
import Foundation
import Testing
@testable import Mosaic

@MainActor
struct MosaicOrbitTests {
    private func pieces(_ kinds: String...) -> [MosaicOrbitItem.Piece] {
        kinds.enumerated().map { MosaicOrbitItem.Piece(id: "\($0.offset)", piece: "\($0.offset)", kind: $0.element) }
    }

    @Test
    func updatesAreSummedUpInWords() {
        #expect(MosaicOrbitText.summary(of: pieces("media")) == "added a photo")
        #expect(MosaicOrbitText.summary(of: pieces("media", "media", "media", "text")) == "added 3 photos and a note")
        #expect(MosaicOrbitText.summary(of: pieces("drawing", "media", "page")) == "added a drawing, a photo, and a page")
        #expect(MosaicOrbitText.summary(of: pieces("somethingNewer")) == "added a piece")
        #expect(MosaicOrbitText.summary(of: []) == "added something new")
        #expect(MosaicOrbitText.summary(of: pieces("photo", "photo", "writing", "checked"))
                == "added 2 photos, wrote in a note, and checked off an item")
        #expect(MosaicOrbitText.summary(of: pieces("checked", "checked")) == "checked off 2 items")
        #expect(MosaicOrbitText.summary(of: pieces("cell", "cell", "banner")) == "added 2 table entries and a banner photo")
    }

    @Test
    func agesAreShort() {
        let now = Date(timeIntervalSince1970: 100_000)
        #expect(MosaicOrbitText.age(of: now.addingTimeInterval(-20), now: now) == "now")
        #expect(MosaicOrbitText.age(of: now.addingTimeInterval(-300), now: now) == "5m")
        #expect(MosaicOrbitText.age(of: now.addingTimeInterval(-7_500), now: now) == "2h")
    }

    @Test
    func feedRowsBecomeBoardsThatOpenWhereTheyChanged() throws {
        let board = UUID(), owner = UUID()
        let pursuit = try #require(MosaicOrbitItem(row: [
            "board_id": board.uuidString, "role": "pursuit", "title": "Golf", "owner_id": owner.uuidString,
            "username": "ada", "display_name": "Ada", "latest_at": "2026-10-22T21:49:12.123456+00:00",
            "pieces": [
                ["id": "ABC-1", "kind": "media"],
                ["id": "car/card/two", "piece": "CAR", "kind": "photo", "in": ["a0000000-0000-0000-0000-000000000003"]],
            ],
            "seen": false,
        ]))
        #expect(pursuit.heading == "Ada · Golf")
        #expect(pursuit.target.pursuitID == board)
        #expect(pursuit.addresses == ["abc-1", "car/card/two"], "where each change is, lowercased as boards store ids")
        #expect(pursuit.newBoardIDs == [UUID(uuidString: "a0000000-0000-0000-0000-000000000003")!],
                "and the node the change sits in, so its widget is marked")
        #expect(!pursuit.seen)

        let mosaic = try #require(MosaicOrbitItem(row: [
            "board_id": board.uuidString, "role": "mosaic", "title": "", "owner_id": owner.uuidString,
            "username": "ada", "display_name": NSNull(), "latest_at": "2026-10-22T21:49:12+00:00",
            "pieces": [], "seen": true,
        ]))
        #expect(mosaic.heading == "ada")
        #expect(mosaic.target.pursuitID == nil)
        #expect(MosaicOrbitItem(row: ["board_id": board.uuidString, "role": "page"]) == nil)
    }

    @Test
    func changesKnowWhereTheyAre() {
        let card = MosaicOrbitItem.Piece(id: "car/carouselitems/ABC", piece: "car", kind: "media")
        #expect(card.address == "car/carouselitems/abc")
        #expect(card.seenKey == "car/carouselitems/abc")
        let swapped = MosaicOrbitItem.Piece(id: "pic#file:mediaFileName", piece: "pic", kind: "photo")
        #expect(swapped.address == "pic", "a change names where it is, not what kind it was")
        let note = MosaicOrbitItem.Piece(id: "cal/calendarentries/2026-10-22#text:note", piece: "cal", kind: "writing")
        #expect(note.address == "cal/calendarentries/2026-10-22")

        let item = MosaicOrbitItem(
            id: UUID(), role: .pursuit, title: "Golf",
            owner: MosaicPersonResult(id: UUID(), username: "ada", displayName: ""),
            latestAt: .now, pieces: [card, swapped, note], seen: false
        )
        #expect(item.addresses == ["car/carouselitems/abc", "pic", "cal/calendarentries/2026-10-22"])
        #expect(item.addedAddresses == ["car/carouselitems/abc"], "a swapped photo and more writing were changes, not additions")
        #expect(MosaicOrbitText.summary(of: [
            MosaicOrbitItem.Piece(id: "l/listitems/a", piece: "l", kind: "listitems"),
            MosaicOrbitItem.Piece(id: "g/graphpoints/b", piece: "g", kind: "graphpoints")
        ]) == "added a list item and a graph point")
    }

    @Test
    func addressesReadAsPaths() {
        #expect(ComposerUpdateAddress.lineage(of: "k/calendarentries/2026-03-05/media/p")
                == ["k", "k/calendarentries", "k/calendarentries/2026-03-05",
                    "k/calendarentries/2026-03-05/media", "k/calendarentries/2026-03-05/media/p"])
        #expect(ComposerUpdateAddress.isWithin("c/carouselitems/two", "c"))
        #expect(!ComposerUpdateAddress.isWithin("cc/carouselitems/two", "c"), "a piece whose id starts the same isn't a container")
        #expect(ComposerUpdateAddress.piece(of: "c/carouselitems/two") == "c")
        #expect(ComposerUpdateAddress.day(year: 2026, month: 3, day: 5) == "2026-03-05", "dates as the server writes them")
        #expect(ComposerUpdateAddress.date(of: "2026-03-05").map { [$0.year, $0.month, $0.day] } == [2026, 3, 5])
        #expect(ComposerUpdateAddress.date(of: "carouselitems") == nil)
    }

    private func anchor(y: CGFloat, shown: Bool = true, order: Int = 0) -> ComposerUpdateAnchor {
        ComposerUpdateAnchor(frame: CGRect(x: 0, y: y, width: 100, height: 50), isPresented: shown, order: order)
    }

    private func update(_ address: String, order: Int = 0) -> ComposerUpdateGuide.Plan.Update {
        ComposerUpdateGuide.Plan.Update(
            address: address,
            piece: ComposerBlockID(rawValue: ComposerUpdateAddress.piece(of: address).uppercased()),
            order: order
        )
    }

    @Test
    func eachUpdateGoesToTheDeepestPlaceShowingIt() {
        let plan = ComposerUpdateGuide.Plan(updates: [
            update("car/carouselitems/c"), update("car/carouselitems/a"),
            update("cal/calendarentries/2026-10-22/media/p", order: 1), update("cal/calendarentries/2026-10-22", order: 1),
            update("g/graphpoints/x", order: 2), update("old/card/legacy", order: 3)
        ], added: ["car/carouselitems/c", "car/carouselitems/a", "cal/calendarentries/2026-10-22/media/p", "g/graphpoints/x"])
        let anchors = [
            "car": anchor(y: 0),
            "car/carouselitems/a": anchor(y: 0, shown: false, order: 0),
            "car/carouselitems/c": anchor(y: 10, order: 2),
            "cal": anchor(y: 200),
            "cal/calendarentries/2026-10-22": anchor(y: 220, shown: false, order: 20261022),
            "g": anchor(y: 400),
            "old": anchor(y: 500)
        ]
        let stops = ComposerUpdateGuide.stops(plan: plan, anchors: anchors)
        #expect(stops.map(\.address) == ["car/carouselitems/a", "car/carouselitems/c", "cal/calendarentries/2026-10-22", "g", "old"],
                "cards in the carousel's own order, whichever is showing; a day's photo and note as one stop")
        #expect(stops[2].covers == ["cal/calendarentries/2026-10-22/media/p", "cal/calendarentries/2026-10-22"])
        #expect(stops[3].covers == ["g/graphpoints/x"], "nothing finer anchored: the piece")
        #expect(stops[4].covers == ["old/card/legacy"], "names from before addresses go to their piece")
        #expect(ComposerUpdateGuide.placement(of: "car/carouselitems/a", anchors: anchors)?.frame.minY == 0,
                "a card turned away is placed at its carousel")
    }

    @Test
    func somethingInsideWhatWasAddedGoesWithIt() {
        let anchors = ["new": anchor(y: 0), "new/carouselitems/x": anchor(y: 0)]
        let added = ComposerUpdateGuide.stops(plan: ComposerUpdateGuide.Plan(
            updates: [update("new"), update("new/carouselitems/x")], added: ["new", "new/carouselitems/x"]
        ), anchors: anchors)
        #expect(added.map(\.address) == ["new"], "a new carousel is one update, not one per card")

        let swapped = ComposerUpdateGuide.stops(plan: ComposerUpdateGuide.Plan(
            updates: [update("new"), update("new/carouselitems/x")], added: ["new/carouselitems/x"]
        ), anchors: anchors)
        #expect(swapped.map(\.address) == ["new", "new/carouselitems/x"],
                "a carousel whose photo changed doesn't swallow a card added to it")
    }

    @Test
    func theNewestAnchorShownWins() {
        var value: [String: ComposerUpdateAnchor] = ["c/carouselitems/a": anchor(y: 0, shown: false)]
        ComposerUpdateAnchorKey.reduce(value: &value) { ["c/carouselitems/a": self.anchor(y: 40)] }
        #expect(value["c/carouselitems/a"]?.isPresented == true, "a card on show beats the carousel's place for it")
        ComposerUpdateAnchorKey.reduce(value: &value) { ["c/carouselitems/a": self.anchor(y: 0, shown: false)] }
        #expect(value["c/carouselitems/a"]?.frame.minY == 40)
    }

    @Test
    func aBoardsProgressCountsItsSeenUpdates() {
        let item = MosaicOrbitItem(
            id: UUID(), role: .pursuit, title: "Golf",
            owner: MosaicPersonResult(id: UUID(), username: "ada", displayName: ""),
            latestAt: .now, pieces: pieces("photo", "photo", "writing", "checked"), seen: false
        )
        #expect(MosaicOrbitModel.progress(of: item, seen: [:]) == 0)
        #expect(MosaicOrbitModel.progress(of: item, seen: seen("0", "2")) == 0.5)
        #expect(MosaicOrbitModel.progress(of: item, seen: seen("0", "1", "2", "3", "elsewhere")) == 1)
    }

    private func seen(_ keys: String..., at time: Date = .now) -> [String: Date] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0, time) })
    }

    private func board(_ title: String, latest: Date, pieces: [MosaicOrbitItem.Piece]) -> MosaicOrbitItem {
        MosaicOrbitItem(
            id: UUID(), role: .pursuit, title: title,
            owner: MosaicPersonResult(id: UUID(), username: "ada", displayName: ""),
            latestAt: latest, pieces: pieces, seen: false
        )
    }

    @Test
    func aDoneBoardStaysDoneUntilSomethingIsAddedAgain() {
        let morning = Date(timeIntervalSince1970: 1_000_000)
        let noon = morning.addingTimeInterval(3 * 3600)
        let note = MosaicOrbitItem.Piece(id: "t#writing", piece: "t", kind: "writing", at: morning)
        let item = board("Golf", latest: morning, pieces: [note])
        #expect(MosaicOrbitModel.progress(of: item, seen: seen("t", at: morning)) == 1, "seen as it was")

        // More written in the same note later the same day: the same change, at a later time.
        let more = MosaicOrbitItem.Piece(id: "t#writing", piece: "t", kind: "writing", at: noon)
        let again = board("Golf", latest: noon, pieces: [more])
        #expect(MosaicOrbitModel.progress(of: again, seen: seen("t", at: morning)) == 0,
                "seeing the earlier version doesn't cover the new one")
        #expect(MosaicOrbitModel.progress(of: again, seen: seen("t", at: noon)) == 1)
        #expect(MosaicOrbitModel.progress(of: board("Golf", latest: morning, pieces: [MosaicOrbitItem.Piece(id: "u", piece: "u", kind: "text")]),
                                         seen: seen("u", at: .distantPast)) == 1,
                "a change from an older server, with no time, counts once seen at all")
    }

    @Test
    func boardsNotDoneComeFirstAndDoneOnesGoLastEachNewestFirst() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let oldDone = board("Old done", latest: now.addingTimeInterval(-7200), pieces: pieces("photo"))
        let newDone = board("New done", latest: now, pieces: pieces("photo"))
        let oldOpen = board("Old open", latest: now.addingTimeInterval(-3600), pieces: pieces("photo"))
        let partly = board("Partly seen", latest: now.addingTimeInterval(-60), pieces: pieces("photo", "photo"))
        let done: Set<UUID> = [oldDone.id, newDone.id]
        let order = MosaicOrbitModel.ordered([oldDone, oldOpen, newDone, partly]) { done.contains($0.id) }
        #expect(order.map(\.title) == ["Partly seen", "Old open", "New done", "Old done"])
    }

    @Test
    func theFeedCarriesTimesCoversAndWhatWasSeen() throws {
        let board = UUID(), owner = UUID()
        let item = try #require(MosaicOrbitItem(row: [
            "board_id": board.uuidString, "role": "pursuit", "title": "Golf",
            "owner_id": owner.uuidString, "username": "ada",
            "latest_at": "2026-10-23T18:00:00.123456+00:00",
            "pieces": [["id": "t#writing", "piece": "T", "kind": "writing", "in": [], "at": "2026-10-23T18:00:00.123456+00:00"]],
            "seen": false,
            "cover_file": "cover.jpg", "cover_asset": "ASSET",
            "seen_keys": ["t": "2026-10-23T18:00:00.123456+00:00"]
        ]))
        #expect(item.pieces.first?.at == ComposerServerTime.date(from: "2026-10-23T18:00:00.123+00:00"))
        #expect(item.cover.coverFile == "cover.jpg" && item.cover.coverAsset == "ASSET")
        #expect(MosaicOrbitModel.progress(of: item, seen: item.seenThrough) == 1,
                "what another device saw counts here, at the same precision")
    }

    @Test
    func theTrailKeepsItsCirclesAndScrollsWhenBoardsDontFit() {
        #expect(MosaicOrbitTrail.lineLength(boards: 2, width: 380) > MosaicOrbitTrail.shortestLine, "a few boards share the width")
        #expect(MosaicOrbitTrail.lineLength(boards: 30, width: 380) == MosaicOrbitTrail.shortestLine, "many keep their length and scroll")
    }

    @Test
    func aGuideForgetsWhatsNewAgainSoItIsReportedOnceMore() {
        var reports: [Set<String>] = []
        let guide = ComposerUpdateGuide(seen: ["t"])
        guide.onSeen = { reports.append($0) }
        guide.markSeen(["t"])
        #expect(reports.isEmpty)
        guide.resetSeen([])
        guide.markSeen(["t"])
        #expect(reports == [["t"]])
    }

    @Test
    func theGuideWalksIntoANodeAndBackOutThenOnToTheNextBoard() {
        let node = UUID()
        let golf = ComposerUpdateGuide.Plan(
            updates: [update("a"), update("z", order: 2)],
            openers: [.init(piece: ComposerBlockID(rawValue: "N"), board: node, opens: true, order: 1)]
        )
        var finished = 0
        var seenReports: [Set<String>] = []
        let guide = ComposerUpdateGuide(seen: ["a"])
        guide.onFinished = { finished += 1 }
        guide.onSeen = { seenReports.append($0) }

        guide.show(board: "golf", plan: golf)
        #expect(guide.label == "3 updates")
        guide.next()
        #expect(guide.request?.address == "a" && guide.request?.opens == false)
        #expect(guide.label == "1 of 3")
        guide.next()
        #expect(guide.request?.address == "n" && guide.request?.opens == false)
        guide.next()
        #expect(guide.request?.piece.rawValue == "N" && guide.request?.opens == true, "the node's updates come next, inside it")

        // The node opens and takes over, then hands back when it's done.
        guide.show(board: "node", plan: ComposerUpdateGuide.Plan(updates: [update("in")]))
        #expect(!guide.isAtRoot)
        guide.next()
        #expect(guide.request?.address == "in")
        #expect(guide.isAtEnd)
        let leaves = guide.leaveCount
        guide.next()
        #expect(guide.leaveCount == leaves + 1, "past its last update, the node closes")

        guide.show(board: "golf", plan: golf)
        #expect(guide.label == "2 of 3", "back where it was")
        guide.next()
        #expect(guide.request?.address == "z", "the node isn't opened twice")
        #expect(guide.isAtEnd)
        guide.next()
        #expect(finished == 1, "past the board's last update, on to the next board")

        guide.previous()
        #expect(guide.request?.address == "n")
        #expect(seenReports == [[node.uuidString.lowercased()], ["in"], ["z"]],
                "reaching a stop sees what it covers, and only what's newly seen is reported")
    }

    @Test
    func reachingADayChecksOffEverythingOnIt() {
        let guide = ComposerUpdateGuide()
        guide.show(board: "golf", plan: ComposerUpdateGuide.Plan(updates: [
            update("cal/calendarentries/2026-10-22/media/p"), update("cal/calendarentries/2026-10-22")
        ]))
        guide.setAnchors([
            "cal": anchor(y: 0),
            "cal/calendarentries/2026-10-22": anchor(y: 0, shown: false, order: 20261022)
        ], board: "golf")
        guide.next()
        #expect(guide.request?.address == "cal/calendarentries/2026-10-22", "the calendar turns to the day")
        #expect(guide.request?.piece.rawValue == "CAL")
        #expect(guide.seen == ["cal/calendarentries/2026-10-22/media/p", "cal/calendarentries/2026-10-22"],
                "the day's photo and note are checked off without opening the day")
    }

    @Test
    func theHostHoldingAnAddressMostCloselyRevealsIt() {
        let guide = ComposerUpdateGuide()
        guide.show(board: "golf", plan: ComposerUpdateGuide.Plan(updates: [update("car/carouselitems/two")]))
        var revealed: [String] = []
        guide.registerHost(.init(claim: { $0.hasPrefix("car/carouselitems/") ? 4 : nil },
                                 reveal: { revealed.append("carousel " + $0) }), id: "carousel:car", board: "golf")
        guide.registerHost(.init(claim: { _ in 0 }, reveal: { revealed.append("tabs " + $0) }), id: "tabs", board: "golf")
        guide.registerHost(.init(claim: { _ in 9 }, reveal: { _ in revealed.append("elsewhere") }), id: "tabs", board: "node")

        guide.host(for: "car/carouselitems/two")?.reveal("car/carouselitems/two")
        guide.host(for: "notes")?.reveal("notes")
        #expect(revealed == ["carousel car/carouselitems/two", "tabs notes"],
                "the carousel turns to its card; the tab set shows a piece on another tab; another board's hosts aren't asked")

        guide.unregisterHost(id: "carousel:car", board: "golf")
        guide.host(for: "car/carouselitems/two")?.reveal("car/carouselitems/two")
        #expect(revealed.last == "tabs car/carouselitems/two", "a carousel off screen no longer answers")
    }

    @Test
    func openingAJournalPageAsksForThatPage() {
        let page = UUID()
        let guide = ComposerUpdateGuide()
        guide.show(board: "golf", plan: ComposerUpdateGuide.Plan(openers: [
            .init(piece: ComposerBlockID(rawValue: "BOOK"), board: page, opens: true, order: 0)
        ]))
        guide.next()
        #expect(guide.request?.opens == false && guide.request?.address == "book", "first the journal is brought into view")
        guide.next()
        #expect(guide.request?.opens == true && guide.request?.board == page, "then it opens on the page with updates")
    }

    @Test
    func theNavigatorCountsPiecesAndStepsThroughWhatsInside() {
        let guide = ComposerUpdateGuide()
        guide.show(board: "golf", plan: ComposerUpdateGuide.Plan(updates: [
            update("car/carouselitems/a"), update("car/carouselitems/b"), update("car/carouselitems/c"),
            update("list", order: 1)
        ]))
        guide.setAnchors([
            "car/carouselitems/a": anchor(y: 0, order: 0), "car/carouselitems/b": anchor(y: 0, shown: false, order: 1),
            "car/carouselitems/c": anchor(y: 0, shown: false, order: 2)
        ], board: "golf")
        #expect(guide.label == "2 updates", "two pieces changed, however many cards are new")
        guide.next()
        #expect(guide.label == "1 of 2" && guide.place == .init(piece: 0, pieces: 2, item: 0, items: 3))
        guide.next()
        guide.next()
        #expect(guide.label == "1 of 2" && guide.place?.item == 2, "still the carousel, on its third new card")
        guide.next()
        #expect(guide.label == "2 of 2" && guide.place?.items == 1)
    }

    @Test
    func hostsOpenWhatTheNavigatorReaches() {
        let guide = ComposerUpdateGuide()
        guide.show(board: "golf", plan: ComposerUpdateGuide.Plan(updates: [update("cal/calendarentries/2026-10-22")]))
        var opened: [String] = []
        guide.registerHost(.init(claim: { $0.hasPrefix("cal/calendarentries/") ? 4 : nil },
                                 reveal: { _ in }, open: { opened.append($0) }), id: "calendar:cal", board: "golf")
        guide.host(for: "cal/calendarentries/2026-10-22")?.open?("cal/calendarentries/2026-10-22")
        #expect(opened == ["cal/calendarentries/2026-10-22"], "the calendar opens the day it was asked for")
        #expect(guide.host(for: "car/carouselitems/a")?.open == nil)
    }

    @Test
    func anchorsAreKeptPerBoard() {
        let guide = ComposerUpdateGuide()
        guide.show(board: "golf", plan: ComposerUpdateGuide.Plan(updates: [update("a")]))
        guide.setAnchors(["a": anchor(y: 300)], board: "golf")
        guide.setAnchors(["in": anchor(y: 10)], board: "node")
        #expect(guide.anchors["a"]?.frame.minY == 300, "a node's anchors don't replace the board's")
        guide.show(board: "node", plan: ComposerUpdateGuide.Plan(updates: [update("in")]))
        #expect(guide.anchors["in"] != nil && guide.anchors["a"] == nil)
    }
}

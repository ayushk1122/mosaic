import Foundation
import Testing
import UIKit
@testable import Mosaic

@MainActor
struct ComposerStoreTests {
    @Test
    func bannerStaysPinnedAcrossTabs() {
        #expect(ComposerBannerMetrics.resized(base: 200, translation: -80) == 120)
        #expect(ComposerBannerMetrics.resized(base: 200, translation: -400) == ComposerBannerMetrics.minimumHeight)
        #expect(ComposerBannerMetrics.resized(base: 200, translation: 400) == ComposerBannerMetrics.maximumHeight)

        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let bannerID = store.addBlock(.banner, to: nil)
        let again = store.addBlock(.banner, to: nil)
        #expect(again == bannerID)
        let banner = store.block(with: bannerID, in: nil)
        #expect(banner?.kind == .banner)
        #expect(banner?.bannerHeight == ComposerBannerMetrics.defaultHeight)
        #expect(banner?.tabID == nil)

        store.addBlock(.tabs, to: nil)
        #expect(store.block(with: bannerID, in: nil)?.tabID == nil)
        let noteID = store.addBlock(.text, to: nil)
        let selected = store.blocks(for: nil).first(where: { $0.kind == .tabs })?.selectedTabID
        #expect(store.block(with: noteID, in: nil)?.tabID == selected)
        #expect(store.blocks(for: nil).filter { $0.kind == .banner }.count == 1)
    }

    @Test
    func cropEdgesResizeOneSideAndRoundTrip() {
        let covered = MediaCropMath.window(contentAspect: 1.5, frameAspect: 1, zoom: 1, panX: 0, panY: 0)
        let framed = MediaCropMath.framing(window: covered, contentAspect: 1.5)
        #expect(abs(framed.frameAspect - 1) < 0.03)
        #expect(abs(framed.zoom - 1) < 0.03)
        #expect(abs(framed.panX) < 0.03)
        #expect(abs(framed.panY) < 0.03)

        let fromRight = MediaCropMath.resized(
            start: MediaCropMath.Window(x: 0, y: 0, width: 1, height: 1),
            edge: .right,
            translation: CGSize(width: -80, height: 0),
            imageSize: CGSize(width: 200, height: 200),
            contentAspect: 1
        )
        #expect(fromRight.x == 0)
        #expect(abs(fromRight.width - 0.6) < 0.03)
        #expect(abs(fromRight.height - 1) < 0.03)

        let fromTop = MediaCropMath.resized(
            start: MediaCropMath.Window(x: 0, y: 0, width: 1, height: 1),
            edge: .top,
            translation: CGSize(width: 0, height: 50),
            imageSize: CGSize(width: 200, height: 200),
            contentAspect: 1
        )
        #expect(fromTop.y > 0.2)
        #expect(abs(fromTop.y + fromTop.height - 1) < 0.03)
        #expect(abs(fromTop.width - 1) < 0.03)
    }

    @Test
    func tableAddsAndRemovesColumnsAndRows() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let pursuitID = store.addBlock(.pursuit, to: nil)
        let pursuit = store.block(with: pursuitID, in: nil)?.pursuitID
        let tableID = store.addBlock(.table, to: pursuit)
        let created = store.block(with: tableID, in: pursuit)
        #expect(created?.text.isEmpty == true)
        #expect(created?.tableColumns.map(\.header) == ["Column 1", "Column 2", "Column 3"])
        #expect(created?.tableRows.count == 3)
        #expect(created?.tableRows.allSatisfy { $0.cells.count == 3 } == true)
        #expect(created?.tableEntries.count == 1)
        #expect(created?.selectedTableEntryID == created?.tableEntries.first?.id)

        store.addTableColumn(to: tableID, in: pursuit)
        #expect(store.block(with: tableID, in: pursuit)?.tableColumns.count == 4)
        #expect(store.block(with: tableID, in: pursuit)?.tableRows.allSatisfy { $0.cells.count == 4 } == true)

        store.removeLastTableColumn(from: tableID, in: pursuit)
        #expect(store.block(with: tableID, in: pursuit)?.tableColumns.count == 3)

        store.addTableRow(to: tableID, in: pursuit)
        #expect(store.block(with: tableID, in: pursuit)?.tableRows.count == 4)

        store.removeLastTableRow(from: tableID, in: pursuit)
        #expect(store.block(with: tableID, in: pursuit)?.tableRows.count == 3)

        for _ in 0..<4 {
            store.removeLastTableColumn(from: tableID, in: pursuit)
            store.removeLastTableRow(from: tableID, in: pursuit)
        }
        #expect(store.block(with: tableID, in: pursuit)?.tableColumns.count == 1)
        #expect(store.block(with: tableID, in: pursuit)?.tableRows.count == 1)
    }

    @Test
    func tableKeepsEarlierEntriesWhenStartingANewOne() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let pursuit = store.block(with: store.addBlock(.pursuit, to: nil), in: nil)?.pursuitID
        let tableID = store.addBlock(.table, to: pursuit)
        guard var table = store.block(with: tableID, in: pursuit) else {
            Issue.record("Missing table")
            return
        }
        let firstID = table.selectedTableEntryID
        table.tableRows[0].cells[0] = "135"
        table.tableEntries[0].rows = table.tableRows
        store.updateBlock(table, in: pursuit)

        store.startTableEntry(on: tableID, in: pursuit)
        let fresh = store.block(with: tableID, in: pursuit)
        #expect(fresh?.tableEntries.count == 2)
        #expect(fresh?.selectedTableEntryID != firstID)
        #expect(fresh?.tableRows[0].cells[0] == "")
        #expect(fresh?.tableEntries.first(where: { $0.id == firstID })?.rows[0].cells[0] == "135")

        store.showTableEntry(firstID ?? "", on: tableID, in: pursuit)
        #expect(store.block(with: tableID, in: pursuit)?.tableRows[0].cells[0] == "135")
        #expect(store.block(with: tableID, in: pursuit)?.selectedTableEntryID == firstID)
    }

    @Test
    func addAndMoveBlocksOnMosaic() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        store.addBlock(.text, to: nil)
        store.addBlock(.heading, to: nil)
        #expect(store.blocks(for: nil).count == 2)

        let second = store.blocks(for: nil)[1]
        store.moveBlock(second.id, direction: .up, in: nil)
        #expect(store.blocks(for: nil)[0].kind == .heading)
    }

    @Test
    func pursuitBlockCreatesPursuitDocument() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        store.addBlock(.pursuit, to: nil)
        let block = store.blocks(for: nil).first
        #expect(block?.kind == .pursuit)
        #expect(store.snapshot.pursuits.count == 1)

        var named = store.blocks(for: nil)[0]
        named.text = "Golf"
        store.updateBlock(named, in: nil)
        #expect(store.blocks(for: nil)[0].text == "Golf")
        #expect(store.snapshot.pursuits[0].title == "Golf")
        #expect(store.title(for: store.snapshot.pursuits[0].id) == "Golf")

        named.pursuitLayout = .tall
        named.pursuitTextX = 0.4
        named.pursuitTextY = 0.2
        named.pursuitShape = .circle
        named.pursuitFill = ComposerRGBColor(red: 0.2, green: 0.4, blue: 0.6)
        named.pursuitImageFileName = "cover.jpg"
        store.updateBlock(named, in: nil)
        let styled = store.blocks(for: nil)[0]
        #expect(styled.pursuitLayout == .tall)
        #expect(styled.pursuitTextX == 0.4)
        #expect(styled.pursuitTextY == 0.2)
        #expect(styled.pursuitShape == .circle)
        #expect(styled.pursuitFill == ComposerRGBColor(red: 0.2, green: 0.4, blue: 0.6))
        #expect(styled.pursuitImageFileName == "cover.jpg")
    }

    @Test
    func addMenuSearchFiltersOptions() {
        let all = BlockMenuOption.menuOptions(matching: "")
        #expect(all.count == BlockMenuOption.allCases.count)

        let mediaOnly = BlockMenuOption.menuOptions(matching: "media")
        #expect(mediaOnly == [.media])

        let none = BlockMenuOption.menuOptions(matching: "zzzz-not-found")
        #expect(none.isEmpty)

        let pursuitPage = BlockMenuOption.menuOptions(matching: "", includingPursuit: false)
        #expect(pursuitPage.count == BlockMenuOption.allCases.count - 1)
        #expect(!pursuitPage.contains(.pursuit))
        #expect(pursuitPage.contains(.carousel))
        #expect(pursuitPage.contains(.calendar))

        let mosaicMenu = BlockMenuOption.menuOptions(
            matching: "",
            includingCalendar: false,
            includingGraph: false,
            includingNode: false,
            includingTable: false
        )
        #expect(!mosaicMenu.contains(.calendar))
        #expect(!mosaicMenu.contains(.graph))
        #expect(!mosaicMenu.contains(.node))
        #expect(!mosaicMenu.contains(.table))
        #expect(mosaicMenu.contains(.pursuit))
        #expect(mosaicMenu.contains(.list))
        #expect(mosaicMenu.contains(.tabs))
        #expect(mosaicMenu.contains(.banner))
        #expect(pursuitPage.contains(.list))
        #expect(pursuitPage.contains(.banner))
        #expect(pursuitPage.contains(.graph))
        #expect(pursuitPage.contains(.node))
        #expect(pursuitPage.contains(.tabs))
        #expect(pursuitPage.contains(.table))
        #expect(mosaicMenu.contains(.background))
        #expect(pursuitPage.contains(.background))

        let folder = BlockMenuOption.menuOptions(matching: "folder")
        #expect(folder == [.node])

        let tabs = BlockMenuOption.menuOptions(matching: "tab")
        #expect(tabs == [.table, .tabs])

        let table = BlockMenuOption.menuOptions(matching: "table")
        #expect(table == [.table])

        let banner = BlockMenuOption.menuOptions(matching: "banner")
        #expect(banner == [.banner])

        let todo = BlockMenuOption.menuOptions(matching: "todo")
        #expect(todo == [.list])

        let chart = BlockMenuOption.menuOptions(matching: "chart")
        #expect(chart == [.graph])

        let carousel = BlockMenuOption.menuOptions(matching: "carosoul")
        #expect(carousel == [.carousel])

        let grouped = BlockMenuOption.menuOptions(matching: "group")
        #expect(grouped == [.group])
        let social = BlockMenuOption.menuOptions(matching: "social")
        #expect(social == [.social])
        let instagram = BlockMenuOption.menuOptions(matching: "instagram")
        #expect(instagram == [.social])
        #expect(mosaicMenu.contains(.social))
        #expect(pursuitPage.contains(.social))
    }

    @Test
    func socialProfileLinkUsesAUsernameOrAFullURL() {
        let placed = ComposerBlock.make(kind: .social, position: BlockPosition(x: 0.2, y: 0.2))
        #expect(placed.socialPlatform == ComposerSocialPlatform.instagram.rawValue)
        #expect(placed.linkURL == "")

        #expect(ComposerSocialPlatform.instagram.profileURL(from: "ada")?.absoluteString == "https://instagram.com/ada")
        #expect(ComposerSocialPlatform.tiktok.profileURL(from: "@ada")?.absoluteString == "https://www.tiktok.com/@ada")
        #expect(ComposerSocialPlatform.twitter.profileURL(from: "ada")?.absoluteString == "https://twitter.com/ada")
        #expect(ComposerSocialPlatform.youtube.profileURL(from: "ada")?.absoluteString == "https://www.youtube.com/@ada")
        #expect(ComposerSocialPlatform.twitch.profileURL(from: "ada")?.absoluteString == "https://www.twitch.tv/ada")
        #expect(ComposerSocialPlatform.instagram.profileURL(from: "https://instagram.com/ada/")?.absoluteString == "https://instagram.com/ada/")
        #expect(ComposerSocialPlatform.instagram.profileURL(from: "  ") == nil)
    }

    @Test
    func socialLogosUseBrandColor() {
        let instagram = coloredPixelCount(UIImage(named: ComposerSocialPlatform.instagram.assetName) ?? UIImage())
        let twitter = coloredPixelCount(UIImage(named: ComposerSocialPlatform.twitter.assetName) ?? UIImage())
        let youtube = coloredPixelCount(UIImage(named: ComposerSocialPlatform.youtube.assetName) ?? UIImage())
        let twitch = coloredPixelCount(UIImage(named: ComposerSocialPlatform.twitch.assetName) ?? UIImage())
        let tiktok = coloredPixelCount(UIImage(named: ComposerSocialPlatform.tiktok.assetName) ?? UIImage())
        #expect(instagram > 20, "instagram \(instagram)")
        #expect(twitter > 20, "twitter \(twitter)")
        #expect(youtube > 20, "youtube \(youtube)")
        #expect(twitch > 20, "twitch \(twitch)")
        #expect(tiktok > 20, "tiktok \(tiktok)")
    }

    @Test
    func carouselKeepsItsMediaAndTurnsOneStep() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let blockID = store.addBlock(.carousel, to: nil)
        var block = store.blocks(for: nil)[0]
        #expect(block.carouselItems.isEmpty)
        #expect(block.kind == .carousel)

        block.carouselItems = [
            CarouselMediaItem(id: "a", fileName: "a.jpg"),
            CarouselMediaItem(id: "b", fileName: "b.jpg"),
            CarouselMediaItem(id: "c", fileName: "c.mov")
        ]
        block.carouselIndex = 1
        store.updateBlock(block, in: nil)

        let saved = store.block(with: blockID, in: nil)
        #expect(saved?.carouselItems.map(\.id) == ["a", "b", "c"])
        #expect(saved?.carouselIndex == 1)

        let data = try? JSONEncoder().encode(store.snapshot)
        let decoded = data.flatMap { try? JSONDecoder().decode(ComposerSnapshot.self, from: $0) }
        #expect(decoded?.mosaicBlocks.first?.carouselItems.map(\.fileName) == ["a.jpg", "b.jpg", "c.mov"])

        #expect(CarouselMotion.wrapped(-1, count: 3) == 2)
        #expect(CarouselMotion.shortestOffset(item: 2, center: 0, count: 3) == -1)
        #expect(CarouselMotion.shortestOffset(item: 1, center: 0, count: 3) == 1)
        #expect(CarouselMotion.shift(drag: 40, predicted: 40, step: 100) == -1)
        #expect(CarouselMotion.shift(drag: -40, predicted: -40, step: 100) == 1)
        #expect(CarouselMotion.shift(drag: 10, predicted: 10, step: 100) == 0)
        #expect(CarouselMotion.shift(drag: 8, predicted: 80, step: 100) == -1)
        #expect(CarouselMotion.indexAfterRemoval(index: 1, removedAt: 1, countAfter: 3) == 1)
        #expect(CarouselMotion.indexAfterRemoval(index: 2, removedAt: 0, countAfter: 3) == 1)
        #expect(CarouselMotion.indexAfterRemoval(index: 2, removedAt: 2, countAfter: 2) == 1)
    }

    @Test
    func textStyleKeepsBoldItalicAndUnderline() throws {
        var block = ComposerBlock.make(kind: .heading, position: BlockPosition(x: 0.1, y: 0.1))
        block.style.isBold = true
        block.style.isItalic = true
        block.style.isUnderlined = true
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(ComposerBlock.self, from: data)
        #expect(decoded.style.isBold)
        #expect(decoded.style.isItalic)
        #expect(decoded.style.isUnderlined)
    }

    @Test
    func carouselPhotosArePreparedSmaller() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        }
        let data = try #require(image.jpegData(compressionQuality: 0.9))
        let prepared = try #require(ComposerImagePreparation.jpeg(from: data, maxPixel: 20))
        let result = try #require(UIImage(data: prepared))
        #expect(max(result.size.width, result.size.height) <= 20)
    }

    @Test
    func calendarOpensOnAMonthAndKeepsADay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let weeks = CalendarMonthModel.weeks(year: 2026, month: 10, calendar: calendar)
        #expect(weeks.count == 5)
        #expect(weeks[0][4]?.day == 1)
        #expect(weeks.flatMap { $0 }.compactMap(\.self).count == 31)
        let august = CalendarMonthModel.weeks(year: 2026, month: 8, calendar: calendar)
        #expect(august.count == 6)
        #expect(august[0][6]?.day == 1)

        let next = CalendarMonthModel.shifting(year: 2026, month: 12, by: 1, calendar: calendar)
        #expect(next.year == 2027)
        #expect(next.month == 1)

        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        store.addBlock(.pursuit, to: nil)
        let pursuitID = store.snapshot.pursuits[0].id
        let blockID = store.addBlock(.calendar, to: pursuitID)
        var block = try #require(store.block(with: blockID, in: pursuitID))
        block.calendarEntries = [
            CalendarDayEntry(
                year: 2026,
                month: 10,
                day: 7,
                note: "Range day",
                media: [
                    CarouselMediaItem(id: "swing", fileName: "swing.jpg"),
                    CarouselMediaItem(id: "green", fileName: "green.jpg"),
                    CarouselMediaItem(id: "putt", fileName: "putt.mov")
                ],
                mediaIndex: 1
            )
        ]
        store.updateBlock(block, in: pursuitID)
        let data = try JSONEncoder().encode(store.snapshot)
        let decoded = try JSONDecoder().decode(ComposerSnapshot.self, from: data)
        let saved = try #require(decoded.pursuits[0].blocks.first?.calendarEntries.first)
        #expect(saved.note == "Range day")
        #expect(saved.media.map(\.fileName) == ["swing.jpg", "green.jpg", "putt.mov"])
        #expect(saved.mediaIndex == 1)
        #expect(saved.hasContent)

        let legacy = Data(#"{"year":2026,"month":10,"day":1,"note":"","mediaFileName":"swing.jpg"}"#.utf8)
        let migrated = try JSONDecoder().decode(CalendarDayEntry.self, from: legacy)
        #expect(migrated.media.map(\.fileName) == ["swing.jpg"])
        #expect(migrated.hasContent)
    }

    @Test
    func nodeIsAFolderInsideAPursuit() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        store.addBlock(.pursuit, to: nil)
        let pursuitID = store.snapshot.pursuits[0].id
        let nodeBlockID = store.addBlock(.node, to: pursuitID)
        let node = try #require(store.block(with: nodeBlockID, in: pursuitID))
        let documentID = try #require(node.pursuitID)
        let document = try #require(store.pursuit(for: documentID))
        #expect(node.kind == .node)
        #expect(document.role == .node)
        #expect(document.blocks.isEmpty)
        #expect(store.title(for: documentID) == "Node")

        var named = node
        named.text = "Range notes"
        store.updateBlock(named, in: pursuitID)
        #expect(store.title(for: documentID) == "Range notes")

        store.deleteBlock(nodeBlockID, in: pursuitID)
        #expect(store.pursuit(for: documentID) == nil)
        #expect(store.blocks(for: pursuitID).isEmpty)
    }

    @Test
    func tabsSwitchThePageAndKeepEachTabsContent() throws {
        #expect(ComposerTabSet.maximumCount(longestSide: 402) == 5)
        #expect(ComposerTabSet.maximumCount(longestSide: 874) == 11)
        #expect(ComposerTabSet.maximumCount(longestSide: 2000) == ComposerTabSet.absoluteMaximum)
        #expect(ComposerTabSet.maximumCount(longestSide: 80) == ComposerTabSet.minimumCount)

        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let noteID = store.addBlock(.text, to: nil)
        let tabsID = store.addBlock(.tabs, to: nil)
        let again = store.addBlock(.tabs, to: nil)
        #expect(again == tabsID)
        #expect(store.blocks(for: nil).filter { $0.kind == .tabs }.count == 1)

        let tabs = try #require(store.block(with: tabsID, in: nil))
        #expect(tabs.tabs.count == 3)
        #expect(tabs.tabs.map(\.title) == ["Tab 1", "Tab 2", "Tab 3"])
        let first = try #require(tabs.selectedTabID)
        #expect(store.block(with: noteID, in: nil)?.tabID == first)
        #expect(tabs.tabID == nil)

        store.addComposerTab(to: tabsID, in: nil, longestSide: 874)
        let added = try #require(store.block(with: tabsID, in: nil))
        #expect(added.tabs.count == 4)
        #expect(added.tabs.last?.title == "Tab 4")
        let fourth = try #require(added.selectedTabID)
        let onFourth = store.addBlock(.heading, to: nil)
        #expect(store.block(with: onFourth, in: nil)?.tabID == fourth)

        let second = added.tabs[1].id
        var showSecond = added
        showSecond.selectedTabID = second
        showSecond.tabs[1].title = "PRs"
        store.updateBlock(showSecond, in: nil)
        let onSecond = store.addBlock(.text, to: nil)
        #expect(store.block(with: onSecond, in: nil)?.tabID == second)

        store.removeComposerTab(second, from: tabsID, in: nil)
        let afterRemove = try #require(store.block(with: tabsID, in: nil))
        #expect(afterRemove.tabs.count == 3)
        #expect(!afterRemove.tabs.contains(where: { $0.id == second }))
        #expect(store.block(with: onSecond, in: nil)?.tabID != second)
        #expect(store.block(with: noteID, in: nil)?.tabID == first)

        let kept = store.removeComposerTab(first, from: tabsID, in: nil)
        _ = kept
        var shrinking = try #require(store.block(with: tabsID, in: nil))
        while shrinking.tabs.count > ComposerTabSet.minimumCount {
            if let id = shrinking.selectedTabID {
                store.removeComposerTab(id, from: tabsID, in: nil)
            }
            shrinking = try #require(store.block(with: tabsID, in: nil))
        }
        let floorCount = shrinking.tabs.count
        if let last = shrinking.tabs.first?.id {
            store.removeComposerTab(last, from: tabsID, in: nil)
        }
        #expect(store.block(with: tabsID, in: nil)?.tabs.count == floorCount)

        store.deleteBlock(tabsID, in: nil)
        #expect(store.blocks(for: nil).allSatisfy { $0.tabID == nil })

        let data = try JSONEncoder().encode(ComposerBlock.make(kind: .tabs, position: BlockPosition(x: 0.1, y: 0.1)))
        let decoded = try JSONDecoder().decode(ComposerBlock.self, from: data)
        #expect(decoded.tabs.map(\.title) == ["Tab 1", "Tab 2", "Tab 3"])
    }

    @Test
    func lineGraphPlacesPointsByDateAndKeepsThem() throws {
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_700_086_400)
        let placed = ComposerLineGraph.placed([
            ComposerGraphPoint(id: "later", x: later, y: 80),
            ComposerGraphPoint(id: "early", x: early, y: 20)
        ])
        #expect(placed.map(\.id) == ["early", "later"])
        #expect(placed[0].nx == 0)
        #expect(placed[1].nx == 1)
        #expect(placed[0].ny < placed[1].ny)

        let flat = ComposerLineGraph.placed([
            ComposerGraphPoint(id: "a", x: early, y: 5),
            ComposerGraphPoint(id: "b", x: later, y: 5)
        ])
        #expect(flat[0].ny == 0.5)
        #expect(flat[1].ny == 0.5)

        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        store.addBlock(.pursuit, to: nil)
        let pursuitID = store.snapshot.pursuits[0].id
        let blockID = store.addBlock(.graph, to: pursuitID)
        var block = try #require(store.block(with: blockID, in: pursuitID))
        #expect(block.graphKind == .line)
        #expect(block.graphXAxis == .date)
        #expect(block.graphYAxis == .integer)
        #expect(block.graphXUnitName == "Date")
        #expect(block.graphYUnitName == "Value")
        block.graphTitle = "Scores"
        block.graphYUnitName = "Score"
        block.graphPoints = [
            ComposerGraphPoint(id: "early", x: early, y: 20),
            ComposerGraphPoint(id: "later", x: later, y: 80)
        ]
        store.updateBlock(block, in: pursuitID)
        let data = try JSONEncoder().encode(store.snapshot)
        let decoded = try JSONDecoder().decode(ComposerSnapshot.self, from: data)
        let saved = try #require(decoded.pursuits[0].blocks.first)
        #expect(saved.graphTitle == "Scores")
        #expect(saved.graphYUnitName == "Score")
        #expect(saved.graphPoints.map(\.y) == [20, 80])
        #expect(saved.graphPoints.map(\.id) == ["early", "later"])
        #expect(ComposerGraphStretch.resized(base: 1, translation: 320, span: 320, leadingOrTop: false) == 2)
        #expect(ComposerGraphStretch.resized(base: 1, translation: -236, span: 236, leadingOrTop: true) == 2)
        #expect(ComposerGraphStretch.clamped(8) == ComposerGraphStretch.maximum)
    }

    @Test
    func listStartsBulletedAndKeepsItsRows() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let blockID = store.addBlock(.list, to: nil)
        var block = try #require(store.block(with: blockID, in: nil))
        #expect(block.kind == .list)
        #expect(block.listMarker == .bullet)
        #expect(block.listItems.count == 1)
        #expect(ComposerListMarker.number.marker(at: 2) == "3.")
        #expect(ComposerListMarker.letter.marker(at: 0) == "a.")
        #expect(ComposerListMarker.letter.marker(at: 26) == "aa.")

        block.listMarker = .checkbox
        block.listItems = [
            ComposerListItem(id: "stretch", text: "Stretch", isChecked: true),
            ComposerListItem(id: "range", text: "Range", isChecked: false)
        ]
        store.updateBlock(block, in: nil)
        let data = try JSONEncoder().encode(store.snapshot)
        let decoded = try JSONDecoder().decode(ComposerSnapshot.self, from: data)
        let saved = try #require(decoded.mosaicBlocks.first)
        #expect(saved.listMarker == .checkbox)
        #expect(saved.listItems.map(\.text) == ["Stretch", "Range"])
        #expect(saved.listItems[0].isChecked)
        #expect(!saved.listItems[1].isChecked)
    }

    @Test
    func wideMediaCanSlideInsideASquareFrame() {
        let frame = CGSize(width: 100, height: 100)
        let limits = MediaFraming.panLimits(contentAspect: 2, frame: frame, zoom: 1)
        #expect(limits.width == 50)
        #expect(limits.height == 0)

        let clamped = MediaFraming.clampedPan(CGSize(width: 80, height: 12), limits: limits)
        #expect(clamped.width == 50)
        #expect(clamped.height == 0)
    }

    @Test
    func mosaicTitleBecomesAHeadingOnce() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        store.placeMosaicTitleIfNeeded()
        let blocks = store.blocks(for: nil)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .heading)
        #expect(blocks[0].text == "Mosaic")

        store.placeMosaicTitleIfNeeded()
        #expect(store.blocks(for: nil).count == 1)

        store.deleteBlock(blocks[0].id, in: nil)
        store.placeMosaicTitleIfNeeded()
        #expect(store.blocks(for: nil).isEmpty)
    }

    @Test
    func pursuitPagesStartBlankOnce() {
        let pursuitID = ComposerDocumentID(rawValue: "golf")
        let snapshot = ComposerSnapshot(
            mosaicTitle: "Mosaic",
            mosaicBlocks: [],
            pursuits: [
                ComposerPursuit(
                    id: pursuitID,
                    title: "Golf",
                    blocks: [ComposerBlock.make(kind: .text, position: BlockPosition(x: 0.2, y: 0.2))]
                )
            ]
        )
        let store = ComposerStore(seedSnapshot: snapshot, persistToDisk: false)
        store.blankPursuitPagesIfNeeded()
        #expect(store.blocks(for: pursuitID).isEmpty)

        store.addBlock(.heading, to: pursuitID)
        store.blankPursuitPagesIfNeeded()
        #expect(store.blocks(for: pursuitID).count == 1)
    }

    @Test
    func blankingPursuitPagesLeavesJournalPagesAlone() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let scrapbookID = store.addBlock(.scrapbook, to: nil)
        let pageID = try #require(store.block(with: scrapbookID, in: nil)?.scrapbookPageIDs.first)
        let note = store.addBlock(.text, to: pageID)
        store.blankPursuitPagesIfNeeded()
        #expect(store.blocks(for: pageID).contains(where: { $0.id == note }))
    }

    @Test
    func boardUndoKeepsJournalPiecesAddedAfterTheSnapshot() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let scrapbookID = store.addBlock(.scrapbook, to: nil)
        let pageID = try #require(store.block(with: scrapbookID, in: nil)?.scrapbookPageIDs.first)
        _ = store.addBlock(.text, to: pageID)
        _ = store.addBlock(.pursuit, to: nil)
        let later = store.addBlock(.heading, to: pageID)
        store.undo(in: nil)
        #expect(store.blocks(for: pageID).contains(where: { $0.id == later }))
        #expect(store.blocks(for: nil).contains(where: { $0.id == scrapbookID }))
    }

    @Test
    func olderSnapshotWithoutTitleFlagStillDecodes() throws {
        let json = #"{"mosaicTitle":"My Mosaic","mosaicBlocks":[],"pursuits":[]}"#
        let decoded = try JSONDecoder().decode(ComposerSnapshot.self, from: Data(json.utf8))
        #expect(decoded.mosaicTitlePlaced == false)
        #expect(decoded.mosaicTitle == "My Mosaic")
    }

    @Test
    func boardBackgroundStaysBehindThePageAndRoundTrips() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let widget = store.addBlock(.pursuit, to: nil)
        let pursuitID = try #require(store.block(with: widget, in: nil)?.pursuitID)
        let color = ComposerBoardBackground.solid(ComposerRGBColor(red: 0.2, green: 0.3, blue: 0.4))
        store.setBoardBackground(color, for: nil)
        store.setBoardBackground(color, for: pursuitID)
        #expect(store.boardBackground(for: nil) == color)
        #expect(store.boardBackground(for: pursuitID) == color)
        let data = try JSONEncoder().encode(store.snapshot)
        let decoded = try JSONDecoder().decode(ComposerSnapshot.self, from: data)
        #expect(decoded.mosaicBackground == color)
        #expect(decoded.pursuits.first?.background == color)
        store.setBoardBackground(nil, for: nil)
        #expect(store.boardBackground(for: nil) == nil)
    }

    @Test
    func snapshotEncodesAndDecodes() throws {
        let snapshot = ComposerSnapshot(
            mosaicTitle: "My Mosaic",
            mosaicBlocks: [ComposerBlock.make(kind: .text, position: BlockPosition(x: 0.1, y: 0.1))],
            pursuits: []
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ComposerSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }

    @Test
    func undoRestoresThePreviousPage() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let added = store.addBlock(.heading, to: nil)
        var block = try #require(store.block(with: added, in: nil))
        block.text = "Hello"
        store.updateBlock(block, in: nil)
        #expect(store.canUndo(in: nil))
        store.undo(in: nil)
        #expect(store.block(with: added, in: nil)?.text == "")
        store.undo(in: nil)
        #expect(store.blocks(for: nil).isEmpty)
        #expect(!store.canUndo(in: nil))
    }

    @Test
    func groupingPacksMembersAndUngroupRestoresThem() throws {
        var first = ComposerBlock.make(kind: .text, position: BlockPosition(x: 0.1, y: 0.1))
        first.text = "One"
        var second = ComposerBlock.make(kind: .heading, position: BlockPosition(x: 0.4, y: 0.2))
        second.text = "Two"
        let frames = [
            first.id: CGRect(x: 40, y: 80, width: 100, height: 40),
            second.id: CGRect(x: 180, y: 120, width: 80, height: 50)
        ]
        let group = try #require(ComposerGroupMath.groupedBlock(
            members: [first, second],
            frames: frames,
            canvasWidth: 400,
            layoutHeight: 900,
            tabID: nil
        ))
        #expect(group.kind == .group)
        #expect(group.groupMembers.count == 2)
        #expect(abs(group.position.x - 0.1) < 0.001)
        #expect(abs(group.groupWidth - 220) < 0.001)
        #expect(abs(group.groupHeight - 90) < 0.001)
        let restored = ComposerGroupMath.ungroupedMembers(of: group, canvasWidth: 400, layoutHeight: 900)
        #expect(restored.count == 2)
        #expect(restored.map(\.text).sorted() == ["One", "Two"])
        #expect(abs(restored[0].position.x - 0.1) < 0.001)
    }

    @Test
    func groupedMemberEditsStayInsideTheGroup() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let origin = BlockPosition(x: 0.2, y: 0.2)
        var table = ComposerBlock.make(kind: .table, position: origin)
        let startingColumns = table.tableColumns.count
        var note = ComposerBlock.make(kind: .text, position: origin)
        note.text = "Note"
        var group = ComposerBlock.make(kind: .group, position: origin)
        group.groupMembers = [table, note]
        group.groupWidth = 240
        group.groupHeight = 180
        store.replacePage([group], in: nil)

        store.addTableColumn(to: table.id, in: nil)
        let savedTable = try #require(store.block(with: table.id, in: nil))
        #expect(savedTable.tableColumns.count == startingColumns + 1)
        #expect(store.blocks(for: nil).count == 1)
        #expect(store.blocks(for: nil)[0].kind == .group)

        note.text = "Updated"
        store.updateBlock(note, in: nil)
        #expect(store.block(with: note.id, in: nil)?.text == "Updated")
        #expect(store.block(with: group.id, in: nil)?.groupMembers.contains(where: { $0.id == note.id && $0.text == "Updated" }) == true)
    }

    @Test
    func tabRowStaysInsideTheSideBorders() {
        #expect(ComposerTabEdge.controlsBelongAbove(chipsMaxX: 360, buttonWidth: 28, gap: 8, viewportWidth: 390))
        #expect(!ComposerTabEdge.controlsBelongAbove(chipsMaxX: 200, buttonWidth: 28, gap: 8, viewportWidth: 390))
        let shifted = ComposerTabEdge.leadingEdge(currentMinX: 300, width: 160, viewportWidth: 390)
        #expect(abs(shifted - 218) < 0.001)
        let pinned = ComposerTabEdge.leadingEdge(currentMinX: -20, width: 80, viewportWidth: 390)
        #expect(abs(pinned - 12) < 0.001)
    }

    @Test
    func dragStopsAtTheSideBorders() {
        let towardLeft = ComposerTabEdge.clampedDrag(
            translation: CGSize(width: -200, height: 40),
            frameMinX: 100,
            frameWidth: 80,
            viewportWidth: 390
        )
        #expect(abs(towardLeft.width - (-96)) < 0.001)
        #expect(abs(towardLeft.height - 40) < 0.001)

        let towardRight = ComposerTabEdge.clampedDrag(
            translation: CGSize(width: 300, height: -12),
            frameMinX: 100,
            frameWidth: 80,
            viewportWidth: 390
        )
        #expect(abs(towardRight.width - 206) < 0.001)
        #expect(abs(towardRight.height - (-12)) < 0.001)

        let inside = ComposerTabEdge.clampedDrag(
            translation: CGSize(width: 20, height: 8),
            frameMinX: 100,
            frameWidth: 80,
            viewportWidth: 390
        )
        #expect(abs(inside.width - 20) < 0.001)

        let widerThanBoard = ComposerTabEdge.clampedDrag(
            translation: CGSize(width: 40, height: 10),
            frameMinX: 40,
            frameWidth: 400,
            viewportWidth: 390
        )
        #expect(abs(widerThanBoard.width - (-36)) < 0.001)
    }

    @Test
    func scrapbookKeepsABoardOnEachPage() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        store.addBlock(.pursuit, to: nil)
        let pursuitID = store.snapshot.pursuits[0].id
        let scrapbookID = store.addBlock(.scrapbook, to: pursuitID)
        let scrapbook = try #require(store.block(with: scrapbookID, in: pursuitID))
        #expect(scrapbook.kind == .scrapbook)
        #expect(scrapbook.text == "Scrapbook")
        #expect(scrapbook.scrapbookPageIDs.count == 2)
        let first = scrapbook.scrapbookPageIDs[0]
        let second = scrapbook.scrapbookPageIDs[1]
        #expect(store.pursuit(for: first)?.role == .page)
        #expect(store.blocks(for: first).isEmpty)

        _ = store.addBlock(.text, to: first)
        #expect(store.blocks(for: first).count == 1)
        #expect(store.blocks(for: second).isEmpty)

        let inserted = try #require(store.insertScrapbookPage(after: 0, on: scrapbookID, in: pursuitID))
        #expect(inserted == 1)
        #expect(store.block(with: scrapbookID, in: pursuitID)?.scrapbookPageIDs.count == 3)

        let data = try JSONEncoder().encode(store.snapshot)
        let decoded = try JSONDecoder().decode(ComposerSnapshot.self, from: data)
        let saved = try #require(decoded.pursuits.first(where: { $0.id == pursuitID })?.blocks.first(where: { $0.id == scrapbookID }))
        #expect(saved.scrapbookPageIDs.count == 3)
        #expect(decoded.pursuits.contains(where: { $0.id == first && $0.blocks.contains(where: { $0.kind == .text }) }))

        store.copyBlock(scrapbookID, in: pursuitID)
        store.deleteBlock(scrapbookID, in: pursuitID)
        let pasted = try #require(store.pasteClipboard(at: BlockPosition(x: 0.2, y: 0.3), in: pursuitID))
        let copy = try #require(store.block(with: pasted, in: pursuitID))
        #expect(pasted != scrapbookID)
        #expect(copy.scrapbookPageIDs.count == 3)
        #expect(Set(copy.scrapbookPageIDs).isDisjoint(with: [first, second]))
        #expect(copy.scrapbookPageIDs.contains { store.blocks(for: $0).contains(where: { $0.kind == .text }) })
        #expect(store.pursuit(for: copy.scrapbookPageIDs[0])?.role == .page)
        #expect(store.clipboard == nil)

        store.deleteBlock(pasted, in: pursuitID)
        #expect(store.pursuit(for: first) == nil)
        #expect(store.pursuit(for: second) == nil)
        #expect(store.blocks(for: pursuitID).isEmpty)
    }

    private func coloredPixelCount(_ image: UIImage) -> Int {
        let side: CGFloat = 80
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let drawn = renderer.image { _ in
            image.withRenderingMode(.alwaysOriginal).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let cg = drawn.cgImage,
              let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }
        let bytesPerPixel = max(cg.bitsPerPixel / 8, 1)
        var colored = 0
        for y in 0 ..< cg.height {
            for x in 0 ..< cg.width {
                let index = y * cg.bytesPerRow + x * bytesPerPixel
                let first = Int(bytes[index])
                let second = Int(bytes[index + 1])
                let third = Int(bytes[index + 2])
                let alpha = bytesPerPixel > 3 ? Int(bytes[index + 3]) : 255
                guard alpha > 20 else { continue }
                let maxChannel = max(first, second, third)
                let minChannel = min(first, second, third)
                if maxChannel > 40, maxChannel - minChannel > 28 {
                    colored += 1
                }
            }
        }
        return colored
    }
}

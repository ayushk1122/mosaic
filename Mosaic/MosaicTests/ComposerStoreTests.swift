import Foundation
import Testing
import UIKit
@testable import Mosaic

@MainActor
struct ComposerStoreTests {
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

        let mosaicMenu = BlockMenuOption.menuOptions(matching: "", includingCalendar: false, includingGraph: false)
        #expect(!mosaicMenu.contains(.calendar))
        #expect(!mosaicMenu.contains(.graph))
        #expect(mosaicMenu.contains(.pursuit))
        #expect(mosaicMenu.contains(.list))
        #expect(pursuitPage.contains(.list))
        #expect(pursuitPage.contains(.graph))

        let todo = BlockMenuOption.menuOptions(matching: "todo")
        #expect(todo == [.list])

        let chart = BlockMenuOption.menuOptions(matching: "chart")
        #expect(chart == [.graph])

        let carousel = BlockMenuOption.menuOptions(matching: "carosoul")
        #expect(carousel == [.carousel])
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
    func olderSnapshotWithoutTitleFlagStillDecodes() throws {
        let json = #"{"mosaicTitle":"My Mosaic","mosaicBlocks":[],"pursuits":[]}"#
        let decoded = try JSONDecoder().decode(ComposerSnapshot.self, from: Data(json.utf8))
        #expect(decoded.mosaicTitlePlaced == false)
        #expect(decoded.mosaicTitle == "My Mosaic")
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
}

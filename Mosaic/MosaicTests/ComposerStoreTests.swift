import Foundation
import Testing
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

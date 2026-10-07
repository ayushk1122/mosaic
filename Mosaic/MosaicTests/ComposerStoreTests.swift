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

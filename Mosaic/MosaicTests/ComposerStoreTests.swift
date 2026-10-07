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

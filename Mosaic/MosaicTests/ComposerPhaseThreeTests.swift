import Foundation
import PencilKit
import Testing
@testable import Mosaic

@MainActor
struct ComposerPhaseThreeTests {
    @Test
    func pieceLookupsFollowEveryEdit() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let text = store.addBlock(.text, to: nil)
        #expect(store.block(with: text, in: nil)?.kind == .text)
        #expect(store.hasTopLevelBlock(text, in: nil))

        let pursuitBlock = store.addBlock(.pursuit, to: nil)
        let pursuit = try #require(store.block(with: pursuitBlock, in: nil)?.pursuitID)
        let inside = store.addBlock(.list, to: pursuit)
        #expect(store.block(with: inside, in: pursuit)?.kind == .list)
        #expect(store.blocks(for: pursuit).map(\.id) == [inside])
        #expect(store.block(with: inside, in: nil) == nil)

        store.deleteBlock(text, in: nil)
        #expect(store.block(with: text, in: nil) == nil)
        #expect(!store.hasTopLevelBlock(text, in: nil))
        store.undo(in: nil)
        #expect(store.block(with: text, in: nil) != nil)

        var edited = try #require(store.block(with: inside, in: pursuit))
        edited.text = "Changed"
        store.updateBlock(edited, in: pursuit)
        #expect(store.block(with: inside, in: pursuit)?.text == "Changed")
        #expect(store.blocks(for: ComposerDocumentID(rawValue: "missing")).isEmpty)
    }

    @Test
    func groupMembersAreFoundButAreNotOnTheBoardItself() {
        var member = ComposerBlock.make(kind: .text, position: BlockPosition(x: 0.1, y: 0.1))
        member.text = "Member"
        var group = ComposerBlock.make(kind: .group, position: BlockPosition(x: 0.2, y: 0.2))
        group.groupMembers = [member]
        var snapshot = ComposerSnapshot.empty
        snapshot.mosaicBlocks = [group]
        let store = ComposerStore(seedSnapshot: snapshot, persistToDisk: false)
        #expect(store.block(with: member.id, in: nil)?.text == "Member")
        #expect(!store.hasTopLevelBlock(member.id, in: nil))
        #expect(store.hasTopLevelBlock(group.id, in: nil))
    }

    @Test
    func floatingControlsStayInsideTheVisibleBoard() throws {
        var metrics = ComposerScrollBubbleMetrics(offset: 300, minOffset: 0, maxOffset: 1000)
        metrics.containerHeight = 800
        let editing = try #require(ComposerVisibleArea(width: 400, isViewing: false, isBookPage: false).rect(metrics))
        #expect(editing.minY == 300)
        #expect(editing.height == 800 - (ComposerAddMenuMetrics.button + 28))
        let page = try #require(ComposerVisibleArea(width: 400, isViewing: true, isBookPage: true).rect(metrics))
        #expect(page.minY == 300 + ScrapbookMetrics.turnCorner)
        #expect(ComposerVisibleArea(width: 0, isViewing: true, isBookPage: false).rect(metrics) == nil)
    }

    @Test
    func cachedTouchAreasMatchTheStrokes() {
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(
                controlPoints: [
                    PKStrokePoint(location: CGPoint(x: 10, y: 10), timeOffset: 0, size: CGSize(width: 4, height: 4),
                                  opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
                    PKStrokePoint(location: CGPoint(x: 60, y: 40), timeOffset: 0.1, size: CGSize(width: 4, height: 4),
                                  opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
                ],
                creationDate: Date()
            )
        )
        let data = PKDrawing(strokes: [stroke]).dataRepresentation()
        let direct = ComposerDrawingMetrics.touchRects(of: ComposerDrawingMetrics.drawing(from: data))
        #expect(!direct.isEmpty)
        #expect(ComposerDrawingMetrics.touchRects(of: data) == direct)
        #expect(ComposerDrawingMetrics.touchRects(of: data) == direct)
        #expect(ComposerDrawingMetrics.touchRects(of: nil as Data?).isEmpty)
    }
}

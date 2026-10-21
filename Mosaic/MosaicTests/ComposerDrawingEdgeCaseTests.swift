import CoreGraphics
import Foundation
import PencilKit
import Testing

@testable import Mosaic

@MainActor
@Suite
struct ComposerDrawingEdgeCaseTests {
    private func ink(_ strokes: Int = 1) -> Data? {
        let drawn = (0..<strokes).map { index in
            let y = CGFloat(20 + index * 6)
            let points = [CGPoint(x: 20, y: y), CGPoint(x: 120, y: y)].enumerated().map { offset, location in
                PKStrokePoint(
                    location: location,
                    timeOffset: TimeInterval(offset) * 0.1,
                    size: CGSize(width: 4, height: 4),
                    opacity: 1,
                    force: 1,
                    azimuth: 0,
                    altitude: .pi / 2
                )
            }
            return PKStroke(ink: PKInk(.pen, color: .white), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        }
        return ComposerDrawingMetrics.data(for: PKDrawing(strokes: drawn))
    }

    private func draw(_ data: Data?, on id: ComposerBlockID, in store: ComposerStore) throws {
        var block = try #require(store.block(with: id, in: nil))
        block.drawingData = data
        store.updateBlock(block, in: nil)
    }

    // MARK: Undo never leaves an empty drawing box behind

    @Test
    func undoAfterTheFirstStrokeRemovesTheWholeDrawing() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let id = store.addBlock(.drawing, at: BlockPosition(x: 0.1, y: 0.1), to: nil)
        try draw(ink(1), on: id, in: store)

        store.undo(in: nil)
        #expect(store.block(with: id, in: nil) == nil)
        #expect(!store.canUndo(in: nil))
    }

    @Test
    func laterStrokesUndoOneAtATimeThenTheDrawingGoes() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let id = store.addBlock(.drawing, at: BlockPosition(x: 0.1, y: 0.1), to: nil)
        let first = ink(1)
        try draw(first, on: id, in: store)
        try draw(ink(2), on: id, in: store)

        store.undo(in: nil)
        #expect(store.block(with: id, in: nil)?.drawingData == first)
        store.undo(in: nil)
        #expect(store.block(with: id, in: nil) == nil)
    }

    @Test
    func aDrawingPlacedAndNeverDrawnInLeavesNoUndoStep() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let id = store.addBlock(.drawing, at: BlockPosition(x: 0.1, y: 0.1), to: nil)
        store.discardEmptyDrawing(id, in: nil)
        #expect(store.block(with: id, in: nil) == nil)
        #expect(!store.canUndo(in: nil))
    }

    @Test
    func erasingEverythingThenUndoBringsTheInkBack() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let id = store.addBlock(.drawing, at: BlockPosition(x: 0.1, y: 0.1), to: nil)
        let drawn = ink(2)
        try draw(drawn, on: id, in: store)
        try draw(nil, on: id, in: store)
        store.discardEmptyDrawing(id, in: nil)
        #expect(store.block(with: id, in: nil) == nil)

        store.undo(in: nil)
        #expect(store.block(with: id, in: nil)?.drawingData == drawn)
    }

    @Test
    func discardingLeavesDrawingsWithInkAlone() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let id = store.addBlock(.drawing, at: BlockPosition(x: 0.1, y: 0.1), to: nil)
        try draw(ink(1), on: id, in: store)
        store.discardEmptyDrawing(id, in: nil)
        #expect(store.block(with: id, in: nil) != nil)
    }

    // MARK: The box fits the ink once drawing ends

    /// Where a point in the drawing's own coordinates lands on the board.
    private func boardPoint(_ local: CGPoint, of block: ComposerBlock, origin: CGPoint) -> CGPoint {
        let scale = CGFloat(block.style.scale)
        let size = ComposerDrawingMetrics.baseSize(of: block)
        let radians = CGFloat(block.rotation * .pi / 180)
        let dx = (local.x - size.width / 2) * scale
        let dy = (local.y - size.height / 2) * scale
        return CGPoint(
            x: origin.x + size.width * scale / 2 + dx * cos(radians) - dy * sin(radians),
            y: origin.y + size.height * scale / 2 + dx * sin(radians) + dy * cos(radians)
        )
    }

    private func inkCenter(of block: ComposerBlock) -> CGPoint {
        let bounds = ComposerDrawingMetrics.drawing(from: block.drawingData).bounds
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    @Test(arguments: [(1.0, 0.0), (1.5, 0.0), (0.6, 30.0), (2.0, 180.0)])
    func shrinkingToTheInkLeavesItInPlace(scale: Double, rotation: Double) throws {
        var block = ComposerBlock.make(kind: .drawing, position: BlockPosition(x: 0, y: 0))
        block.drawingWidth = 358
        block.drawingHeight = 280
        block.style.scale = scale
        block.rotation = rotation
        block.drawingData = ink(3)
        let origin = CGPoint(x: 16, y: 400)
        let before = boardPoint(inkCenter(of: block), of: block, origin: origin)

        let frame = try #require(ComposerDrawingMetrics.inkFrame(of: block))
        let (fitted, newOrigin) = ComposerDrawingMetrics.reframed(block, to: frame, origin: origin)
        #expect(fitted.drawingWidth < 200 && fitted.drawingHeight < 60)
        let after = boardPoint(inkCenter(of: fitted), of: fitted, origin: newOrigin)
        #expect(abs(after.x - before.x) < 0.5 && abs(after.y - before.y) < 0.5)

        // Already fitted: nothing more to do.
        #expect(ComposerDrawingMetrics.inkFrame(of: fitted) == nil)
    }

    @Test
    func drawingAgainOpensThePageBackUpWithoutMovingTheInk() throws {
        var block = ComposerBlock.make(kind: .drawing, position: BlockPosition(x: 0, y: 0))
        block.drawingWidth = 358
        block.drawingHeight = 280
        block.drawingData = ink(1)
        let (fitted, fittedOrigin) = ComposerDrawingMetrics.reframed(
            block,
            to: try #require(ComposerDrawingMetrics.inkFrame(of: block)),
            origin: CGPoint(x: 16, y: 400)
        )
        let before = boardPoint(inkCenter(of: fitted), of: fitted, origin: fittedOrigin)

        let room = try #require(ComposerDrawingMetrics.drawingRoomFrame(of: fitted, origin: fittedOrigin, pageWidth: 390))
        let (opened, openedOrigin) = ComposerDrawingMetrics.reframed(fitted, to: room, origin: fittedOrigin)
        #expect(abs(openedOrigin.x - ComposerDrawingMetrics.pageMargin) < 0.5)
        #expect(abs(opened.drawingWidth - (390 - 2 * Double(ComposerDrawingMetrics.pageMargin))) < 0.5)
        #expect(opened.drawingHeight >= Double(ComposerDrawingMetrics.defaultSize.height) - 0.5)
        let after = boardPoint(inkCenter(of: opened), of: opened, origin: openedOrigin)
        #expect(abs(after.x - before.x) < 0.5 && abs(after.y - before.y) < 0.5)

        // A tilted drawing keeps its box while drawing.
        var tilted = fitted
        tilted.rotation = 20
        #expect(ComposerDrawingMetrics.drawingRoomFrame(of: tilted, origin: fittedOrigin, pageWidth: 390) == nil)
    }

    @Test
    func drawingRoomNeverReachesAboveTheBoard() throws {
        var block = ComposerBlock.make(kind: .drawing, position: BlockPosition(x: 0, y: 0))
        block.drawingWidth = 100
        block.drawingHeight = 40
        block.drawingData = ink(1)
        let room = try #require(ComposerDrawingMetrics.drawingRoomFrame(of: block, origin: CGPoint(x: 100, y: 10), pageWidth: 390))
        #expect(room.minY >= -10.5)
    }

    @Test
    func reshapingADrawingIsNotAnUndoStep() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let id = store.addBlock(.drawing, at: BlockPosition(x: 0.1, y: 0.1), to: nil)
        try draw(ink(1), on: id, in: store)
        var reshaped = try #require(store.block(with: id, in: nil))
        reshaped.drawingWidth = 120
        store.reshapeDrawing(reshaped, in: nil)
        #expect(store.block(with: id, in: nil)?.drawingWidth == 120)

        store.undo(in: nil)
        #expect(store.block(with: id, in: nil) == nil)
    }

    // MARK: Boards stay small enough to sync

    @Test
    func aDrawingGetsWhatsLeftOfTheBoardsBudget() {
        var big = ComposerBlock.make(kind: .drawing, position: BlockPosition(x: 0, y: 0))
        big.drawingData = Data(count: 900_000)
        let current = ComposerBlock.make(kind: .drawing, position: BlockPosition(x: 0, y: 0))
        var group = ComposerBlock.make(kind: .group, position: BlockPosition(x: 0, y: 0))
        var grouped = ComposerBlock.make(kind: .drawing, position: BlockPosition(x: 0, y: 0))
        grouped.drawingData = Data(count: 100_000)
        group.groupMembers = [grouped]

        let limit = ComposerDrawingMetrics.byteLimit(for: current.id, on: [big, group, current])
        #expect(limit == ComposerDrawingMetrics.boardBudget - 1_000_000)
        #expect(ComposerDrawingMetrics.byteLimit(for: current.id, on: [current]) == ComposerDrawingMetrics.maximumBytes)
        // A drawing's own ink doesn't count against it.
        #expect(ComposerDrawingMetrics.byteLimit(for: big.id, on: [big]) == ComposerDrawingMetrics.maximumBytes)
    }

    @Test
    func pastingADrawingIntoAFullBoardIsRefused() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let first = store.addBlock(.drawing, at: BlockPosition(x: 0.1, y: 0.1), to: nil)
        try draw(Data(count: 800_000), on: first, in: store)
        store.copyBlock(first, in: nil)

        #expect(store.pasteClipboard(at: BlockPosition(x: 0.2, y: 0.2), in: nil) == nil)

        // A small drawing still fits.
        let small = store.addBlock(.drawing, at: BlockPosition(x: 0.3, y: 0.3), to: nil)
        try draw(ink(1), on: small, in: store)
        store.copyBlock(small, in: nil)
        #expect(store.pasteClipboard(at: BlockPosition(x: 0.4, y: 0.4), in: nil) != nil)
    }

    @Test
    func unreadableStrokesAreProtected() {
        #expect(ComposerDrawingMetrics.isReadable(nil))
        #expect(ComposerDrawingMetrics.isReadable(ink(1)))
        #expect(!ComposerDrawingMetrics.isReadable(Data("from a newer PencilKit".utf8)))
    }

    // MARK: Groups

    @Test
    func ungroupingKeepsSmallDrawingsSmall() {
        var drawing = ComposerBlock.make(kind: .drawing, position: BlockPosition(x: 0, y: 0))
        drawing.style.scale = 0.35
        ComposerGroupMath.bake(1.0001 + 0.001, into: &drawing)
        #expect(drawing.style.scale < 0.45)
        #expect(drawing.style.scale >= ComposerDrawingMetrics.minimumScale)
    }

    // MARK: Saved form

    @Test
    func onlyDrawingsSaveADrawingArea() throws {
        let text = ComposerBlock.make(kind: .text, position: BlockPosition(x: 0, y: 0))
        let drawing = ComposerBlock.make(kind: .drawing, position: BlockPosition(x: 0, y: 0))
        let textJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(text)) as? [String: Any])
        let drawingJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(drawing)) as? [String: Any])
        #expect(textJSON["drawingWidth"] == nil)
        #expect(textJSON["drawingHeight"] == nil)
        #expect(drawingJSON["drawingWidth"] as? Double == Double(ComposerDrawingMetrics.defaultSize.width))
        #expect(try JSONDecoder().decode(ComposerBlock.self, from: JSONEncoder().encode(text)) == text)
    }

    // MARK: Pieces from newer versions

    private func futureBlock(_ fields: [String: Any]) throws -> ComposerBlock {
        var json = fields
        json["id"] = ["rawValue": "future"]
        json["kind"] = "hologram"
        return try JSONDecoder().decode(ComposerBlock.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test
    func movingOrRetabbingANewerPieceIsSaved() throws {
        var future = try futureBlock(["position": ["x": 0.1, "y": 0.2], "tabID": "tab-1", "glow": 3])
        future.position = BlockPosition(x: 0.5, y: 0.6)
        future.tabID = nil
        let saved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(future)) as? [String: Any])
        let position = try #require(saved["position"] as? [String: Double])
        #expect(position["x"] == 0.5 && position["y"] == 0.6)
        #expect(saved["tabID"] == nil)
        #expect(saved["glow"] as? Int == 3)
        #expect(saved["kind"] as? String == "hologram")
    }

    @Test
    func boardsANewerPieceUsesAreNotCleanedUp() throws {
        let page = ComposerPursuit(id: ComposerDocumentID(rawValue: "page-owned-by-future"), title: "Page", blocks: [], role: .page)
        let orphan = ComposerPursuit(id: ComposerDocumentID(rawValue: "orphan"), title: "Orphan", blocks: [], role: .page)
        let future = try futureBlock(["pages": [["rawValue": "page-owned-by-future"]]])
        var snapshot = ComposerSnapshot(mosaicTitle: "M", mosaicBlocks: [future], pursuits: [page, orphan])

        let removed = ComposerBoardSync.pruneUnreferenced(&snapshot)
        #expect(removed.map(\.rawValue) == ["orphan"])
        #expect(snapshot.pursuits.map(\.id.rawValue) == ["page-owned-by-future"])
    }

    @Test
    func mediaANewerPieceUsesStaysLinked() throws {
        let future = try futureBlock(["clip": "A1B2C3.mov", "caption": "great swing"])
        let snapshot = ComposerSnapshot(mosaicTitle: "M", mosaicBlocks: [future], pursuits: [])
        let names = ComposerMediaCatalog.references(snapshot: snapshot, mosaicID: UUID()).map(\.fileName)
        #expect(names == ["A1B2C3.mov"])
    }
}

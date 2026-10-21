import CoreGraphics
import Foundation
import PencilKit
import SwiftUI
import Testing

@testable import Mosaic

@MainActor
@Suite
struct ComposerDrawingTests {
    private func stroke(from start: CGPoint, to end: CGPoint) -> PKStroke {
        let points = [start, end].enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(index) * 0.1,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    /// Opacity of one point of `image`, from 0 to 1.
    private func alpha(in image: UIImage, at point: CGPoint) -> CGFloat {
        guard let cgImage = image.cgImage else { return 0 }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            let scale = image.scale
            context.translateBy(x: -point.x * scale, y: -(image.size.height - point.y) * scale)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
            return true
        }
        return drawn ? CGFloat(pixel[3]) / 255 : 0
    }

    @Test
    func newDrawingStartsEmptyWithADrawingArea() {
        let block = ComposerBlock.make(kind: .drawing, position: BlockPosition(x: 0.1, y: 0.1))
        #expect(block.drawingData == nil)
        #expect(block.drawingWidth > 0 && block.drawingHeight > 0)
        #expect(block.canRotate)
    }

    @Test
    func drawingSurvivesSavingAndLoading() throws {
        let drawing = PKDrawing(strokes: [stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 200, y: 120))])
        var block = ComposerBlock.make(kind: .drawing, position: BlockPosition(x: 0.1, y: 0.2))
        block.drawingData = ComposerDrawingMetrics.data(for: drawing)
        block.drawingWidth = 358
        block.style.scale = 1.5
        block.rotation = 15

        let decoded = try JSONDecoder().decode(ComposerBlock.self, from: JSONEncoder().encode(block))
        #expect(decoded == block)
        #expect(ComposerDrawingMetrics.drawing(from: decoded.drawingData).strokes.count == 1)
    }

    @Test
    func emptyInkSavesAsNothing() {
        #expect(ComposerDrawingMetrics.data(for: PKDrawing()) == nil)
        #expect(ComposerDrawingMetrics.drawing(from: nil).strokes.isEmpty)
        #expect(ComposerDrawingMetrics.drawing(from: Data("not a drawing".utf8)).strokes.isEmpty)
    }

    @Test
    func onlyTheInkPicksTheDrawingUp() {
        let drawing = PKDrawing(strokes: [stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 60, y: 20))])
        let rects = ComposerDrawingMetrics.touchRects(of: drawing)
        #expect(rects.count == 1)
        let shape = ComposerInkHitShape(rects: rects, scale: 2)
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 640, height: 560))
        #expect(path.contains(CGPoint(x: 80, y: 40)))
        #expect(!path.contains(CGPoint(x: 400, y: 400)))

        let whole = ComposerInkHitShape(rects: nil, scale: 1).path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(whole.contains(CGPoint(x: 90, y: 90)))
    }

    @Test
    func groupingReachesThePieceUnderADrawing() {
        let video = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0, y: 0))
        var drawing = ComposerBlock.make(kind: .drawing, position: BlockPosition(x: 0, y: 0))
        // A short stroke near the drawing's top-left; the rest of the drawing is empty.
        drawing.drawingData = ComposerDrawingMetrics.data(for: PKDrawing(strokes: [
            stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 60, y: 20))
        ]))
        let box = CGRect(x: 100, y: 100, width: 320, height: 280)
        // Later targets sit in front, the same order the board draws pieces in.
        let targets = [
            ComposerGroupingTarget(block: video, frame: box),
            ComposerGroupingTarget(block: drawing, frame: box)
        ]
        func picked(_ point: CGPoint) -> ComposerBlockID? {
            targets.reversed().first { $0.contains(point) }?.id
        }

        #expect(picked(CGPoint(x: 140, y: 120)) == drawing.id)
        #expect(picked(CGPoint(x: 300, y: 300)) == video.id)

        drawing.style.scale = 2
        let doubled = ComposerGroupingTarget(block: drawing, frame: CGRect(x: 0, y: 0, width: 640, height: 560))
        #expect(doubled.contains(CGPoint(x: 80, y: 40)))
        #expect(!doubled.contains(CGPoint(x: 300, y: 300)))

        // Turned a half turn, the ink sits near the bottom-right instead.
        drawing.style.scale = 1
        drawing.rotation = 180
        let flipped = ComposerGroupingTarget(block: drawing, frame: box)
        #expect(flipped.contains(CGPoint(x: box.maxX - 40, y: box.maxY - 20)))
        #expect(!flipped.contains(CGPoint(x: 140, y: 120)))
    }

    @Test
    func groupedDrawingsLandOnTheVideoInFullScreen() throws {
        var video = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0, y: 0))
        var drawing = ComposerBlock.make(kind: .drawing, position: BlockPosition(x: 0, y: 0))
        drawing.drawingWidth = 200
        drawing.drawingHeight = 100
        drawing.drawingData = ComposerDrawingMetrics.data(for: PKDrawing(strokes: [
            stroke(from: CGPoint(x: 20, y: 50), to: CGPoint(x: 60, y: 50))
        ]))
        var group = ComposerBlock.make(kind: .group, position: BlockPosition(x: 0, y: 0))
        group.groupWidth = 400
        group.groupHeight = 200
        group.groupMembers = [video, drawing]
        let sizes = [video.id: CGSize(width: 200, height: 100), drawing.id: CGSize(width: 200, height: 100)]

        // Same box as the video: the markup scales by 1000 / 200 = 5.
        let data = try #require(ComposerMediaMarkup.data(for: video, in: group, memberSizes: sizes))
        let bounds = ComposerDrawingMetrics.drawing(from: data).bounds
        #expect(abs(bounds.midX - 200) < 12)
        #expect(abs(bounds.midY - 250) < 12)

        // Rendered the way the full-screen viewer does, the ink shows up at that spot.
        let image = try #require(ComposerDrawingMetrics.image(
            of: ComposerDrawingMetrics.drawing(from: data),
            size: CGSize(width: 1000, height: 500),
            scale: 1
        ))
        #expect(alpha(in: image, at: CGPoint(x: 200, y: 250)) > 0.5)
        #expect(alpha(in: image, at: CGPoint(x: 800, y: 100)) < 0.05)

        // A drawing behind the video is hidden by it on the board, so it isn't shown either.
        group.groupMembers = [drawing, video]
        #expect(ComposerMediaMarkup.data(for: video, in: group, memberSizes: sizes) == nil)

        // A drawing off to the side of the video isn't shown.
        var aside = drawing
        aside.position = BlockPosition(x: 0.5, y: 0)
        group.groupMembers = [video, aside]
        #expect(ComposerMediaMarkup.data(for: video, in: group, memberSizes: sizes) == nil)

        // Half-size drawing over a video turned a half turn: the stroke flips to the other side.
        drawing.style.scale = 0.5
        video.rotation = 180
        group.groupMembers = [video, drawing]
        let flipped = try #require(ComposerMediaMarkup.data(for: video, in: group, memberSizes: sizes))
        let turned = ComposerDrawingMetrics.drawing(from: flipped).bounds
        // Stroke center (20, 25) on the group becomes (180, 75) on the turned video, times 5.
        #expect(abs(turned.midX - 900) < 12)
        #expect(abs(turned.midY - 375) < 12)
    }

    @Test
    func groupedDrawingsLineUpWithAFramedPhoto() throws {
        // A Polaroid photo 200 wide: the member is measured with its frame around it.
        var photo = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0, y: 0))
        photo.frameStyle = .polaroid
        let inner = CGSize(width: 200, height: 150)
        let insets = ComposerPhotoFrameModifier.insets(for: .polaroid, width: inner.width)
        let padded = CGSize(width: inner.width + 2 * insets.side, height: inner.height + insets.top + insets.bottom)
        let solved = ComposerPhotoFrameModifier.mediaFrame(inPadded: padded, style: .polaroid)
        #expect(abs(solved.width - inner.width) < 0.01)
        #expect(abs(solved.height - inner.height) < 0.01)
        #expect(abs(solved.minX - insets.side) < 0.01 && abs(solved.minY - insets.top) < 0.01)

        // A stroke over the middle of the photo itself lands in the middle of the viewer's photo.
        var drawing = ComposerBlock.make(kind: .drawing, position: BlockPosition(x: 0, y: 0))
        drawing.drawingWidth = Double(padded.width)
        drawing.drawingHeight = Double(padded.height)
        let middle = CGPoint(x: insets.side + inner.width / 2, y: insets.top + inner.height / 2)
        drawing.drawingData = ComposerDrawingMetrics.data(for: PKDrawing(strokes: [
            stroke(from: CGPoint(x: middle.x - 10, y: middle.y), to: CGPoint(x: middle.x + 10, y: middle.y))
        ]))
        var group = ComposerBlock.make(kind: .group, position: BlockPosition(x: 0, y: 0))
        group.groupWidth = Double(padded.width)
        group.groupHeight = Double(padded.height)
        group.groupMembers = [photo, drawing]
        let data = try #require(ComposerMediaMarkup.data(
            for: photo,
            in: group,
            memberSizes: [photo.id: padded, drawing.id: padded]
        ))
        let bounds = ComposerDrawingMetrics.drawing(from: data).bounds
        let reference = ComposerMediaMarkup.referenceWidth
        #expect(abs(bounds.midX - reference / 2) < 6)
        #expect(abs(bounds.midY - reference * inner.height / inner.width / 2) < 6)
    }

    @Test
    func drawingsRenderAsAnImage() {
        let drawing = PKDrawing(strokes: [stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 100, y: 80))])
        let image = ComposerDrawingMetrics.image(of: drawing, size: CGSize(width: 320, height: 280), scale: 2)
        #expect(image != nil)
        #expect(ComposerDrawingMetrics.image(of: PKDrawing(), size: CGSize(width: 320, height: 280), scale: 2) == nil)
    }

    @Test
    func drawingsCanGoOnJournalPages() {
        let block = ComposerBlock.make(kind: .drawing, position: BlockPosition(x: 0, y: 0))
        #expect(ComposerStore.allowsPlacement(of: block, onMosaic: false, onJournalPage: true))
        #expect(ComposerStore.allowsPlacement(of: block, onMosaic: true, onJournalPage: false))
    }

    // MARK: Pieces from newer versions of the app

    private let futurePiece: [String: Any] = [
        "id": ["rawValue": "future"],
        "kind": "hologram",
        "position": ["x": 0.4, "y": 0.5],
        "tabID": "tab-2",
        "hologramColor": "teal",
        "layers": [1, 2.5, true, NSNull(), ["depth": 3]] as [Any]
    ]

    /// A board saved by a newer app: one piece this version knows and one it doesn't.
    private var futureBoard: String {
        get throws {
            var text = ComposerBlock.make(kind: .text, position: BlockPosition(x: 0.1, y: 0.1))
            text.text = "Hello"
            let page = ComposerPursuit(id: ComposerDocumentID(rawValue: "page-1"), title: "Swing notes", blocks: [text])
            var board = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any])
            var blocks = try #require(board["blocks"] as? [Any])
            blocks.append(futurePiece)
            board["blocks"] = blocks
            return String(decoding: try JSONSerialization.data(withJSONObject: board), as: UTF8.self)
        }
    }

    @Test
    func unknownPiecesDontBreakTheBoard() throws {
        let page = try JSONDecoder().decode(ComposerPursuit.self, from: Data(try futureBoard.utf8))
        #expect(page.blocks.count == 2)
        #expect(page.blocks[0].kind == .text)
        let future = page.blocks[1]
        #expect(future.kind == .unsupported)
        #expect(future.id.rawValue == "future")
        #expect(future.position == BlockPosition(x: 0.4, y: 0.5))
        #expect(future.tabID == "tab-2")
        #expect(!future.canRotate)
    }

    @Test
    func unknownPiecesAreSavedBackUnchanged() throws {
        let page = try JSONDecoder().decode(ComposerPursuit.self, from: Data(try futureBoard.utf8))
        let saved = try JSONEncoder().encode(page)

        let written = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        let writtenFuture = try #require((written["blocks"] as? [[String: Any]])?.last)
        #expect(NSDictionary(dictionary: futurePiece).isEqual(to: writtenFuture))

        let reloaded = try JSONDecoder().decode(ComposerPursuit.self, from: saved)
        #expect(reloaded == page)
    }

    @Test
    func unknownPiecesInsideAGroupSurvive() throws {
        let empty = ComposerBlock.make(kind: .group, position: BlockPosition(x: 0, y: 0))
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(empty)) as? [String: Any])
        json["groupMembers"] = [["id": ["rawValue": "future"], "kind": "confetti", "emoji": "⛳️"]]
        let group = try JSONDecoder().decode(ComposerBlock.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(group.groupMembers.first?.kind == .unsupported)
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(group)) as? [String: Any]
        let member = (saved?["groupMembers"] as? [[String: Any]])?.first
        #expect(member?["kind"] as? String == "confetti")
        #expect(member?["emoji"] as? String == "⛳️")
    }
}

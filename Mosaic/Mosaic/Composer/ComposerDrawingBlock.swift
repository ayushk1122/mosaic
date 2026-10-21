import PencilKit
import SwiftUI
import UIKit

enum ComposerDrawingMetrics {
    static let defaultSize = CGSize(width: 320, height: 280)
    /// Strokes are saved inside the board, so a drawing stops taking new ink past this size.
    static let maximumBytes = 1_000_000
    /// All drawings on one board together. Saved as base64, this keeps a board well under the
    /// server's 2 MB limit with room for everything else on it.
    static let boardBudget = 1_200_000
    static let minimumScale = 0.3
    static let pageMargin: CGFloat = 16
    /// Room around each stroke that still picks the drawing up, so thin lines are easy to grab.
    static let touchPadding: CGFloat = 14

    static func baseSize(of block: ComposerBlock) -> CGSize {
        CGSize(width: max(block.drawingWidth, 40), height: max(block.drawingHeight, 40))
    }

    static func drawing(from data: Data?) -> PKDrawing {
        guard let data, let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    /// No ink saves as nothing, so an empty drawing is recognizable without decoding it.
    static func data(for drawing: PKDrawing) -> Data? {
        drawing.strokes.isEmpty ? nil : drawing.dataRepresentation()
    }

    /// False for saved strokes this device can't read, which must not be drawn over and replaced.
    static func isReadable(_ data: Data?) -> Bool {
        guard let data else { return true }
        return (try? PKDrawing(data: data)) != nil
    }

    /// Stroke bytes held by these pieces, including drawings inside groups.
    static func bytes(in blocks: [ComposerBlock]) -> Int {
        blocks.reduce(0) { total, block in
            total + (block.drawingData?.count ?? 0) + bytes(in: block.groupMembers)
        }
    }

    /// Room left around the ink when a finished drawing's box shrinks to fit it.
    static let inkMargin: CGFloat = 12
    static let minimumSide: CGFloat = 32

    /// The box, in the drawing's own points, that just fits its visible ink. Nil when there's no
    /// ink or the box already fits.
    static func inkFrame(of block: ComposerBlock) -> CGRect? {
        let size = baseSize(of: block)
        let box = CGRect(origin: .zero, size: size)
        let visible = drawing(from: block.drawingData).strokes
            .map(\.renderBounds)
            .filter { $0.intersects(box) }
            .reduce(CGRect.null) { $0.union($1.intersection(box)) }
        guard !visible.isNull else { return nil }
        var frame = visible.insetBy(dx: -inkMargin, dy: -inkMargin)
        if frame.width < minimumSide { frame = frame.insetBy(dx: (frame.width - minimumSide) / 2, dy: 0) }
        if frame.height < minimumSide { frame = frame.insetBy(dx: 0, dy: (frame.height - minimumSide) / 2) }
        let fits = abs(frame.minX) < 1 && abs(frame.minY) < 1
            && abs(frame.width - size.width) < 1 && abs(frame.height - size.height) < 1
        return fits ? nil : frame
    }

    /// The box to draw in: across the page and at least as tall as a new drawing, always
    /// covering the current box. Nil for tilted drawings, which keep their box, or when nothing changes.
    static func drawingRoomFrame(of block: ComposerBlock, origin: CGPoint, pageWidth: CGFloat) -> CGRect? {
        guard block.rotation == 0, pageWidth > 1 else { return nil }
        let scale = CGFloat(max(block.style.scale, 0.05))
        let size = baseSize(of: block)
        let left = min((pageMargin - origin.x) / scale, 0)
        let right = max((pageWidth - pageMargin - origin.x) / scale, size.width)
        let shortfall = max(defaultSize.height - size.height * scale, 0) / 2 / scale
        let top = max(-shortfall, -origin.y / scale)
        let bottom = size.height + shortfall
        let frame = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        let unchanged = abs(frame.minX) < 1 && abs(frame.minY) < 1
            && abs(frame.width - size.width) < 1 && abs(frame.height - size.height) < 1
        return unchanged ? nil : frame
    }

    /// Gives the drawing the box `frame` (in its current points) without moving any ink on the
    /// board, tilt and size included. `origin` is the box's top-left on the board; returns the new one.
    static func reframed(_ block: ComposerBlock, to frame: CGRect, origin: CGPoint) -> (block: ComposerBlock, origin: CGPoint) {
        let scale = CGFloat(max(block.style.scale, 0.05))
        let size = baseSize(of: block)
        let center = CGPoint(x: origin.x + size.width * scale / 2, y: origin.y + size.height * scale / 2)
        let shift = CGPoint(x: (frame.midX - size.width / 2) * scale, y: (frame.midY - size.height / 2) * scale)
        let radians = CGFloat(block.rotation * .pi / 180)
        let newCenter = CGPoint(
            x: center.x + shift.x * cos(radians) - shift.y * sin(radians),
            y: center.y + shift.x * sin(radians) + shift.y * cos(radians)
        )
        var updated = block
        let moved = drawing(from: block.drawingData)
            .transformed(using: CGAffineTransform(translationX: -frame.minX, y: -frame.minY))
        updated.drawingData = data(for: moved)
        updated.drawingWidth = Double(frame.width)
        updated.drawingHeight = Double(frame.height)
        let newOrigin = CGPoint(
            x: newCenter.x - frame.width * scale / 2,
            y: newCenter.y - frame.height * scale / 2
        )
        return (updated, newOrigin)
    }

    /// How large one drawing may grow on a board, given the other drawings already there.
    static func byteLimit(for blockID: ComposerBlockID, on board: [ComposerBlock]) -> Int {
        let others = bytes(in: board) - bytes(in: board.filter { $0.id == blockID })
        return max(min(maximumBytes, boardBudget - others), 0)
    }

    /// Drawn as light-mode ink, so a black pen stays black on every board and in dark mode.
    static func image(of drawing: PKDrawing, size: CGSize, scale: CGFloat) -> UIImage? {
        guard !drawing.strokes.isEmpty, size.width > 0, size.height > 0 else { return nil }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: CGRect(origin: .zero, size: size), scale: max(scale, 1))
        }
        return image
    }

    /// The areas that pick the drawing up, in its own points: around each stroke, or around all
    /// of them once there are too many to test one by one.
    static func touchRects(of drawing: PKDrawing) -> [CGRect] {
        let bounds = drawing.strokes.count > 400 ? [drawing.bounds] : drawing.strokes.map(\.renderBounds)
        return bounds.map { $0.insetBy(dx: -touchPadding, dy: -touchPadding) }
    }
}

/// Drawings grouped with a photo or video, moved onto that media's frame so the full-screen
/// viewer can lay them over it.
enum ComposerMediaMarkup {
    /// The media's width in markup points; the viewer scales the markup to the media's size.
    static let referenceWidth: CGFloat = 1000

    /// Strokes from drawings in front of `media` in `group` that land on the media's frame, or nil.
    static func data(
        for media: ComposerBlock,
        in group: ComposerBlock,
        memberSizes: [ComposerBlockID: CGSize]
    ) -> Data? {
        guard let mediaIndex = group.groupMembers.firstIndex(where: { $0.id == media.id }),
              let mediaSize = memberSizes[media.id], mediaSize.width > 1, mediaSize.height > 1 else { return nil }
        let base = CGSize(width: max(group.groupWidth, 1), height: max(group.groupHeight, 1))
        let mediaCenter = CGPoint(
            x: CGFloat(media.position.x) * base.width + mediaSize.width / 2,
            y: CGFloat(media.position.y) * base.height + mediaSize.height / 2
        )
        let toMarkup = CGAffineTransform(translationX: -mediaCenter.x, y: -mediaCenter.y)
            .concatenating(CGAffineTransform(rotationAngle: -radians(media.rotation)))
            .concatenating(CGAffineTransform(translationX: mediaSize.width / 2, y: mediaSize.height / 2))
            .concatenating(CGAffineTransform(scaleX: referenceWidth / mediaSize.width, y: referenceWidth / mediaSize.width))
        let frame = CGRect(x: 0, y: 0, width: referenceWidth, height: referenceWidth * mediaSize.height / mediaSize.width)

        var strokes: [PKStroke] = []
        for drawing in group.groupMembers[(mediaIndex + 1)...] where drawing.kind == .drawing {
            let size = ComposerDrawingMetrics.baseSize(of: drawing)
            // The board only shows ink inside the drawing's box, so ink moved past it stays hidden here too.
            let box = CGRect(origin: .zero, size: size)
            let ink = PKDrawing(strokes: ComposerDrawingMetrics.drawing(from: drawing.drawingData).strokes.filter {
                $0.renderBounds.intersects(box)
            })
            guard !ink.strokes.isEmpty else { continue }
            let scale = CGFloat(max(drawing.style.scale, 0.05))
            let shown = CGSize(width: size.width * scale, height: size.height * scale)
            let center = CGPoint(
                x: CGFloat(drawing.position.x) * base.width + shown.width / 2,
                y: CGFloat(drawing.position.y) * base.height + shown.height / 2
            )
            let toGroup = CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(translationX: -shown.width / 2, y: -shown.height / 2))
                .concatenating(CGAffineTransform(rotationAngle: radians(drawing.rotation)))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
            let placed = ink.transformed(using: toGroup.concatenating(toMarkup))
            guard placed.bounds.intersects(frame) else { continue }
            strokes += placed.strokes
        }
        return strokes.isEmpty ? nil : PKDrawing(strokes: strokes).dataRepresentation()
    }

    private static func radians(_ degrees: Double) -> CGFloat {
        CGFloat(degrees * .pi / 180)
    }
}

/// Markup laid over media in the full-screen viewer, filling the media's frame.
struct ComposerMediaMarkupOverlay: View {
    let data: Data

    @Environment(\.displayScale) private var displayScale
    @State private var rendered: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                if let rendered {
                    Image(uiImage: rendered)
                        .resizable()
                        .interpolation(.high)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: ComposerDrawingRenderKey(data: data, size: proxy.size, pixelScale: displayScale)) {
                guard proxy.size.width > 1, proxy.size.height > 1 else { return }
                let width = ComposerMediaMarkup.referenceWidth
                let size = CGSize(width: width, height: width * proxy.size.height / proxy.size.width)
                rendered = ComposerDrawingMetrics.image(
                    of: ComposerDrawingMetrics.drawing(from: data),
                    size: size,
                    scale: proxy.size.width / width * displayScale
                )
            }
        }
        .allowsHitTesting(false)
    }
}

struct ComposerDrawingCanvasBlock: View {
    @Binding var block: ComposerBlock
    var livePinchScale: CGFloat
    var isSelected: Bool
    var isDrawing: Bool
    var isViewing: Bool
    var byteLimit: Int = ComposerDrawingMetrics.maximumBytes
    var onFullChange: (Bool) -> Void = { _ in }
    var inkSession: ComposerInkSession?

    @Environment(\.displayScale) private var displayScale
    @State private var rendered: UIImage?
    @State private var touchRects: [CGRect] = []

    private var scale: CGFloat { CGFloat(max(block.style.scale, 0.05)) }

    var body: some View {
        let base = ComposerDrawingMetrics.baseSize(of: block)
        let shown = scale * livePinchScale
        let size = CGSize(width: base.width * shown, height: base.height * shown)
        let isEmpty = block.drawingData == nil
        ZStack(alignment: .topLeading) {
            if isDrawing {
                ComposerInkCanvas(
                    data: $block.drawingData,
                    baseSize: base,
                    zoom: scale,
                    byteLimit: byteLimit,
                    onFullChange: onFullChange,
                    session: inkSession
                )
            } else if let rendered {
                Image(uiImage: rendered)
                    .resizable()
                    .interpolation(.high)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .overlay {
            if !isViewing, isDrawing || (isEmpty && isSelected) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .shadow(color: .black.opacity(0.35), radius: 1)
                    .allowsHitTesting(false)
            }
        }
        // Only the ink picks the drawing up, so pieces behind it stay reachable. Once selected,
        // or while being drawn in, its whole box responds.
        .contentShape(ComposerInkHitShape(
            rects: isDrawing || isSelected ? nil : (isEmpty ? [] : touchRects),
            scale: shown
        ))
        .allowsHitTesting(!isViewing)
        .accessibilityElement()
        .accessibilityLabel("Drawing")
        .task(id: ComposerDrawingRenderKey(data: block.drawingData, size: base, pixelScale: scale * displayScale)) {
            let drawing = ComposerDrawingMetrics.drawing(from: block.drawingData)
            rendered = ComposerDrawingMetrics.image(of: drawing, size: base, scale: scale * displayScale)
            touchRects = ComposerDrawingMetrics.touchRects(of: drawing)
        }
    }
}

private struct ComposerDrawingRenderKey: Equatable {
    var data: Data?
    var size: CGSize
    var pixelScale: CGFloat
}

/// The whole box when `rects` is nil, otherwise just the given areas, scaled to the piece's size.
struct ComposerInkHitShape: Shape {
    var rects: [CGRect]?
    var scale: CGFloat

    func path(in rect: CGRect) -> Path {
        guard let rects else { return Path(rect) }
        var path = Path()
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        for area in rects {
            path.addRect(area.applying(transform).intersection(rect))
        }
        return path
    }
}

/// Lets the board collect the open canvas's strokes on Done. PencilKit reports a finished stroke
/// a moment after the finger lifts, so a quick Done would otherwise see the drawing as empty.
final class ComposerInkSession {
    fileprivate var commit: (() -> Void)?

    func commitPendingInk() {
        commit?()
    }
}

/// PencilKit's canvas with Apple's tool palette. Draws in the drawing's own points and zooms to
/// the piece's scale, so strokes keep their place however large the piece is.
struct ComposerInkCanvas: UIViewRepresentable {
    @Binding var data: Data?
    var baseSize: CGSize
    var zoom: CGFloat
    var byteLimit: Int
    var onFullChange: (Bool) -> Void
    var session: ComposerInkSession?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ComposerPKCanvasView {
        let canvas = ComposerPKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawingPolicy = .anyInput
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.showsHorizontalScrollIndicator = false
        canvas.showsVerticalScrollIndicator = false
        canvas.bounces = false
        canvas.bouncesZoom = false
        canvas.isScrollEnabled = false
        canvas.pinchGestureRecognizer?.isEnabled = false
        canvas.minimumZoomScale = 0.05
        canvas.maximumZoomScale = 8
        context.coordinator.parent = self
        context.coordinator.load(data, into: canvas)
        canvas.delegate = context.coordinator
        context.coordinator.fit(canvas, baseSize: baseSize, zoom: zoom)
        context.coordinator.showTools(for: canvas)
        connect(canvas, coordinator: context.coordinator)
        return canvas
    }

    private func connect(_ canvas: ComposerPKCanvasView, coordinator: Coordinator) {
        session?.commit = { [weak canvas, weak coordinator] in
            guard let canvas, let coordinator else { return }
            coordinator.canvasViewDrawingDidChange(canvas)
        }
    }

    func updateUIView(_ canvas: ComposerPKCanvasView, context: Context) {
        context.coordinator.parent = self
        connect(canvas, coordinator: context.coordinator)
        context.coordinator.fit(canvas, baseSize: baseSize, zoom: zoom)
        // The board's own Undo can change the strokes while drawing.
        if data != context.coordinator.lastData {
            context.coordinator.load(data, into: canvas)
        }
    }

    static func dismantleUIView(_ canvas: ComposerPKCanvasView, coordinator: Coordinator) {
        coordinator.hideTools(for: canvas)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: ComposerInkCanvas?
        private(set) var lastData: Data?
        private var lastDrawing = PKDrawing()
        private var isLoading = false
        private var isFull = false
        private let toolPicker: PKToolPicker = {
            // White first, like new text, since boards start dark. The palette then remembers
            // the last tool and color between drawings.
            let pen = PKToolPickerInkingItem(type: .pen, color: .white, width: 4)
            let picker = PKToolPicker(toolItems: [
                pen,
                PKToolPickerInkingItem(type: .marker, color: .systemYellow),
                PKToolPickerInkingItem(type: .pencil, color: .white),
                PKToolPickerEraserItem(type: .vector),
                PKToolPickerLassoItem(),
                PKToolPickerRulerItem()
            ])
            picker.selectedToolItemIdentifier = pen.identifier
            picker.stateAutosaveName = "composer.drawing"
            return picker
        }()

        func load(_ data: Data?, into canvas: PKCanvasView) {
            isLoading = true
            let drawing = ComposerDrawingMetrics.drawing(from: data)
            canvas.drawing = drawing
            lastDrawing = drawing
            lastData = data
            // PencilKit's own undo would otherwise bring back strokes the board just replaced.
            canvas.undoManager?.removeAllActions()
            isLoading = false
        }

        func fit(_ canvas: PKCanvasView, baseSize: CGSize, zoom: CGFloat) {
            if abs(canvas.zoomScale - zoom) > 0.0001 {
                canvas.zoomScale = zoom
            }
            let size = CGSize(width: baseSize.width * zoom, height: baseSize.height * zoom)
            if canvas.contentSize != size {
                canvas.contentSize = size
            }
            if canvas.contentOffset != .zero {
                canvas.contentOffset = .zero
            }
        }

        func showTools(for canvas: ComposerPKCanvasView) {
            toolPicker.colorUserInterfaceStyle = .light
            toolPicker.addObserver(canvas)
            toolPicker.setVisible(true, forFirstResponder: canvas)
            canvas.wantsFirstResponder = true
        }

        func hideTools(for canvas: ComposerPKCanvasView) {
            canvas.wantsFirstResponder = false
            toolPicker.setVisible(false, forFirstResponder: canvas)
            toolPicker.removeObserver(canvas)
            canvas.resignFirstResponder()
        }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            guard !isLoading else { return }
            let drawing = canvas.drawing
            let data = ComposerDrawingMetrics.data(for: drawing)
            let limit = parent?.byteLimit ?? ComposerDrawingMetrics.maximumBytes
            if let data, data.count > limit, data.count > (lastData?.count ?? 0) {
                isLoading = true
                canvas.drawing = lastDrawing
                canvas.undoManager?.removeAllActions()
                isLoading = false
                setFull(true)
                return
            }
            lastDrawing = drawing
            lastData = data
            setFull(false)
            parent?.data = data
        }

        private func setFull(_ full: Bool) {
            guard full != isFull else { return }
            isFull = full
            parent?.onFullChange(full)
        }
    }
}

/// Takes focus once it's on screen, which is what shows the tool palette.
final class ComposerPKCanvasView: PKCanvasView {
    var wantsFirstResponder = false {
        didSet { claimFocusIfNeeded() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        claimFocusIfNeeded()
    }

    private func claimFocusIfNeeded() {
        guard wantsFirstResponder, window != nil, !isFirstResponder else { return }
        becomeFirstResponder()
    }
}

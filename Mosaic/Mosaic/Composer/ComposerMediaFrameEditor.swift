import AVFoundation
import SwiftUI

struct MediaFraming {
    static func fillSize(contentAspect: CGFloat, in frame: CGSize) -> CGSize {
        let aspect = max(contentAspect, 0.01)
        let frameAspect = frame.width / max(frame.height, 1)
        if aspect > frameAspect {
            let height = frame.height
            return CGSize(width: height * aspect, height: height)
        }
        let width = frame.width
        return CGSize(width: width, height: width / aspect)
    }

    static func panLimits(contentAspect: CGFloat, frame: CGSize, zoom: CGFloat) -> CGSize {
        let filled = fillSize(contentAspect: contentAspect, in: frame)
        let scaled = CGSize(width: filled.width * zoom, height: filled.height * zoom)
        return CGSize(
            width: max(0, (scaled.width - frame.width) / 2),
            height: max(0, (scaled.height - frame.height) / 2)
        )
    }

    static func clampedPan(_ pan: CGSize, limits: CGSize) -> CGSize {
        CGSize(
            width: min(max(pan.width, -limits.width), limits.width),
            height: min(max(pan.height, -limits.height), limits.height)
        )
    }
}

enum MediaCropEdge: Equatable {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight
    case center

    var movesLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft || self == .center }
    var movesRight: Bool { self == .right || self == .topRight || self == .bottomRight || self == .center }
    var movesTop: Bool { self == .top || self == .topLeft || self == .topRight || self == .center }
    var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight || self == .center }
}

/// The visible crop, in fractions of the full photo. Edges resize one side; corners resize two.
enum MediaCropMath {
    struct Window: Equatable {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat

        func frameAspect(contentAspect: CGFloat) -> CGFloat {
            (width / max(height, 0.001)) * max(contentAspect, 0.01)
        }

        func rect(in imageRect: CGRect) -> CGRect {
            CGRect(
                x: imageRect.minX + x * imageRect.width,
                y: imageRect.minY + y * imageRect.height,
                width: width * imageRect.width,
                height: height * imageRect.height
            )
        }
    }

    static let minimumSpan: CGFloat = 0.12

    static func window(
        contentAspect: CGFloat,
        frameAspect: CGFloat,
        zoom: CGFloat,
        panX: CGFloat,
        panY: CGFloat
    ) -> Window {
        let frame = CGSize(width: max(frameAspect, 0.01), height: 1)
        let z = min(max(zoom, 1), 4)
        let base = MediaFraming.fillSize(contentAspect: contentAspect, in: frame)
        let scaled = CGSize(width: base.width * z, height: base.height * z)
        let pan = MediaFraming.clampedPan(
            CGSize(width: panX * frame.width, height: panY * frame.height),
            limits: MediaFraming.panLimits(contentAspect: contentAspect, frame: frame, zoom: z)
        )
        let originX = (frame.width - scaled.width) / 2 + pan.width
        let originY = (frame.height - scaled.height) / 2 + pan.height
        return Window(
            x: (-originX) / max(scaled.width, 0.001),
            y: (-originY) / max(scaled.height, 0.001),
            width: frame.width / max(scaled.width, 0.001),
            height: frame.height / max(scaled.height, 0.001)
        )
    }

    static func framing(window: Window, contentAspect: CGFloat) -> (zoom: CGFloat, panX: CGFloat, panY: CGFloat, frameAspect: CGFloat) {
        let aspect = min(max(window.frameAspect(contentAspect: contentAspect), MediaFrameShape.minimumAspect), MediaFrameShape.maximumAspect)
        let frame = CGSize(width: aspect, height: 1)
        let base = MediaFraming.fillSize(contentAspect: contentAspect, in: frame)
        let rawZoom = (frame.width / max(window.width, 0.001)) / max(base.width, 0.001)
        let zoom = min(max(rawZoom, 1), 4)
        let scaled = CGSize(width: base.width * zoom, height: base.height * zoom)
        let u = window.x + window.width / 2
        let v = window.y + window.height / 2
        let pan = MediaFraming.clampedPan(
            CGSize(width: scaled.width * (0.5 - u), height: scaled.height * (0.5 - v)),
            limits: MediaFraming.panLimits(contentAspect: contentAspect, frame: frame, zoom: zoom)
        )
        return (
            zoom,
            frame.width > 0 ? pan.width / frame.width : 0,
            frame.height > 0 ? pan.height / frame.height : 0,
            aspect
        )
    }

    /// Largest centered window of `aspect` inside the photo.
    static func covered(aspect: CGFloat, contentAspect: CGFloat) -> Window {
        let ratio = max(aspect, 0.01) / max(contentAspect, 0.01)
        var width: CGFloat = 1
        var height = width / ratio
        if height > 1 {
            height = 1
            width = height * ratio
        }
        if width > 1 {
            width = 1
            height = width / ratio
        }
        return Window(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    static func window(aspect: CGFloat, centeredOn current: Window, contentAspect: CGFloat) -> Window {
        let ratio = max(aspect, 0.01) / max(contentAspect, 0.01)
        let centerX = current.x + current.width / 2
        let centerY = current.y + current.height / 2
        var height = current.height
        var width = height * ratio
        if width > 1 {
            width = 1
            height = width / ratio
        }
        if height > 1 {
            height = 1
            width = height * ratio
        }
        var window = Window(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
        window = parked(window)
        return clampZoom(window, contentAspect: contentAspect, edge: .center)
    }

    static func moved(_ start: Window, translation: CGSize, imageSize: CGSize) -> Window {
        guard imageSize.width > 1, imageSize.height > 1 else { return start }
        var window = start
        window.x = start.x + translation.width / imageSize.width
        window.y = start.y + translation.height / imageSize.height
        return parked(window)
    }

    static func scaled(_ start: Window, factor: CGFloat, contentAspect: CGFloat) -> Window {
        let scale = min(max(factor, 0.2), 8)
        let centerX = start.x + start.width / 2
        let centerY = start.y + start.height / 2
        let width = start.width / scale
        let height = start.height / scale
        var window = Window(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
        window = parked(window)
        window = clampSpan(window, edge: .center)
        window = clampAspect(window, contentAspect: contentAspect, edge: .center)
        return clampZoom(window, contentAspect: contentAspect, edge: .center)
    }

    static func resized(
        start: Window,
        edge: MediaCropEdge,
        translation: CGSize,
        imageSize: CGSize,
        contentAspect: CGFloat
    ) -> Window {
        guard imageSize.width > 1, imageSize.height > 1 else { return start }
        let dx = translation.width / imageSize.width
        let dy = translation.height / imageSize.height
        var window = start
        if edge.movesLeft {
            let proposed = min(max(start.x + dx, 0), start.x + start.width - minimumSpan)
            window.width = start.width - (proposed - start.x)
            window.x = proposed
        }
        if edge.movesRight {
            window.width = min(max(start.width + dx, minimumSpan), 1 - start.x)
        }
        if edge.movesTop {
            let proposed = min(max(start.y + dy, 0), start.y + start.height - minimumSpan)
            window.height = start.height - (proposed - start.y)
            window.y = proposed
        }
        if edge.movesBottom {
            window.height = min(max(start.height + dy, minimumSpan), 1 - start.y)
        }
        window = parked(window)
        window = clampAspect(window, contentAspect: contentAspect, edge: edge)
        return clampZoom(window, contentAspect: contentAspect, edge: edge)
    }

    private static func parked(_ window: Window) -> Window {
        var window = window
        window.width = min(max(window.width, minimumSpan), 1)
        window.height = min(max(window.height, minimumSpan), 1)
        window.x = min(max(window.x, 0), 1 - window.width)
        window.y = min(max(window.y, 0), 1 - window.height)
        return window
    }

    private static func clampSpan(_ window: Window, edge: MediaCropEdge) -> Window {
        var window = window
        if window.width < minimumSpan {
            let extra = minimumSpan - window.width
            if edge.movesLeft && !edge.movesRight {
                window.x -= extra
            } else if edge.movesLeft {
                window.x -= extra / 2
            }
            window.width = minimumSpan
        }
        if window.height < minimumSpan {
            let extra = minimumSpan - window.height
            if edge.movesTop && !edge.movesBottom {
                window.y -= extra
            } else if edge.movesTop {
                window.y -= extra / 2
            }
            window.height = minimumSpan
        }
        return parked(window)
    }

    private static func clampAspect(_ window: Window, contentAspect: CGFloat, edge: MediaCropEdge) -> Window {
        var window = window
        let content = max(contentAspect, 0.01)
        let maxWidth = window.height * (MediaFrameShape.maximumAspect / content)
        let minWidth = window.height * (MediaFrameShape.minimumAspect / content)
        if window.width > maxWidth {
            window = setWidth(window, maxWidth, edge: edge)
        } else if window.width < minWidth {
            window = setWidth(window, minWidth, edge: edge)
        }
        let maxHeight = window.width * content / MediaFrameShape.minimumAspect
        let minHeight = window.width * content / MediaFrameShape.maximumAspect
        if window.height > maxHeight {
            window = setHeight(window, maxHeight, edge: edge)
        } else if window.height < minHeight {
            window = setHeight(window, minHeight, edge: edge)
        }
        return parked(window)
    }

    private static func setWidth(_ window: Window, _ width: CGFloat, edge: MediaCropEdge) -> Window {
        var window = window
        let next = min(max(width, minimumSpan), 1)
        let delta = next - window.width
        if edge.movesLeft && !edge.movesRight {
            window.x -= delta
        } else if edge.movesLeft && edge.movesRight {
            window.x -= delta / 2
        }
        window.width = next
        return window
    }

    private static func setHeight(_ window: Window, _ height: CGFloat, edge: MediaCropEdge) -> Window {
        var window = window
        let next = min(max(height, minimumSpan), 1)
        let delta = next - window.height
        if edge.movesTop && !edge.movesBottom {
            window.y -= delta
        } else if edge.movesTop && edge.movesBottom {
            window.y -= delta / 2
        }
        window.height = next
        return window
    }

    private static func clampZoom(_ window: Window, contentAspect: CGFloat, edge: MediaCropEdge) -> Window {
        let window = parked(window)
        let zoom = framing(window: window, contentAspect: contentAspect).zoom
        guard zoom > 3.99 else { return window }
        let factor = zoom / 4
        return parked(setWidth(setHeight(window, window.height * factor, edge: edge), window.width * factor, edge: edge))
    }
}

func mediaClipShape(_ shape: MediaFrameShape) -> AnyShape {
    switch shape {
    case .rectangle, .square:
        AnyShape(Rectangle())
    case .rounded, .landscape, .wide, .banner:
        AnyShape(MediaRoundedRect())
    case .roundedRectangle:
        AnyShape(MediaRoundedRectangle())
    case .circle:
        AnyShape(Ellipse())
    case .oval:
        AnyShape(Ellipse())
    case .capsule:
        AnyShape(Capsule())
    case .triangle:
        AnyShape(MediaTriangle())
    case .diamond:
        AnyShape(MediaRegularPolygon(sides: 4))
    case .pentagon:
        AnyShape(MediaRegularPolygon(sides: 5))
    case .hexagon:
        AnyShape(MediaRegularPolygon(sides: 6))
    case .octagon:
        AnyShape(MediaRegularPolygon(sides: 8))
    case .star:
        AnyShape(MediaStar())
    case .heart:
        AnyShape(MediaHeart())
    }
}

private struct VideoTrimRequest: Identifiable {
    let id = UUID()
    let url: URL
    let maximumDuration: TimeInterval
}

struct ComposerMediaFrameEditor: View {
    @Environment(\.composerMediaVersions) private var mediaVersions
    let mediaURL: URL
    let isVideo: Bool
    let initialShape: MediaFrameShape
    let initialZoom: Double
    let initialPanX: Double
    let initialPanY: Double
    let initialFrameAspect: Double
    var onCancel: () -> Void
    var onDone: (MediaFrameShape, Double, Double, Double, Double) -> Void
    var onReplaceVideo: (URL) -> URL? = { _ in nil }

    @State private var shape: MediaFrameShape
    @State private var zoom: CGFloat
    @State private var panX: CGFloat
    @State private var panY: CGFloat
    @State private var frameAspect: CGFloat
    @State private var image: UIImage?
    @State private var aspect: CGFloat = 1
    @State private var isReady = false
    @State private var stageSize: CGSize = CGSize(width: 320, height: 420)
    @State private var crop = MediaCropMath.Window(x: 0, y: 0, width: 1, height: 1)
    @State private var cropOrigin: MediaCropMath.Window?
    @State private var moveOrigin: MediaCropMath.Window?
    @State private var activeEdge: MediaCropEdge?
    @State private var pinchOriginWindow: MediaCropMath.Window?
    @State private var playbackURL: URL
    @State private var trimRequest: VideoTrimRequest?
    @State private var trimFailed = false

    init(
        mediaURL: URL,
        isVideo: Bool,
        initialShape: MediaFrameShape,
        initialZoom: Double,
        initialPanX: Double,
        initialPanY: Double,
        initialFrameAspect: Double,
        onCancel: @escaping () -> Void,
        onDone: @escaping (MediaFrameShape, Double, Double, Double, Double) -> Void,
        onReplaceVideo: @escaping (URL) -> URL? = { _ in nil }
    ) {
        self.mediaURL = mediaURL
        self.isVideo = isVideo
        self.initialShape = initialShape
        self.initialZoom = initialZoom
        self.initialPanX = initialPanX
        self.initialPanY = initialPanY
        self.initialFrameAspect = initialFrameAspect
        self.onCancel = onCancel
        self.onDone = onDone
        self.onReplaceVideo = onReplaceVideo
        _shape = State(initialValue: initialShape)
        _playbackURL = State(initialValue: mediaURL)
        _zoom = State(initialValue: CGFloat(min(max(initialZoom, 1), 4)))
        _panX = State(initialValue: CGFloat(initialPanX))
        _panY = State(initialValue: CGFloat(initialPanY))
        _frameAspect = State(initialValue: Self.startingAspect(stored: initialFrameAspect, shape: initialShape))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Drag an edge to crop · Drag to move · Pinch to zoom")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.bottom, 8)
                aspectControl
                shapeChoices
            }
            .background(Color.black)
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 16) {
                        if isVideo {
                            Button("Trim", action: beginTrim)
                        }
                        Button("Done", action: commit)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .fullScreenCover(item: $trimRequest) { request in
            ComposerVideoTrimEditor(url: request.url, maximumDuration: request.maximumDuration) {
                trimRequest = nil
            } onSave: { editedURL in
                if let saved = onReplaceVideo(editedURL) {
                    playbackURL = saved
                }
                trimRequest = nil
            }
            .ignoresSafeArea()
        }
        .alert("This video can’t be trimmed on this device.", isPresented: $trimFailed) {
            Button("OK", role: .cancel) {}
        }
        .task(id: ComposerMediaLoadKey(playbackURL, versions: mediaVersions)) {
            if isVideo {
                let loadedAspect = await Self.videoAspect(at: playbackURL)
                guard !Task.isCancelled else { return }
                aspect = loadedAspect
            } else {
                let loaded = UIImage(contentsOfFile: playbackURL.path)
                image = loaded
                if let loaded, loaded.size.height > 0 {
                    aspect = loaded.size.width / loaded.size.height
                }
            }
            if initialFrameAspect <= 0.05, shape.presetAspect == nil {
                frameAspect = min(max(aspect, MediaFrameShape.minimumAspect), MediaFrameShape.maximumAspect)
            }
            crop = MediaCropMath.window(
                contentAspect: aspect,
                frameAspect: frameAspect,
                zoom: zoom,
                panX: panX,
                panY: panY
            )
            isReady = true
        }
    }

    private var stage: some View {
        GeometryReader { proxy in
            let imageRect = imageRect(in: proxy.size)
            let cropRect = crop.rect(in: imageRect)
            ZStack {
                if isReady {
                    cropStage(imageRect: imageRect, cropRect: cropRect)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .coordinateSpace(name: "cropStage")
            .gesture(moveGesture(imageSize: imageRect.size))
            .simultaneousGesture(pinchGesture())
            .onAppear { stageSize = proxy.size }
            .onChange(of: proxy.size) { _, newSize in
                stageSize = newSize
            }
        }
    }

    private func cropStage(imageRect: CGRect, cropRect: CGRect) -> some View {
        let clip = mediaClipShape(shape)
        return ZStack {
            previewContent
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)
            Color.black.opacity(0.55)
                .overlay {
                    clip
                        .frame(width: cropRect.width, height: cropRect.height)
                        .position(x: cropRect.midX, y: cropRect.midY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .allowsHitTesting(false)
            clip
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .allowsHitTesting(false)
            if activeEdge != nil {
                cropGrid(in: cropRect)
            }
            cropHandles(around: cropRect, imageSize: imageRect.size)
        }
    }

    private func cropGrid(in rect: CGRect) -> some View {
        ZStack {
            ForEach(1..<3, id: \.self) { index in
                Rectangle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 0.5, height: rect.height)
                    .position(x: rect.minX + rect.width * CGFloat(index) / 3, y: rect.midY)
                Rectangle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: rect.width, height: 0.5)
                    .position(x: rect.midX, y: rect.minY + rect.height * CGFloat(index) / 3)
            }
        }
        .allowsHitTesting(false)
    }

    private func cropHandles(around rect: CGRect, imageSize: CGSize) -> some View {
        ZStack {
            edgeHandle(.top, at: CGPoint(x: rect.midX, y: rect.minY), imageSize: imageSize) {
                Capsule().frame(width: 28, height: 5)
            }
            edgeHandle(.bottom, at: CGPoint(x: rect.midX, y: rect.maxY), imageSize: imageSize) {
                Capsule().frame(width: 28, height: 5)
            }
            edgeHandle(.left, at: CGPoint(x: rect.minX, y: rect.midY), imageSize: imageSize) {
                Capsule().frame(width: 5, height: 28)
            }
            edgeHandle(.right, at: CGPoint(x: rect.maxX, y: rect.midY), imageSize: imageSize) {
                Capsule().frame(width: 5, height: 28)
            }
            cornerHandle(.topLeft, at: CGPoint(x: rect.minX, y: rect.minY), imageSize: imageSize)
            cornerHandle(.topRight, at: CGPoint(x: rect.maxX, y: rect.minY), imageSize: imageSize)
            cornerHandle(.bottomLeft, at: CGPoint(x: rect.minX, y: rect.maxY), imageSize: imageSize)
            cornerHandle(.bottomRight, at: CGPoint(x: rect.maxX, y: rect.maxY), imageSize: imageSize)
        }
    }

    private func edgeHandle<Mark: View>(_ edge: MediaCropEdge, at point: CGPoint, imageSize: CGSize, @ViewBuilder mark: () -> Mark) -> some View {
        mark()
            .foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(point)
            .highPriorityGesture(edgeGesture(edge, imageSize: imageSize))
            .accessibilityLabel(edgeLabel(edge))
    }

    private func cornerHandle(_ edge: MediaCropEdge, at point: CGPoint, imageSize: CGSize) -> some View {
        CropCornerMark(edge: edge)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(point)
            .highPriorityGesture(edgeGesture(edge, imageSize: imageSize))
            .accessibilityLabel(edgeLabel(edge))
    }

    private func edgeGesture(_ edge: MediaCropEdge, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("cropStage"))
            .onChanged { value in
                let origin = cropOrigin ?? crop
                if cropOrigin == nil {
                    cropOrigin = crop
                }
                activeEdge = edge
                crop = MediaCropMath.resized(
                    start: origin,
                    edge: edge,
                    translation: value.translation,
                    imageSize: imageSize,
                    contentAspect: aspect
                )
                frameAspect = crop.frameAspect(contentAspect: aspect)
            }
            .onEnded { _ in
                cropOrigin = nil
                activeEdge = nil
            }
    }

    private func edgeLabel(_ edge: MediaCropEdge) -> String {
        switch edge {
        case .left: "Crop left edge"
        case .right: "Crop right edge"
        case .top: "Crop top edge"
        case .bottom: "Crop bottom edge"
        case .topLeft: "Crop top left"
        case .topRight: "Crop top right"
        case .bottomLeft: "Crop bottom left"
        case .bottomRight: "Crop bottom right"
        case .center: "Crop"
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if isVideo {
            ComposerInlineVideo(url: playbackURL, isPaused: true, fillsFrame: false)
                .allowsHitTesting(false)
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color.white.opacity(0.08)
        }
    }

    private var shapeChoices: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MediaFrameShape.allCases, id: \.self) { option in
                    Button {
                        shape = option
                        if let preset = option.presetAspect {
                            frameAspect = preset
                            crop = MediaCropMath.covered(aspect: preset, contentAspect: aspect)
                        }
                    } label: {
                        Image(systemName: option.systemImage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(shape == option ? MosaicBrand.inkBlack : .white.opacity(0.92))
                            .frame(width: 44, height: 44)
                            .background(
                                shape == option ? MosaicBrand.cream : Color.white.opacity(0.12),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.label)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(red: 0.20, green: 0.21, blue: 0.23))
    }

    private func moveGesture(imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("cropStage"))
            .onChanged { value in
                guard activeEdge == nil else { return }
                let origin = moveOrigin ?? crop
                if moveOrigin == nil {
                    moveOrigin = crop
                }
                crop = MediaCropMath.moved(origin, translation: value.translation, imageSize: imageSize)
            }
            .onEnded { _ in
                moveOrigin = nil
            }
    }

    private func pinchGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let origin = pinchOriginWindow ?? crop
                if pinchOriginWindow == nil {
                    pinchOriginWindow = crop
                }
                crop = MediaCropMath.scaled(origin, factor: value, contentAspect: aspect)
                frameAspect = crop.frameAspect(contentAspect: aspect)
            }
            .onEnded { _ in
                pinchOriginWindow = nil
            }
    }

    private func commit() {
        let framed = MediaCropMath.framing(window: crop, contentAspect: aspect)
        onDone(shape, Double(framed.zoom), Double(framed.panX), Double(framed.panY), Double(framed.frameAspect))
    }

    private func beginTrim() {
        let source = playbackURL
        Task {
            guard let editable = await ComposerVideoCompatibility.editableURL(for: source) else {
                trimFailed = true
                return
            }
            let asset = AVURLAsset(url: editable)
            let seconds = (try? await asset.load(.duration))?.seconds ?? 0
            let maximum = seconds.isFinite && seconds > 0 ? seconds : 600
            trimRequest = VideoTrimRequest(url: editable, maximumDuration: maximum)
        }
    }

    private func imageRect(in container: CGSize) -> CGRect {
        let maxWidth = max(container.width - 48, 120)
        let maxHeight = max(container.height - 24, 120)
        let content = max(aspect, 0.01)
        var width = maxWidth
        var height = width / content
        if height > maxHeight {
            height = maxHeight
            width = height * content
        }
        return CGRect(
            x: (container.width - width) / 2,
            y: (container.height - height) / 2,
            width: width,
            height: height
        )
    }

    private var aspectControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.portrait")
                .foregroundStyle(Color.white.opacity(0.7))
            Slider(
                value: Binding(
                    get: { min(max(crop.frameAspect(contentAspect: aspect), MediaFrameShape.minimumAspect), MediaFrameShape.maximumAspect) },
                    set: { newValue in
                        frameAspect = newValue
                        crop = MediaCropMath.window(aspect: newValue, centeredOn: crop, contentAspect: aspect)
                    }
                ),
                in: MediaFrameShape.minimumAspect...MediaFrameShape.maximumAspect
            )
            .tint(MosaicBrand.cream)
            Image(systemName: "rectangle")
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shape aspect")
    }

    private static func startingAspect(stored: Double, shape: MediaFrameShape) -> CGFloat {
        if stored > 0.05 {
            return min(max(CGFloat(stored), MediaFrameShape.minimumAspect), MediaFrameShape.maximumAspect)
        }
        return shape.presetAspect ?? 1
    }

    private static func videoAspect(at url: URL) async -> CGFloat {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return 16.0 / 9.0 }
        let natural = try? await track.load(.naturalSize)
        let transform = try? await track.load(.preferredTransform)
        guard let natural, let transform else { return 16.0 / 9.0 }
        let transformed = natural.applying(transform)
        let width = abs(transformed.width)
        let height = abs(transformed.height)
        guard height > 0 else { return 16.0 / 9.0 }
        return width / height
    }
}

private struct CropCornerMark: View {
    let edge: MediaCropEdge

    var body: some View {
        Canvas { context, size in
            let arm: CGFloat = 16
            let inset: CGFloat = 14
            let left = edge.movesLeft
            let top = edge.movesTop
            let x = left ? inset : size.width - inset
            let y = top ? inset : size.height - inset
            var path = Path()
            path.move(to: CGPoint(x: left ? x + arm : x - arm, y: y))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x, y: top ? y + arm : y - arm))
            context.stroke(
                path,
                with: .color(.white),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
    }
}

struct MediaRoundedRect: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: min(rect.width, rect.height) * 0.18, style: .continuous).path(in: rect)
    }
}

struct MediaRoundedRectangle: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: min(rect.width, rect.height) * 0.28, style: .continuous).path(in: rect)
    }
}

struct MediaRegularPolygon: Shape {
    var sides: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radiusX = rect.width / 2
        let radiusY = rect.height / 2
        var path = Path()
        for index in 0..<max(sides, 3) {
            let angle = (CGFloat(index) / CGFloat(sides)) * 2 * .pi - .pi / 2
            let point = CGPoint(
                x: center.x + radiusX * cos(angle),
                y: center.y + radiusY * sin(angle)
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

struct MediaStar: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerX = rect.width / 2
        let outerY = rect.height / 2
        let innerX = outerX * 0.46
        let innerY = outerY * 0.46
        var path = Path()
        let count = 10
        for index in 0..<count {
            let angle = (CGFloat(index) / CGFloat(count)) * 2 * .pi - .pi / 2
            let radiusX = index.isMultiple(of: 2) ? outerX : innerX
            let radiusY = index.isMultiple(of: 2) ? outerY : innerY
            let point = CGPoint(
                x: center.x + radiusX * cos(angle),
                y: center.y + radiusY * sin(angle)
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

struct MediaHeart: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + width * 0.5, y: rect.minY + height * 0.92))
        path.addCurve(
            to: CGPoint(x: rect.minX + width * 0.05, y: rect.minY + height * 0.38),
            control1: CGPoint(x: rect.minX + width * 0.18, y: rect.minY + height * 0.72),
            control2: CGPoint(x: rect.minX + width * 0.02, y: rect.minY + height * 0.55)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + width * 0.5, y: rect.minY + height * 0.32),
            control1: CGPoint(x: rect.minX + width * 0.05, y: rect.minY + height * 0.12),
            control2: CGPoint(x: rect.minX + width * 0.28, y: rect.minY + height * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + width * 0.95, y: rect.minY + height * 0.38),
            control1: CGPoint(x: rect.minX + width * 0.72, y: rect.minY + height * 0.08),
            control2: CGPoint(x: rect.minX + width * 0.95, y: rect.minY + height * 0.12)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + width * 0.5, y: rect.minY + height * 0.92),
            control1: CGPoint(x: rect.minX + width * 0.98, y: rect.minY + height * 0.55),
            control2: CGPoint(x: rect.minX + width * 0.82, y: rect.minY + height * 0.72)
        )
        path.closeSubpath()
        return path
    }
}

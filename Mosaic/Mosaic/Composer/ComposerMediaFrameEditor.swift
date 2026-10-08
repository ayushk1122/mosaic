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

func mediaClipShape(_ shape: MediaFrameShape) -> AnyShape {
    switch shape {
    case .rectangle, .square:
        AnyShape(Rectangle())
    case .rounded:
        AnyShape(MediaRoundedRect())
    case .roundedRectangle:
        AnyShape(MediaRoundedRectangle())
    case .circle:
        AnyShape(Circle())
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

struct ComposerMediaFrameEditor: View {
    let mediaURL: URL
    let isVideo: Bool
    let initialShape: MediaFrameShape
    let initialZoom: Double
    let initialPanX: Double
    let initialPanY: Double
    var onCancel: () -> Void
    var onDone: (MediaFrameShape, Double, Double, Double) -> Void

    @State private var shape: MediaFrameShape
    @State private var zoom: CGFloat
    @State private var panX: CGFloat
    @State private var panY: CGFloat
    @State private var image: UIImage?
    @State private var aspect: CGFloat = 1
    @State private var isReady = false
    @State private var stageSize: CGSize = CGSize(width: 320, height: 420)
    @State private var dragOrigin: CGSize?
    @State private var pinchOrigin: CGFloat = 1

    init(
        mediaURL: URL,
        isVideo: Bool,
        initialShape: MediaFrameShape,
        initialZoom: Double,
        initialPanX: Double,
        initialPanY: Double,
        onCancel: @escaping () -> Void,
        onDone: @escaping (MediaFrameShape, Double, Double, Double) -> Void
    ) {
        self.mediaURL = mediaURL
        self.isVideo = isVideo
        self.initialShape = initialShape
        self.initialZoom = initialZoom
        self.initialPanX = initialPanX
        self.initialPanY = initialPanY
        self.onCancel = onCancel
        self.onDone = onDone
        _shape = State(initialValue: initialShape)
        _zoom = State(initialValue: CGFloat(min(max(initialZoom, 1), 4)))
        _panX = State(initialValue: CGFloat(initialPanX))
        _panY = State(initialValue: CGFloat(initialPanY))
        _pinchOrigin = State(initialValue: CGFloat(min(max(initialZoom, 1), 4)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Drag to move · Pinch to zoom")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.bottom, 8)
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
                    Button("Done", action: commit)
                        .fontWeight(.semibold)
                }
            }
        }
        .task(id: mediaURL) {
            if isVideo {
                aspect = await Self.videoAspect(at: mediaURL)
            } else {
                let loaded = UIImage(contentsOfFile: mediaURL.path)
                image = loaded
                if let loaded, loaded.size.height > 0 {
                    aspect = loaded.size.width / loaded.size.height
                }
            }
            isReady = true
        }
    }

    private var stage: some View {
        GeometryReader { proxy in
            let frame = previewFrame(in: proxy.size)
            ZStack {
                if isReady {
                    framedPreview(in: frame)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(in: frame))
            .simultaneousGesture(pinchGesture(in: frame))
            .onAppear { stageSize = proxy.size }
            .onChange(of: proxy.size) { _, newSize in
                stageSize = newSize
            }
        }
    }

    private func framedPreview(in frame: CGSize) -> some View {
        let clip = mediaClipShape(shape)
        let pan = resolvedPan(in: frame)
        let filled = MediaFraming.fillSize(contentAspect: aspect, in: frame)
        return ZStack {
            previewContent
                .frame(width: filled.width * zoom, height: filled.height * zoom)
                .offset(pan)
                .frame(width: frame.width, height: frame.height)
                .clipShape(clip)
                .overlay {
                    clip.stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                }
        }
        .frame(width: frame.width, height: frame.height)
    }

    @ViewBuilder
    private var previewContent: some View {
        if isVideo {
            ComposerInlineVideo(url: mediaURL, isPaused: true, fillsFrame: false)
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

    private func dragGesture(in frame: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let origin = dragOrigin ?? CGSize(width: panX * frame.width, height: panY * frame.height)
                if dragOrigin == nil {
                    dragOrigin = origin
                }
                let proposed = CGSize(
                    width: origin.width + value.translation.width,
                    height: origin.height + value.translation.height
                )
                let clamped = MediaFraming.clampedPan(proposed, limits: limits(in: frame))
                panX = frame.width > 0 ? clamped.width / frame.width : 0
                panY = frame.height > 0 ? clamped.height / frame.height : 0
            }
            .onEnded { _ in
                dragOrigin = nil
            }
    }

    private func pinchGesture(in frame: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = min(max(pinchOrigin * value, 1), 4)
                let clamped = resolvedPan(in: frame)
                panX = frame.width > 0 ? clamped.width / frame.width : 0
                panY = frame.height > 0 ? clamped.height / frame.height : 0
            }
            .onEnded { _ in
                pinchOrigin = zoom
            }
    }

    private func commit() {
        let frame = previewFrame(in: stageSize)
        let pan = resolvedPan(in: frame)
        let savedX = frame.width > 0 ? Double(pan.width / frame.width) : 0
        let savedY = frame.height > 0 ? Double(pan.height / frame.height) : 0
        onDone(shape, Double(zoom), savedX, savedY)
    }

    private func resolvedPan(in frame: CGSize) -> CGSize {
        MediaFraming.clampedPan(
            CGSize(width: panX * frame.width, height: panY * frame.height),
            limits: limits(in: frame)
        )
    }

    private func limits(in frame: CGSize) -> CGSize {
        MediaFraming.panLimits(contentAspect: aspect, frame: frame, zoom: zoom)
    }

    private func previewFrame(in container: CGSize) -> CGSize {
        let shapeAspect: CGFloat = shape.usesSquareFrame ? 1 : max(aspect, 0.4)
        let maxWidth = max(container.width - 48, 120)
        let maxHeight = max(container.height - 24, 120)
        var width = maxWidth
        var height = width / shapeAspect
        if height > maxHeight {
            height = maxHeight
            width = height * shapeAspect
        }
        return CGSize(width: width, height: height)
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
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<max(sides, 3) {
            let angle = (CGFloat(index) / CGFloat(sides)) * 2 * .pi - .pi / 2
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
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
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.46
        var path = Path()
        let count = 10
        for index in 0..<count {
            let angle = (CGFloat(index) / CGFloat(count)) * 2 * .pi - .pi / 2
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
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

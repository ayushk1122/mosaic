import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ComposerMediaCanvasBlock: View {
    @Binding var block: ComposerBlock
    let mediaURL: URL?
    let scale: CGFloat
    let livePinchScale: CGFloat
    let isSelected: Bool
    let isLifted: Bool
    let isRelocating: Bool
    var isPaused: Bool
    var showsMenu: Bool
    var onOpenMenu: () -> Void
    var onCrop: () -> Void

    @State private var preview: UIImage?
    @State private var videoAspect: CGFloat = 16.0 / 9.0
    @State private var itemFrame: CGRect = .zero

    @Environment(\.composerViewportWidth) private var viewportWidth

    private var iconPlacement: ComposerChromePlacement {
        ComposerChromePlacement.resolve(itemFrame: itemFrame, viewportWidth: viewportWidth)
    }

    private var showsLift: Bool { isLifted }
    private var isVideo: Bool { Self.isVideo(mediaURL) }

    private var displayWidth: CGFloat {
        max(72, 200 * scale * livePinchScale)
    }

    var body: some View {
        mediaContent
            .overlay(alignment: .topLeading) {
                if isSelected, !isLifted, !isRelocating {
                    mediaChrome
                }
            }
            .shadow(color: .white.opacity(showsLift ? 0.85 : 0), radius: showsLift ? 3 : 0)
            .shadow(color: .white.opacity(showsLift ? 0.4 : 0), radius: showsLift ? 14 : 0)
            .animation(.easeOut(duration: 0.16), value: showsLift)
            .contentShape(MediaIconHitShape(
                menuOpen: showsMenu,
                iconX: iconPlacement.x,
                cropBelow: iconPlacement.cropBelow
            ))
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("composerRoot"))
            } action: { frame in
                itemFrame = frame
            }
        .task(id: mediaURL) {
            if isVideo, let mediaURL {
                videoAspect = await Self.videoAspect(at: mediaURL)
            } else {
                preview = await Self.loadPreview(at: mediaURL)
            }
        }
    }

    private var mediaContent: some View {
        framedMedia
            .overlay {
                if isVideo, isPaused {
                    Image(systemName: "play.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.4), in: Circle())
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    private var framedMedia: some View {
        if isVideo, let mediaURL {
            framed(
                ComposerInlineVideo(url: mediaURL, isPaused: isPaused, fillsFrame: false)
                    .allowsHitTesting(false)
            )
        } else if let preview {
            framed(
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
            )
        } else {
            ProgressView()
                .tint(.white)
                .frame(width: 44, height: 44)
        }
    }

    private func framed<Content: View>(_ content: Content) -> some View {
        let frame = CGSize(width: displayWidth, height: shapeHeight)
        let zoom = CGFloat(min(max(block.mediaZoom, 1), 4))
        let filled = MediaFraming.fillSize(contentAspect: contentAspect, in: frame)
        let pan = MediaFraming.clampedPan(
            CGSize(width: block.mediaPanX * frame.width, height: block.mediaPanY * frame.height),
            limits: MediaFraming.panLimits(contentAspect: contentAspect, frame: frame, zoom: zoom)
        )
        return content
            .frame(width: filled.width * zoom, height: filled.height * zoom)
            .offset(pan)
            .frame(width: frame.width, height: frame.height)
            .clipped()
            .clipShape(mediaClipShape(block.mediaShape))
    }

    private var shapeHeight: CGFloat {
        if block.mediaShape.usesSquareFrame {
            return displayWidth
        }
        return displayWidth / max(isVideo ? videoAspect : imageAspect, 0.4)
    }

    private var contentAspect: CGFloat {
        isVideo ? videoAspect : imageAspect
    }

    private var imageAspect: CGFloat {
        guard let preview, preview.size.height > 0 else { return 1 }
        return preview.size.width / preview.size.height
    }

    private var mediaChrome: some View {
        ZStack(alignment: .topLeading) {
            if showsMenu {
                cropIconButton
                    .offset(x: iconPlacement.x, y: iconPlacement.cropBelow ? 36 : -46)
            }
            mediaIconButton
                .offset(x: iconPlacement.x, y: -2)
        }
        .fixedSize()
        .animation(.easeOut(duration: 0.16), value: iconPlacement)
    }

    private var cropIconButton: some View {
        Image(systemName: "crop")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 32, height: 32)
            .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Circle())
            .highPriorityGesture(TapGesture().onEnded { onCrop() })
            .accessibilityLabel("Crop")
            .accessibilityAddTraits(.isButton)
    }

    private var mediaIconButton: some View {
        Image(systemName: "photo")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 32, height: 32)
            .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Circle())
            .highPriorityGesture(TapGesture().onEnded { onOpenMenu() })
            .accessibilityLabel("Media options")
            .accessibilityAddTraits(.isButton)
    }

    private static func isVideo(_ url: URL?) -> Bool {
        guard let url else { return false }
        let ext = url.pathExtension.lowercased()
        return ["mov", "mp4", "m4v", "avi"].contains(ext)
    }

    private static func loadPreview(at url: URL?) async -> UIImage? {
        guard let url else { return nil }
        if isVideo(url) {
            return await videoPoster(at: url)
        }
        return UIImage(contentsOfFile: url.path)
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

    private static func videoPoster(at url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cgImage = try? await generator.image(at: time).image else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct MediaTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct MediaIconHitShape: Shape {
    var menuOpen: Bool
    var iconX: CGFloat
    var cropBelow: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(x: rect.minX + iconX - 4, y: rect.minY - 8, width: 40, height: 40))
        if menuOpen {
            let cropY = cropBelow ? rect.minY + 28 : rect.minY - 54
            path.addEllipse(in: CGRect(x: rect.minX + iconX - 4, y: cropY, width: 44, height: 44))
        }
        return path
    }
}

struct ComposerInlineVideo: UIViewRepresentable {
    let url: URL
    let isPaused: Bool
    let fillsFrame: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ComposerPlayerView {
        let view = ComposerPlayerView()
        view.playerLayer.videoGravity = fillsFrame ? .resizeAspectFill : .resizeAspect
        installPlayer(on: view, context: context)
        return view
    }

    func updateUIView(_ uiView: ComposerPlayerView, context: Context) {
        uiView.playerLayer.videoGravity = fillsFrame ? .resizeAspectFill : .resizeAspect
        if context.coordinator.url != url {
            context.coordinator.stop()
            installPlayer(on: uiView, context: context)
            return
        }
        context.coordinator.isPaused = isPaused
        guard let player = context.coordinator.player else { return }
        if isPaused {
            player.pause()
        } else if player.timeControlStatus != .playing {
            player.play()
        }
    }

    private func installPlayer(on view: ComposerPlayerView, context: Context) {
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .none
        view.player = player
        context.coordinator.url = url
        context.coordinator.player = player
        context.coordinator.isPaused = isPaused
        context.coordinator.startLooping()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        if isPaused {
            player.pause()
        } else {
            player.play()
        }
    }

    static func dismantleUIView(_ uiView: ComposerPlayerView, coordinator: Coordinator) {
        coordinator.stop()
        uiView.player?.pause()
        uiView.player = nil
    }

    final class Coordinator {
        var url: URL?
        var player: AVPlayer?
        var isPaused = false
        private var endObserver: NSObjectProtocol?

        func startLooping() {
            guard let player, let item = player.currentItem else { return }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.player?.seek(to: .zero)
                if self?.isPaused == false {
                    self?.player?.play()
                }
            }
        }

        func stop() {
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
            endObserver = nil
            player?.pause()
            player = nil
        }
    }
}

final class ComposerPlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspect
        }
    }
}

enum ComposerMediaImport {
    @MainActor
    static func save(_ item: PhotosPickerItem, to store: ComposerStore) async -> String? {
        let isVideo = item.supportedContentTypes.contains { type in
            type.conforms(to: .movie) || type.conforms(to: .video)
        }
        if isVideo, let movie = try? await item.loadTransferable(type: ComposerMovieFile.self) {
            return try? store.saveMediaFile(from: movie.url)
        }
        if let data = try? await item.loadTransferable(type: Data.self) {
            return try? store.saveMediaData(data)
        }
        return nil
    }
}

struct ComposerMovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: copy.path) {
                try FileManager.default.removeItem(at: copy)
            }
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

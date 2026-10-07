import AVFoundation
import SwiftUI

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

    @State private var preview: UIImage?
    @State private var videoAspect: CGFloat = 16.0 / 9.0

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
            .contentShape(MediaIconHitShape(menuOpen: showsMenu))
        .task(id: mediaURL) {
            if isVideo, let mediaURL {
                videoAspect = await Self.videoAspect(at: mediaURL)
            } else {
                preview = await Self.loadPreview(at: mediaURL)
            }
        }
    }

    private var mediaContent: some View {
        ZStack {
            if isVideo, let mediaURL {
                ComposerInlineVideo(
                    url: mediaURL,
                    isPaused: isPaused,
                    fillsFrame: block.mediaShape != .rectangle
                )
                    .frame(width: displayWidth, height: shapeHeight)
                    .overlay {
                        if isPaused {
                            Image(systemName: "play.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(.black.opacity(0.4), in: Circle())
                        }
                    }
                    .clipShape(frameShape)
                    .allowsHitTesting(false)
            } else if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: displayWidth, height: shapeHeight)
                    .clipShape(frameShape)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(width: 44, height: 44)
            }
        }
    }

    private var shapeHeight: CGFloat {
        if block.mediaShape.usesSquareFrame {
            return displayWidth
        }
        return displayWidth / max(isVideo ? videoAspect : imageAspect, 0.4)
    }

    private var imageAspect: CGFloat {
        guard let preview, preview.size.height > 0 else { return 1 }
        return preview.size.width / preview.size.height
    }

    private var frameShape: AnyShape {
        switch block.mediaShape {
        case .rectangle:
            AnyShape(Rectangle())
        case .square:
            AnyShape(Rectangle())
        case .rounded:
            AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        case .circle:
            AnyShape(Circle())
        case .triangle:
            AnyShape(MediaTriangle())
        }
    }

    private var mediaChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsMenu {
                ComposerMediaShapeChoices(shape: block.mediaShape) { option in
                    block.mediaShape = option
                    block.mediaWarp = nil
                }
            }
            mediaIconButton
        }
        .fixedSize()
        .offset(x: -40, y: showsMenu ? -70 : -2)
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

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(x: rect.minX - 48, y: rect.minY - 8, width: 40, height: 40))
        if menuOpen {
            path.addRect(CGRect(x: rect.minX - 48, y: rect.minY - 84, width: 270, height: 84))
        }
        return path
    }
}

private struct ComposerMediaShapeChoices: View {
    let shape: MediaFrameShape
    var onShape: (MediaFrameShape) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MediaFrameShape.allCases, id: \.self) { option in
                Button {
                    onShape(option)
                } label: {
                    Image(systemName: option.systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(shape == option ? MosaicBrand.inkBlack : .white.opacity(0.92))
                        .frame(width: 36, height: 36)
                        .background(shape == option ? MosaicBrand.cream : Color.white.opacity(0.12), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .highPriorityGesture(TapGesture().onEnded { onShape(option) })
                .accessibilityLabel(option.label)
            }
        }
        .padding(12)
        .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ComposerInlineVideo: UIViewRepresentable {
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

private final class ComposerPlayerView: UIView {
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

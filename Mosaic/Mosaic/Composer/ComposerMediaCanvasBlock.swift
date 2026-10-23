import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ComposerMediaCanvasBlock: View {
    @Environment(\.composerMediaVersions) private var mediaVersions
    @Environment(\.composerMediaWaiting) private var mediaWaiting
    @Environment(\.composerMediaPreviews) private var mediaPreviews
    @Environment(\.composerStillsOnly) private var stillsOnly

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
    var onBodyTap: (() -> Void)? = nil
    var onReplace: (() -> Void)? = nil

    @State private var preview: UIImage?
    @State private var loadFailed = false
    @State private var videoAspect: CGFloat = 16.0 / 9.0
    @State private var itemFrame: CGRect = .zero
    @State private var menuFrame: CGRect = .zero
    @State private var cropFrame: CGRect = .zero
    @State private var replaceFrame: CGRect = .zero
    @State private var menuReplaceFrame: CGRect = .zero

    @Environment(\.composerViewportWidth) private var viewportWidth
    @Environment(\.composerCoordinateSpace) private var composerSpace
    @Environment(\.composerPieceOpacity) private var pieceOpacity

    private var iconPlacement: ComposerChromePlacement {
        ComposerChromePlacement.resolve(itemFrame: itemFrame, viewportWidth: viewportWidth)
    }

    private var showsLift: Bool { isLifted }
    private var isVideo: Bool { Self.isVideo(mediaURL) }
    private var isUnavailable: Bool { loadFailed && !mediaWaiting.includes(mediaURL) }
    private var showsReplace: Bool { isSelected && isUnavailable && onReplace != nil && !isLifted && !isRelocating }

    private var displayWidth: CGFloat {
        max(72, 200 * scale * livePinchScale)
    }

    var body: some View {
        mediaContent
            .compositingGroup()
            .opacity(pieceOpacity)
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
                showsReplace: showsMenuReplace,
                iconX: iconPlacement.x,
                cropBelow: iconPlacement.cropBelow
            ))
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(composerSpace))
            } action: { frame in
                itemFrame = frame
            }
            .preference(
                key: ComposerMediaChromeFrameKey.self,
                value: [
                    block.id: ComposerMediaChromeFrames(
                        menu: isSelected ? menuFrame : .zero,
                        crop: isSelected && showsMenu ? cropFrame : .zero,
                        replace: isSelected && showsMenuReplace ? menuReplaceFrame : showsReplace ? replaceFrame : .zero
                    )
                ]
            )
        .task(id: ComposerMediaLoadKey(mediaURL, versions: mediaVersions)) {
            if isVideo, let mediaURL, !stillsOnly {
                // A photo replaced by a video must not keep showing the old photo if the video is missing.
                preview = nil
                loadFailed = !FileManager.default.fileExists(atPath: mediaURL.path)
                let loaded = await Self.videoAspect(at: mediaURL)
                guard !Task.isCancelled else { return }
                videoAspect = loaded
            } else {
                let loaded = await Self.loadPreview(at: mediaURL)
                guard !Task.isCancelled else { return }
                preview = loaded
                loadFailed = loaded == nil && mediaURL != nil
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
            .modifier(ComposerPhotoFrameModifier(
                style: block.frameStyle,
                caption: block.frameCaption,
                seed: ComposerPhotoFrameModifier.seed(for: block.id),
                width: displayWidth
            ))
            .contentShape(Rectangle())
            .modifier(MediaBodyTapModifier(isEnabled: onBodyTap != nil, action: { onBodyTap?() }))
    }

    @ViewBuilder
    private var framedMedia: some View {
        if isVideo, let mediaURL, !loadFailed, !stillsOnly {
            framed(
                ComposerInlineVideo(url: mediaURL, isPaused: isPaused, fillsFrame: false)
                    .allowsHitTesting(false)
            )
        } else if let preview {
            framed(ComposerPicture(image: preview))
        } else if isUnavailable {
            framed(ComposerMediaUnavailable(
                isVideo: isVideo,
                onReplace: showsReplace ? onReplace : nil,
                onReplaceFrame: { replaceFrame = $0 }
            ))
        } else if let placeholder {
            framed(ComposerMediaPlaceholder(preview: placeholder))
        } else {
            ProgressView()
                .tint(.white)
                .frame(width: 44, height: 44)
        }
    }

    private func framed<Content: View>(_ content: Content) -> some View {
        ComposerMediaCrop(block: block).framed(content, width: displayWidth, contentAspect: contentAspect)
    }

    private var contentAspect: CGFloat {
        // As a still, a video's first frame has the video's own shape.
        guard isVideo, !stillsOnly else { return imageAspect }
        // A video still downloading takes its preview's shape, so it doesn't resize on arrival.
        if loadFailed, let placeholder { return CGFloat(placeholder.aspect) }
        return videoAspect
    }

    /// A visitor's blurred stand-in, and the shape to hold until the file arrives.
    private var placeholder: ComposerMediaPreview? {
        block.mediaFileName.flatMap { mediaPreviews[$0] }
    }

    private var imageAspect: CGFloat {
        guard let preview, preview.size.height > 0 else { return placeholder.map { CGFloat($0.aspect) } ?? 1 }
        return preview.size.width / preview.size.height
    }

    private var showsMenuReplace: Bool { showsMenu && onReplace != nil }

    private var mediaChrome: some View {
        ZStack(alignment: .topLeading) {
            if showsMenu {
                cropIconButton
                    .offset(x: iconPlacement.x, y: iconPlacement.cropBelow ? 36 : -46)
            }
            if showsMenuReplace {
                replaceIconButton
                    .offset(x: iconPlacement.x, y: iconPlacement.cropBelow ? 76 : -86)
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
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(composerSpace))
            } action: { frame in
                cropFrame = frame
            }
            .highPriorityGesture(TapGesture().onEnded { onCrop() })
            .accessibilityLabel("Crop")
            .accessibilityAddTraits(.isButton)
    }

    private var replaceIconButton: some View {
        Image(systemName: "arrow.left.arrow.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 32, height: 32)
            .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Circle())
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(composerSpace))
            } action: { frame in
                menuReplaceFrame = frame
            }
            .highPriorityGesture(TapGesture().onEnded { onReplace?() })
            .accessibilityLabel("Replace media")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("composer.media.replace")
    }

    private var mediaIconButton: some View {
        Image(systemName: "photo")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 32, height: 32)
            .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Circle())
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(composerSpace))
            } action: { frame in
                menuFrame = frame
            }
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
        return await Task.detached(priority: .userInitiated) {
            ComposerAnimatedImage.image(contentsOf: url)
        }.value
    }

    static func videoAspect(at url: URL) async -> CGFloat {
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

/// A media block's frame shape, zoom, and pan. The same crop draws at any width.
struct ComposerMediaCrop: Equatable {
    var shape: MediaFrameShape
    var frameAspect: Double
    var zoom: Double
    var panX: Double
    var panY: Double
    /// Drawings grouped in front of this media, placed on its frame (see `ComposerMediaMarkup`).
    var markup: Data?

    init(block: ComposerBlock) {
        shape = block.mediaShape
        frameAspect = block.mediaFrameAspect
        zoom = block.mediaZoom
        panX = block.mediaPanX
        panY = block.mediaPanY
    }

    /// Width divided by height of the cropped frame.
    func aspect(contentAspect: CGFloat) -> CGFloat {
        let aspect: CGFloat = if frameAspect > 0.05 {
            CGFloat(frameAspect)
        } else if let preset = shape.presetAspect {
            preset
        } else {
            Self.originalShape(contentAspect: contentAspect)
        }
        return min(max(aspect, MediaFrameShape.minimumAspect), MediaFrameShape.maximumAspect)
    }

    /// The uncropped frame: the photo's own shape, kept between a tall 0.4 and the widest frame.
    /// The crop editor starts from the same value, so opening it and tapping Done changes nothing.
    static func originalShape(contentAspect: CGFloat) -> CGFloat {
        min(max(contentAspect, 0.4), MediaFrameShape.maximumAspect)
    }

    func framed<Content: View>(_ content: Content, width: CGFloat, contentAspect: CGFloat) -> some View {
        let frame = CGSize(width: width, height: width / aspect(contentAspect: contentAspect))
        let zoom = CGFloat(min(max(zoom, 1), 4))
        let filled = MediaFraming.fillSize(contentAspect: contentAspect, in: frame)
        let pan = MediaFraming.clampedPan(
            CGSize(width: panX * frame.width, height: panY * frame.height),
            limits: MediaFraming.panLimits(contentAspect: contentAspect, frame: frame, zoom: zoom)
        )
        return content
            .frame(width: filled.width * zoom, height: filled.height * zoom)
            .offset(pan)
            .frame(width: frame.width, height: frame.height)
            .clipped()
            .clipShape(mediaClipShape(shape))
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

struct ComposerMediaChromeFrames: Equatable {
    var menu = CGRect.zero
    var crop = CGRect.zero
    var replace = CGRect.zero

    func hitsMenu(_ point: CGPoint) -> Bool {
        menu.width > 1 && menu.insetBy(dx: -10, dy: -10).contains(point)
    }

    func hitsReplace(_ point: CGPoint) -> Bool {
        replace.width > 1 && replace.insetBy(dx: -8, dy: -8).contains(point)
    }

    func hitsCrop(_ point: CGPoint) -> Bool {
        crop.width > 1 && crop.insetBy(dx: -10, dy: -10).contains(point)
    }
}

struct ComposerMediaChromeFrameKey: PreferenceKey {
    static var defaultValue: [ComposerBlockID: ComposerMediaChromeFrames] = [:]

    static func reduce(
        value: inout [ComposerBlockID: ComposerMediaChromeFrames],
        nextValue: () -> [ComposerBlockID: ComposerMediaChromeFrames]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct MediaIconHitShape: Shape {
    var menuOpen: Bool
    var showsReplace: Bool
    var iconX: CGFloat
    var cropBelow: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(x: rect.minX + iconX - 4, y: rect.minY - 8, width: 40, height: 40))
        if menuOpen {
            let cropY = cropBelow ? rect.minY + 28 : rect.minY - 54
            path.addEllipse(in: CGRect(x: rect.minX + iconX - 4, y: cropY, width: 44, height: 44))
        }
        if showsReplace {
            let replaceY = cropBelow ? rect.minY + 68 : rect.minY - 94
            path.addEllipse(in: CGRect(x: rect.minX + iconX - 4, y: replaceY, width: 44, height: 44))
        }
        return path
    }
}

private struct ComposerStillsOnlyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Videos show their first frame as a picture instead of a player, for images of a board made by
    /// capturing it (a player's picture doesn't capture).
    var composerStillsOnly: Bool {
        get { self[ComposerStillsOnlyKey.self] }
        set { self[ComposerStillsOnlyKey.self] = newValue }
    }
}

struct ComposerInlineVideo: UIViewRepresentable {
    @Environment(\.composerMediaVersions) private var mediaVersions

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
        if context.coordinator.url != url || context.coordinator.mediaVersion != mediaVersions[url.lastPathComponent, default: 0] {
            context.coordinator.stop()
            installPlayer(on: uiView, context: context)
            return
        }
        context.coordinator.isPaused = isPaused
        guard let player = context.coordinator.player else { return }
        if isPaused {
            player.pause()
            context.coordinator.releaseAudio()
        } else if player.timeControlStatus != .playing {
            context.coordinator.claimAudio()
            player.play()
        }
    }

    private func installPlayer(on view: ComposerPlayerView, context: Context) {
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .none
        view.player = player
        context.coordinator.url = url
        context.coordinator.mediaVersion = mediaVersions[url.lastPathComponent, default: 0]
        context.coordinator.player = player
        context.coordinator.isPaused = isPaused
        context.coordinator.startLooping()
        if isPaused {
            player.pause()
        } else {
            context.coordinator.claimAudio()
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
        var mediaVersion = 0
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
            releaseAudio()
        }

        func claimAudio() { ComposerVideoAudio.claim(ObjectIdentifier(self)) }
        func releaseAudio() { ComposerVideoAudio.release(ObjectIdentifier(self)) }
    }
}

/// Only a video that actually plays takes over audio, so a paused video on screen doesn't stop the
/// person's music; once the last one pauses or leaves the screen, their music can resume.
enum ComposerVideoAudio {
    private(set) static var playing: Set<ObjectIdentifier> = []
    /// Bumped by every claim and release, so a hand-back still waiting is dropped once a video plays again.
    private static var handBack = 0

    static func claim(_ video: ObjectIdentifier) {
        handBack += 1
        if playing.isEmpty {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        playing.insert(video)
    }

    /// Just after a pause the player's audio is often still running, and iOS refuses to end the
    /// session; with no retry the person's music never came back. So it waits a moment, ends it off
    /// the main thread, and tries once more if refused.
    static func release(_ video: ObjectIdentifier) {
        guard playing.remove(video) != nil, playing.isEmpty else { return }
        handBack += 1
        let current = handBack
        Task {
            for delay in [400, 800] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard current == handBack, playing.isEmpty else { return }
                let ended = await Task.detached(priority: .utility) {
                    (try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)) != nil
                }.value
                if ended { return }
            }
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

enum ComposerImagePreparation: Sendable {
    nonisolated static func jpeg(from data: Data, maxPixel: CGFloat = 1800, quality: CGFloat = 0.82) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let destinationOptions = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, destinationOptions)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// The largest a single board photo is stored at; uploads already cap their original here.
    nonisolated static let boardMaxPixel: CGFloat = 2560

    /// GIFs keep their bytes so they still animate. PNGs within the limit keep their bytes
    /// (and transparency). Everything else, and oversized PNGs, becomes a JPEG at `boardMaxPixel`.
    nonisolated static func boardImage(from data: Data) -> (data: Data, fileExtension: String) {
        if ComposerAnimatedImage.isGIF(data) { return (data, "gif") }
        let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        if let source, CGImageSourceGetType(source) as String? == UTType.png.identifier,
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
           let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
           max(width, height) <= boardMaxPixel {
            return (data, "png")
        }
        if let jpeg = jpeg(from: data, maxPixel: boardMaxPixel, quality: 0.86) { return (jpeg, "jpg") }
        return (data, "jpg")
    }
}

struct PreparedCarouselMedia: Sendable {
    /// A JPEG, or the original bytes of a GIF.
    var imageData: Data?
    var videoURL: URL?
}

enum ComposerMediaImport {
    @MainActor
    static func save(_ item: PhotosPickerItem, to store: ComposerStore) async -> String? {
        let isVideo = item.supportedContentTypes.contains { type in
            type.conforms(to: .movie) || type.conforms(to: .video)
        }
        if isVideo {
            // The picker's copy is already in the temp folder; move it rather than leave a duplicate.
            // A video that can't be transferred as a file is not read into memory and saved as a photo.
            guard let movie = try? await item.loadTransferable(type: ComposerMovieFile.self) else { return nil }
            return try? store.saveMediaFile(from: movie.url, removeSource: true)
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        let prepared = await Task.detached(priority: .userInitiated) {
            ComposerImagePreparation.boardImage(from: data)
        }.value
        return try? store.saveMediaData(prepared.data, fileExtension: prepared.fileExtension)
    }

    nonisolated static func prepareForCarousel(_ item: PhotosPickerItem) async -> PreparedCarouselMedia? {
        let isVideo = item.supportedContentTypes.contains { type in
            type.conforms(to: .movie) || type.conforms(to: .video)
        }
        if isVideo, let movie = try? await item.loadTransferable(type: ComposerMovieFile.self) {
            return PreparedCarouselMedia(videoURL: movie.url)
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        if ComposerAnimatedImage.isGIF(data) {
            return PreparedCarouselMedia(imageData: data)
        }
        let prepared = await Task.detached(priority: .userInitiated) {
            ComposerImagePreparation.jpeg(from: data) ?? data
        }.value
        return PreparedCarouselMedia(imageData: prepared)
    }

    @MainActor
    static func importCarouselItems(
        _ items: [PhotosPickerItem],
        ids: [String],
        store: ComposerStore,
        apply: @MainActor (String, String?) -> Void
    ) async {
        await withTaskGroup(of: (String, PreparedCarouselMedia?).self) { group in
            for pair in zip(ids, items) {
                let id = pair.0
                let item = pair.1
                group.addTask {
                    let prepared = await prepareForCarousel(item)
                    return (id, prepared)
                }
            }
            for await (id, prepared) in group {
                let fileName = prepared.flatMap { try? store.storePreparedCarouselMedia($0) }
                apply(id, fileName)
            }
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

private struct MediaBodyTapModifier: ViewModifier {
    var isEnabled: Bool
    var action: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.highPriorityGesture(TapGesture().onEnded { action() })
        } else {
            content
        }
    }
}

struct ComposerMediaLightbox: View {
    @Environment(\.composerMediaVersions) private var mediaVersions
    @Environment(\.composerMediaWaiting) private var mediaWaiting

    let url: URL
    /// A media block's crop, shown as on the board. Carousel items have none.
    var crop: ComposerMediaCrop? = nil
    var onClose: () -> Void

    @State private var image: UIImage?
    @State private var videoAspect: CGFloat?
    @State private var loadFailed = false
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private static let maximumZoom: CGFloat = 5
    private static let doubleTapZoom: CGFloat = 2.5

    private var isVideo: Bool { ComposerMediaStill.isVideo(url) }

    private var canZoom: Bool {
        !loadFailed && (isVideo || image != nil)
    }

    private var scale: CGFloat {
        min(max(zoom * pinch, 1), Self.maximumZoom)
    }

    /// Keeps the zoomed media covering the screen: it can't be dragged past its own edges.
    private static func clamped(_ offset: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        let limitX = max(size.width * (scale - 1) / 2, 0)
        let limitY = max(size.height * (scale - 1) / 2, 0)
        return CGSize(
            width: min(max(offset.width, -limitX), limitX),
            height: min(max(offset.height, -limitY), limitY)
        )
    }

    private func zoomOut() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            zoom = 1
            pan = .zero
        }
    }

    /// Zooms in on the tapped spot, or back out.
    private func toggleZoom(at point: CGPoint, in size: CGSize) {
        guard zoom <= 1.01 else { return zoomOut() }
        let target = Self.doubleTapZoom
        let toward = CGSize(width: (size.width / 2 - point.x) * (target - 1), height: (size.height / 2 - point.y) * (target - 1))
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            zoom = target
            pan = Self.clamped(toward, scale: target, in: size)
        }
    }

    private var contentAspect: CGFloat? {
        if isVideo { return videoAspect }
        guard let image, image.size.height > 0 else { return nil }
        return image.size.width / image.size.height
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.94)
                    .ignoresSafeArea()
                media
                    .scaleEffect(scale)
                    .offset(Self.clamped(
                        CGSize(width: pan.width + drag.width, height: pan.height + drag.height),
                        scale: scale,
                        in: proxy.size
                    ))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            // A double tap zooms; a single tap zooms back out, or closes when not zoomed.
            .gesture(
                SpatialTapGesture(count: 2)
                    .onEnded { value in
                        guard canZoom else { return }
                        toggleZoom(at: value.location, in: proxy.size)
                    }
                    .exclusively(before: TapGesture().onEnded {
                        if zoom > 1.01 { zoomOut() } else { onClose() }
                    })
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        let next = min(max(zoom * value.magnification, 1), Self.maximumZoom)
                        if next <= 1.01 {
                            zoomOut()
                        } else {
                            zoom = next
                            pan = Self.clamped(pan, scale: next, in: proxy.size)
                        }
                    },
                isEnabled: canZoom
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        pan = Self.clamped(
                            CGSize(width: pan.width + value.translation.width, height: pan.height + value.translation.height),
                            scale: zoom,
                            in: proxy.size
                        )
                    },
                isEnabled: canZoom && zoom > 1.01
            )
        }
        .task(id: ComposerMediaLoadKey(url, versions: mediaVersions)) {
            if isVideo {
                loadFailed = !FileManager.default.fileExists(atPath: url.path)
                guard crop != nil else { return }
                let loaded = await ComposerMediaCanvasBlock.videoAspect(at: url)
                guard !Task.isCancelled else { return }
                videoAspect = loaded
            } else {
                let loaded = await ComposerMediaStill.image(at: url)
                guard !Task.isCancelled else { return }
                image = loaded
                loadFailed = loaded == nil
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(isVideo ? "Video" : "Photo")
        .accessibilityValue(zoom > 1.01 ? "Zoomed \(Int((zoom * 100).rounded())) percent" : "")
        .accessibilityZoomAction { action in
            guard canZoom else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                switch action.direction {
                case .zoomIn: zoom = min(zoom * 1.5, Self.maximumZoom)
                case .zoomOut: zoom = max(zoom / 1.5, 1)
                @unknown default: break
                }
                if zoom <= 1.01 { pan = .zero }
            }
        }
        .accessibilityAction(.escape, onClose)
    }

    @ViewBuilder
    private var media: some View {
        Group {
            if loadFailed, !mediaWaiting.includes(url) {
                ComposerMediaUnavailable(isVideo: isVideo)
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .allowsHitTesting(false)
            } else if let crop, let contentAspect {
                GeometryReader { proxy in
                    let width = min(
                        max(proxy.size.width - 32, 1),
                        max(proxy.size.height - 56, 1) * crop.aspect(contentAspect: contentAspect)
                    )
                    crop.framed(croppedContent, width: width, contentAspect: contentAspect)
                        .overlay {
                            if let markup = crop.markup {
                                ComposerMediaMarkupOverlay(data: markup)
                                    .clipShape(mediaClipShape(crop.shape))
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .allowsHitTesting(false)
            } else if crop == nil, isVideo {
                ComposerInlineVideo(url: url, isPaused: false, fillsFrame: false)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 28)
                    .allowsHitTesting(false)
            } else if crop == nil, let image {
                ComposerPicture(image: image, contentMode: .fit)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 28)
                    .allowsHitTesting(false)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
    }

    @ViewBuilder
    private var croppedContent: some View {
        if isVideo {
            ComposerInlineVideo(url: url, isPaused: false, fillsFrame: false)
        } else if let image {
            ComposerPicture(image: image)
        }
    }
}

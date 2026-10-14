import SwiftUI
import PhotosUI
import LinkPresentation

/// Content remains a link on disk so older clients can still decode the board.
extension ComposerBlock {
    var isContent: Bool { kind == .link && socialPlatform.hasPrefix("content:") }
    var contentPlatform: ComposerContentPlatform? {
        guard isContent else { return nil }
        return ComposerContentPlatform(rawValue: String(socialPlatform.dropFirst("content:".count)))
    }
}

enum ComposerContentPlatform: String, CaseIterable, Identifiable {
    case youtube, instagram, tiktok, twitch
    var id: String { rawValue }
    var title: String {
        switch self {
        case .youtube: "YouTube"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .twitch: "Twitch"
        }
    }

    /// A saved crop sets the card's shape. Otherwise YouTube and Twitch stay 16:9 so letterboxed
    /// thumbnails crop cleanly, and vertical platforms take the cover's own shape so the whole preview shows.
    func cardSize(cover: CGSize?, cropAspect: Double = 0) -> CGSize {
        let aspect: CGFloat
        if cropAspect > 0.05 {
            aspect = min(max(CGFloat(cropAspect), MediaFrameShape.minimumAspect), MediaFrameShape.maximumAspect)
        } else {
            switch self {
            case .youtube, .twitch:
                aspect = 16 / 9
            case .instagram, .tiktok:
                if let cover, cover.width > 0, cover.height > 0 {
                    aspect = min(max(cover.width / cover.height, 9 / 16), 16 / 9)
                } else {
                    aspect = self == .tiktok ? 9 / 16 : 4 / 5
                }
            }
        }
        let height = min(320, 260 / aspect)
        return CGSize(width: height * aspect, height: height)
    }

    /// Accept only HTTPS content links, never arbitrary schemes or lookalike domains.
    static func parse(_ input: String) -> (platform: Self, url: URL)? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: text), parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil, parts.port == nil,
              let rawHost = parts.host?.lowercased() else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let path = parts.path.split(separator: "/").map(String.init)
        let platform: Self
        switch host {
        case "youtu.be":
            guard path.count == 1 else { return nil }
            platform = .youtube
        case "youtube.com", "m.youtube.com":
            guard (path == ["watch"] && parts.queryItems?.contains(where: { $0.name == "v" && !($0.value ?? "").isEmpty }) == true)
                    || (path.count == 2 && ["shorts", "live"].contains(path[0])) else { return nil }
            platform = .youtube
        case "instagram.com":
            guard path.count == 2, ["p", "reel", "reels", "tv"].contains(path[0]) else { return nil }
            platform = .instagram
        case "tiktok.com", "m.tiktok.com":
            guard (path.count == 3 && path[0].hasPrefix("@") && ["video", "photo"].contains(path[1]))
                    || (path.count == 2 && path[0] == "t") else { return nil }
            platform = .tiktok
        case "vm.tiktok.com", "vt.tiktok.com":
            guard path.count == 1 else { return nil }
            platform = .tiktok
        case "clips.twitch.tv":
            guard path.count == 1 else { return nil }
            platform = .twitch
        case "twitch.tv", "m.twitch.tv":
            guard (path.count == 2 && path[0] == "videos")
                    || (path.count == 3 && path[1] == "clip") else { return nil }
            platform = .twitch
        default: return nil
        }
        parts.scheme = "https"
        parts.host = rawHost
        parts.fragment = nil
        guard let url = parts.url else { return nil }
        return (platform, url)
    }
}

/// Where the cover sits inside the card. Pan is a fraction of the card's width and height.
struct ComposerContentFraming: Equatable {
    var zoom: Double
    var panX: Double
    var panY: Double
    var frameAspect: Double

    init(zoom: Double = 1, panX: Double = 0, panY: Double = 0, frameAspect: Double = 0) {
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
        self.frameAspect = frameAspect
    }

    init(_ block: ComposerBlock) {
        self.init(zoom: block.mediaZoom, panX: block.mediaPanX, panY: block.mediaPanY, frameAspect: block.mediaFrameAspect)
    }

    /// Keeps the cover covering the card, so a drag never reveals an empty edge.
    func clamped(cover: CGSize, in frame: CGSize) -> Self {
        guard cover.height > 0, frame.width > 0, frame.height > 0 else { return self }
        var next = self
        next.zoom = min(max(zoom, 1), 4)
        let limits = MediaFraming.panLimits(contentAspect: cover.width / cover.height, frame: frame, zoom: CGFloat(next.zoom))
        next.panX = min(max(panX, -Double(limits.width / frame.width)), Double(limits.width / frame.width))
        next.panY = min(max(panY, -Double(limits.height / frame.height)), Double(limits.height / frame.height))
        return next
    }
}

enum ComposerContentCoverFile {
    /// Saves a cover at most 1280 pixels on the long edge. Returns the media file name.
    static func save(_ cover: UIImage, to store: ComposerStore) throws -> String {
        let size = cover.size
        let scale = min(1, 1280 / max(size.width, size.height, 1))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            cover.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { throw ComposerRestoreError.invalidMedia }
        return try store.saveMediaData(data)
    }
}

private struct ComposerContentCover: View {
    let image: UIImage
    let frame: CGSize
    let framing: ComposerContentFraming

    var body: some View {
        let contentAspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        let zoom = CGFloat(min(max(framing.zoom, 1), 4))
        let filled = MediaFraming.fillSize(contentAspect: contentAspect, in: frame)
        let pan = MediaFraming.clampedPan(
            CGSize(width: framing.panX * frame.width, height: framing.panY * frame.height),
            limits: MediaFraming.panLimits(contentAspect: contentAspect, frame: frame, zoom: zoom)
        )
        Image(uiImage: image)
            .resizable()
            .frame(width: filled.width * zoom, height: filled.height * zoom)
            .offset(pan)
            .frame(width: frame.width, height: frame.height)
    }
}

struct ComposerContentCard: View {
    @Binding var block: ComposerBlock
    let mediaURL: URL?
    let isViewing: Bool
    let isSelected: Bool
    let liveScale: CGFloat
    let onCrop: () -> Void
    let onDelete: () -> Void
    @Environment(ComposerStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.composerMediaVersions) private var versions
    @Environment(\.composerViewportWidth) private var viewportWidth
    @Environment(\.composerCoordinateSpace) private var composerSpace
    @State private var image: UIImage?
    @State private var editing = false
    @State private var itemFrame: CGRect = .zero

    private var sourceLogo: ComposerSocialPlatform? {
        block.contentPlatform.flatMap { ComposerSocialPlatform(rawValue: $0.rawValue) }
    }

    private var cardScale: CGFloat { CGFloat(max(0.3, block.style.scale)) * liveScale }

    var body: some View {
        let size = (block.contentPlatform ?? .youtube).cardSize(cover: image?.size, cropAspect: block.mediaFrameAspect)
        Button {
            if isViewing {
                if let target = ComposerContentPlatform.parse(block.linkURL ?? "") { openURL(target.url) }
            } else { editing = true }
        } label: {
            ZStack {
                Color(white: 0.18)
                if let image {
                    ComposerContentCover(image: image, frame: size, framing: ComposerContentFraming(block))
                } else if let sourceLogo {
                    ComposerSocialMark(platform: sourceLogo, side: 44)
                } else {
                    Image(systemName: "link").font(.largeTitle).foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.8)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 100)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .center, spacing: 8) {
                    if let sourceLogo {
                        ComposerSocialMark(platform: sourceLogo, side: 26)
                            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                            .accessibilityHidden(true)
                    }
                    Text(block.text.isEmpty ? "Content" : block.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                }
                .padding(12)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .scaleEffect(cardScale, anchor: .topLeading)
        .frame(width: size.width * cardScale, height: size.height * cardScale, alignment: .topLeading)
        .accessibilityLabel("\(block.contentPlatform?.title ?? "Content"): \(block.text)")
        .accessibilityHint(isViewing ? "Opens the original post" : "Edits this content link")
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(composerSpace))
        } action: { frame in
            itemFrame = frame
        }
        .overlay(alignment: .topLeading) {
            if isSelected, !isViewing, image != nil {
                cropButton
                    .offset(x: ComposerChromePlacement.resolve(itemFrame: itemFrame, viewportWidth: viewportWidth).x, y: -2)
            }
        }
        .task(id: ComposerMediaLoadKey(mediaURL, versions: versions)) {
            guard let mediaURL else { image = nil; return }
            let loaded = await Task.detached { UIImage(contentsOfFile: mediaURL.path) }.value
            guard !Task.isCancelled else { return }
            image = loaded
        }
        .onAppear { if !isViewing && (block.linkURL ?? "").isEmpty { editing = true } }
        .sheet(isPresented: $editing, onDismiss: {
            if (block.linkURL ?? "").isEmpty { onDelete() }
        }) {
            ComposerContentEditor(platform: block.contentPlatform ?? .youtube, link: block.linkURL ?? "",
                                  title: block.text == "Content" ? "" : block.text, cover: image,
                                  framing: ComposerContentFraming(block)) { platform, url, title, cover, framing in
                var updated = block
                updated.socialPlatform = "content:" + platform.rawValue
                updated.linkURL = url.absoluteString
                updated.text = title.isEmpty ? platform.title + " content" : title
                if let cover, cover !== image || updated.mediaFileName == nil {
                    updated.mediaFileName = try ComposerContentCoverFile.save(cover, to: store)
                } else if cover == nil && block.linkURL != url.absoluteString {
                    updated.mediaFileName = nil
                }
                updated.mediaZoom = framing.zoom
                updated.mediaPanX = framing.panX
                updated.mediaPanY = framing.panY
                updated.mediaFrameAspect = framing.frameAspect
                block = updated
                editing = false
            }
        }
    }

    private var cropButton: some View {
        Image(systemName: "crop")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 32, height: 32)
            .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Circle())
            .highPriorityGesture(TapGesture().onEnded { onCrop() })
            .accessibilityLabel("Crop cover")
            .accessibilityAddTraits(.isButton)
    }
}

struct ComposerContentEditor: View {
    @State var platform: ComposerContentPlatform
    @State var link: String
    @State var title: String
    @State var cover: UIImage?
    @State var framing: ComposerContentFraming
    let onSave: (ComposerContentPlatform, URL, String, UIImage?, ComposerContentFraming) throws -> Void

    init(
        platform: ComposerContentPlatform,
        link: String,
        title: String,
        cover: UIImage?,
        framing: ComposerContentFraming,
        onSave: @escaping (ComposerContentPlatform, URL, String, UIImage?, ComposerContentFraming) throws -> Void
    ) {
        _platform = State(initialValue: platform)
        _link = State(initialValue: link)
        _title = State(initialValue: title)
        _cover = State(initialValue: cover)
        _framing = State(initialValue: framing)
        self.onSave = onSave
    }

    @Environment(\.dismiss) private var dismiss
    @State private var dragStart: ComposerContentFraming?
    @State private var pinchStart: ComposerContentFraming?
    @State private var attempt = 0
    @State private var loading = false
    @State private var message: String?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var provider: LPMetadataProvider?

    private var target: (platform: ComposerContentPlatform, url: URL)? { ComposerContentPlatform.parse(link) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ComposerSocialPlatformPicker(
                        platforms: [.instagram, .tiktok, .youtube, .twitch],
                        platform: Binding(
                            get: { ComposerSocialPlatform(rawValue: platform.rawValue) ?? .youtube },
                            set: { if let source = ComposerContentPlatform(rawValue: $0.rawValue) { platform = source } }
                        )
                    )
                    ComposerSocialLinkField(placeholder: "Paste the full content link", link: $link)
                    if !link.isEmpty && target == nil {
                        Text("Paste the full HTTPS link to a post, video, reel, or clip—not a username.")
                            .font(.caption).foregroundStyle(.white.opacity(0.65))
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Preview").font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))
                            Spacer()
                            Button("Refresh") { attempt += 1 }
                                .font(.subheadline)
                                .disabled(target == nil || loading)
                        }
                        if loading { ProgressView("Loading preview…").tint(.white) }
                        if let cover {
                            coverPreview(cover)
                        }
                        TextField("Title", text: $title)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            Label(cover == nil ? "Choose cover photo" : "Change cover photo", systemImage: "photo")
                                .font(.subheadline)
                        }.disabled(loading)
                        if let message { Text(message).font(.caption).foregroundStyle(.white.opacity(0.65)) }
                        Text("Opens the original post. If a preview isn’t available, choose a cover photo.")
                            .font(.caption).foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MosaicBrand.inkBlack)
            .foregroundStyle(.white)
            .navigationTitle("Content").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let target else { return }
                        do {
                            try onSave(target.platform, target.url, title.trimmingCharacters(in: .whitespacesAndNewlines), cover, framing)
                        } catch {
                            message = "The cover couldn’t be saved. Please try again."
                        }
                    }.disabled(target == nil || loading)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: link) { _, _ in
            provider?.cancel()
            cover = nil
            framing = ComposerContentFraming()
            title = ""
            message = nil
            if let target {
                platform = target.platform
                attempt += 1
            }
        }
        .onChange(of: platform) { _, next in
            if let target, target.platform != next { link = "" }
        }
        .task(id: attempt) {
            guard attempt > 0, let target else { return }
            let original = link
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard !Task.isCancelled else { return }
            loading = true
            defer { loading = false }
            let fetcher = LPMetadataProvider()
            fetcher.timeout = 12
            fetcher.shouldFetchSubresources = true
            provider = fetcher
            let postURL = target.url
            async let fullInstagramCover = target.platform == .instagram ? ComposerInstagramCover.fetch(for: postURL) : nil
            var fetched = false
            do {
                let metadata = try await fetcher.startFetchingMetadata(for: target.url)
                guard !Task.isCancelled, link == original else { return }
                fetched = true
                if title.isEmpty { title = metadata.title ?? "" }
                if let imageProvider = metadata.imageProvider, imageProvider.canLoadObject(ofClass: UIImage.self) {
                    let image: UIImage? = await withCheckedContinuation { continuation in
                        _ = imageProvider.loadObject(ofClass: UIImage.self) { object, _ in
                            continuation.resume(returning: object as? UIImage)
                        }
                    }
                    guard !Task.isCancelled, link == original else { return }
                    if let image {
                        cover = image
                        framing = ComposerContentFraming()
                    }
                }
            } catch {}
            let fullCover = await fullInstagramCover
            guard !Task.isCancelled, link == original else { return }
            if let fullCover {
                cover = fullCover
                framing = ComposerContentFraming()
            }
            if cover == nil {
                message = fetched ? "No preview image was available. You can choose a cover photo."
                    : "Preview unavailable. You can still save the link and choose a cover photo."
            }
        }
        .task(id: pickedPhoto) {
            let original = link
            guard let pickedPhoto, let data = try? await pickedPhoto.loadTransferable(type: Data.self),
                  !Task.isCancelled, link == original else { return }
            cover = UIImage(data: data)
            framing = ComposerContentFraming()
        }
        .onDisappear { provider?.cancel() }
    }

    /// Shown at the card's real size and shape, so what you frame here is what the board shows.
    private func coverPreview(_ cover: UIImage) -> some View {
        let frame = platform.cardSize(cover: cover.size, cropAspect: framing.frameAspect)
        let drag = DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStart ?? framing
                if dragStart == nil { dragStart = framing }
                var next = framing
                next.panX = start.panX + value.translation.width / frame.width
                next.panY = start.panY + value.translation.height / frame.height
                framing = next.clamped(cover: cover.size, in: frame)
            }
            .onEnded { _ in dragStart = nil }
        let pinch = MagnificationGesture()
            .onChanged { value in
                let start = pinchStart ?? framing
                if pinchStart == nil { pinchStart = framing }
                var next = framing
                next.zoom = start.zoom * Double(value)
                framing = next.clamped(cover: cover.size, in: frame)
            }
            .onEnded { _ in pinchStart = nil }
        return VStack(spacing: 8) {
            ComposerContentCover(image: cover, frame: frame, framing: framing)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15)))
                .contentShape(Rectangle())
                .gesture(drag.simultaneously(with: pinch))
                .accessibilityLabel("Cover position")
                .accessibilityHint("Drag to move the cover. Pinch to zoom.")
            HStack(spacing: 12) {
                Text("Drag to move · Pinch to zoom")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
                if framing != ComposerContentFraming(frameAspect: framing.frameAspect) {
                    Button("Reset") { framing = ComposerContentFraming(frameAspect: framing.frameAspect) }
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

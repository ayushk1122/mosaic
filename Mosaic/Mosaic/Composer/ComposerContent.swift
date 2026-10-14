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

struct ComposerContentCard: View {
    @Binding var block: ComposerBlock
    let mediaURL: URL?
    let isViewing: Bool
    let liveScale: CGFloat
    let onDelete: () -> Void
    @Environment(ComposerStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.composerMediaVersions) private var versions
    @State private var image: UIImage?
    @State private var editing = false

    private var sourceLogo: ComposerSocialPlatform? {
        block.contentPlatform.flatMap { ComposerSocialPlatform(rawValue: $0.rawValue) }
    }

    private var cardScale: CGFloat { CGFloat(max(0.3, block.style.scale)) * liveScale }

    var body: some View {
        Button {
            if isViewing {
                if let target = ComposerContentPlatform.parse(block.linkURL ?? "") { openURL(target.url) }
            } else { editing = true }
        } label: {
            ZStack {
                Color(white: 0.18)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let sourceLogo {
                    ComposerSocialMark(platform: sourceLogo, side: 44)
                } else {
                    Image(systemName: "link").font(.largeTitle).foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 260, height: 146)
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
        .frame(width: 260 * cardScale, height: 146 * cardScale, alignment: .topLeading)
        .accessibilityLabel("\(block.contentPlatform?.title ?? "Content"): \(block.text)")
        .accessibilityHint(isViewing ? "Opens the original post" : "Edits this content link")
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
                                  title: block.text == "Content" ? "" : block.text, cover: image) { platform, url, title, cover in
                var updated = block
                updated.socialPlatform = "content:" + platform.rawValue
                updated.linkURL = url.absoluteString
                updated.text = title.isEmpty ? platform.title + " content" : title
                if let cover, cover !== image || updated.mediaFileName == nil {
                    let size = cover.size
                    let scale = min(1, 1280 / max(size.width, size.height, 1))
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1
                    let resized = UIGraphicsImageRenderer(size: CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale)), format: format).image { _ in
                        cover.draw(in: CGRect(origin: .zero, size: CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))))
                    }
                    guard let data = resized.jpegData(compressionQuality: 0.85) else { throw ComposerRestoreError.invalidMedia }
                    updated.mediaFileName = try store.saveMediaData(data)
                } else if cover == nil && block.linkURL != url.absoluteString {
                    updated.mediaFileName = nil
                }
                block = updated
                editing = false
            }
        }
    }
}

private struct ComposerContentEditor: View {
    @State var platform: ComposerContentPlatform
    @State var link: String
    @State var title: String
    @State var cover: UIImage?
    let onSave: (ComposerContentPlatform, URL, String, UIImage?) throws -> Void
    @Environment(\.dismiss) private var dismiss
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
                            Image(uiImage: cover).resizable().scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
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
                            try onSave(target.platform, target.url, title.trimmingCharacters(in: .whitespacesAndNewlines), cover)
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
            do {
                let metadata = try await fetcher.startFetchingMetadata(for: target.url)
                guard !Task.isCancelled, link == original else { return }
                if title.isEmpty { title = metadata.title ?? "" }
                if let imageProvider = metadata.imageProvider, imageProvider.canLoadObject(ofClass: UIImage.self) {
                    let image: UIImage? = await withCheckedContinuation { continuation in
                        _ = imageProvider.loadObject(ofClass: UIImage.self) { object, _ in
                            continuation.resume(returning: object as? UIImage)
                        }
                    }
                    guard !Task.isCancelled, link == original else { return }
                    cover = image
                }
                if cover == nil { message = "No preview image was available. You can choose a cover photo." }
            } catch {
                guard !Task.isCancelled, link == original else { return }
                message = "Preview unavailable. You can still save the link and choose a cover photo."
            }
        }
        .task(id: pickedPhoto) {
            let original = link
            guard let pickedPhoto, let data = try? await pickedPhoto.loadTransferable(type: Data.self),
                  !Task.isCancelled, link == original else { return }
            cover = UIImage(data: data)
        }
        .onDisappear { provider?.cancel() }
    }
}

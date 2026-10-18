import AVFoundation
import PhotosUI
import SwiftUI

struct CarouselLayout {
    var width: CGFloat

    /// Lower than other blocks, so a carousel of social logos can shrink to a single logo's size.
    static let minimumScale = 0.2

    /// Scales evenly down to the minimum, so every card keeps its shape at any size.
    init(scale: CGFloat) {
        width = 300 * max(scale, CGFloat(Self.minimumScale))
    }

    init(width: CGFloat) {
        self.width = width
    }

    var height: CGFloat { width * 0.72 }
    var cardWidth: CGFloat { width * 0.56 }
    var cardHeight: CGFloat { height * 0.94 }
    var step: CGFloat { max(cardWidth * 0.84, 1) }
    var maxCardWidth: CGFloat { width * 0.66 }
    var socialSide: CGFloat { cardHeight * 0.6 }
    /// A social's handle sits below its logo and grows and shrinks with the carousel.
    var handleFontSize: CGFloat { width * 0.042 }
    var handleOffset: CGFloat { width * 0.075 }

    /// A card keeps its item's shape, as large as fits `maxCardWidth` by `cardHeight`.
    func cardSize(aspect: CGFloat) -> CGSize {
        let aspect = max(aspect, 0.1)
        if aspect > maxCardWidth / cardHeight {
            return CGSize(width: maxCardWidth, height: maxCardWidth / aspect)
        }
        return CGSize(width: cardHeight * aspect, height: cardHeight)
    }

    func scale(for delta: CGFloat) -> CGFloat {
        1 - 0.24 * min(abs(delta), 1)
    }

    func opacity(for delta: CGFloat) -> Double {
        let distance = abs(delta)
        if distance >= 1.75 { return 0 }
        if distance <= 1 { return Double(1 - 0.34 * distance) }
        return Double(0.66 * (1 - (distance - 1) / 0.75))
    }
}

enum ComposerMediaStill {
    nonisolated static func isVideo(_ url: URL) -> Bool {
        ["mov", "mp4", "m4v", "avi"].contains(url.pathExtension.lowercased())
    }

    static func image(at url: URL) async -> UIImage? {
        if isVideo(url) {
            return await videoPoster(at: url)
        }
        return await Task.detached(priority: .userInitiated) {
            ComposerAnimatedImage.image(contentsOf: url)
        }.value
    }

    private static func videoPoster(at url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let image = try? await generator.image(at: time).image else { return nil }
        return UIImage(cgImage: image)
    }
}

/// One carousel card's face. It fills whatever frame the carousel or editor gives it.
struct ComposerCarouselItemFace: View {
    let item: CarouselMediaItem
    let poster: UIImage?
    var compact = false
    var isUnavailable = false

    /// Width divided by height, matching the item's block on a board: a photo or video's own
    /// shape, a content card's shape, and a square logo for a social.
    static func aspect(of item: CarouselMediaItem, poster: UIImage?) -> CGFloat {
        switch item.kind {
        case .social:
            return 1
        case .content:
            let size = (item.contentPlatform ?? .youtube).cardSize(cover: poster?.size)
            return size.width / max(size.height, 1)
        case .media:
            guard let poster, poster.size.height > 0 else { return 4.0 / 5.0 }
            return min(max(poster.size.width / poster.size.height, 0.5), 2)
        }
    }

    var body: some View {
        ZStack {
            switch item.kind {
            case .media:
                if let poster {
                    ComposerPicture(image: poster)
                } else if isUnavailable {
                    ComposerMediaUnavailable(isVideo: ComposerMediaStill.isVideo(URL(fileURLWithPath: item.fileName)), compact: compact)
                } else {
                    Color.white.opacity(0.08)
                    ProgressView()
                        .tint(.white)
                }
            case .social:
                if compact {
                    social
                } else {
                    Image((item.socialPlatform ?? .instagram).assetName)
                        .renderingMode(.original)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .accessibilityLabel(socialLabel)
                }
            case .content:
                content
            }
        }
    }

    private var socialLabel: String {
        let platform = item.socialPlatform ?? .instagram
        return "\(platform.title) \(platform.handle(from: item.link))"
    }

    private var social: some View {
        let platform = item.socialPlatform ?? .instagram
        return ZStack {
            Color(white: 0.14)
            VStack(spacing: compact ? 6 : 10) {
                ComposerSocialMark(platform: platform, side: compact ? 30 : 52)
                Text(platform.handle(from: item.link))
                    .font((compact ? Font.caption2 : .caption).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(socialLabel)
    }

    private var content: some View {
        let logo = item.contentPlatform.flatMap { ComposerSocialPlatform(rawValue: $0.rawValue) }
        let title = item.title.isEmpty ? (item.contentPlatform?.title ?? "Content") : item.title
        return Color(white: 0.18)
            .overlay {
                if let poster {
                    ComposerPicture(image: poster)
                } else if let logo {
                    ComposerSocialMark(platform: logo, side: compact ? 28 : 44)
                }
            }
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    .frame(height: compact ? 44 : 72)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 6) {
                    if let logo, poster != nil {
                        ComposerSocialMark(platform: logo, side: compact ? 14 : 20)
                    }
                    if !compact {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(compact ? 6 : 10)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.contentPlatform?.title ?? "Content"): \(title)")
    }
}

struct ComposerCarouselCanvasBlock: View {
    @Binding var block: ComposerBlock
    let scale: CGFloat
    let livePinchScale: CGFloat
    let isSelected: Bool
    let isLifted: Bool
    let isRelocating: Bool
    let allowsDirectControl: Bool
    var onEdit: () -> Void
    var onPresentMedia: ((URL, ComposerMediaCrop?) -> Void)? = nil
    /// Social and content cards open their links. Boards do this while viewing.
    var opensLinks = false

    @Environment(ComposerStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.composerViewportWidth) private var viewportWidth
    @Environment(\.composerCoordinateSpace) private var composerSpace

    @GestureState private var drag: CGFloat = 0
    @State private var settle: CGFloat = 0
    @State private var playing = false
    @State private var posters: [String: UIImage] = [:]
    @State private var loadingPosters: Set<String> = []
    @State private var failedPosters: Set<String> = []
    @Environment(\.composerMediaWaiting) private var mediaWaiting
    @State private var itemFrame: CGRect = .zero
    @State private var editFrame: CGRect = .zero

    private var layout: CarouselLayout {
        CarouselLayout(scale: scale * livePinchScale)
    }

    private var count: Int { block.carouselItems.count }
    private var ready: Bool { count >= CarouselMotion.minimumCount }

    private var centerIndex: Int {
        CarouselMotion.wrapped(block.carouselIndex, count: count)
    }

    private var pan: CGFloat {
        isLifted || isRelocating ? 0 : drag + settle
    }

    private var iconPlacement: ComposerChromePlacement {
        ComposerChromePlacement.resolve(itemFrame: itemFrame, viewportWidth: viewportWidth)
    }

    private var posterKey: String {
        block.carouselItems.map { "\($0.fileName):\(store.mediaVersions[$0.fileName, default: 0])" }.joined(separator: "|")
    }

    var body: some View {
        face
            .overlay(alignment: .topLeading) {
                if isSelected, !isLifted, !isRelocating {
                    editButton
                        .offset(x: iconPlacement.x, y: -2)
                }
            }
            .shadow(color: .white.opacity(isLifted ? 0.85 : 0), radius: isLifted ? 3 : 0)
            .shadow(color: .white.opacity(isLifted ? 0.4 : 0), radius: isLifted ? 14 : 0)
            .animation(.easeOut(duration: 0.16), value: isLifted)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(composerSpace))
            } action: { frame in
                itemFrame = frame
            }
            .onChange(of: posterKey, initial: true) { _, _ in
                requestPosters()
            }
            .onChange(of: centerIndex) { _, _ in
                playing = false
            }
            .onChange(of: isSelected) { _, selected in
                if !selected { playing = false }
            }
            .onChange(of: isLifted) { _, lifted in
                guard lifted else { return }
                playing = false
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    settle = 0
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Carousel")
            .accessibilityIdentifier("composer.carousel")
    }

    @ViewBuilder
    private var face: some View {
        if ready {
            carousel
        } else {
            placeholder
        }
    }

    private var carousel: some View {
        ZStack {
            ForEach(cardSlots) { slot in
                card(slot.item, delta: CGFloat(slot.offset) + pan / layout.step)
            }
        }
        .frame(width: layout.width, height: layout.height)
        .clipped()
        .contentShape(Rectangle())
        .modifier(CarouselScrollModifier(
            isEnabled: allowsDirectControl && count > 1 && !isLifted && !isRelocating,
            gesture: scrollGesture
        ))
    }

    private var cardSlots: [CarouselCardSlot] {
        block.carouselItems.enumerated().flatMap { index, item in
            CarouselMotion.offsets(item: index, center: centerIndex, count: count)
                .map { CarouselCardSlot(item: item, offset: $0) }
        }
    }

    private var placeholder: some View {
        let size = layout.cardSize(aspect: 4.0 / 5.0)
        return ZStack {
            Color.white.opacity(0.06)
            Image(systemName: "plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .frame(width: layout.width, height: layout.height)
        .allowsHitTesting(false)
    }

    private func card(_ item: CarouselMediaItem, delta: CGFloat) -> some View {
        let isCenter = abs(delta) < 0.35
        let hasFile = item.kind == .media && !item.fileName.isEmpty
        let url = hasFile ? store.mediaURL(for: item.fileName) : nil
        let isVideo = url.map(ComposerMediaStill.isVideo) ?? false
        let isSocial = item.kind == .social
        let poster = posters[item.fileName]
        let size = isSocial
            ? CGSize(width: layout.socialSide, height: layout.socialSide)
            : layout.cardSize(aspect: ComposerCarouselItemFace.aspect(of: item, poster: poster))
        return ZStack {
            if isCenter, isVideo, playing, let url {
                ComposerInlineVideo(url: url, isPaused: false, fillsFrame: true)
            } else {
                ComposerCarouselItemFace(
                    item: item,
                    poster: poster,
                    isUnavailable: failedPosters.contains(item.fileName) && !mediaWaiting.includes(item.fileName)
                )
            }
            if isCenter, isVideo, !playing {
                Image(systemName: "play.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.4), in: Circle())
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .modifier(CarouselCardFrame(isFramed: !isSocial, isCenter: isCenter))
        .overlay(alignment: .bottom) {
            if isSocial, let platform = item.socialPlatform {
                Text(platform.handle(from: item.link))
                    .font(.system(size: layout.handleFontSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize()
                    .offset(y: layout.handleOffset)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.18), value: size)
        .scaleEffect(layout.scale(for: delta))
        .opacity(layout.opacity(for: delta))
        .offset(x: delta * layout.step)
        .zIndex(2 - Double(min(abs(delta), 2)))
        .allowsHitTesting(isCenter && allowsDirectControl && !isLifted)
        .onTapGesture {
            guard isCenter else { return }
            if present(item) || item.kind != .media { return }
            guard isVideo else { return }
            playing.toggle()
        }
    }

    /// Opens a social or content card's link, or shows media full screen. False when nothing opened.
    @discardableResult
    private func present(_ item: CarouselMediaItem) -> Bool {
        if item.kind != .media {
            guard opensLinks || onPresentMedia != nil, let link = item.linkURL else { return false }
            openURL(link)
            return true
        }
        guard let onPresentMedia, !item.fileName.isEmpty else { return false }
        onPresentMedia(store.mediaURL(for: item.fileName), nil)
        return true
    }

    private var scrollGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($drag) { value, state, _ in
                guard !isLifted, !isRelocating else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = min(max(value.translation.width, -layout.step), layout.step)
            }
            .onChanged { _ in
                if playing { playing = false }
            }
            .onEnded { value in
                let step = layout.step
                let translation = min(max(value.translation.width, -step), step)
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let shift = CarouselMotion.shift(
                    drag: translation,
                    predicted: value.predictedEndTranslation.width,
                    step: step
                )
                let fraction = translation / max(step, 1)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    settle = (fraction + CGFloat(shift)) * step
                    if shift != 0 {
                        block.carouselIndex = CarouselMotion.wrapped(centerIndex + shift, count: count)
                    }
                }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    settle = 0
                }
                if shift != 0 {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
    }

    private var editButton: some View {
        Image(systemName: "rectangle.stack")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 32, height: 32)
            .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Circle())
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(composerSpace))
            } action: { frame in
                editFrame = frame
            }
            .preference(key: ComposerTextStyleIconFrameKey.self, value: [block.id: editFrame])
            .highPriorityGesture(TapGesture().onEnded { onEdit() })
            .accessibilityLabel("Edit carousel")
            .accessibilityAddTraits(.isButton)
    }

    private func requestPosters() {
        loadCarouselPosters(
            items: block.carouselItems,
            posters: posters,
            loading: loadingPosters,
            urlFor: { store.mediaURL(for: $0) }
        ) { name in
            loadingPosters.insert(name)
        } finish: { name, image in
            if let image {
                posters[name] = image
                failedPosters.remove(name)
            } else {
                failedPosters.insert(name)
            }
            loadingPosters.remove(name)
        }
    }
}

@MainActor
private func loadCarouselPosters(
    items: [CarouselMediaItem],
    posters: [String: UIImage],
    loading: Set<String>,
    urlFor: (String) -> URL,
    markLoading: (String) -> Void,
    finish: @escaping @MainActor (String, UIImage?) -> Void
) {
    for item in items {
        let name = item.fileName
        guard !name.isEmpty, posters[name] == nil, !loading.contains(name) else { continue }
        markLoading(name)
        let url = urlFor(name)
        Task { @MainActor in
            var image = await ComposerMediaStill.image(at: url)
            if image == nil, FileManager.default.fileExists(atPath: url.path) {
                image = await ComposerMediaStill.image(at: url)
            }
            finish(name, image)
        }
    }
}

private struct CarouselCardSlot: Identifiable {
    let item: CarouselMediaItem
    let offset: Int
    var id: String { "\(item.id)@\(offset)" }
}

/// Photos, videos, and content get a rounded card. A social stays a bare logo, like on the board.
private struct CarouselCardFrame: ViewModifier {
    let isFramed: Bool
    let isCenter: Bool

    func body(content: Content) -> some View {
        if isFramed {
            content
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(isCenter ? 0.16 : 0.06), lineWidth: 1)
                }
        } else {
            content
        }
    }
}

private struct CarouselScrollModifier<G: Gesture>: ViewModifier {
    let isEnabled: Bool
    let gesture: G

    func body(content: Content) -> some View {
        if isEnabled {
            content.highPriorityGesture(gesture)
        } else {
            content
        }
    }
}

struct ComposerCarouselEditor: View {
    private enum Source {
        case stored(documentID: ComposerDocumentID?, blockID: ComposerBlockID)
        case local(items: Binding<[CarouselMediaItem]>, index: Binding<Int>)
    }

    private let source: Source

    init(documentID: ComposerDocumentID?, blockID: ComposerBlockID) {
        source = .stored(documentID: documentID, blockID: blockID)
    }

    init(items: Binding<[CarouselMediaItem]>, index: Binding<Int>) {
        source = .local(items: items, index: index)
    }

    @Environment(ComposerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var posters: [String: UIImage] = [:]
    @State private var loadingPosters: Set<String> = []
    @State private var failedPosters: Set<String> = []
    @Environment(\.composerMediaWaiting) private var mediaWaiting
    @State private var showPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var replacingID: String?
    @State private var isImporting = false
    @State private var socialDraft: CarouselMediaItem?
    @State private var contentDraft: CarouselMediaItem?

    private var items: [CarouselMediaItem] {
        switch source {
        case let .stored(documentID, blockID):
            store.block(with: blockID, in: documentID)?.carouselItems ?? []
        case let .local(items, _):
            items.wrappedValue
        }
    }

    private var carouselIndex: Int {
        switch source {
        case let .stored(documentID, blockID):
            store.block(with: blockID, in: documentID)?.carouselIndex ?? 0
        case let .local(_, index):
            index.wrappedValue
        }
    }

    private var canRemove: Bool {
        items.count > CarouselMotion.minimumCount
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Photos, videos, socials, or content. Mix them in any order. The center one is larger, and a video there can play.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(items) { item in
                            itemCard(item)
                        }
                        addCard
                    }
                    .padding(.vertical, 8)
                    .padding(.trailing, 8)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(MosaicBrand.inkBlack)
            .navigationTitle("Carousel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(MosaicBrand.inkBlack)
        .photosPicker(
            isPresented: $showPicker,
            selection: $pickerItems,
            maxSelectionCount: replacingID == nil ? 12 : 1,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: pickerItems) { _, picked in
            guard !picked.isEmpty else { return }
            let chosen = picked
            let replacing = replacingID
            pickerItems = []
            replacingID = nil
            Task { await importPicked(chosen, replacing: replacing) }
        }
        .onChange(of: items.map { "\($0.fileName):\(store.mediaVersions[$0.fileName, default: 0])" }.joined(separator: "|"), initial: true) { _, _ in
            requestPosters()
        }
        .sheet(item: $socialDraft) { draft in
            let platform = draft.socialPlatform ?? .instagram
            ComposerSocialEditor(
                platform: platform,
                link: draft.link,
                onCancel: { socialDraft = nil },
                onSave: { platform, link in
                    var next = draft
                    next.platform = platform.rawValue
                    guard let url = platform.profileURL(from: link) else {
                        socialDraft = nil
                        return
                    }
                    next.link = url.absoluteString
                    put(next)
                    socialDraft = nil
                }
            )
        }
        .sheet(item: $contentDraft) { draft in
            ComposerContentEditor(
                platform: draft.contentPlatform ?? .youtube,
                link: draft.link,
                title: draft.title,
                cover: posters[draft.fileName],
                framing: ComposerContentFraming()
            ) { platform, url, title, cover, _ in
                var next = draft
                next.platform = platform.rawValue
                next.link = url.absoluteString
                next.title = title
                if let cover {
                    if cover !== posters[draft.fileName] || draft.fileName.isEmpty {
                        next.fileName = try ComposerContentCoverFile.save(cover, to: store)
                        posters[next.fileName] = cover
                    }
                } else if url.absoluteString == draft.link, posters[draft.fileName] == nil {
                    // The saved cover just hadn't loaded (or synced) yet; keep it, as the board card does.
                } else {
                    next.fileName = ""
                }
                put(next)
                contentDraft = nil
            }
        }
    }

    private func itemCard(_ item: CarouselMediaItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                switch item.kind {
                case .media:
                    replacingID = item.id
                    showPicker = true
                case .social:
                    socialDraft = item
                case .content:
                    contentDraft = item
                }
            } label: {
                thumbnail(item)
            }
            .buttonStyle(.plain)
            .disabled(item.isPending)
            .accessibilityLabel(item.kind == .media ? "Replace item" : "Edit item")

            // A pending item left over from an interrupted import (undo, relaunch) can be removed.
            if canRemove, !item.isPending || !isImporting {
                Button {
                    remove(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(.black.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityLabel("Remove item")
            }
        }
    }

    private func thumbnail(_ item: CarouselMediaItem) -> some View {
        ZStack {
            ComposerCarouselItemFace(
                item: item,
                poster: posters[item.fileName],
                compact: true,
                isUnavailable: failedPosters.contains(item.fileName) && !mediaWaiting.includes(item.fileName)
            )
            if item.kind == .media, ComposerMediaStill.isVideo(store.mediaURL(for: item.fileName)) {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(.black.opacity(0.4), in: Circle())
            }
        }
        .frame(width: thumbnailWidth(item), height: 128)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func thumbnailWidth(_ item: CarouselMediaItem) -> CGFloat {
        let aspect = ComposerCarouselItemFace.aspect(of: item, poster: posters[item.fileName])
        return min(max(128 * aspect, 72), 228)
    }

    private var addCard: some View {
        Menu {
            Button {
                replacingID = nil
                showPicker = true
            } label: {
                Label("Photos & videos", systemImage: "photo.on.rectangle")
            }
            Button {
                socialDraft = CarouselMediaItem(fileName: "", kind: .social, platform: ComposerSocialPlatform.instagram.rawValue)
            } label: {
                Label("Social", systemImage: "person.crop.circle")
            }
            Button {
                contentDraft = CarouselMediaItem(fileName: "", kind: .content, platform: ComposerContentPlatform.youtube.rawValue)
            } label: {
                Label("Content", systemImage: "play.rectangle")
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                Text("Add")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.white.opacity(0.86))
            .frame(width: 96, height: 128)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .buttonStyle(.plain)
        .disabled(isImporting)
        .accessibilityLabel("Add item")
        .accessibilityIdentifier("carousel.add")
    }

    /// Replaces the item with the same id, or adds it at the end.
    private func put(_ item: CarouselMediaItem) {
        update { media, _ in
            if let index = media.firstIndex(where: { $0.id == item.id }) {
                media[index] = item
            } else {
                media.append(item)
            }
        }
    }

    private func remove(_ item: CarouselMediaItem) {
        guard canRemove, let removedAt = items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            update { media, index in
                let current = CarouselMotion.wrapped(carouselIndex, count: media.count)
                media.removeAll { $0.id == item.id }
                index = CarouselMotion.indexAfterRemoval(
                    index: current,
                    removedAt: removedAt,
                    countAfter: media.count
                )
            }
        }
    }

    private func importPicked(_ picked: [PhotosPickerItem], replacing: String?) async {
        isImporting = true
        defer { isImporting = false }
        if let replacing {
            await ComposerMediaImport.importCarouselItems(picked, ids: [replacing], store: store) { id, fileName in
                guard let fileName else { return }
                update { media, _ in
                    guard let index = media.firstIndex(where: { $0.id == id }) else { return }
                    media[index].fileName = fileName
                }
            }
            return
        }

        let placeholders = picked.map { _ in CarouselMediaItem(fileName: "") }
        update { media, _ in
            media.append(contentsOf: placeholders)
        }
        await ComposerMediaImport.importCarouselItems(
            picked,
            ids: placeholders.map(\.id),
            store: store
        ) { id, fileName in
            update { media, _ in
                if let fileName, let index = media.firstIndex(where: { $0.id == id }) {
                    media[index].fileName = fileName
                } else {
                    media.removeAll { $0.id == id }
                }
            }
        }
    }

    private func requestPosters() {
        loadCarouselPosters(
            items: items,
            posters: posters,
            loading: loadingPosters,
            urlFor: { store.mediaURL(for: $0) }
        ) { name in
            loadingPosters.insert(name)
        } finish: { name, image in
            if let image {
                posters[name] = image
                failedPosters.remove(name)
            } else {
                failedPosters.insert(name)
            }
            loadingPosters.remove(name)
        }
    }

    private func update(_ body: (inout [CarouselMediaItem], inout Int) -> Void) {
        switch source {
        case let .stored(documentID, blockID):
            guard var block = store.block(with: blockID, in: documentID) else { return }
            body(&block.carouselItems, &block.carouselIndex)
            block.carouselIndex = block.carouselItems.isEmpty
                ? 0
                : CarouselMotion.wrapped(block.carouselIndex, count: block.carouselItems.count)
            store.updateBlock(block, in: documentID)
        case let .local(items, index):
            var nextItems = items.wrappedValue
            var nextIndex = index.wrappedValue
            body(&nextItems, &nextIndex)
            nextIndex = nextItems.isEmpty ? 0 : CarouselMotion.wrapped(nextIndex, count: nextItems.count)
            items.wrappedValue = nextItems
            index.wrappedValue = nextIndex
        }
    }
}

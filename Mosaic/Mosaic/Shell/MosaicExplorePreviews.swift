import CryptoKit
import SwiftUI
import UIKit

/// Makes the image Explore shows for each of the owner's shared boards: its pieces as a visitor
/// sees them, framed at 3:4. Made when a board is first shared, and again when its content or its Pursuits'
/// privacy has changed, at most once an hour.
@MainActor
@Observable
final class MosaicExplorePreviews {
    @ObservationIgnored private weak var store: ComposerStore?
    @ObservationIgnored private let account: MosaicAccount
    @ObservationIgnored private var queue: [(UUID, Bool)] = []
    @ObservationIgnored private var running = false

    static let refreshInterval: TimeInterval = 60 * 60
    /// Raised when previews are drawn differently, so every shared board gets a new one once.
    static let rendererVersion = 3

    init(store: ComposerStore, account: MosaicAccount) {
        self.store = store
        self.account = account
    }

    /// `force` makes one now, as when a board has just been shared.
    func refresh(boardID: UUID, force: Bool) {
        queue.append((boardID, force))
        run()
    }

    /// Every shared board whose preview is missing or out of date.
    func refreshStale() {
        Task { [weak self] in
            guard let self, let config = SupabaseSyncConfig.current(),
                  let owner = account.session?.userID,
                  let token = await account.accessToken(),
                  let shared = try? await MosaicExploreClient(config: config).sharedBoards(ownerID: owner, accessToken: token)
            else { return }
            let versionKey = "explore.preview.version.\(owner.uuidString.lowercased())"
            let redraw = UserDefaults.standard.integer(forKey: versionKey) < Self.rendererVersion
            for (id, madeAt) in shared {
                let due = madeAt.map { Date().timeIntervalSince($0) > Self.refreshInterval } ?? true
                if due || redraw { queue.append((id, madeAt == nil || redraw)) }
            }
            UserDefaults.standard.set(Self.rendererVersion, forKey: versionKey)
            run()
        }
    }

    private func run() {
        guard !running, !queue.isEmpty else { return }
        running = true
        Task { [weak self] in
            while let self, !self.queue.isEmpty {
                let (id, force) = self.queue.removeFirst()
                await self.make(boardID: id, force: force)
            }
            self?.running = false
        }
    }

    private func make(boardID: UUID, force: Bool) async {
        guard let store, let config = SupabaseSyncConfig.current(),
              let owner = account.session?.userID,
              let token = await account.accessToken(),
              let documentID = Self.documentID(of: boardID, in: store)
        else { return }
        let boards = (try? await MosaicSettingsClient(config: config).loadBoards(userID: owner, accessToken: token)) ?? []
        let levels = MosaicPursuitPrivacy.levels(from: boards)
        let fingerprint = Self.fingerprint(store: store, documentID: documentID, levels: levels)
        let key = "explore.preview.\(owner.uuidString.lowercased()).\(boardID.uuidString.lowercased())"
        guard force || UserDefaults.standard.string(forKey: key) != fingerprint else { return }
        guard let jpeg = await MosaicBoardPreviewRenderer.render(
            store: store,
            documentID: documentID,
            privacy: MosaicPrivacyDisplay(mode: .visitor, levels: levels)
        ) else { return }
        do {
            try await MosaicExploreClient(config: config).publishPreview(jpeg, for: boardID, ownerID: owner, accessToken: token)
            UserDefaults.standard.set(fingerprint, forKey: key)
        } catch {
            // Tried again on the next refresh.
        }
    }

    /// The Mosaic is the board without a document id; a Pursuit is found by its id.
    private static func documentID(of boardID: UUID, in store: ComposerStore) -> ComposerDocumentID?? {
        if let mosaicID = ComposerBackgroundRestore.state(at: store.location)?.mosaicID, mosaicID == boardID {
            return .some(nil)
        }
        guard let pursuit = store.snapshot.pursuits.first(where: { ComposerBoardSync.uuid($0.id) == boardID && $0.role == .pursuit })
        else { return nil }
        return .some(pursuit.id)
    }

    /// What the preview depends on: the board's pieces and background, and its Pursuits' privacy.
    private static func fingerprint(store: ComposerStore, documentID: ComposerDocumentID?, levels: [UUID: MosaicVisibilityLevel]) -> String {
        struct Input: Encodable {
            var blocks: [ComposerBlock]
            var background: ComposerBoardBackground?
            var levels: [String: String]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let input = Input(
            blocks: store.blocks(for: documentID),
            background: store.boardBackground(for: documentID),
            levels: Dictionary(uniqueKeysWithValues: levels.map { ($0.key.uuidString, $0.value.rawValue) })
        )
        let data = (try? encoder.encode(input)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Lays a board out off screen at the owner's screen width, gives its photos a moment to load, and
/// captures a 3:4 frame around its pieces. Photos load on their own after the board appears, which
/// an image renderer would miss.
@MainActor
enum MosaicBoardPreviewRenderer {
    /// Pixel size of the published image.
    static let output = CGSize(width: 540, height: 720)

    static func render(store: ComposerStore, documentID: ComposerDocumentID?, privacy: MosaicPrivacyDisplay) async -> Data? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        // Pieces are sized for the width they were placed at; another width would shift them.
        let width = scene.screen.bounds.width
        let size = CGSize(width: width, height: width * 2)
        let frames = MosaicBoardPreviewFrames()
        let canvas = MosaicBoardPreviewCanvas(store: store, documentID: documentID, size: size, frames: frames)
            .environment(store)
            .environment(\.mosaicPrivacyDisplay, privacy)
            .environment(\.composerViewportWidth, size.width)
            .environment(\.composerMediaVersions, store.mediaVersions)
            .environment(\.composerStillsOnly, true)
        let host = UIHostingController(rootView: canvas)
        // No status bar or home indicator room: the image is the board edge to edge.
        host.safeAreaRegions = []
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .black
        let window = UIWindow(windowScene: scene)
        // Off screen and behind everything: never seen, but laid out and drawn.
        window.frame = CGRect(x: -size.width * 4, y: 0, width: size.width, height: size.height)
        window.windowLevel = .normal - 1
        window.isUserInteractionEnabled = false
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        // Photos, video stills, and widget backgrounds load on their own after the board appears.
        try? await Task.sleep(for: .milliseconds(2500))
        let crop = crop(around: frames.content(in: size), in: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = output.width / crop.width
        let image = UIGraphicsImageRenderer(size: crop.size, format: format).image { _ in
            host.view.drawHierarchy(
                in: CGRect(x: -crop.minX, y: -crop.minY, width: size.width, height: size.height),
                afterScreenUpdates: true
            )
        }
        return image.jpegData(compressionQuality: 0.8)
    }

    /// A 3:4 frame that holds the content with a little room around it, never zooming in past
    /// 60% of the board's width. Short content sits in the middle; tall content shows from its top.
    static func crop(around content: CGRect?, in size: CGSize) -> CGRect {
        let margin: CGFloat = 14
        guard let content, !content.isEmpty else {
            return CGRect(x: 0, y: 0, width: size.width, height: min(size.width * 4 / 3, size.height))
        }
        let width = min(
            size.width,
            max(content.width + margin * 2, (content.height + margin * 2) * 3 / 4, size.width * 0.6)
        )
        let height = min(width * 4 / 3, size.height)
        let x = min(max(content.midX - width / 2, 0), size.width - width)
        let fits = content.height + margin * 2 <= height
        let y = fits ? content.midY - height / 2 : content.minY - margin
        return CGRect(x: x, y: min(max(y, 0), size.height - height), width: width, height: height)
    }
}

/// Where the preview's banner and pieces landed, read once the board has laid out.
@MainActor
final class MosaicBoardPreviewFrames {
    var rects: [ComposerBlock.ID: CGRect] = [:]

    /// Everything shown, trimmed to the board; nil when the board is empty.
    func content(in size: CGSize) -> CGRect? {
        let bounds = CGRect(origin: .zero, size: size)
        let shown = rects.values
            .map { $0.intersection(bounds) }
            .filter { !$0.isNull && $0.width > 1 && $0.height > 1 }
        guard let first = shown.first else { return nil }
        return shown.dropFirst().reduce(first) { $0.union($1) }
    }
}

/// A board as a visitor sees it: background, banner, and the pieces on the open tab.
struct MosaicBoardPreviewCanvas: View {
    let store: ComposerStore
    let documentID: ComposerDocumentID?
    let size: CGSize
    var frames: MosaicBoardPreviewFrames?

    private static let space = "explore.preview"

    @Environment(\.mosaicPrivacyDisplay) private var privacy
    @FocusState private var focus: ComposerBlockID?

    private var blocks: [ComposerBlock] { store.blocks(for: documentID) }

    /// Banners sit above the board; a tab bar shows only its open tab's pieces; hidden Pursuits are gone.
    private var pieces: [ComposerBlock] {
        let shownTab = blocks.first { $0.kind == .tabs }?.selectedTabID
        return blocks.filter { block in
            guard block.kind != .banner, block.kind != .unsupported, privacy.look(of: block) != .removed else { return false }
            guard let shownTab, block.kind != .tabs else { return true }
            return block.tabID == shownTab
        }
    }

    var body: some View {
        let layoutHeight = CGFloat(store.layoutHeight(for: documentID) ?? 900)
        let background = store.boardBackground(for: documentID)
        ZStack(alignment: .top) {
            ComposerBoardBackdrop(
                background: background,
                mediaURL: background?.mediaFileName.map { store.mediaURL(for: $0) },
                fallback: MosaicBrand.inkBlack
            )
            VStack(spacing: 0) {
                if let banner = blocks.first(where: { $0.kind == .banner }) {
                    ComposerBannerBlock(
                        block: .constant(banner),
                        mediaURL: banner.mediaFileName.map { store.mediaURL(for: $0) },
                        isSelected: false,
                        isEditing: false,
                        isViewing: true,
                        focusBlockID: $focus,
                        onSelect: {},
                        onBeginEditing: {},
                        onCommit: {},
                        onReplaceMedia: {},
                        onDelete: {}
                    )
                    .modifier(MosaicBoardPreviewMeasure(id: banner.id, frames: frames, space: Self.space))
                }
                ZStack(alignment: .topLeading) {
                    ForEach(pieces) { block in
                        ComposerCanvasBlockView(
                            documentID: documentID,
                            block: .constant(block),
                            isEditing: false,
                            isSelected: false,
                            isLifted: false,
                            isRelocating: false,
                            livePinchScale: 1,
                            focusBlockID: $focus,
                            mediaURL: block.mediaFileName.map { store.mediaURL(for: $0) },
                            pursuitImageURL: block.pursuitImageFileName.map { store.mediaURL(for: $0) },
                            isMediaPaused: true,
                            actions: .inert,
                            showsMediaMenu: false,
                            showsPursuitPencil: false,
                            allowsCarouselControl: false,
                            isViewing: true,
                            canvasSize: CGSize(width: size.width, height: layoutHeight),
                            pinsTabsToPageEdges: false
                        )
                        .modifier(MosaicBoardPreviewMeasure(id: block.id, frames: frames, space: Self.space))
                        .rotationEffect(.degrees(block.rotation))
                        .composerPieceLook(block)
                        .offset(x: CGFloat(block.position.x) * size.width, y: CGFloat(block.position.y) * layoutHeight)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
        .coordinateSpace(name: Self.space)
        .allowsHitTesting(false)
    }
}

/// Records a piece's frame on the preview, after its turn and position are applied.
private struct MosaicBoardPreviewMeasure: ViewModifier {
    let id: ComposerBlock.ID
    let frames: MosaicBoardPreviewFrames?
    let space: String

    func body(content: Content) -> some View {
        if let frames {
            content.onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(space))
            } action: { rect in
                frames.rects[id] = rect
            }
        } else {
            content
        }
    }
}

private extension ComposerBlockActions {
    /// A preview only shows pieces; nothing in it responds.
    static var inert: ComposerBlockActions {
        ComposerBlockActions(
            onCommit: {},
            onBeginEditing: {},
            onDelete: {},
            onMediaData: { _ in },
            onStyleChange: {},
            onStyleMenuChange: { _ in },
            onClaimFormatTap: {},
            onOpenMediaMenu: {},
            onCropMedia: {},
            onEditPursuit: {},
            onEditCarousel: {},
            onSelectTabs: {},
            onEditSocial: {},
            onPresentMedia: nil,
            onBodyTap: nil,
            onOpenSocial: nil,
            onOpenFolder: { _ in },
            onOpenScrapbook: { _ in },
            onOpenMemberMediaMenu: { _ in },
            onCropMemberMedia: { _ in },
            onEditMemberPursuit: { _ in },
            onEditMemberCarousel: { _ in },
            onEditMemberSocial: { _ in },
            onOpenMemberSocial: { _ in }
        )
    }
}

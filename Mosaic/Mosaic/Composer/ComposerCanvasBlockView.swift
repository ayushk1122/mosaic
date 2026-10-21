import SwiftUI

struct ComposerChromePlacement: Equatable {
    var x: CGFloat
    var cropBelow: Bool

    static let iconDiameter: CGFloat = 32
    static let gap: CGFloat = 4
    private static let screenMargin: CGFloat = 8

    static var leading: ComposerChromePlacement {
        ComposerChromePlacement(x: -(iconDiameter + gap), cropBelow: false)
    }

    /// Puts the menu icon against the item. `contentWidth` is the visible width when the layout frame is wider than the glyphs.
    static func resolve(
        itemFrame: CGRect,
        viewportWidth: CGFloat,
        contentWidth: CGFloat? = nil
    ) -> ComposerChromePlacement {
        guard viewportWidth > 1, itemFrame.width > 1 else { return .leading }
        let visibleWidth = min(max(contentWidth ?? itemFrame.width, 1), itemFrame.width)
        let leadingX = -(iconDiameter + gap)
        let trailingX = visibleWidth + gap
        let leadingFits = itemFrame.minX + leadingX >= screenMargin
        let trailingFits = itemFrame.minX + trailingX + iconDiameter <= viewportWidth - screenMargin
        let x: CGFloat
        if leadingFits {
            x = leadingX
        } else if trailingFits {
            x = trailingX
        } else if itemFrame.minX <= viewportWidth - itemFrame.maxX {
            x = min(max(screenMargin - itemFrame.minX, 0), max(visibleWidth - iconDiameter, 0))
        } else {
            x = max(visibleWidth - iconDiameter - gap, 0)
        }
        // Crop and Replace stack above the menu icon, which needs about 96 points of room.
        return ComposerChromePlacement(x: x, cropBelow: itemFrame.minY < 96)
    }

    /// Where a floating control goes around a piece, in the same coordinates as `item` and `visible`.
    /// It centers over the piece and slides inward at the sides; it sits above the piece, flips below
    /// when there's no room, and pins to the top of the visible area when neither fits. `anchorY`
    /// (the finger) replaces the piece's top and bottom for pieces taller than the screen.
    struct FloatingPlacement: Equatable {
        var origin: CGPoint
        var isBelow: Bool
    }

    static let floatingMargin: CGFloat = 8

    static func floating(
        size: CGSize,
        around item: CGRect,
        visible: CGRect,
        gap: CGFloat = 10,
        anchorY: CGFloat? = nil
    ) -> FloatingPlacement {
        let margin = floatingMargin
        let minX = visible.minX + margin
        let maxX = max(visible.maxX - margin - size.width, minX)
        let x = min(max(item.midX - size.width / 2, minX), maxX)

        let top = anchorY ?? item.minY
        let bottom = anchorY ?? item.maxY
        let minY = visible.minY + margin
        let maxY = max(visible.maxY - margin - size.height, minY)
        let above = top - gap - size.height
        if above >= minY, above <= maxY {
            return FloatingPlacement(origin: CGPoint(x: x, y: above), isBelow: false)
        }
        let below = bottom + gap
        if below >= minY, below <= maxY {
            return FloatingPlacement(origin: CGPoint(x: x, y: below), isBelow: true)
        }
        // A piece scrolled off screen keeps its control at the nearer edge, not the far one.
        if bottom < visible.minY {
            return FloatingPlacement(origin: CGPoint(x: x, y: minY), isBelow: false)
        }
        if top > visible.maxY {
            return FloatingPlacement(origin: CGPoint(x: x, y: maxY), isBelow: true)
        }
        // Squeezed, or the piece is taller than the screen: hold it against whichever edge has more
        // room, so it covers as little of the piece as it can.
        let roomAbove = top - gap - visible.minY
        let roomBelow = visible.maxY - (bottom + gap)
        return roomBelow > roomAbove
            ? FloatingPlacement(origin: CGPoint(x: x, y: maxY), isBelow: true)
            : FloatingPlacement(origin: CGPoint(x: x, y: minY), isBelow: false)
    }
}

private struct ComposerViewportWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct ComposerBlockLockedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside a locked piece: its own resize handles and pinches stay off.
    var composerBlockLocked: Bool {
        get { self[ComposerBlockLockedKey.self] }
        set { self[ComposerBlockLockedKey.self] = newValue }
    }
}

extension EnvironmentValues {
    var composerViewportWidth: CGFloat {
        get { self[ComposerViewportWidthKey.self] }
        set { self[ComposerViewportWidthKey.self] = newValue }
    }
}

/// A piece's opacity and drop shadow. Applied after the tilt, so the light always falls from above.
/// Every style uses the same two shadow layers with different values: switching between styles
/// changes numbers only, so the piece isn't rebuilt (no photo reload or video restart).
struct ComposerPieceLookModifier: ViewModifier {
    var opacity: Double
    var shadow: ComposerPieceShadow
    var color: ComposerShadowColor

    private struct Layer {
        var strength: Double
        var radius: CGFloat
        var drop: CGFloat
    }

    /// A tight shadow at the edge and a wider one further out. White needs more strength to read as a glow.
    private var layers: (near: Layer, far: Layer) {
        let boost = color == .white ? 1.5 : 1
        switch shadow {
        case .none:
            return (Layer(strength: 0, radius: 0, drop: 0), Layer(strength: 0, radius: 0, drop: 0))
        case .soft:
            return (Layer(strength: 0.32 * boost, radius: 6, drop: 3), Layer(strength: 0, radius: 0, drop: 0))
        case .lifted:
            return (Layer(strength: 0.22 * boost, radius: 3, drop: 2), Layer(strength: 0.3 * boost, radius: 18, drop: 12))
        }
    }

    func body(content: Content) -> some View {
        let tint: Color = color == .white ? .white : .black
        let (near, far) = layers
        content
            .shadow(color: tint.opacity(min(near.strength, 1)), radius: near.radius, x: 0, y: near.drop)
            .shadow(color: tint.opacity(min(far.strength, 1)), radius: far.radius, x: 0, y: far.drop)
            .opacity(opacity)
            .animation(.easeInOut(duration: 0.2), value: shadow)
            .animation(.easeInOut(duration: 0.2), value: color)
    }
}

extension View {
    func composerPieceLook(_ block: ComposerBlock) -> some View {
        modifier(ComposerPieceLookModifier(opacity: block.opacity, shadow: block.shadow, color: block.shadowColor))
    }
}

struct ComposerBlockActions {
    var onCommit: () -> Void
    var onBeginEditing: () -> Void
    var onDelete: () -> Void
    var onMediaData: (Data) -> Void
    var onStyleChange: () -> Void
    var onStyleMenuChange: (Bool) -> Void
    var onClaimFormatTap: () -> Void
    var onOpenMediaMenu: () -> Void
    var onCropMedia: () -> Void
    var onEditPursuit: () -> Void
    var onEditCarousel: () -> Void
    var onSelectTabs: () -> Void
    var onEditSocial: () -> Void
    var onPresentMedia: ((URL, ComposerMediaCrop?) -> Void)?
    var onBodyTap: (() -> Void)?
    var onOpenSocial: (() -> Void)?
    var onOpenFolder: (ComposerBlock) -> Void
    var onOpenScrapbook: (ComposerBlock) -> Void
    var onOpenMemberMediaMenu: (ComposerBlockID) -> Void
    var onCropMemberMedia: (ComposerBlockID) -> Void
    var onEditMemberPursuit: (ComposerBlockID) -> Void
    var onEditMemberCarousel: (ComposerBlockID) -> Void
    var onEditMemberSocial: (ComposerBlockID) -> Void
    var onOpenMemberSocial: (ComposerBlock) -> Void
    var onReplaceMedia: (() -> Void)? = nil
    var onReplaceMemberMedia: ((ComposerBlockID) -> Void)? = nil
    /// True for one frame when the board recognized a tap (not a drag-release).
    var opensContentEditor: Bool = false
    var onContentEditorPresented: () -> Void = {}
}

struct ComposerCanvasBlockView: View {
    @Environment(\.composerMediaVersions) private var mediaVersions

    let documentID: ComposerDocumentID?
    @Binding var block: ComposerBlock
    let isEditing: Bool
    let isSelected: Bool
    let isLifted: Bool
    let isRelocating: Bool
    var livePinchScale: CGFloat
    var focusBlockID: FocusState<ComposerBlockID?>.Binding
    let mediaURL: URL?
    let pursuitImageURL: URL?
    var isMediaPaused: Bool
    var actions: ComposerBlockActions
    var showsMediaMenu: Bool
    var showsPursuitPencil: Bool
    /// The selection handles sit on top of the widget, so the board draws the pencil above them.
    var pencilCoveredByChrome: Bool = false
    var allowsCarouselControl: Bool
    var isViewing: Bool
    var canvasSize: CGSize
    var cornerResizing: Binding<Bool> = .constant(false)
    var mediaMenuBlockID: ComposerBlockID? = nil
    var pinsTabsToPageEdges: Bool = true
    var isDrawing: Bool = false
    var drawingByteLimit: Int = ComposerDrawingMetrics.maximumBytes
    var onDrawingFullChange: (Bool) -> Void = { _ in }
    var inkSession: ComposerInkSession?

    @Environment(\.composerCoordinateSpace) private var composerSpace
    @Environment(MosaicVisit.self) private var visit: MosaicVisit?
    @Environment(\.mosaicPrivacyDisplay) private var privacyDisplay
    @State private var pursuitBackground: UIImage?
    @State private var pursuitPencilFrame: CGRect = .zero

    var body: some View {
        canvasContent
        .frame(
            maxWidth: block.isContent || block.kind == .text || block.kind == .heading || block.kind == .list || block.kind == .media || block.kind == .pursuit || block.kind == .node || block.kind == .carousel || block.kind == .calendar || block.kind == .graph || block.kind == .tabs || block.kind == .table || block.kind == .social || block.kind == .group || block.kind == .scrapbook || block.kind == .drawing || block.kind == .sticker ? nil : 280,
            alignment: .topLeading
        )
        .accessibilityIdentifier("composer.block.\(block.id.rawValue)")
        .modifier(NonTextInteractionModifier(
            handlesCanvasGestures: block.isContent || block.kind == .text || block.kind == .heading || block.kind == .list || block.kind == .media || block.kind == .pursuit || block.kind == .node || block.kind == .carousel || block.kind == .calendar || block.kind == .graph || block.kind == .tabs || block.kind == .table || block.kind == .social || block.kind == .group || block.kind == .scrapbook || block.kind == .drawing || block.kind == .sticker || block.kind == .unsupported,
            editsOnTap: block.kind != .pursuit && block.kind != .node && block.kind != .tabs && block.kind != .table && block.kind != .social && block.kind != .group && block.kind != .scrapbook,
            isViewing: isViewing,
            onTap: actions.onBeginEditing,
            onDelete: actions.onDelete
        ))
    }

    @ViewBuilder
    private var canvasContent: some View {
        switch block.kind {
            case .text, .heading:
                ComposerTextCanvasBlock(
                    block: $block,
                    isEditing: isEditing,
                    isSelected: isSelected,
                    isLifted: isLifted,
                    isRelocating: isRelocating,
                    livePinchScale: livePinchScale,
                    focusBlockID: focusBlockID,
                    onCommit: actions.onCommit,
                    onStyleChange: actions.onStyleChange,
                    onStyleMenuChange: actions.onStyleMenuChange,
                    onClaimFormatTap: actions.onClaimFormatTap,
                    isViewing: isViewing
                )
            case .list:
                ComposerListCanvasBlock(
                    block: $block,
                    isEditing: isEditing,
                    isSelected: isSelected,
                    isLifted: isLifted,
                    isRelocating: isRelocating,
                    livePinchScale: livePinchScale,
                    isViewing: isViewing,
                    onCommit: actions.onCommit,
                    onStyleChange: actions.onStyleChange,
                    onStyleMenuChange: actions.onStyleMenuChange,
                    onClaimFormatTap: actions.onClaimFormatTap
                )
            case .carousel:
                ComposerCarouselCanvasBlock(
                    block: $block,
                    scale: CGFloat(block.style.scale),
                    livePinchScale: livePinchScale,
                    isSelected: isSelected,
                    isLifted: isLifted,
                    isRelocating: isRelocating,
                    allowsDirectControl: allowsCarouselControl,
                    onEdit: actions.onEditCarousel,
                    onPresentMedia: actions.onPresentMedia
                )
            case .calendar:
                ComposerCalendarCanvasBlock(
                    block: $block,
                    scale: CGFloat(block.style.scale),
                    livePinchScale: livePinchScale,
                    isLifted: isLifted,
                    isRelocating: isRelocating,
                    isViewing: isViewing
                )
            case .graph:
                ComposerGraphCanvasBlock(
                    block: $block,
                    scale: CGFloat(block.style.scale),
                    livePinchScale: livePinchScale,
                    isLifted: isLifted,
                    isRelocating: isRelocating,
                    isViewing: isViewing
                )
            case .tabs:
                ComposerTabsCanvasBlock(
                    documentID: documentID,
                    block: $block,
                    livePinchScale: livePinchScale,
                    isSelected: isSelected,
                    isLifted: isLifted,
                    isRelocating: isRelocating,
                    isViewing: isViewing,
                    onActivate: actions.onSelectTabs,
                    pinsToPageEdges: pinsTabsToPageEdges
                )
            case .banner:
                EmptyView()
            case .table:
                ComposerTableCanvasBlock(
                    documentID: documentID,
                    block: $block,
                    livePinchScale: livePinchScale,
                    isSelected: isSelected,
                    isLifted: isLifted,
                    isRelocating: isRelocating,
                    isViewing: isViewing,
                    onActivate: actions.onSelectTabs
                )
            case .group:
                ComposerGroupCanvasBlock(
                    block: $block,
                    documentID: documentID,
                    livePinchScale: livePinchScale,
                    isSelected: isSelected,
                    isLifted: isLifted,
                    isViewing: isViewing,
                    canvasSize: canvasSize,
                    mediaMenuBlockID: mediaMenuBlockID,
                    onPresentMedia: actions.onPresentMedia,
                    onOpenFolder: actions.onOpenFolder,
                    onOpenMediaMenu: actions.onOpenMemberMediaMenu,
                    onCropMedia: actions.onCropMemberMedia,
                    onReplaceMedia: actions.onReplaceMemberMedia,
                    onEditPursuit: actions.onEditMemberPursuit,
                    onEditCarousel: actions.onEditMemberCarousel,
                    onEditSocial: actions.onEditMemberSocial,
                    onOpenSocial: actions.onOpenMemberSocial,
                    onOpenScrapbook: actions.onOpenScrapbook,
                    onStyleMenuChange: actions.onStyleMenuChange,
                    onClaimFormatTap: actions.onClaimFormatTap,
                    onActivate: actions.onSelectTabs
                )
            case .social:
                ComposerSocialCanvasBlock(
                    block: $block,
                    canvasSize: canvasSize,
                    livePinchScale: livePinchScale,
                    isSelected: isSelected,
                    isLifted: isLifted,
                    isRelocating: isRelocating,
                    isViewing: isViewing,
                    cornerResizing: cornerResizing,
                    onEdit: actions.onEditSocial,
                    onOpen: actions.onOpenSocial
                )
            case .media:
                ComposerMediaCanvasBlock(
                    block: $block,
                    mediaURL: mediaURL,
                    scale: CGFloat(block.style.scale),
                    livePinchScale: livePinchScale,
                    isSelected: isSelected,
                    isLifted: isLifted,
                    isRelocating: isRelocating,
                    isPaused: isMediaPaused,
                    showsMenu: showsMediaMenu,
                    onOpenMenu: actions.onOpenMediaMenu,
                    onCrop: actions.onCropMedia,
                    onBodyTap: actions.onBodyTap,
                    onReplace: actions.onReplaceMedia
                )
            case .scrapbook:
                ComposerScrapbookCover(
                    title: block.text,
                    scale: CGFloat(max(block.style.scale, 0.45)) * livePinchScale,
                    isSelected: isSelected && !isViewing
                )
            case .link:
                if block.isContent {
                    ComposerContentCard(
                        block: $block,
                        mediaURL: mediaURL,
                        isViewing: isViewing,
                        isSelected: isSelected && !isLifted && !isRelocating,
                        liveScale: livePinchScale,
                        opensEditor: actions.opensContentEditor,
                        onEditorPresented: actions.onContentEditorPresented,
                        onCrop: actions.onCropMedia,
                        onDelete: actions.onDelete
                    )
                } else {
                    linkEditor
                }
            case .node, .pursuit:
                pursuitView
            case .drawing:
                ComposerDrawingCanvasBlock(
                    block: $block,
                    livePinchScale: livePinchScale,
                    isSelected: isSelected,
                    isDrawing: isDrawing,
                    isViewing: isViewing,
                    byteLimit: drawingByteLimit,
                    onFullChange: onDrawingFullChange,
                    inkSession: inkSession
                )
            case .sticker:
                ComposerStickerCanvasBlock(block: block, mediaURL: mediaURL, livePinchScale: livePinchScale)
            case .unsupported:
                EmptyView()
        }
    }

    private var linkEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isEditing {
                TextField("Title", text: $block.text)
                    .font(.body.weight(.medium))
                TextField("https://", text: Binding(
                    get: { block.linkURL ?? "" },
                    set: { block.linkURL = $0 }
                ))
                .font(.caption)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            } else {
                Text(block.text.isEmpty ? "Link" : block.text)
                    .font(.body.weight(.medium))
                if let url = block.linkURL, !url.isEmpty {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(MosaicBrand.inkBlack)
    }

    private var pursuitView: some View {
        pursuitWidget
            .overlay(alignment: .topTrailing) {
                if let visit, block.kind == .pursuit,
                   let id = block.pursuitID.flatMap(ComposerBoardSync.uuid),
                   visit.access(id) != .open {
                    MosaicVisitLockBadge(access: visit.access(id))
                        .offset(x: 8, y: -8)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("visit.lock.\(id.uuidString.lowercased())")
                } else if privacyDisplay.look(of: block) == .locked {
                    MosaicVisitLockBadge(access: .locked)
                        .offset(x: 8, y: -8)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("mosaic.previewLock.\(block.id.rawValue)")
                } else if !isSelected, let level = privacyDisplay.badge(for: block) {
                    MosaicPrivacyBadge(level: level)
                        .offset(x: 8, y: -8)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("mosaic.privacyBadge.\(block.id.rawValue)")
                }
            }
            .opacity(privacyDisplay.look(of: block) == .removed ? 0 : 1)
            .allowsHitTesting(privacyDisplay.look(of: block) != .removed)
            .overlay(alignment: .bottomTrailing) {
                if showsPursuitPencil, !pencilCoveredByChrome, !isEditing, !isLifted, !isRelocating {
                    pursuitPencil
                        .padding(8)
                }
            }
            .onChange(of: isEditing) { _, editing in
                guard editing else { return }
                Task { @MainActor in
                    focusBlockID.wrappedValue = block.id
                }
            }
            .onAppear {
                guard isEditing else { return }
                Task { @MainActor in
                    focusBlockID.wrappedValue = block.id
                }
            }
            .task(id: ComposerMediaLoadKey(pursuitImageURL, versions: mediaVersions)) {
                guard let pursuitImageURL else {
                    pursuitBackground = nil
                    return
                }
                let loaded = await Task.detached(priority: .userInitiated) {
                    ComposerAnimatedImage.image(contentsOf: pursuitImageURL)
                }.value
                guard !Task.isCancelled else { return }
                pursuitBackground = loaded
            }
    }

    private var pursuitWidget: some View {
        let moving = isLifted || isRelocating
        let size = block.pursuitLayout.moduleSize(
            scale: CGFloat(block.style.scale) * livePinchScale,
            aspect: block.pursuitFrameAspect > 0.05 ? CGFloat(block.pursuitFrameAspect) : nil
        )
        return PursuitWidgetFace(
            text: $block.text,
            textX: block.pursuitTextX,
            textY: block.pursuitTextY,
            style: block.style,
            liveScale: livePinchScale,
            fill: block.pursuitFill,
            image: pursuitBackground,
            imageZoom: block.pursuitImageZoom,
            imagePanX: block.pursuitImagePanX,
            imagePanY: block.pursuitImagePanY,
            textItems: $block.pursuitTexts,
            showsField: isEditing,
            focusBlockID: focusBlockID,
            focusID: block.id,
            onSubmit: actions.onCommit,
            namePlaceholder: block.kind == .node ? "Node" : "Pursuit"
        )
        .frame(width: size.width, height: size.height)
        .shadow(color: .white.opacity(moving ? 0.95 : 0), radius: moving ? 2 : 0)
        .shadow(color: .white.opacity(moving ? 0.55 : 0), radius: moving ? 10 : 0)
        .contentShape(Rectangle())
        .accessibilityLabel(block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (block.kind == .node ? "Node" : "Pursuit") : block.text)
        .accessibilityIdentifier(block.pursuitID.map { block.kind == .node ? "composer.node.open.\($0.rawValue)" : "composer.pursuit.open.\($0.rawValue)" } ?? "composer.pursuit.open")
    }

    private var pursuitPencil: some View {
        Image(systemName: "pencil")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 26, height: 26)
            .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Circle())
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(composerSpace))
            } action: { frame in
                pursuitPencilFrame = frame
            }
            .preference(key: ComposerPencilFrameKey.self, value: [block.id: pursuitPencilFrame])
            .highPriorityGesture(TapGesture().onEnded { actions.onEditPursuit() })
            .accessibilityLabel(block.kind == .node ? "Edit Node" : "Edit Pursuit")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("composer.pursuit.edit.\(block.id.rawValue)")
    }
}

private struct NonTextInteractionModifier: ViewModifier {
    let handlesCanvasGestures: Bool
    let editsOnTap: Bool
    let isViewing: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        if handlesCanvasGestures || isViewing {
            content
        } else if editsOnTap {
            content
                .onTapGesture(perform: onTap)
                .contextMenu {
                    Button("Delete", role: .destructive, action: onDelete)
                }
        } else {
            content
                .contextMenu {
                    Button("Delete", role: .destructive, action: onDelete)
                }
        }
    }
}

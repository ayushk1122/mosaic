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
        return ComposerChromePlacement(x: x, cropBelow: itemFrame.minY < 56)
    }
}

private struct ComposerViewportWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var composerViewportWidth: CGFloat {
        get { self[ComposerViewportWidthKey.self] }
        set { self[ComposerViewportWidthKey.self] = newValue }
    }
}

struct ComposerCanvasBlockView: View {
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
    var onCommit: () -> Void
    var onBeginEditing: () -> Void
    var onDelete: () -> Void
    var onMediaData: (Data) -> Void
    var onStyleChange: () -> Void
    var onStyleMenuChange: (Bool) -> Void = { _ in }
    var showsMediaMenu: Bool
    var onOpenMediaMenu: () -> Void
    var onCropMedia: () -> Void
    var showsPursuitPencil: Bool
    var onEditPursuit: () -> Void
    var allowsCarouselControl: Bool
    var onEditCarousel: () -> Void
    var isViewing: Bool

    @State private var pursuitBackground: UIImage?
    @State private var pursuitPencilFrame: CGRect = .zero

    var body: some View {
        Group {
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
                    onCommit: onCommit,
                    onStyleChange: onStyleChange,
                    onStyleMenuChange: onStyleMenuChange
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
                    onCommit: onCommit,
                    onStyleChange: onStyleChange,
                    onStyleMenuChange: onStyleMenuChange
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
                    onEdit: onEditCarousel
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
                    onOpenMenu: onOpenMediaMenu,
                    onCrop: onCropMedia
                )
            case .link:
                linkEditor
            case .pursuit:
                pursuitView
            }
        }
        .frame(
            maxWidth: block.kind == .text || block.kind == .heading || block.kind == .list || block.kind == .media || block.kind == .pursuit || block.kind == .carousel || block.kind == .calendar || block.kind == .graph ? nil : 280,
            alignment: .topLeading
        )
        .accessibilityIdentifier("composer.block.\(block.id.rawValue)")
        .modifier(NonTextInteractionModifier(
            handlesCanvasGestures: block.kind == .text || block.kind == .heading || block.kind == .list || block.kind == .media || block.kind == .pursuit || block.kind == .carousel || block.kind == .calendar || block.kind == .graph,
            editsOnTap: block.kind != .pursuit,
            onTap: onBeginEditing,
            onDelete: onDelete
        ))
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
            .overlay(alignment: .bottomTrailing) {
                if showsPursuitPencil, !isEditing, !isLifted, !isRelocating {
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
            .task(id: pursuitImageURL) {
                guard let pursuitImageURL else {
                    pursuitBackground = nil
                    return
                }
                pursuitBackground = UIImage(contentsOfFile: pursuitImageURL.path)
            }
    }

    private var pursuitWidget: some View {
        let moving = isLifted || isRelocating
        let size = block.pursuitLayout.moduleSize(scale: CGFloat(block.style.scale) * livePinchScale)
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
            onSubmit: onCommit
        )
        .frame(width: size.width, height: size.height)
        .shadow(color: .white.opacity(moving ? 0.95 : 0), radius: moving ? 2 : 0)
        .shadow(color: .white.opacity(moving ? 0.55 : 0), radius: moving ? 10 : 0)
        .contentShape(Rectangle())
        .accessibilityLabel(block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Pursuit" : block.text)
        .accessibilityIdentifier(block.pursuitID.map { "composer.pursuit.open.\($0.rawValue)" } ?? "composer.pursuit.open")
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
                proxy.frame(in: .named("composerRoot"))
            } action: { frame in
                pursuitPencilFrame = frame
            }
            .preference(key: ComposerPencilFrameKey.self, value: [block.id: pursuitPencilFrame])
            .highPriorityGesture(TapGesture().onEnded { onEditPursuit() })
            .accessibilityLabel("Edit Pursuit")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("composer.pursuit.edit.\(block.id.rawValue)")
    }
}

private struct NonTextInteractionModifier: ViewModifier {
    let handlesCanvasGestures: Bool
    let editsOnTap: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        if handlesCanvasGestures {
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

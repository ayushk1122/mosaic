import SwiftUI

struct ComposerChromePlacement: Equatable {
    var x: CGFloat
    var cropBelow: Bool

    static let leading = ComposerChromePlacement(x: -40, cropBelow: false)

    static func resolve(itemFrame: CGRect, viewportWidth: CGFloat) -> ComposerChromePlacement {
        guard viewportWidth > 1, itemFrame.width > 1 else { return .leading }
        let reach: CGFloat = 46
        let leadingRoom = itemFrame.minX
        let trailingRoom = viewportWidth - itemFrame.maxX
        let useTrailing = leadingRoom < reach && trailingRoom >= leadingRoom
        let x: CGFloat
        if useTrailing {
            x = trailingRoom < reach ? max(4, itemFrame.width - 36) : itemFrame.width + 8
        } else if leadingRoom < reach {
            x = 4
        } else {
            x = -40
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
    var onPursuitImage: (Data) -> Void
    var onStyleChange: () -> Void
    var showsMediaMenu: Bool
    var onOpenMediaMenu: () -> Void
    var onCropMedia: () -> Void
    var showsPursuitPencil: Bool
    var onEditPursuit: () -> Void

    @State private var pursuitBackground: UIImage?
    @Environment(\.composerViewportWidth) private var viewportWidth

    private var pursuitIconPlacement: ComposerChromePlacement {
        ComposerChromePlacement.resolve(itemFrame: pursuitItemFrame, viewportWidth: viewportWidth)
    }

    @State private var pursuitItemFrame: CGRect = .zero
    @State private var pursuitIconFrame: CGRect = .zero
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
                    onStyleChange: onStyleChange
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
            maxWidth: block.kind == .text || block.kind == .heading || block.kind == .media || block.kind == .pursuit ? nil : 280,
            alignment: .topLeading
        )
        .accessibilityIdentifier("composer.block.\(block.id.rawValue)")
        .modifier(NonTextInteractionModifier(
            handlesCanvasGestures: block.kind == .text || block.kind == .heading || block.kind == .media || block.kind == .pursuit,
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
            .overlay(alignment: .topLeading) {
                if isSelected, !isEditing, !isLifted, !isRelocating {
                    pursuitIconStack
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showsPursuitPencil, !isEditing, !isLifted, !isRelocating {
                    pursuitPencil
                        .padding(8)
                }
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("composerRoot"))
            } action: { frame in
                pursuitItemFrame = frame
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

    private var pursuitPanelBelow: Bool {
        let top = pursuitIconFrame.height > 1 ? pursuitIconFrame.minY : pursuitItemFrame.minY
        return top < 36
    }

    private var pursuitStylePanel: some View {
        PursuitStylePanel(
            block: $block,
            onChange: onStyleChange,
            onPickImage: onPursuitImage
        )
        .fixedSize()
    }

    private var pursuitIconStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsMediaMenu, !pursuitPanelBelow {
                pursuitStylePanel
            }
            pursuitStyleIcon
            if showsMediaMenu, pursuitPanelBelow {
                pursuitStylePanel
            }
        }
        .offset(x: pursuitIconPlacement.x, y: -2)
    }

    private var pursuitStyleIcon: some View {
        Image(systemName: "square.grid.2x2")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 32, height: 32)
            .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Circle())
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("composerRoot"))
            } action: { frame in
                pursuitIconFrame = frame
            }
            .preference(
                key: ComposerChromeIconFrameKey.self,
                value: [block.id: pursuitIconFrame]
            )
            .highPriorityGesture(TapGesture().onEnded { onOpenMediaMenu() })
            .accessibilityLabel("Pursuit style")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("composer.pursuit.style.\(block.id.rawValue)")
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
        .contentShape(
            PursuitStyleHitShape(
                showsIcon: isSelected && !isEditing && !isLifted && !isRelocating,
                iconX: pursuitIconPlacement.x,
                showsPanel: showsMediaMenu,
                panelBelow: pursuitPanelBelow
            )
        )
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

private struct PursuitStyleHitShape: Shape {
    var showsIcon: Bool
    var iconX: CGFloat
    var showsPanel: Bool
    var panelBelow: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if showsIcon {
            path.addEllipse(in: CGRect(x: rect.minX + iconX - 6, y: rect.minY - 10, width: 44, height: 44))
        }
        if showsPanel {
            let height: CGFloat = 280
            path.addRect(
                CGRect(
                    x: rect.minX + iconX - 8,
                    y: panelBelow ? rect.minY + 28 : rect.minY - height,
                    width: 260,
                    height: height
                )
            )
        }
        return path
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

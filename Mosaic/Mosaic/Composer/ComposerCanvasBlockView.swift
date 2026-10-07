import SwiftUI

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
    var isMediaPaused: Bool
    var opensPursuitInParentStack: Bool
    var onCommit: () -> Void
    var onBeginEditing: () -> Void
    var onDelete: () -> Void
    var onMediaData: (Data) -> Void
    var onStyleChange: () -> Void
    var showsMediaMenu: Bool
    var onOpenMediaMenu: () -> Void

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
                    onOpenMenu: onOpenMediaMenu
                )
            case .link:
                linkEditor
            case .pursuit:
                pursuitView
            }
        }
        .frame(
            maxWidth: block.kind == .text || block.kind == .heading || block.kind == .media ? nil : 280,
            alignment: .topLeading
        )
        .accessibilityIdentifier("composer.block.\(block.id.rawValue)")
        .modifier(NonTextInteractionModifier(
            handlesCanvasGestures: block.kind == .text || block.kind == .heading || block.kind == .media,
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

    @ViewBuilder
    private var pursuitView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                TextField("Pursuit name", text: $block.text)
                    .font(.title3.weight(.semibold))
            } else {
                Text(block.text)
                    .font(.title3.weight(.semibold))
            }
            if opensPursuitInParentStack, let pursuitID = block.pursuitID {
                NavigationLink(value: pursuitID) {
                    Text("Open")
                        .font(.caption.weight(.medium))
                }
                .accessibilityIdentifier("composer.pursuit.open.\(pursuitID.rawValue)")
            }
        }
        .foregroundStyle(MosaicBrand.inkBlack)
    }
}

private struct NonTextInteractionModifier: ViewModifier {
    let handlesCanvasGestures: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        if handlesCanvasGestures {
            content
        } else {
            content
                .onTapGesture(perform: onTap)
                .contextMenu {
                    Button("Delete", role: .destructive, action: onDelete)
                }
        }
    }
}

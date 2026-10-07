import SwiftUI

struct ComposerTextCanvasBlock: View {
    @Binding var block: ComposerBlock
    let isEditing: Bool
    let isSelected: Bool
    let isRelocating: Bool
    var focusBlockID: FocusState<ComposerBlockID?>.Binding
    let onCommit: () -> Void
    let onStyleChange: () -> Void

    @State private var showsStyleDialog = false
    @State private var pinchBaseScale: CGFloat = 1
    @State private var livePinchScale: CGFloat = 1
    @State private var isPinching = false

    private var isHeading: Bool { block.kind == .heading }

    private var displayScale: CGFloat {
        let persisted = CGFloat(block.style.scale)
        return isPinching ? pinchBaseScale * livePinchScale : persisted
    }

    var body: some View {
        textContent
            .overlay(alignment: .topLeading) {
                if isSelected, !isRelocating {
                    formatIconButton
                        .offset(x: -40, y: -2)
                }
            }
            .scaleEffect(displayScale, anchor: .topLeading)
            .gesture(pinchGesture)
            .accessibilityIdentifier("composer.block.\(block.id.rawValue)")
        .onChange(of: isSelected) { _, selected in
            if !selected {
                showsStyleDialog = false
            }
        }
        .onChange(of: isEditing) { _, editing in
            guard editing else { return }
            showsStyleDialog = false
            Task { @MainActor in
                focusBlockID.wrappedValue = block.id
            }
        }
        .onAppear {
            pinchBaseScale = CGFloat(block.style.scale)
            guard isEditing else { return }
            Task { @MainActor in
                focusBlockID.wrappedValue = block.id
            }
        }
        .popover(isPresented: $showsStyleDialog, arrowEdge: .leading) {
            ComposerTextStylePanel(style: $block.style, onChange: onStyleChange)
                .padding(4)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var formatIconButton: some View {
        Button {
            showsStyleDialog = true
        } label: {
            Image(systemName: "textformat")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 32, height: 32)
                .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Text style")
        .accessibilityIdentifier("composer.text.style.\(block.id.rawValue)")
    }

    @ViewBuilder
    private var textContent: some View {
        if isEditing {
            textField
        } else {
            displayedText
        }
    }

    private var displayedText: some View {
        Text(block.text.isEmpty ? (isHeading ? "Heading" : "Text") : block.text)
            .font(block.style.size.font(isHeading: isHeading))
            .foregroundStyle(block.style.color.color.opacity(block.text.isEmpty ? 0.28 : 1))
            .multilineTextAlignment(block.style.alignment.alignment)
            .frame(minWidth: 28, maxWidth: 260, minHeight: 28, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
    }

    private var textField: some View {
        TextField(
            "",
            text: $block.text,
            prompt: Text(isHeading ? "Heading" : "Text")
                .foregroundStyle(block.style.color.color.opacity(0.28)),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(block.style.size.font(isHeading: isHeading))
        .foregroundStyle(block.style.color.color)
        .tint(block.style.color.color)
        .multilineTextAlignment(block.style.alignment.alignment)
        .focused(focusBlockID, equals: block.id)
        .submitLabel(.done)
        .onSubmit(onCommit)
        .disabled(isRelocating)
        .frame(minWidth: 28, maxWidth: 260, minHeight: 28, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard isSelected, !isEditing, !isRelocating else { return }
                isPinching = true
                livePinchScale = value
            }
            .onEnded { value in
                guard isSelected, !isEditing, !isRelocating else { return }
                var updated = block
                updated.style.scale = min(max(Double(pinchBaseScale * value), 0.6), 3.2)
                block = updated
                pinchBaseScale = CGFloat(block.style.scale)
                livePinchScale = 1
                isPinching = false
                onStyleChange()
            }
    }
}

struct ComposerTextStylePanel: View {
    @Binding var style: TextBlockStyle
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Text style")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 6) {
                ForEach(TextBlockSize.allCases, id: \.self) { size in
                    Button {
                        style.size = size
                        onChange()
                    } label: {
                        Text(size.shortLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(style.size == size ? MosaicBrand.inkBlack : .white.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                style.size == size ? MosaicBrand.cream : Color.white.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                ForEach(TextBlockColor.allCases, id: \.self) { color in
                    Button {
                        style.color = color
                        onChange()
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 18, height: 18)
                            .overlay {
                                if style.color == color {
                                    Circle().stroke(MosaicBrand.cream, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.label)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 200)
        .background(Color(red: 0.20, green: 0.21, blue: 0.23))
    }
}

private extension TextBlockSize {
    var shortLabel: String {
        switch self {
        case .body: "S"
        case .large: "M"
        case .title: "L"
        }
    }
}

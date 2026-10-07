import SwiftUI
import UIKit

struct ComposerTextCanvasBlock: View {
    @Binding var block: ComposerBlock
    let isEditing: Bool
    let isSelected: Bool
    let isLifted: Bool
    let isRelocating: Bool
    var livePinchScale: CGFloat
    var focusBlockID: FocusState<ComposerBlockID?>.Binding
    let onCommit: () -> Void
    let onStyleChange: () -> Void
    var showsFormatButton: Bool = true
    var onStyleMenuChange: (Bool) -> Void = { _ in }

    @State private var showsStyleDialog = false
    @State private var itemFrame: CGRect = .zero
    @State private var styleIconFrame: CGRect = .zero
    @State private var contentWidth: CGFloat = 0

    @Environment(\.composerViewportWidth) private var viewportWidth

    private var iconPlacement: ComposerChromePlacement {
        let visible = contentWidth > 1 ? contentWidth : nil
        return ComposerChromePlacement.resolve(
            itemFrame: itemFrame,
            viewportWidth: viewportWidth,
            contentWidth: visible
        )
    }

    private var isHeading: Bool { block.kind == .heading }

    private var showsMoveAffordance: Bool { isLifted || isRelocating }

    private var activeFont: Font {
        let size = block.style.fontSize * block.style.scale * Double(livePinchScale)
        if let family = block.style.fontFamilyName {
            return ComposerInstalledFont.font(family: family, size: size)
        }
        return block.style.fontChoice.font(size: size)
    }

    var body: some View {
        textContent
            .background(alignment: .topLeading) {
                Text(measuredLine)
                    .font(activeFont)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .allowsHitTesting(false)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { width in
                        guard abs(width - contentWidth) > 0.5 else { return }
                        contentWidth = width
                    }
            }
            .overlay(alignment: .topLeading) {
                if showsFormatButton, isSelected, !isRelocating, !isLifted {
                    formatIconStack
                        .offset(x: iconPlacement.x, y: -2)
                        .animation(.easeOut(duration: 0.16), value: iconPlacement.x)
                }
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("composerRoot"))
            } action: { frame in
                itemFrame = frame
            }
            .animation(.easeOut(duration: 0.16), value: showsMoveAffordance)
            .accessibilityIdentifier("composer.block.\(block.id.rawValue)")
        .onChange(of: isSelected) { _, selected in
            if !selected {
                showsStyleDialog = false
            }
        }
        .onChange(of: showsStyleDialog) { _, isOpen in
            onStyleMenuChange(isOpen)
        }
        .onChange(of: isEditing) { _, editing in
            guard editing else { return }
            showsStyleDialog = false
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
    }

    private var formatIconStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            formatIcon
            if showsStyleDialog {
                stylePanel
            }
        }
    }

    private var measuredLine: String {
        let raw = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return isHeading ? "Heading" : "Text"
        }
        return raw
    }

    private var stylePanel: some View {
        ComposerTextStylePanel(style: $block.style, onChange: onStyleChange)
            .fixedSize()
    }

    private var formatIcon: some View {
        Image(systemName: "textformat")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 32, height: 32)
            .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Circle())
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("composerRoot"))
            } action: { frame in
                styleIconFrame = frame
            }
            .preference(
                key: ComposerTextStyleIconFrameKey.self,
                value: [block.id: styleIconFrame]
            )
            .highPriorityGesture(TapGesture().onEnded {
                showsStyleDialog.toggle()
            })
            .accessibilityLabel("Text style")
            .accessibilityAddTraits(.isButton)
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
            .font(activeFont)
            .foregroundStyle(block.style.displayColor.opacity(block.text.isEmpty ? 0.28 : 1))
            .multilineTextAlignment(block.style.alignment.alignment)
            .shadow(color: .white.opacity(showsMoveAffordance ? 0.95 : 0), radius: showsMoveAffordance ? 2 : 0)
            .shadow(color: .white.opacity(showsMoveAffordance ? 0.55 : 0), radius: showsMoveAffordance ? 10 : 0)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 28, maxWidth: 260, minHeight: 28, alignment: .topLeading)
            .contentShape(Rectangle())
    }

    private var textField: some View {
        TextField(
            "",
            text: $block.text,
            prompt: Text(isHeading ? "Heading" : "Text")
                .foregroundStyle(block.style.displayColor.opacity(0.28)),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(activeFont)
        .foregroundStyle(block.style.displayColor)
        .tint(block.style.displayColor)
        .multilineTextAlignment(block.style.alignment.alignment)
        .focused(focusBlockID, equals: block.id)
        .submitLabel(.done)
        .onSubmit(onCommit)
        .disabled(isRelocating)
        .frame(minWidth: 28, maxWidth: 260, minHeight: 28, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

}

struct ComposerTextStylePanel: View {
    @Binding var style: TextBlockStyle
    var onChange: () -> Void
    var showsSize: Bool = false
    var onDelete: (() -> Void)? = nil
    var fillsBar: Bool = false

    @State private var showsFonts = false
    @State private var showsColor = false

    private let families = ComposerInstalledFont.familyNames

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        showsFonts.toggle()
                        if showsFonts { showsColor = false }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(style.fontLabel)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .rotationEffect(.degrees(showsFonts ? 180 : 0))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Font")

                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        showsColor.toggle()
                        if showsColor { showsFonts = false }
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(style.displayColor)
                        .frame(width: 28, height: 28)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color")

                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete text")
                }
            }

            if showsSize {
                HStack(spacing: 10) {
                    Text("Size")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Slider(value: $style.fontSize, in: 12...80, step: 1)
                        .tint(.white)
                        .onChange(of: style.fontSize) { _, _ in
                            onChange()
                        }
                    Text("\(Int(style.fontSize.rounded()))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 28, alignment: .trailing)
                }
            }

            if showsFonts {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(families, id: \.self) { family in
                            Button {
                                style.fontFamilyName = family
                                onChange()
                                withAnimation(.easeOut(duration: 0.16)) {
                                    showsFonts = false
                                }
                            } label: {
                                Text(family)
                                    .font(ComposerInstalledFont.font(family: family, size: 15))
                                    .foregroundStyle(.white.opacity(style.fontFamilyName == family ? 1 : 0.8))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 7)
                                    .background(
                                        style.fontFamilyName == family ? Color.white.opacity(0.08) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 180)
            }

            if showsColor {
                ComposerColorSquare(color: style.displayColor) { red, green, blue in
                    style.customColor = ComposerRGBColor(red: red, green: green, blue: blue)
                    onChange()
                }
                .frame(height: 140)
            }
        }
        .padding(fillsBar ? 0 : 12)
        .frame(maxWidth: fillsBar ? .infinity : 228, alignment: .leading)
        .frame(width: fillsBar ? nil : 228)
        .background(fillsBar ? Color.clear : Color(red: 0.20, green: 0.21, blue: 0.23))
    }
}

struct ComposerColorSquare: View {
    let color: Color
    var onPick: (Double, Double, Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                LinearGradient(
                    colors: [.white, .clear, .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .position(knobPosition(in: proxy.size))
                    .allowsHitTesting(false)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                        let y = min(max(value.location.y / max(proxy.size.height, 1), 0), 1)
                        let rgb = Self.rgb(hue: x, vertical: y)
                        onPick(rgb.0, rgb.1, rgb.2)
                    }
            )
        }
        .frame(height: 112)
        .accessibilityLabel("Color")
    }

    private func knobPosition(in size: CGSize) -> CGPoint {
        let uiColor = UIColor(color)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let y: CGFloat
        if brightness < 0.98 && saturation > 0.15 {
            y = (1 - brightness) * 0.5 + 0.5
        } else {
            y = saturation * 0.5
        }
        return CGPoint(x: hue * size.width, y: y * size.height)
    }

    /// Top of the square is white, the middle is the hue, and the bottom is black.
    private static func rgb(hue: Double, vertical: Double) -> (Double, Double, Double) {
        let saturation: CGFloat
        let brightness: CGFloat
        if vertical < 0.5 {
            saturation = CGFloat(vertical / 0.5)
            brightness = 1
        } else {
            saturation = 1
            brightness = CGFloat(1 - (vertical - 0.5) / 0.5)
        }
        let uiColor = UIColor(hue: CGFloat(hue), saturation: saturation, brightness: brightness, alpha: 1)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue))
    }
}

import PhotosUI
import SwiftUI

struct PursuitStylePanel: View {
    @Binding var block: ComposerBlock
    var onChange: () -> Void
    var onPickImage: (Data) -> Void

    @State private var showsShapes = false
    @State private var showsColor = false
    @State private var pickedImage: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                styleButton(accessibilityLabel: "Background color", isActive: showsColor) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        showsColor.toggle()
                        if showsColor { showsShapes = false }
                    }
                } label: {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                center: .center
                            )
                        )
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
                }

                if showsColor {
                    HStack(alignment: .center, spacing: 8) {
                        ComposerColorSquare(color: fillColor) { red, green, blue in
                            block.pursuitFill = ComposerRGBColor(red: red, green: green, blue: blue)
                            onChange()
                        }
                        .frame(width: 168, height: 96)

                        if block.pursuitFill != nil {
                            Button {
                                block.pursuitFill = nil
                                onChange()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear color")
                        }
                    }
                }
            }

            HStack(alignment: .center, spacing: 8) {
                styleButton(accessibilityLabel: "Shape", isActive: showsShapes) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        showsShapes.toggle()
                        if showsShapes { showsColor = false }
                    }
                } label: {
                    Image(systemName: "square.on.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }

                if showsShapes {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(PursuitWidgetShape.allCases, id: \.self) { shape in
                                Button {
                                    block.pursuitLayout = shape
                                    onChange()
                                } label: {
                                    PursuitShapeGlyph(layout: shape, isSelected: block.pursuitLayout == shape)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(shape.label)
                            }
                        }
                    }
                    .frame(width: 196)
                }
            }

            PhotosPicker(selection: $pickedImage, matching: .images) {
                styleIcon {
                    Image(systemName: "photo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Background image")
        }
        .onChange(of: pickedImage) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    onPickImage(data)
                }
                pickedImage = nil
            }
        }
    }

    private var fillColor: Color {
        guard let fill = block.pursuitFill else {
            return Color.white.opacity(0.22)
        }
        return Color(red: fill.red, green: fill.green, blue: fill.blue, opacity: fill.opacity)
    }

    private func styleButton<Icon: View>(
        accessibilityLabel: String,
        isActive: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Icon
    ) -> some View {
        Button(action: action) {
            styleIcon(isActive: isActive, label: label)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func styleIcon<Icon: View>(isActive: Bool = false, @ViewBuilder label: () -> Icon) -> some View {
        label()
            .frame(width: 32, height: 32)
            .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(isActive ? 0.7 : 0.12), lineWidth: 1))
    }
}

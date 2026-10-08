import SwiftUI

struct ComposerListCanvasBlock: View {
    @Binding var block: ComposerBlock
    let isEditing: Bool
    let isSelected: Bool
    let isLifted: Bool
    let isRelocating: Bool
    var livePinchScale: CGFloat
    var isViewing: Bool
    let onCommit: () -> Void
    let onStyleChange: () -> Void
    var onStyleMenuChange: (Bool) -> Void = { _ in }

    @FocusState private var focusedItemID: String?
    @State private var showsStyleDialog = false
    @State private var itemFrame: CGRect = .zero
    @State private var styleIconFrame: CGRect = .zero

    @Environment(\.composerViewportWidth) private var viewportWidth

    private var pointSize: CGFloat {
        CGFloat(block.style.fontSize * block.style.scale * Double(livePinchScale))
    }

    private var listWidth: CGFloat {
        min(520, max(168, pointSize * 12))
    }

    private var activeFont: Font {
        block.style.displayFont(at: Double(pointSize))
    }

    private var iconPlacement: ComposerChromePlacement {
        ComposerChromePlacement.resolve(
            itemFrame: itemFrame,
            viewportWidth: viewportWidth,
            contentWidth: listWidth
        )
    }

    private var showsMoveAffordance: Bool { isLifted || isRelocating }
    private var canEditRows: Bool { isEditing && !isViewing }

    var body: some View {
        rows
            .frame(width: listWidth, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if isSelected, !isViewing, !isRelocating, !isLifted {
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
            .onChange(of: isSelected) { _, selected in
                if !selected { showsStyleDialog = false }
            }
            .onChange(of: showsStyleDialog) { _, isOpen in
                onStyleMenuChange(isOpen)
            }
            .onChange(of: isEditing) { _, editing in
                guard !isViewing else { return }
                if editing {
                    if block.listItems.isEmpty {
                        block.listItems = [ComposerListItem()]
                    }
                    showsStyleDialog = false
                    focusedItemID = block.listItems.first?.id
                } else {
                    let kept = block.listItems.filter {
                        !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    block.listItems = kept.isEmpty ? [ComposerListItem()] : kept
                    focusedItemID = nil
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("List")
            .accessibilityIdentifier("composer.list.\(block.id.rawValue)")
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: max(4, pointSize * 0.28)) {
            ForEach(displayedItems) { item in
                row(item)
            }
        }
        .shadow(color: .white.opacity(showsMoveAffordance ? 0.95 : 0), radius: showsMoveAffordance ? 2 : 0)
        .shadow(color: .white.opacity(showsMoveAffordance ? 0.55 : 0), radius: showsMoveAffordance ? 10 : 0)
    }

    private var displayedItems: [ComposerListItem] {
        block.listItems.isEmpty ? [ComposerListItem(id: "placeholder", text: "")] : block.listItems
    }

    private func row(_ item: ComposerListItem) -> some View {
        let checked = block.listMarker == .checkbox && item.isChecked
        let isEmpty = item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker(for: item)
            if canEditRows, let index = block.listItems.firstIndex(where: { $0.id == item.id }) {
                TextField(
                    "",
                    text: $block.listItems[index].text,
                    prompt: Text("List").foregroundStyle(block.style.displayColor.opacity(0.28))
                )
                .textFieldStyle(.plain)
                .font(activeFont)
                .foregroundStyle(block.style.displayColor.opacity(checked ? 0.55 : 1))
                .tint(block.style.displayColor)
                .focused($focusedItemID, equals: item.id)
                .submitLabel(.next)
                .onSubmit { advance(from: item.id) }
                .disabled(isRelocating)
            } else {
                Text(isEmpty ? "List" : item.text)
                    .font(activeFont)
                    .underline(block.style.isUnderlined, color: block.style.displayColor)
                    .strikethrough(checked, color: block.style.displayColor.opacity(0.7))
                    .foregroundStyle(block.style.displayColor.opacity(isEmpty ? 0.28 : (checked ? 0.55 : 1)))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func marker(for item: ComposerListItem) -> some View {
        if block.listMarker == .checkbox {
            let symbol = item.isChecked ? "checkmark.square.fill" : "square"
            Image(systemName: symbol)
                .font(.system(size: max(15, pointSize * 0.9), weight: .regular))
                .foregroundStyle(block.style.displayColor.opacity(item.isChecked ? 1 : 0.85))
                .frame(width: max(22, pointSize), alignment: .center)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded {
                    guard !isViewing, !isLifted, !isRelocating else { return }
                    toggle(item.id)
                })
                .accessibilityLabel(item.isChecked ? "Checked" : "Unchecked")
                .accessibilityAddTraits(.isButton)
        } else if let index = block.listItems.firstIndex(where: { $0.id == item.id }) {
            Text(block.listMarker.marker(at: index))
                .font(activeFont)
                .foregroundStyle(block.style.displayColor.opacity(0.85))
                .frame(minWidth: max(16, pointSize), alignment: .trailing)
        }
    }

    private var formatIconStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            formatIcon
            if showsStyleDialog {
                ComposerTextStylePanel(
                    style: $block.style,
                    onChange: onStyleChange,
                    listMarker: $block.listMarker
                )
                .fixedSize()
            }
        }
    }

    private var formatIcon: some View {
        Image(systemName: "list.bullet")
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
            .preference(key: ComposerTextStyleIconFrameKey.self, value: [block.id: styleIconFrame])
            .highPriorityGesture(TapGesture().onEnded {
                showsStyleDialog.toggle()
            })
            .accessibilityLabel("List style")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("composer.list.style.\(block.id.rawValue)")
    }

    private func toggle(_ id: String) {
        guard let index = block.listItems.firstIndex(where: { $0.id == id }) else { return }
        block.listItems[index].isChecked.toggle()
    }

    private func advance(from id: String) {
        guard let index = block.listItems.firstIndex(where: { $0.id == id }) else { return }
        let text = block.listItems[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            if block.listItems.count > 1 {
                block.listItems.remove(at: index)
                let focusIndex = index > 0 ? index - 1 : 0
                focusedItemID = block.listItems[focusIndex].id
            } else {
                onCommit()
            }
            return
        }
        let next = ComposerListItem()
        block.listItems.insert(next, at: index + 1)
        focusedItemID = next.id
    }
}

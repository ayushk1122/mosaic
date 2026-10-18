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
    var onClaimFormatTap: () -> Void = {}

    @FocusState private var focusedItemID: String?
    @State private var showsStyleDialog = false
    @State private var itemFrame: CGRect = .zero
    @State private var styleIconFrame: CGRect = .zero
    @State private var unwrapped = CGSize(width: 96, height: 28)
    @State private var wrapped = CGSize(width: 96, height: 28)
    @State private var claimedFormatTap = false

    @Environment(\.composerViewportWidth) private var viewportWidth
    @Environment(\.composerCoordinateSpace) private var composerSpace
    @Environment(\.composerPaperPage) private var onPaper

    private var readingColor: Color {
        block.style.readingColor(onPaper: onPaper)
    }

    private var pointSize: CGFloat {
        CGFloat(block.style.fontSize * block.style.scale * Double(livePinchScale))
    }

    private var activeFont: Font {
        block.style.displayFont(at: Double(pointSize))
    }

    private var iconPlacement: ComposerChromePlacement {
        ComposerChromePlacement.resolve(
            itemFrame: itemFrame,
            viewportWidth: viewportWidth,
            contentWidth: fitted.width
        )
    }

    /// Longest line stays tight. A line wider than the page wraps inside the same bullet.
    private var rowMaxWidth: CGFloat {
        let room = viewportWidth - itemFrame.minX - 28
        if viewportWidth > 1, room > 96 { return room }
        return 280
    }

    private var fitted: CGSize {
        if unwrapped.width <= rowMaxWidth + 0.5 {
            return CGSize(width: max(unwrapped.width, 48), height: max(unwrapped.height, 20))
        }
        return CGSize(width: rowMaxWidth, height: max(wrapped.height, 20))
    }

    private var showsMoveAffordance: Bool { isLifted || isRelocating }
    private var canEditRows: Bool { isEditing && !isViewing }

    var body: some View {
        rows
            .background {
                ZStack(alignment: .topLeading) {
                    measuredRows(wrapping: false)
                        .fixedSize(horizontal: true, vertical: true)
                        .hidden()
                        .allowsHitTesting(false)
                        .onGeometryChange(for: CGSize.self) { proxy in
                            proxy.size
                        } action: { size in
                            let next = CGSize(width: max(size.width, 48), height: max(size.height, 20))
                            guard abs(next.width - unwrapped.width) > 0.5 || abs(next.height - unwrapped.height) > 0.5 else { return }
                            unwrapped = next
                        }
                    measuredRows(wrapping: true)
                        .frame(width: rowMaxWidth, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .allowsHitTesting(false)
                        .onGeometryChange(for: CGSize.self) { proxy in
                            proxy.size
                        } action: { size in
                            let next = CGSize(width: max(size.width, 48), height: max(size.height, 20))
                            guard abs(next.width - wrapped.width) > 0.5 || abs(next.height - wrapped.height) > 0.5 else { return }
                            wrapped = next
                        }
                }
            }
            .frame(width: fitted.width, height: fitted.height, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                if isSelected, !isViewing, !isRelocating, !isLifted {
                    formatIconStack
                        .offset(x: iconPlacement.x, y: -2)
                        .animation(.easeOut(duration: 0.16), value: iconPlacement.x)
                }
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(composerSpace))
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
                    focus(block.listItems.first?.id)
                } else {
                    let kept = block.listItems.filter {
                        !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    block.listItems = kept.isEmpty ? [ComposerListItem()] : kept
                    focusedItemID = nil
                }
            }
            .onAppear {
                guard isEditing, !isViewing else { return }
                focus(focusedItemID ?? block.listItems.first?.id)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("List")
            .accessibilityIdentifier("composer.list.\(block.id.rawValue)")
    }

    private func measuredRows(wrapping: Bool) -> some View {
        VStack(alignment: .leading, spacing: max(4, pointSize * 0.28)) {
            ForEach(displayedItems) { item in
                let isEmpty = item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(for: item)
                    Text(isEmpty ? "List" : item.text)
                        .font(activeFont)
                        .fixedSize(horizontal: !wrapping, vertical: true)
                        .frame(maxWidth: wrapping ? .infinity : nil, alignment: .leading)
                }
            }
        }
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
        if isViewing {
            // Viewers see only written rows, never the "List" placeholder of a blank bullet.
            return block.listItems.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        return block.listItems.isEmpty ? [ComposerListItem(id: "placeholder", text: "")] : block.listItems
    }

    /// Looks the row up by id on every read and write, so a row removed while its field is
    /// still focused can't read or write past the end of the list.
    private func textBinding(for id: String) -> Binding<String> {
        Binding(
            get: { block.listItems.first(where: { $0.id == id })?.text ?? "" },
            set: { text in
                guard let index = block.listItems.firstIndex(where: { $0.id == id }) else { return }
                block.listItems[index].text = text
            }
        )
    }

    private func row(_ item: ComposerListItem) -> some View {
        let checked = block.listMarker == .checkbox && item.isChecked
        let isEmpty = item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker(for: item)
            if canEditRows, block.listItems.contains(where: { $0.id == item.id }) {
                let text = textBinding(for: item.id)
                TextField(
                    "",
                    text: text,
                    prompt: Text("List").foregroundStyle(readingColor.opacity(0.28)),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(activeFont)
                .foregroundStyle(readingColor.opacity(checked ? 0.55 : 1))
                .tint(readingColor)
                .focused($focusedItemID, equals: item.id)
                .lineLimit(1...40)
                .onChange(of: text.wrappedValue) { _, _ in
                    continueRow(item.id)
                }
                .disabled(isRelocating)
            } else {
                Text(isEmpty ? "List" : item.text)
                    .font(activeFont)
                    .underline(block.style.isUnderlined, color: readingColor)
                    .strikethrough(checked, color: readingColor.opacity(0.7))
                    .foregroundStyle(readingColor.opacity(isEmpty ? 0.28 : (checked ? 0.55 : 1)))
                    .fixedSize(horizontal: false, vertical: true)
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
                .foregroundStyle(readingColor.opacity(item.isChecked ? 1 : 0.85))
                .frame(width: max(22, pointSize), alignment: .center)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded {
                    guard !isViewing, !isLifted, !isRelocating else { return }
                    toggle(item.id)
                })
                .accessibilityLabel(item.isChecked ? "Checked" : "Unchecked")
                .accessibilityAddTraits(.isButton)
        } else if let index = displayedItems.firstIndex(where: { $0.id == item.id }) {
            Text(block.listMarker.marker(at: index))
                .font(activeFont)
                .foregroundStyle(readingColor.opacity(0.85))
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
                proxy.frame(in: .named(composerSpace))
            } action: { frame in
                styleIconFrame = frame
            }
            .preference(key: ComposerTextStyleIconFrameKey.self, value: [block.id: styleIconFrame])
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !claimedFormatTap else { return }
                        claimedFormatTap = true
                        onClaimFormatTap()
                    }
                    .onEnded { value in
                        claimedFormatTap = false
                        guard hypot(value.translation.width, value.translation.height) < 12 else { return }
                        showsStyleDialog.toggle()
                    }
            )
            .accessibilityLabel("List style")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("composer.list.style.\(block.id.rawValue)")
    }

    private func toggle(_ id: String) {
        guard let index = block.listItems.firstIndex(where: { $0.id == id }) else { return }
        block.listItems[index].isChecked.toggle()
    }

    /// A return stays on this bullet. A return on the blank line that follows starts the next bullet.
    private func continueRow(_ id: String) {
        guard let index = block.listItems.firstIndex(where: { $0.id == id }) else { return }
        let text = block.listItems[index].text
        guard text.hasSuffix("\n") else { return }
        let withoutLast = String(text.dropLast())
        let startsNext = withoutLast.isEmpty || withoutLast.hasSuffix("\n")
        guard startsNext else { return }
        let kept = withoutLast.hasSuffix("\n") ? String(withoutLast.dropLast()) : withoutLast
        if kept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if block.listItems.count > 1 {
                block.listItems.remove(at: index)
                let focusIndex = index > 0 ? index - 1 : 0
                focus(block.listItems[focusIndex].id)
            } else {
                block.listItems[index].text = ""
                onCommit()
            }
            return
        }
        block.listItems[index].text = kept
        let next = ComposerListItem()
        block.listItems.insert(next, at: index + 1)
        focus(next.id)
    }

    private func focus(_ id: String?) {
        guard let id else { return }
        Task { @MainActor in
            focusedItemID = id
        }
    }
}

import SwiftUI
import UIKit

struct ComposerTableCanvasBlock: View {
    let documentID: ComposerDocumentID?
    @Binding var block: ComposerBlock
    var livePinchScale: CGFloat
    var isSelected: Bool
    var isLifted: Bool
    var isRelocating: Bool
    var isViewing: Bool
    var onActivate: () -> Void

    @Environment(ComposerStore.self) private var store
    @Environment(\.composerBlockLocked) private var isLocked
    @Environment(\.composerUpdateAddresses) private var updateAddresses
    @Environment(ComposerUpdateGuide.self) private var updateGuide: ComposerUpdateGuide?
    @FocusState private var focus: TableFocus?
    @State private var editing: TableFocus?
    @State private var pinchScale: CGFloat = 1

    private enum TableFocus: Hashable {
        case title
        case header(String)
        case cell(String, Int)
    }

    /// Chrome stays laid out while selected so a long-press drag does not jump size.
    private var showsChrome: Bool {
        isSelected && !isViewing
    }

    /// Interactive editing only while the table is idle (not lifted / relocating).
    private var showsEdits: Bool {
        showsChrome && !isLifted && !isRelocating
    }

    private var metric: CGFloat {
        CGFloat(min(max(block.style.scale, 0.45), 3.2)) * pinchScale
    }

    private var columns: [ComposerTableColumn] {
        block.tableColumns
    }

    private var canAddColumn: Bool {
        showsChrome && columns.count < ComposerTable.maximumColumns
    }

    private var canRemoveColumn: Bool {
        showsChrome && columns.count > ComposerTable.minimumColumns
    }

    private var canAddRow: Bool {
        showsChrome && block.tableRows.count < ComposerTable.maximumRows
    }

    private var canRemoveRow: Bool {
        showsChrome && block.tableRows.count > ComposerTable.minimumRows
    }

    private var pieceKey: String { block.id.rawValue.lowercased() }
    private var entriesPrefix: String { "\(pieceKey)/tableentries/" }

    private func address(of row: ComposerTableRow) -> String {
        "\(entriesPrefix)\(block.selectedTableEntryID?.lowercased() ?? "")/rows/\(row.id.lowercased())"
    }

    /// The entry an address is in, when it isn't the entry on screen.
    private func hiddenEntry(of address: String) -> ComposerTableEntry? {
        guard address.hasPrefix(entriesPrefix) else { return nil }
        let id = String(address.dropFirst(entriesPrefix.count).split(separator: "/").first ?? "")
        guard id != block.selectedTableEntryID?.lowercased() else { return nil }
        return block.tableEntries.first { $0.id.lowercased() == id }
    }

    /// Rows with updates in entries not on screen, which have a place in the navigator's order at the table.
    private var hiddenRows: [String: Int] {
        guard updateGuide != nil else { return [:] }
        var rows: [String: Int] = [:]
        for address in updateAddresses where hiddenEntry(of: address) != nil {
            let parts = address.split(separator: "/").prefix(5)
            guard parts.count == 5 else { continue }
            rows[parts.joined(separator: "/")] = 0
        }
        return rows
    }

    var body: some View {
        table
            .hiddenUpdateAnchors(hiddenRows)
            // Orbit's navigator: a row in another entry is shown by turning to that entry.
            .revealHost("table:\(pieceKey)", claim: { address in
                hiddenEntry(of: address) == nil ? nil : pieceKey.count + 1
            }, reveal: { address in
                if let entry = hiddenEntry(of: address) { show(entry) }
            })
    }

    @ViewBuilder
    private var table: some View {
        let _ = livePinchScale
        VStack(alignment: .leading, spacing: 8 * metric) {
            titleView
            entryBar
            HStack(alignment: .top, spacing: 8 * metric) {
                grid
                if canAddColumn || canRemoveColumn {
                    VStack(spacing: 6 * metric) {
                        if canAddColumn {
                            control("plus", label: "Add column") {
                                store.addTableColumn(to: block.id, in: documentID)
                            }
                        }
                        if canRemoveColumn {
                            control("minus", label: "Remove last column") {
                                store.removeLastTableColumn(from: block.id, in: documentID)
                            }
                        }
                    }
                    .padding(.top, 6 * metric)
                    .opacity(showsEdits ? 1 : 0)
                    .allowsHitTesting(showsEdits)
                }
            }
            if canAddRow || canRemoveRow {
                HStack(spacing: 6 * metric) {
                    if canAddRow {
                        control("plus", label: "Add row") {
                            store.addTableRow(to: block.id, in: documentID)
                        }
                    }
                    if canRemoveRow {
                        control("minus", label: "Remove last row") {
                            store.removeLastTableRow(from: block.id, in: documentID)
                        }
                    }
                }
                .opacity(showsEdits ? 1 : 0)
                .allowsHitTesting(showsEdits)
            }
        }
        // Light inset so the size box hugs the table with a little breathing room.
        // Tied to selection (not lift) so press-and-drag does not shrink the box.
        .padding(showsChrome ? 10 * metric : 0)
        .fixedSize(horizontal: true, vertical: true)
        .overlay {
            TablePinchCatcher(isEnabled: !isViewing && !isLifted && !isRelocating && !isLocked) { scale in
                pinchScale = min(max(scale, 0.35), 4)
            } onEnded: { scale in
                onActivate()
                block.style.scale = min(max(block.style.scale * Double(scale), 0.45), 3.2)
                pinchScale = 1
            }
        }
        .shadow(color: .white.opacity(isLifted || isRelocating ? 0.28 : 0), radius: isLifted || isRelocating ? 8 : 0)
        .onChange(of: isSelected) { _, selected in
            if !selected {
                editing = nil
                focus = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("composer.table.\(block.id.rawValue)")
    }

    @ViewBuilder
    private var titleView: some View {
        let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if editing == .title, showsEdits {
            TextField("Add title", text: titleBinding)
                .font(.system(size: 17 * metric, weight: .semibold))
                .foregroundStyle(.white)
                .focused($focus, equals: .title)
                .submitLabel(.done)
                .onSubmit {
                    editing = nil
                    focus = nil
                }
                .onAppear {
                    DispatchQueue.main.async {
                        focus = .title
                    }
                }
        } else if !trimmed.isEmpty || showsChrome {
            Text(trimmed.isEmpty ? "Add title" : trimmed)
                .font(.system(size: 17 * metric, weight: .semibold))
                .foregroundStyle(.white.opacity(trimmed.isEmpty ? 0.45 : 0.92))
                .lineLimit(2)
                .frame(minHeight: 28 * metric, alignment: .leading)
                .contentShape(Rectangle())
                // Simultaneous with the board drag: short taps edit, long-press still moves.
                .simultaneousGesture(TapGesture().onEnded { begin(.title) })
                .allowsHitTesting(showsEdits)
                .accessibilityLabel(trimmed.isEmpty ? "Add title" : trimmed)
                .accessibilityAddTraits(.isButton)
        }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                    headerCell(column, isLast: index == columns.count - 1)
                }
            }
            .background(Color.white.opacity(0.08))
            ForEach(Array(block.tableRows.enumerated()), id: \.element.id) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.element.id) { columnIndex, column in
                        bodyCell(row, columnIndex: columnIndex, isLast: columnIndex == columns.count - 1)
                    }
                }
                .background(rowIndex.isMultiple(of: 2) ? Color.white.opacity(0.03) : Color.clear)
                .updateAnchor(address(of: row), order: rowIndex)
            }
        }
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14 * metric, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14 * metric, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14 * metric, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func headerCell(_ column: ComposerTableColumn, isLast: Bool) -> some View {
        let target = TableFocus.header(column.id)
        return ZStack {
            if editing == target, showsEdits {
                TextField("Header", text: headerBinding(column.id))
                    .font(.system(size: 13 * metric, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .focused($focus, equals: target)
                    .submitLabel(.done)
                    .onSubmit { editing = nil }
                    .onAppear { focus = target }
            } else {
                Text(column.header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Header" : column.header)
                    .font(.system(size: 13 * metric, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10 * metric)
        .frame(width: 108 * metric, height: 36 * metric, alignment: .leading)
        .overlay(alignment: .trailing) {
            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { begin(target) })
        .accessibilityLabel(column.header.isEmpty ? "Header" : column.header)
    }

    private func bodyCell(_ row: ComposerTableRow, columnIndex: Int, isLast: Bool) -> some View {
        let target = TableFocus.cell(row.id, columnIndex)
        let value = cellValue(row, columnIndex: columnIndex)
        return ZStack {
            if editing == target, showsEdits {
                TextField("Label", text: cellBinding(row.id, columnIndex: columnIndex))
                    .font(.system(size: 13 * metric, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))
                    .focused($focus, equals: target)
                    .submitLabel(.done)
                    .onSubmit { editing = nil }
                    .onAppear { focus = target }
            } else {
                Text(value.isEmpty ? (showsEdits ? "Label" : " ") : value)
                    .font(.system(size: 13 * metric, weight: .regular))
                    .foregroundStyle(.white.opacity(value.isEmpty ? 0.35 : 0.78))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10 * metric)
        .frame(width: 108 * metric, height: 34 * metric, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
        .overlay(alignment: .trailing) {
            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { begin(target) })
    }

    private func control(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12 * metric, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 28 * metric, height: 28 * metric)
            .background(Color.white.opacity(0.14), in: Circle())
            .padding(4 * metric)
            .contentShape(Circle())
            .simultaneousGesture(TapGesture().onEnded {
                editing = nil
                focus = nil
                action()
            })
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private func begin(_ target: TableFocus) {
        guard !isViewing else { return }
        onActivate()
        guard showsEdits else { return }
        editing = target
        DispatchQueue.main.async {
            focus = target
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { block.text },
            set: { block.text = $0 }
        )
    }

    private func headerBinding(_ columnID: String) -> Binding<String> {
        Binding(
            get: { block.tableColumns.first(where: { $0.id == columnID })?.header ?? "" },
            set: { newValue in
                guard let index = block.tableColumns.firstIndex(where: { $0.id == columnID }) else { return }
                block.tableColumns[index].header = newValue
            }
        )
    }

    private func cellValue(_ row: ComposerTableRow, columnIndex: Int) -> String {
        guard row.cells.indices.contains(columnIndex) else { return "" }
        return row.cells[columnIndex].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cellBinding(_ rowID: String, columnIndex: Int) -> Binding<String> {
        Binding(
            get: {
                guard let row = block.tableRows.first(where: { $0.id == rowID }),
                      row.cells.indices.contains(columnIndex) else { return "" }
                return row.cells[columnIndex]
            },
            set: { newValue in
                guard let index = block.tableRows.firstIndex(where: { $0.id == rowID }) else { return }
                while block.tableRows[index].cells.count <= columnIndex {
                    block.tableRows[index].cells.append("")
                }
                block.tableRows[index].cells[columnIndex] = newValue
                rememberVisibleRows()
            }
        )
    }

    private var orderedEntries: [ComposerTableEntry] {
        ComposerTable.ordered(block.tableEntries)
    }

    /// Viewers browse through the binding, which keeps it on screen only; the owner's
    /// edit-mode browse goes through the store so the current entry's cells are kept.
    private func show(_ entry: ComposerTableEntry) {
        if isViewing {
            block.selectedTableEntryID = entry.id
            block.tableRows = entry.rows
        } else {
            store.showTableEntry(entry.id, on: block.id, in: documentID)
        }
    }

    private var entryBar: some View {
        let entries = orderedEntries
        let index = entries.firstIndex(where: { $0.id == block.selectedTableEntryID }) ?? max(entries.count - 1, 0)
        let current = entries.indices.contains(index) ? entries[index] : nil
        let canBrowse = showsEdits || isViewing
        return HStack(spacing: 8 * metric) {
            if canBrowse {
                entryControl("chevron.left", label: "Previous entry", enabled: index > 0) {
                    guard index > 0 else { return }
                    show(entries[index - 1])
                }
            }
            Text(current.map { ComposerTable.stampLabel(for: $0.stampedAt, among: entries) } ?? "")
                .font(.system(size: 12 * metric, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
            if canBrowse {
                entryControl("chevron.right", label: "Next entry", enabled: index + 1 < entries.count) {
                    guard index + 1 < entries.count else { return }
                    show(entries[index + 1])
                }
            }
            if showsEdits {
                Text("New entry")
                    .font(.system(size: 12 * metric, weight: .semibold))
                    .foregroundStyle(.white.opacity(entries.count >= ComposerTable.maximumEntries ? 0.28 : 0.92))
                    .padding(.horizontal, 10 * metric)
                    .padding(.vertical, 6 * metric)
                    .background(Color.white.opacity(0.14), in: Capsule())
                    .contentShape(Capsule())
                    .simultaneousGesture(TapGesture().onEnded {
                        guard entries.count < ComposerTable.maximumEntries else { return }
                        editing = nil
                        store.startTableEntry(on: block.id, in: documentID)
                    })
                    .accessibilityLabel("New entry")
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func entryControl(_ systemName: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12 * metric, weight: .bold))
            .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.28))
            .frame(width: 28 * metric, height: 28 * metric)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                guard enabled else { return }
                editing = nil
                action()
            })
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private func rememberVisibleRows() {
        guard let index = block.tableEntries.firstIndex(where: { $0.id == block.selectedTableEntryID }) else { return }
        block.tableEntries[index].rows = block.tableRows
    }
}

/// A pinch recognizer on the page scroll view that only accepts fingers on this table.
/// The scroll view’s own pinch stays disabled, so the page cannot zoom.
private struct TablePinchCatcher: UIViewRepresentable {
    static let recognizerName = "mosaic.table.pinch"

    var isEnabled: Bool
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> TablePinchCatcherView {
        let view = TablePinchCatcherView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: TablePinchCatcherView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        uiView.install()
    }

    static func dismantleUIView(_ uiView: TablePinchCatcherView, coordinator: Coordinator) {
        coordinator.detach()
        uiView.coordinator = nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = true
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat) -> Void = { _ in }
        weak var pinch: UIPinchGestureRecognizer?
        weak var tableView: UIView?
        private var tracking = false

        func detach() {
            if let pinch {
                pinch.view?.removeGestureRecognizer(pinch)
            }
            self.pinch = nil
            tableView = nil
            tracking = false
        }

        @objc func pinched(_ recognizer: UIPinchGestureRecognizer) {
            guard isEnabled, let table = tableView else { return }
            if let scrollView = recognizer.view as? UIScrollView {
                TablePinchCatcherView.lockPageZoom(scrollView)
            }
            let inside = table.bounds.insetBy(dx: -16, dy: -16).contains(recognizer.location(in: table))
            switch recognizer.state {
            case .began:
                tracking = inside
                if tracking { onChanged(recognizer.scale) }
            case .changed:
                guard tracking else { return }
                onChanged(recognizer.scale)
            case .ended, .cancelled, .failed:
                if tracking { onEnded(recognizer.scale) }
                tracking = false
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let table = tableView else { return false }
            return table.bounds.insetBy(dx: -16, dy: -16).contains(touch.location(in: table))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer.name != nil || !(otherGestureRecognizer is UIPinchGestureRecognizer)
        }
    }
}

private final class TablePinchCatcherView: UIView {
    weak var coordinator: TablePinchCatcher.Coordinator?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        install()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        install()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        install()
    }

    func install() {
        guard let coordinator, let scrollView = enclosingScrollView() else { return }
        coordinator.tableView = self
        if coordinator.pinch?.view !== scrollView {
            if let existing = coordinator.pinch {
                existing.view?.removeGestureRecognizer(existing)
            }
            let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(TablePinchCatcher.Coordinator.pinched))
            pinch.delegate = coordinator
            pinch.cancelsTouchesInView = false
            pinch.name = TablePinchCatcher.recognizerName
            scrollView.addGestureRecognizer(pinch)
            coordinator.pinch = pinch
        }
        Self.lockPageZoom(scrollView)
    }

    private func enclosingScrollView() -> UIScrollView? {
        var current: UIView? = self
        while let view = current {
            if let scrollView = view as? UIScrollView { return scrollView }
            current = view.superview
        }
        return nil
    }

    static func lockPageZoom(_ scrollView: UIScrollView) {
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1
        scrollView.bouncesZoom = false
        if let systemPinch = scrollView.pinchGestureRecognizer, systemPinch.name != TablePinchCatcher.recognizerName {
            systemPinch.isEnabled = false
        }
        if scrollView.zoomScale != 1 {
            scrollView.setZoomScale(1, animated: false)
        }
    }
}

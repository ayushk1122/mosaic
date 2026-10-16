import SwiftUI

struct ComposerTabsCanvasBlock: View {
    let documentID: ComposerDocumentID?
    @Binding var block: ComposerBlock
    var livePinchScale: CGFloat
    var isSelected: Bool
    var isLifted: Bool
    var isRelocating: Bool
    var isViewing: Bool
    var onActivate: () -> Void
    var pinsToPageEdges: Bool = true

    @Environment(ComposerStore.self) private var store
    @Environment(\.composerViewportWidth) private var viewportWidth
    @Environment(\.composerCoordinateSpace) private var composerSpace
    @FocusState private var titleFocus: String?
    @State private var renamingID: String?
    @State private var chipsFrame: CGRect = .zero

    private var showsEdits: Bool {
        isSelected && !isViewing
    }

    private var maximumCount: Int {
        ComposerTabSet.maximumCount(longestSide: ComposerTabSet.longestScreenSide())
    }

    private var metric: CGFloat {
        CGFloat(min(max(block.style.scale, 0.45), 3.2)) * livePinchScale
    }

    private var placeControlsAbove: Bool {
        guard showsEdits else { return false }
        return ComposerTabEdge.controlsBelongAbove(
            chipsMaxX: chipsFrame.maxX,
            buttonWidth: 28 * metric,
            gap: 8 * metric,
            viewportWidth: viewportWidth
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8 * metric) {
            chips
            if showsColumn, !placeControlsAbove {
                VStack(spacing: 6 * metric) {
                    if canAdd { addButton }
                    if canRemove { removeButton }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if placeControlsAbove {
                HStack(spacing: 6 * metric) {
                    if canAdd { addButton }
                    if canRemove { removeButton }
                }
                .offset(y: -(34 * metric))
            }
        }
        // Room between the tabs and the size box so the corner grabs stay clear of them.
        .padding(showsEdits ? 10 * metric : 0)
        .fixedSize(horizontal: true, vertical: true)
        .shadow(color: .white.opacity(isLifted || isRelocating ? 0.28 : 0), radius: isLifted || isRelocating ? 8 : 0)
        .animation(.snappy(duration: 0.22), value: block.selectedTabID)
        .animation(.snappy(duration: 0.22), value: showsEdits)
        .onChange(of: isSelected) { _, selected in
            if !selected {
                renamingID = nil
                titleFocus = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("composer.tabs.\(block.id.rawValue)")
    }

    private var showsColumn: Bool { canAdd || canRemove }

    private var chips: some View {
        HStack(spacing: 2 * metric) {
            ForEach(block.tabs) { tab in
                tabChip(tab)
            }
        }
        .padding(.vertical, 2 * metric)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(composerSpace))
        } action: { frame in
            chipsFrame = frame
            pullInsideBorders(frame)
        }
    }

    private func pullInsideBorders(_ frame: CGRect) {
        guard pinsToPageEdges, !isLifted, !isRelocating else { return }
        let target = ComposerTabEdge.leadingEdge(
            currentMinX: frame.minX,
            width: frame.width,
            viewportWidth: viewportWidth
        )
        let delta = target - frame.minX
        guard abs(delta) > 1, viewportWidth > 1 else { return }
        block.position.x += Double(delta / viewportWidth)
    }

    private func tabChip(_ tab: ComposerTab) -> some View {
        let selected = block.selectedTabID == tab.id
        let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ZStack {
            if renamingID == tab.id, showsEdits {
                TextField("Title", text: titleBinding(for: tab.id))
                    .font(.system(size: 13 * metric, weight: .medium))
                    .foregroundStyle(Color.black)
                    .multilineTextAlignment(.center)
                    .focused($titleFocus, equals: tab.id)
                    .submitLabel(.done)
                    .onSubmit {
                        renamingID = nil
                        titleFocus = nil
                    }
                    .onAppear {
                        DispatchQueue.main.async { titleFocus = tab.id }
                    }
                    .frame(minWidth: 44 * metric)
            } else {
                Text(title.isEmpty ? "Title" : title)
                    .font(.system(size: 13 * metric, weight: .medium))
                    .foregroundStyle(selected ? Color.black.opacity(0.88) : Color.white.opacity(0.52))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12 * metric)
        .padding(.vertical, 7 * metric)
        .background(selected ? Color.white.opacity(0.92) : Color.clear, in: Capsule())
        .contentShape(Capsule())
        .simultaneousGesture(TapGesture().onEnded {
            choose(tab)
        })
        .accessibilityLabel(title.isEmpty ? "Title" : title)
        .accessibilityAddTraits(renamingID == tab.id ? [] : (selected ? [.isButton, .isSelected] : .isButton))
    }

    private func choose(_ tab: ComposerTab) {
        let alreadyOpen = block.selectedTabID == tab.id
        if showsEdits, alreadyOpen {
            renamingID = tab.id
            // The field only exists after this update, so focus it on the next turn.
            DispatchQueue.main.async { titleFocus = tab.id }
        } else {
            renamingID = nil
            block.selectedTabID = tab.id
        }
        if !isViewing {
            onActivate()
        }
    }

    private var canAdd: Bool {
        showsEdits && block.tabs.count < maximumCount
    }

    private var canRemove: Bool {
        showsEdits && block.tabs.count > ComposerTabSet.minimumCount
    }

    private var addButton: some View {
        Image(systemName: "plus")
            .font(.system(size: 12 * metric, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 28 * metric, height: 28 * metric)
            .background(Color.white.opacity(0.14), in: Circle())
            .contentShape(Circle())
            .simultaneousGesture(TapGesture().onEnded {
                renamingID = nil
                store.addComposerTab(to: block.id, in: documentID, longestSide: ComposerTabSet.longestScreenSide())
            })
            .accessibilityLabel("Add tab")
            .accessibilityAddTraits(.isButton)
    }

    private var removeButton: some View {
        Image(systemName: "minus")
            .font(.system(size: 12 * metric, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 28 * metric, height: 28 * metric)
            .background(Color.white.opacity(0.14), in: Circle())
            .contentShape(Circle())
            .simultaneousGesture(TapGesture().onEnded {
                guard let last = block.tabs.last else { return }
                renamingID = nil
                store.removeComposerTab(last.id, from: block.id, in: documentID)
            })
            .accessibilityLabel("Remove last tab")
            .accessibilityAddTraits(.isButton)
    }

    private func titleBinding(for tabID: String) -> Binding<String> {
        Binding(
            get: { block.tabs.first(where: { $0.id == tabID })?.title ?? "" },
            set: { newValue in
                guard let index = block.tabs.firstIndex(where: { $0.id == tabID }) else { return }
                block.tabs[index].title = newValue
            }
        )
    }
}

enum ComposerTabEdge {
    static let margin: CGFloat = 12
    /// How close a held component may sit to the side of the board.
    static let dragMargin: CGFloat = 4

    static func controlsBelongAbove(
        chipsMaxX: CGFloat,
        buttonWidth: CGFloat,
        gap: CGFloat,
        viewportWidth: CGFloat
    ) -> Bool {
        guard viewportWidth > 1, chipsMaxX > 1 else { return false }
        return chipsMaxX + gap + buttonWidth > viewportWidth - margin
    }

    static func leadingEdge(currentMinX: CGFloat, width: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        guard viewportWidth > 1, width > 1 else { return currentMinX }
        var minX = currentMinX
        let maxX = currentMinX + width
        let right = viewportWidth - margin
        if maxX > right {
            minX -= maxX - right
        }
        if minX < margin {
            minX = margin
        }
        return minX
    }

    /// Keeps a held block inside the side edges. Pass a page height to lock the top and bottom too.
    static func clampedDrag(
        translation: CGSize,
        frameMinX: CGFloat,
        frameWidth: CGFloat,
        viewportWidth: CGFloat,
        frameMinY: CGFloat = 0,
        frameHeight: CGFloat = 0,
        viewportHeight: CGFloat = 0
    ) -> CGSize {
        guard viewportWidth > 1, frameWidth > 1 else { return translation }
        let available = viewportWidth - dragMargin * 2
        let dx: CGFloat
        if frameWidth >= available {
            dx = dragMargin - frameMinX
        } else {
            let minDx = dragMargin - frameMinX
            let maxDx = viewportWidth - dragMargin - (frameMinX + frameWidth)
            dx = min(max(translation.width, minDx), maxDx)
        }
        guard viewportHeight > 1, frameHeight > 1 else {
            return CGSize(width: dx, height: translation.height)
        }
        let availableY = viewportHeight - dragMargin * 2
        let dy: CGFloat
        if frameHeight >= availableY {
            dy = dragMargin - frameMinY
        } else {
            let minDy = dragMargin - frameMinY
            let maxDy = viewportHeight - dragMargin - (frameMinY + frameHeight)
            dy = min(max(translation.height, minDy), maxDy)
        }
        return CGSize(width: dx, height: dy)
    }

    /// Shifts an origin so a placed frame sits fully inside the page.
    static func clampedOrigin(
        _ origin: CGPoint,
        size: CGSize,
        viewportWidth: CGFloat,
        viewportHeight: CGFloat
    ) -> CGPoint {
        guard viewportWidth > 1, viewportHeight > 1 else { return origin }
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let maxX = max(viewportWidth - dragMargin - width, dragMargin)
        let maxY = max(viewportHeight - dragMargin - height, dragMargin)
        return CGPoint(
            x: min(max(origin.x, dragMargin), maxX),
            y: min(max(origin.y, dragMargin), maxY)
        )
    }
}

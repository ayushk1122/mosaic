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

    @Environment(ComposerStore.self) private var store
    @Environment(\.composerViewportWidth) private var viewportWidth
    @FocusState private var titleFocus: String?
    @State private var renamingID: String?

    private var showsEdits: Bool {
        isSelected && !isViewing
    }

    private var maximumCount: Int {
        ComposerTabSet.maximumCount(longestSide: ComposerTabSet.longestScreenSide())
    }

    private var metric: CGFloat {
        CGFloat(min(max(block.style.scale, 0.45), 3.2)) * livePinchScale
    }

    private var rowLimit: CGFloat {
        viewportWidth > 1 ? viewportWidth - 32 : 320
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabRow
            ScrollView(.horizontal, showsIndicators: false) {
                tabRow
            }
            .frame(width: rowLimit, alignment: .leading)
        }
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

    private var tabRow: some View {
        let showsColumn = canAdd || canRemove
        return HStack(alignment: .center, spacing: 8 * metric) {
            HStack(spacing: 2 * metric) {
                ForEach(block.tabs) { tab in
                    tabChip(tab)
                }
            }
            if showsColumn {
                VStack(spacing: 6 * metric) {
                    if canAdd {
                        addButton
                    }
                    if canRemove {
                        removeButton
                    }
                }
            }
        }
        .padding(.vertical, 2 * metric)
        .fixedSize(horizontal: true, vertical: true)
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
                    .onSubmit { renamingID = nil }
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
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func choose(_ tab: ComposerTab) {
        let alreadyOpen = block.selectedTabID == tab.id
        if showsEdits, alreadyOpen {
            renamingID = tab.id
            titleFocus = tab.id
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
            .highPriorityGesture(TapGesture().onEnded {
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

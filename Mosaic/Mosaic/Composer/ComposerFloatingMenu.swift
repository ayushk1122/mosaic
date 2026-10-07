import SwiftUI

private enum ComposerAddMenuColors {
    /// Menu rows and chrome — gunmetal for dark-mode alignment.
    static let bubble = Color(red: 0.20, green: 0.21, blue: 0.23)
    static let bubbleStroke = Color.white.opacity(0.10)
    /// Slightly lighter so search reads as an input, same width as rows.
    static let searchField = Color(red: 0.30, green: 0.31, blue: 0.34)
    static let searchStroke = Color.white.opacity(0.08)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryIcon = Color.white.opacity(0.55)
}

struct ComposerPencilFrameKey: PreferenceKey {
    static var defaultValue: [ComposerBlockID: CGRect] = [:]

    static func reduce(value: inout [ComposerBlockID: CGRect], nextValue: () -> [ComposerBlockID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct ComposerTextStyleIconFrameKey: PreferenceKey {
    static var defaultValue: [ComposerBlockID: CGRect] = [:]

    static func reduce(value: inout [ComposerBlockID: CGRect], nextValue: () -> [ComposerBlockID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct ComposerTrashDropZoneFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct ComposerFloatingMenu: View {
    @Binding var isExpanded: Bool
    var showsTrashDropZone: Bool
    var isTrashHighlighted: Bool
    var onSelect: (BlockMenuOption) -> Void

    @State private var searchText = ""

    private let plusSize: CGFloat = 56
    private let rowWidth: CGFloat = 184
    private let listMaxHeight: CGFloat = 300

    private var filteredOptions: [BlockMenuOption] {
        BlockMenuOption.menuOptions(matching: searchText)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if isExpanded, !showsTrashDropZone {
                integratedSearchField
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .trailing, spacing: 8) {
                        if filteredOptions.isEmpty {
                            Text("No results")
                                .font(.caption)
                                .foregroundStyle(ComposerAddMenuColors.secondaryIcon)
                                .frame(width: rowWidth, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(filteredOptions) { option in
                                Button {
                                    onSelect(option)
                                } label: {
                                    ComposerMenuOptionRow(option: option, width: rowWidth)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("composer.add.\(option.rawValue)")
                            }
                        }
                    }
                }
                .frame(maxHeight: listMaxHeight, alignment: .bottomTrailing)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            trashOrPlusButton
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isExpanded)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: showsTrashDropZone)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isTrashHighlighted)
        .onChange(of: isExpanded) { _, expanded in
            if !expanded {
                searchText = ""
            }
        }
    }

    private var integratedSearchField: some View {
        TextField(
            "",
            text: $searchText,
            prompt: Text("Type to search")
                .font(.subheadline)
                .foregroundStyle(ComposerAddMenuColors.secondaryIcon)
        )
        .font(.subheadline)
        .foregroundStyle(ComposerAddMenuColors.primaryText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: rowWidth, alignment: .leading)
        .background(ComposerAddMenuColors.searchField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ComposerAddMenuColors.searchStroke, lineWidth: 1)
        }
        .accessibilityIdentifier("composer.add.search")
    }

    @ViewBuilder
    private var trashOrPlusButton: some View {
        if showsTrashDropZone {
            trashButton
        } else {
            plusButton
        }
    }

    private var plusButton: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(isExpanded ? 45 : 0))
                .frame(width: plusSize, height: plusSize)
                .background(MosaicBrand.inkBlack, in: Circle())
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        }
        .accessibilityIdentifier("composer.addButton")
        .accessibilityLabel(isExpanded ? "Close add menu" : "Add to Mosaic")
    }

    private var trashButton: some View {
        Image(systemName: "trash.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: plusSize, height: plusSize)
            .background(isTrashHighlighted ? Color.red.opacity(0.92) : Color(red: 0.36, green: 0.18, blue: 0.18), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(isTrashHighlighted ? 0.45 : 0.14), lineWidth: isTrashHighlighted ? 2 : 1))
            .scaleEffect(isTrashHighlighted ? 1.1 : 1)
            .shadow(color: .black.opacity(0.20), radius: 10, y: 4)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ComposerTrashDropZoneFrameKey.self,
                        value: proxy.frame(in: .named("composerRoot"))
                    )
                }
            }
            .accessibilityIdentifier("composer.trashDropZone")
            .accessibilityLabel("Drop here to delete")
    }
}

private struct ComposerMenuOptionRow: View {
    let option: BlockMenuOption
    var width: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: option.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(ComposerAddMenuColors.secondaryIcon)
                .frame(width: 22, alignment: .center)

            Text(option.title)
                .font(.body.weight(.medium))
                .foregroundStyle(ComposerAddMenuColors.primaryText)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 11)
        .frame(width: width, alignment: .leading)
        .background(ComposerAddMenuColors.bubble, in: Capsule())
        .overlay(Capsule().stroke(ComposerAddMenuColors.bubbleStroke, lineWidth: 1))
    }
}

struct ComposerPlacementGhost: View {
    let option: BlockMenuOption

    var body: some View {
        Image(systemName: option.systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(ComposerAddMenuColors.primaryText)
            .frame(width: 44, height: 44)
            .background(ComposerAddMenuColors.bubble.opacity(0.92), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.20), radius: 6, y: 3)
            .accessibilityLabel(option.title)
            .accessibilityIdentifier("composer.placement.ghost")
    }
}

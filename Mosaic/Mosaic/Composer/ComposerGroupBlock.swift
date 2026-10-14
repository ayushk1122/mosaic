import SwiftUI

struct ComposerBlockFrameKey: PreferenceKey {
    static var defaultValue: [ComposerBlockID: CGRect] = [:]

    static func reduce(value: inout [ComposerBlockID: CGRect], nextValue: () -> [ComposerBlockID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

enum ComposerGroupMath {
    static func groupedBlock(
        members: [ComposerBlock],
        frames: [ComposerBlockID: CGRect],
        canvasWidth: CGFloat,
        layoutHeight: CGFloat,
        tabID: String?
    ) -> ComposerBlock? {
        let chosen = members.compactMap { block -> (ComposerBlock, CGRect)? in
            guard let frame = frames[block.id], frame.width > 1, frame.height > 1 else { return nil }
            return (block, frame)
        }
        guard chosen.count >= 2, canvasWidth > 1, layoutHeight > 1 else { return nil }
        let union = chosen.dropFirst().reduce(chosen[0].1) { $0.union($1.1) }
        guard union.width > 1, union.height > 1 else { return nil }
        let packed = chosen.map { block, frame in
            var member = block
            member.position = BlockPosition(
                x: Double((frame.minX - union.minX) / union.width),
                y: Double((frame.minY - union.minY) / union.height)
            )
            member.tabID = nil
            return member
        }
        var group = ComposerBlock.make(kind: .group, position: BlockPosition(
            x: Double(min(max(union.minX / canvasWidth, 0), 1)),
            y: Double(max(union.minY / layoutHeight, 0))
        ))
        group.groupMembers = packed
        group.groupWidth = Double(union.width)
        group.groupHeight = Double(union.height)
        group.tabID = tabID
        group.style.scale = 1
        return group
    }

    static func ungroupedMembers(
        of group: ComposerBlock,
        canvasWidth: CGFloat,
        layoutHeight: CGFloat
    ) -> [ComposerBlock] {
        let scale = max(group.style.scale, 0.01)
        let width = group.groupWidth * scale
        let height = group.groupHeight * scale
        let originX = canvasWidth * group.position.x
        let originY = layoutHeight * group.position.y
        return group.groupMembers.map { member in
            var copy = member
            let x = originX + copy.position.x * width
            let y = originY + copy.position.y * height
            copy.position = BlockPosition(
                x: canvasWidth > 1 ? x / canvasWidth : 0,
                y: layoutHeight > 1 ? y / layoutHeight : 0
            )
            copy.tabID = group.tabID
            bake(scale, into: &copy)
            return copy
        }
    }

    static func bake(_ scale: Double, into block: inout ComposerBlock) {
        guard abs(scale - 1) > 0.001 else { return }
        switch block.kind {
        case .text, .heading, .list:
            block.style.fontSize = min(max(block.style.fontSize * scale, 12), 160)
        case .graph:
            block.graphWidthScale *= scale
            block.graphHeightScale *= scale
        case .banner:
            block.bannerHeight *= scale
        case .group:
            block.style.scale *= scale
        default:
            block.style.scale *= scale
        }
    }
}

struct ComposerGroupCanvasBlock: View {
    @Binding var block: ComposerBlock
    var documentID: ComposerDocumentID?
    var livePinchScale: CGFloat
    var isSelected: Bool
    var isLifted: Bool
    var isViewing: Bool
    var canvasSize: CGSize
    var mediaMenuBlockID: ComposerBlockID?
    var onPresentMedia: ((URL, ComposerMediaCrop?) -> Void)?
    var onOpenFolder: (ComposerBlock) -> Void
    var onOpenMediaMenu: (ComposerBlockID) -> Void
    var onCropMedia: (ComposerBlockID) -> Void
    var onEditPursuit: (ComposerBlockID) -> Void
    var onEditCarousel: (ComposerBlockID) -> Void
    var onEditSocial: (ComposerBlockID) -> Void
    var onOpenSocial: (ComposerBlock) -> Void
    var onOpenScrapbook: (ComposerBlock) -> Void = { _ in }
    var onStyleMenuChange: (Bool) -> Void = { _ in }
    var onClaimFormatTap: () -> Void = {}
    var onActivate: () -> Void = {}
    var onUngroup: () -> Void

    @Environment(ComposerStore.self) private var store
    @FocusState private var childFocus: ComposerBlockID?
    @State private var editingMemberID: ComposerBlockID?
    @State private var activeMemberID: ComposerBlockID?
    @State private var playingMediaIDs: Set<ComposerBlockID> = []

    private var baseWidth: CGFloat { max(CGFloat(block.groupWidth), 1) }
    private var baseHeight: CGFloat { max(CGFloat(block.groupHeight), 1) }
    private var scale: CGFloat { CGFloat(max(block.style.scale, 0.2)) * livePinchScale }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(block.groupMembers) { member in
                memberView(member.id)
                    .offset(
                        x: CGFloat(member.position.x) * baseWidth,
                        y: CGFloat(member.position.y) * baseHeight
                    )
            }
        }
        .frame(width: baseWidth, height: baseHeight, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: baseWidth * scale, height: baseHeight * scale, alignment: .topLeading)
        .contentShape(Rectangle())
        .overlay(alignment: .topTrailing) {
            if isSelected, !isLifted, !isViewing {
                Button(action: onUngroup) {
                    Text("Ungroup")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Capsule())
                }
                .buttonStyle(.plain)
                .offset(y: -36)
                .accessibilityLabel("Ungroup")
            }
        }
        .onChange(of: isSelected) { _, selected in
            if !selected {
                editingMemberID = nil
                activeMemberID = nil
                playingMediaIDs = []
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Group")
        .accessibilityIdentifier("composer.group.\(block.id.rawValue)")
    }

    private func memberBinding(_ id: ComposerBlockID) -> Binding<ComposerBlock> {
        Binding(
            get: {
                block.groupMembers.first(where: { $0.id == id })
                    ?? ComposerBlock.make(kind: .text, position: BlockPosition(x: 0, y: 0))
            },
            set: { updated in
                guard let index = block.groupMembers.firstIndex(where: { $0.id == id }) else { return }
                var group = block
                group.groupMembers[index] = updated
                block = group
            }
        )
    }

    private func memberView(_ id: ComposerBlockID) -> some View {
        let member = block.groupMembers.first(where: { $0.id == id }) ?? ComposerBlock.make(kind: .text, position: BlockPosition(x: 0, y: 0))
        let memberActive = activeMemberID == id && !isLifted && !isViewing
        let writesText = member.kind == .text || member.kind == .heading || member.kind == .list || member.kind == .link
        return ComposerCanvasBlockView(
            documentID: documentID,
            block: memberBinding(id),
            isEditing: writesText && editingMemberID == id && memberActive,
            isSelected: memberActive && member.kind != .social,
            isLifted: isLifted,
            isRelocating: false,
            livePinchScale: 1,
            focusBlockID: $childFocus,
            mediaURL: member.mediaFileName.map { store.mediaURL(for: $0) },
            pursuitImageURL: member.pursuitImageFileName.map { store.mediaURL(for: $0) },
            isMediaPaused: isLifted || !playingMediaIDs.contains(id),
            actions: ComposerBlockActions(
                onCommit: {},
                onBeginEditing: { activate(id) },
                onDelete: {},
                onMediaData: { _ in },
                onStyleChange: {},
                onStyleMenuChange: onStyleMenuChange,
                onClaimFormatTap: onClaimFormatTap,
                onOpenMediaMenu: { onOpenMediaMenu(id) },
                onCropMedia: { onCropMedia(id) },
                onEditPursuit: { onEditPursuit(id) },
                onEditCarousel: { onEditCarousel(id) },
                onSelectTabs: { activate(id) },
                onEditSocial: { onEditSocial(id) },
                onUngroup: {},
                onPresentMedia: isViewing ? onPresentMedia : nil,
                onBodyTap: mediaBodyTap(id),
                onOpenSocial: socialOpen(member),
                onOpenFolder: { _ in },
                onOpenScrapbook: { _ in },
                onOpenMemberMediaMenu: { _ in },
                onCropMemberMedia: { _ in },
                onEditMemberPursuit: { _ in },
                onEditMemberCarousel: { _ in },
                onEditMemberSocial: { _ in },
                onOpenMemberSocial: { _ in }
            ),
            showsMediaMenu: mediaMenuBlockID == id,
            showsPursuitPencil: memberActive && (member.kind == .pursuit || member.kind == .node),
            allowsCarouselControl: isViewing || memberActive,
            isViewing: isViewing,
            canvasSize: canvasSize,
            pinsTabsToPageEdges: false
        )
        .simultaneousGesture(TapGesture().onEnded { activate(id) })
        .modifier(
            GroupMemberTapModifier(
                isEnabled: (isViewing || memberActive) && editingMemberID != id && usesMemberTap(member.kind),
                action: { handleMemberTap(member) }
            )
        )
    }

    private func activate(_ id: ComposerBlockID) {
        guard !isViewing, !isLifted else { return }
        activeMemberID = id
        let kind = block.groupMembers.first(where: { $0.id == id })?.kind
        if kind == .text || kind == .heading || kind == .list || kind == .link {
            editingMemberID = id
        } else {
            editingMemberID = nil
        }
        onActivate()
    }

    private func usesMemberTap(_ kind: BlockKind) -> Bool {
        switch kind {
        case .text, .heading, .list, .link, .pursuit, .node, .scrapbook:
            return true
        default:
            return false
        }
    }

    private func handleMemberTap(_ member: ComposerBlock) {
        switch member.kind {
        case .text, .heading, .list, .link:
            activate(member.id)
        case .pursuit, .node:
            onOpenFolder(member)
        case .scrapbook:
            onOpenScrapbook(member)
        default:
            break
        }
    }

    private func mediaBodyTap(_ id: ComposerBlockID) -> (() -> Void)? {
        guard !isLifted else { return nil }
        guard block.groupMembers.first(where: { $0.id == id })?.kind == .media else { return nil }
        guard isViewing || activeMemberID == id else { return nil }
        return {
            guard let member = block.groupMembers.first(where: { $0.id == id }) else { return }
            if isViewing {
                guard let name = member.mediaFileName, !name.isEmpty else { return }
                onPresentMedia?(store.mediaURL(for: name), ComposerMediaCrop(block: member))
            } else if playingMediaIDs.contains(id) {
                playingMediaIDs.remove(id)
            } else {
                playingMediaIDs.insert(id)
            }
        }
    }

    private func socialOpen(_ member: ComposerBlock) -> (() -> Void)? {
        guard member.kind == .social else { return nil }
        guard isViewing || (activeMemberID == member.id && !isLifted) else { return nil }
        return { onOpenSocial(member) }
    }
}

private struct GroupMemberTapModifier: ViewModifier {
    var isEnabled: Bool
    var action: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.onTapGesture(perform: action)
        } else {
            content
        }
    }
}

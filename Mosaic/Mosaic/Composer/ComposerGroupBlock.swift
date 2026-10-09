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
    var onUngroup: () -> Void

    @Environment(ComposerStore.self) private var store
    @FocusState private var childFocus: ComposerBlockID?

    private var baseWidth: CGFloat { max(CGFloat(block.groupWidth), 1) }
    private var baseHeight: CGFloat { max(CGFloat(block.groupHeight), 1) }
    private var scale: CGFloat { CGFloat(max(block.style.scale, 0.2)) * livePinchScale }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(block.groupMembers) { member in
                memberView(member)
                    .offset(
                        x: CGFloat(member.position.x) * baseWidth,
                        y: CGFloat(member.position.y) * baseHeight
                    )
                    .allowsHitTesting(false)
            }
        }
        .frame(width: baseWidth, height: baseHeight, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: baseWidth * scale, height: baseHeight * scale, alignment: .topLeading)
        .contentShape(Rectangle())
        .overlay {
            if isSelected, !isLifted {
                Rectangle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            }
        }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Group")
        .accessibilityIdentifier("composer.group.\(block.id.rawValue)")
    }

    private func memberView(_ member: ComposerBlock) -> some View {
        ComposerCanvasBlockView(
            documentID: documentID,
            block: Binding(get: { member }, set: { _ in }),
            isEditing: false,
            isSelected: false,
            isLifted: false,
            isRelocating: false,
            livePinchScale: 1,
            focusBlockID: $childFocus,
            mediaURL: member.mediaFileName.map { store.mediaURL(for: $0) },
            pursuitImageURL: member.pursuitImageFileName.map { store.mediaURL(for: $0) },
            isMediaPaused: true,
            onCommit: {},
            onBeginEditing: {},
            onDelete: {},
            onMediaData: { _ in },
            onStyleChange: {},
            showsMediaMenu: false,
            onOpenMediaMenu: {},
            onCropMedia: {},
            showsPursuitPencil: false,
            onEditPursuit: {},
            allowsCarouselControl: false,
            onEditCarousel: {},
            isViewing: true,
            canvasSize: .zero
        )
    }
}

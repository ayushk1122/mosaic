import SwiftUI
import UIKit

struct MosaicComposerView: View {
    let documentID: ComposerDocumentID?

    @Environment(ComposerStore.self) private var store
    @State private var menuExpanded = false
    @State private var placingOption: BlockMenuOption?
    @State private var ghostLocation: CGPoint = .zero
    @State private var canvasSize: CGSize = .zero
    @State private var editingBlockID: ComposerBlockID?
    @State private var selectedBlockID: ComposerBlockID?
    @FocusState private var focusedTextBlockID: ComposerBlockID?
    @State private var textDragSession = TextDragSession()
    @GestureState private var textDragVisual = TextDragVisual.inactive
    @GestureState private var textPinchVisual = TextPinchVisual.inactive
    @State private var trashDropZoneFrame: CGRect = .zero

    private var blocks: [ComposerBlock] {
        store.blocks(for: documentID)
    }

    private var pageTitle: String {
        if documentID == nil {
            return "Mosaic"
        }
        return store.title(for: documentID)
    }

    private var canvasHeight: CGFloat {
        let lowest = blocks.map(\.position.y).max() ?? 0.15
        return max(900, CGFloat(lowest + 0.3) * 1200)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard placingOption == nil else { return }
                                if editingBlockID != nil {
                                    commitTextEditing()
                                } else {
                                    dismissBlockInteraction()
                                }
                            }

                        if blocks.isEmpty, placingOption == nil {
                            emptyState
                                .padding(.horizontal, 24)
                                .padding(.top, 48)
                        }

                        if placingOption != nil {
                            Text("Drag to place")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.white.opacity(0.45))
                                .position(x: canvasSize.width * 0.5, y: 28)
                        }

                        ForEach(blocks) { block in
                            blockView(for: block)
                                .id(block.id)
                                .offset(liveOffset(for: block))
                                .opacity(textDragVisual.blockID == block.id && textDragVisual.isMoving ? 0.96 : 1)
                                .modifier(
                                    RelocateGestureModifier(
                                        isEnabled: isTextLikeKind(block.kind) && placingOption == nil,
                                        claimsTouches: editingBlockID != block.id,
                                        gesture: textPressGesture(for: block),
                                        pinch: textPinchGesture(for: block)
                                    )
                                )
                        }

                        if let placingOption {
                            ComposerPlacementGhost(option: placingOption)
                                .offset(x: ghostLocation.x - 22, y: ghostLocation.y - 22)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: canvasHeight)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { canvasSize = proxy.size }
                                .onChange(of: proxy.size) { _, newSize in
                                    canvasSize = newSize
                                    if placingOption != nil, ghostLocation == .zero {
                                        ghostLocation = clamped(
                                            point: CGPoint(x: newSize.width * 0.5, y: newSize.height * 0.35)
                                        )
                                    }
                                }
                        }
                    )
                    .coordinateSpace(name: "composerCanvas")
                    .modifier(
                        PlacementGestureModifier(
                            isActive: placingOption != nil,
                            gesture: placementDragGesture
                        )
                    )
                }
                .scrollDisabled(textDragVisual.isMoving)
                .scrollDismissesKeyboard(.interactively)

            ComposerFloatingMenu(
                isExpanded: $menuExpanded,
                showsTrashDropZone: textDragVisual.isMoving,
                isTrashHighlighted: textDragVisual.hoveringTrash
            ) { option in
                beginPlacement(for: option)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .coordinateSpace(name: "composerRoot")
        .onPreferenceChange(ComposerTrashDropZoneFrameKey.self) { frame in
            let rounded = CGRect(
                x: frame.origin.x.rounded(),
                y: frame.origin.y.rounded(),
                width: frame.size.width.rounded(),
                height: frame.size.height.rounded()
            )
            guard rounded != trashDropZoneFrame else { return }
            trashDropZoneFrame = rounded
        }
        .background(MosaicBrand.inkBlack)
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if editingBlockID != nil {
                    Spacer()
                    Button("Done") {
                        commitTextEditing()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("composer.text.done")
                }
            }
        }
        .navigationDestination(for: ComposerDocumentID.self) { pursuitID in
            MosaicComposerView(documentID: pursuitID)
        }
        .accessibilityIdentifier(documentID == nil ? "mosaic.screen" : "pursuit.screen")
    }

    @ViewBuilder
    private func blockView(for block: ComposerBlock) -> some View {
        if blocks.contains(where: { $0.id == block.id }) {
            ComposerCanvasBlockView(
                documentID: documentID,
                block: blockBinding(for: block.id, fallback: block),
                isEditing: editingBlockID == block.id,
                isSelected: selectedBlockID == block.id,
                isLifted: textDragVisual.blockID == block.id && textDragVisual.lifted,
                isRelocating: textDragVisual.blockID == block.id && textDragVisual.isMoving,
                livePinchScale: textPinchVisual.blockID == block.id ? textPinchVisual.scale : 1,
                focusBlockID: $focusedTextBlockID,
                mediaURL: block.mediaFileName.map { store.mediaURL(for: $0) },
                opensPursuitInParentStack: documentID == nil,
                onCommit: commitTextEditing,
                onBeginEditing: {
                    selectedBlockID = block.id
                    editingBlockID = block.id
                    focusedTextBlockID = block.id
                },
                onDelete: {
                    store.deleteBlock(block.id, in: documentID)
                    if editingBlockID == block.id {
                        editingBlockID = nil
                    }
                    if selectedBlockID == block.id {
                        selectedBlockID = nil
                    }
                },
                onMediaData: { data in
                    if let fileName = try? store.saveMediaData(data) {
                        guard var updated = store.blocks(for: documentID).first(where: { $0.id == block.id }) else {
                            return
                        }
                        updated.mediaFileName = fileName
                        store.updateBlock(updated, in: documentID)
                    }
                },
                onStyleChange: {
                    guard let current = store.blocks(for: documentID).first(where: { $0.id == block.id }) else {
                        return
                    }
                    store.updateBlock(current, in: documentID)
                }
            )
        }
    }

    private func blockBinding(for blockID: ComposerBlockID, fallback: ComposerBlock) -> Binding<ComposerBlock> {
        Binding(
            get: {
                store.block(with: blockID, in: documentID) ?? fallback
            },
            set: { updated in
                guard store.block(with: blockID, in: documentID) != nil else { return }
                store.updateBlock(updated, in: documentID)
            }
        )
    }

    private var placementDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("composerCanvas"))
            .onChanged { value in
                ghostLocation = clamped(point: value.location)
            }
            .onEnded { value in
                guard let placingOption else { return }
                let point = clamped(point: value.location)
                if isTextLikeKind(placingOption.blockKind) {
                    placeTextAndBeginEditing(option: placingOption, at: point)
                } else {
                    place(option: placingOption, at: point)
                }
                self.placingOption = nil
            }
    }

    private func beginPlacement(for option: BlockMenuOption) {
        menuExpanded = false
        placingOption = option
        ghostLocation = clamped(
            point: CGPoint(
                x: canvasSize.width * 0.5,
                y: canvasSize.height * 0.35
            )
        )
    }

    private func place(option: BlockMenuOption, at point: CGPoint) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let position = normalizedPosition(from: point)
        let newID = store.addBlock(option.blockKind, at: position, to: documentID)
        if option.blockKind == .link {
            editingBlockID = newID
        }
    }

    private func placeTextAndBeginEditing(option: BlockMenuOption, at point: CGPoint) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let position = normalizedPosition(from: point)
        let newID = store.addBlock(option.blockKind, at: position, to: documentID)
        beginTextEditing(newID)
    }

    private func beginTextEditing(_ blockID: ComposerBlockID) {
        guard textDragVisual.blockID == nil else { return }
        selectedBlockID = blockID
        editingBlockID = blockID
        Task { @MainActor in
            focusedTextBlockID = blockID
        }
    }

    private func commitTextEditing() {
        let finishedID = editingBlockID
        editingBlockID = nil
        focusedTextBlockID = nil
        if let finishedID, blocks.contains(where: { $0.id == finishedID && isTextLikeKind($0.kind) }) {
            selectedBlockID = finishedID
        }
    }

    private func dismissBlockInteraction() {
        editingBlockID = nil
        selectedBlockID = nil
        focusedTextBlockID = nil
        textDragSession.reset()
    }

    private func textPressGesture(for block: ComposerBlock) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("composerRoot"))
            .updating($textDragVisual) { value, visual, _ in
                let session = textDragSession
                if session.isPinching {
                    visual = .inactive
                    return
                }
                if session.blockID != block.id {
                    session.blockID = block.id
                    session.started = Date()
                    session.baseline = nil
                    session.didHaptic = false
                }

                let elapsed = Date().timeIntervalSince(session.started)
                let distance = hypot(value.translation.width, value.translation.height)
                var next = TextDragVisual(blockID: block.id, lifted: false, isMoving: false, translation: .zero, hoveringTrash: false)

                if elapsed >= 0.28 {
                    next.lifted = true
                    if !session.didHaptic {
                        session.didHaptic = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }

                if elapsed >= 0.32, distance > 6 {
                    if session.baseline == nil {
                        session.baseline = value.translation
                    }
                    let baseline = session.baseline ?? .zero
                    next.isMoving = true
                    next.translation = CGSize(
                        width: value.translation.width - baseline.width,
                        height: value.translation.height - baseline.height
                    )
                    next.hoveringTrash = trashDropZoneFrame.insetBy(dx: -28, dy: -28).contains(value.location)
                    session.lastTranslation = next.translation
                    session.hoveringTrash = next.hoveringTrash
                }

                visual = next
            }
            .onEnded { value in
                let elapsed = Date().timeIntervalSince(textDragSession.started)
                let distance = hypot(value.translation.width, value.translation.height)
                let didMove = textDragSession.baseline != nil && !textDragSession.isPinching
                let translation = textDragSession.lastTranslation
                let shouldDelete = textDragSession.hoveringTrash
                textDragSession.reset()

                if didMove {
                    editingBlockID = nil
                    focusedTextBlockID = nil
                    if shouldDelete {
                        deleteBlock(block.id)
                        selectedBlockID = nil
                    } else {
                        let origin = canvasPoint(for: block.position)
                        moveBlock(
                            block.id,
                            to: CGPoint(
                                x: origin.x + translation.width,
                                y: origin.y + translation.height
                            )
                        )
                        selectedBlockID = block.id
                    }
                } else if distance < 12, elapsed < 0.32, editingBlockID != block.id {
                    beginTextEditing(block.id)
                }
            }
    }

    private func textPinchGesture(for block: ComposerBlock) -> some Gesture {
        MagnificationGesture()
            .updating($textPinchVisual) { value, visual, _ in
                textDragSession.isPinching = true
                textDragSession.baseline = nil
                visual = TextPinchVisual(blockID: block.id, scale: value)
            }
            .onEnded { value in
                textDragSession.isPinching = false
                textDragSession.baseline = nil
                guard var current = store.block(with: block.id, in: documentID) else { return }
                let next = current.style.fontSize * current.style.scale * Double(value)
                current.style.fontSize = min(max(next, 12), 80)
                current.style.scale = 1
                store.updateBlock(current, in: documentID)
            }
    }

    private func deleteBlock(_ blockID: ComposerBlockID) {
        store.deleteBlock(blockID, in: documentID)
        if editingBlockID == blockID {
            editingBlockID = nil
        }
        if selectedBlockID == blockID {
            selectedBlockID = nil
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func moveBlock(_ blockID: ComposerBlockID, to canvasPoint: CGPoint) {
        guard var block = blocks.first(where: { $0.id == blockID }) else { return }
        block.position = normalizedPosition(from: canvasPoint)
        store.updateBlock(block, in: documentID)
    }

    private func isTextLikeKind(_ kind: BlockKind) -> Bool {
        kind == .text || kind == .heading
    }

    private func liveOffset(for block: ComposerBlock) -> CGSize {
        let base = anchorOffset(for: block.position)
        guard textDragVisual.blockID == block.id, textDragVisual.isMoving else { return base }
        return CGSize(
            width: base.width + textDragVisual.translation.width,
            height: base.height + textDragVisual.translation.height
        )
    }

    private func anchorOffset(for position: BlockPosition) -> CGSize {
        let point = canvasPoint(for: position)
        return CGSize(width: point.x, height: point.y)
    }

    private func canvasPoint(for position: BlockPosition) -> CGPoint {
        CGPoint(
            x: canvasSize.width * position.x,
            y: canvasSize.height * position.y
        )
    }

    private func normalizedPosition(from point: CGPoint) -> BlockPosition {
        let width = max(canvasSize.width, 1)
        let height = max(canvasSize.height, 1)
        return BlockPosition(
            x: Double(min(max(point.x / width, 0), 1)),
            y: Double(min(max(point.y / height, 0), 1))
        )
    }

    private func clamped(point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 28), max(canvasSize.width - 28, 28)),
            y: min(max(point.y, 28), max(canvasSize.height - 28, 28))
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add the first piece of your Mosaic")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Tap +, choose a tool, then drag it onto the page.")
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("composer.emptyState")
    }
}

private struct PlacementGestureModifier<G: Gesture>: ViewModifier {
    let isActive: Bool
    let gesture: G

    func body(content: Content) -> some View {
        if isActive {
            content.highPriorityGesture(gesture)
        } else {
            content
        }
    }
}

private struct TextDragVisual: Equatable {
    var blockID: ComposerBlockID?
    var lifted: Bool
    var isMoving: Bool
    var translation: CGSize
    var hoveringTrash: Bool

    static let inactive = TextDragVisual(
        blockID: nil,
        lifted: false,
        isMoving: false,
        translation: .zero,
        hoveringTrash: false
    )
}

private final class TextDragSession {
    var blockID: ComposerBlockID?
    var started = Date()
    var baseline: CGSize?
    var lastTranslation: CGSize = .zero
    var hoveringTrash = false
    var didHaptic = false
    var isPinching = false

    func reset() {
        blockID = nil
        started = Date()
        baseline = nil
        lastTranslation = .zero
        hoveringTrash = false
        didHaptic = false
        isPinching = false
    }
}

private struct TextPinchVisual: Equatable {
    var blockID: ComposerBlockID?
    var scale: CGFloat

    static let inactive = TextPinchVisual(blockID: nil, scale: 1)
}

private struct RelocateGestureModifier<Drag: Gesture, Pinch: Gesture>: ViewModifier {
    let isEnabled: Bool
    let claimsTouches: Bool
    let gesture: Drag
    let pinch: Pinch

    func body(content: Content) -> some View {
        if !isEnabled {
            content
        } else if claimsTouches {
            content
                .highPriorityGesture(gesture)
                .simultaneousGesture(pinch)
        } else {
            content
                .simultaneousGesture(gesture)
                .simultaneousGesture(pinch)
        }
    }
}

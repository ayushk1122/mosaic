import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MosaicComposerView: View {
    let documentID: ComposerDocumentID?

    @Environment(ComposerStore.self) private var store
    @Environment(MosaicChrome.self) private var chrome
    @Environment(\.mosaicTabBarHidden) private var mosaicTabBarHidden
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var menuExpanded = false
    @State private var placingOption: BlockMenuOption?
    @State private var ghostLocation: CGPoint = .zero
    @State private var canvasSize: CGSize = .zero
    @State private var grownCanvasHeight: CGFloat = 0
    @State private var editingBlockID: ComposerBlockID?
    @State private var selectedBlockID: ComposerBlockID?
    @FocusState private var focusedTextBlockID: ComposerBlockID?
    @State private var textDragSession = TextDragSession()
    @GestureState private var textDragVisual = TextDragVisual.inactive
    @GestureState private var textPinchVisual = TextPinchVisual.inactive
    @State private var trashDropZoneFrame: CGRect = .zero
    @State private var showMediaPicker = false
    @State private var pickedMediaItem: PhotosPickerItem?
    @State private var pendingMediaBlockID: ComposerBlockID?
    @State private var playingMediaIDs: Set<ComposerBlockID> = []
    @State private var mediaEditRequest: MediaEditRequest?
    @State private var styleMenuBlockID: ComposerBlockID?
    @State private var viewportWidth: CGFloat = 0
    @State private var openedPursuitID: ComposerDocumentID?
    @State private var pencilFrames: [ComposerBlockID: CGRect] = [:]
    @State private var textStyleIconFrames: [ComposerBlockID: CGRect] = [:]
    @State private var graphResizeFrames: [ComposerBlockID: ComposerGraphResizeFrames] = [:]
    @State private var socialCornerFrames: [ComposerBlockID: ComposerSocialCornerFrames] = [:]
    @State private var socialCornerResizing = false
    @State private var isGrouping = false
    @State private var groupSelection: Set<ComposerBlockID> = []
    @State private var blockFrames: [ComposerBlockID: CGRect] = [:]
    @State private var pursuitEditRequest: PursuitEditRequest?
    @State private var showCarouselPicker = false
    @State private var pickedCarouselItems: [PhotosPickerItem] = []
    @State private var pendingCarouselBlockID: ComposerBlockID?
    @State private var carouselEditRequest: CarouselEditRequest?
    @State private var socialEditRequest: SocialEditRequest?

    private var blocks: [ComposerBlock] {
        store.blocks(for: documentID)
    }

    private var visibleBlocks: [ComposerBlock] {
        guard let tabs = blocks.first(where: { $0.kind == .tabs }),
              let selected = tabs.selectedTabID else { return blocks }
        return blocks.filter { $0.kind == .tabs || $0.kind == .banner || $0.tabID == selected }
    }

    private var scrollingBlocks: [ComposerBlock] {
        visibleBlocks.filter { $0.kind != .banner }
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.top, 8)
        .accessibilityLabel("Back")
    }

    private func bannerHeader(_ block: ComposerBlock) -> some View {
        ComposerBannerBlock(
            block: blockBinding(for: block.id, fallback: block),
            mediaURL: block.mediaFileName.map { store.mediaURL(for: $0) },
            isSelected: selectedBlockID == block.id,
            isEditing: editingBlockID == block.id,
            isViewing: chrome.isViewing,
            focusBlockID: $focusedTextBlockID,
            onSelect: {
                selectedBlockID = block.id
            },
            onBeginEditing: {
                selectedBlockID = block.id
                editingBlockID = block.id
                focusedTextBlockID = block.id
            },
            onCommit: commitTextEditing,
            onReplaceMedia: {
                selectedBlockID = block.id
                pendingMediaBlockID = block.id
                showMediaPicker = true
            },
            onDelete: {
                store.deleteBlock(block.id, in: documentID)
                if editingBlockID == block.id {
                    editingBlockID = nil
                    focusedTextBlockID = nil
                }
                if selectedBlockID == block.id {
                    selectedBlockID = nil
                }
            }
        )
    }

    /// Page height the saved positions were laid out against. It does not change when one block moves.
    private var layoutHeight: CGFloat {
        if let stored = store.layoutHeight(for: documentID), stored > 1 {
            return CGFloat(stored)
        }
        return proposedLayoutHeight
    }

    private var proposedLayoutHeight: CGFloat {
        let lowest = visibleBlocks.map(\.position.y).max() ?? 0.15
        return max(900, CGFloat(lowest + 0.3) * 1200)
    }

    private var neededCanvasHeight: CGFloat {
        let lowestPixel = visibleBlocks.map { CGFloat($0.position.y) * layoutHeight }.max() ?? 0
        return max(layoutHeight, lowestPixel + 360)
    }

    /// Grows to fit a block that moves downward, and does not shrink when that block moves back up.
    private var canvasHeight: CGFloat {
        max(grownCanvasHeight, neededCanvasHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let banner = blocks.first(where: { $0.kind == .banner }) {
                bannerHeader(banner)
            }
            ZStack(alignment: .bottomTrailing) {
            ScrollView(.vertical) {
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

                        if blocks.isEmpty, placingOption == nil, documentID == nil {
                            emptyState
                                .padding(.horizontal, 24)
                                .padding(.top, 48)
                        }

                        ForEach(scrollingBlocks) { block in
                            blockView(for: block)
                                .id(block.id)
                                .zIndex(styleMenuBlockID == block.id ? 2 : (block.kind == .tabs ? 1 : 0))
                                .background {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: ComposerBlockFrameKey.self,
                                            value: [block.id: proxy.frame(in: .named("composerCanvas"))]
                                        )
                                    }
                                }
                                .offset(liveOffset(for: block))
                                .opacity(blockOpacity(for: block))
                                .modifier(
                                    RelocateGestureModifier(
                                        isEnabled: !chrome.isViewing && supportsCanvasGestures(block.kind) && placingOption == nil && styleMenuBlockID != block.id,
                                        claimsTouches: !isGrouping && claimsCanvasTouches(for: block),
                                        pinchPriority: block.kind == .calendar || block.kind == .graph || block.kind == .tabs,
                                        pinchEnabled: block.kind != .table && block.kind != .social,
                                        gesture: textPressGesture(for: block),
                                        pinch: textPinchGesture(for: block)
                                    )
                                )
                                .modifier(
                                    ViewingMediaTapModifier(
                                        isEnabled: chrome.isViewing && (block.kind == .media || isFolder(block.kind) || block.kind == .social),
                                        onTap: { handleViewingTap(on: block) }
                                    )
                                )
                        }

                        if let placingOption {
                            ComposerPlacementGhost(option: placingOption)
                                .offset(x: ghostLocation.x - 22, y: ghostLocation.y - 22)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(
                        width: viewportWidth > 1 ? viewportWidth : nil,
                        height: canvasHeight,
                        alignment: .topLeading
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { canvasSize = proxy.size }
                                .onChange(of: proxy.size) { _, newSize in
                                    canvasSize = newSize
                                    if placingOption != nil, ghostLocation == .zero {
                                        ghostLocation = clamped(
                                            point: CGPoint(x: newSize.width * 0.5, y: layoutHeight * 0.35)
                                        )
                                    }
                                }
                        }
                    )
                    .background(ComposerCanvasZoomLock())
                    .coordinateSpace(name: "composerCanvas")
                    .modifier(
                        PlacementGestureModifier(
                            isActive: placingOption != nil,
                            gesture: placementDragGesture
                        )
                    )
                }
                .scrollDisabled(textDragVisual.isMoving || socialCornerResizing)
                .scrollDismissesKeyboard(.interactively)

            if isGrouping {
                groupingBar
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
            HStack(alignment: .bottom, spacing: 12) {
                viewEyeButton
                if !chrome.isViewing, !isGrouping {
                    ComposerFloatingMenu(
                        isExpanded: $menuExpanded,
                        showsTrashDropZone: textDragVisual.isMoving,
                        isTrashHighlighted: textDragVisual.hoveringTrash,
                        includesPursuit: documentID == nil,
                        includesCalendar: documentID != nil,
                        includesGraph: documentID != nil,
                        includesNode: documentID != nil,
                        includesTabs: !blocks.contains(where: { $0.kind == .tabs }),
                        includesBanner: !blocks.contains(where: { $0.kind == .banner }),
                        includesTable: documentID != nil
                    ) { option in
                        beginPlacement(for: option)
                    }
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
            .opacity(isGrouping ? 0 : 1)
            .allowsHitTesting(!isGrouping)
        }
        }
        .overlay(alignment: .bottomLeading) {
            if !chrome.isViewing, !isGrouping {
                undoButton
                    .padding(.leading, 20)
                    .padding(.bottom, 20)
            }
        }
        .coordinateSpace(name: "composerRoot")
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            viewportWidth = width
        }
        .environment(\.composerViewportWidth, viewportWidth)
        .onPreferenceChange(ComposerPencilFrameKey.self) { frames in
            pencilFrames = frames
        }
        .onPreferenceChange(ComposerTextStyleIconFrameKey.self) { frames in
            textStyleIconFrames = frames
        }
        .onPreferenceChange(ComposerGraphResizeFrameKey.self) { frames in
            graphResizeFrames = frames
        }
        .onPreferenceChange(ComposerSocialCornerFrameKey.self) { frames in
            socialCornerFrames = frames
        }
        .onPreferenceChange(ComposerBlockFrameKey.self) { frames in
            blockFrames = frames
        }
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
        .overlay(alignment: .topLeading) {
            if documentID != nil {
                backButton
            }
        }
        .background(MosaicBrand.inkBlack)
        .onAppear {
            _ = ComposerInstalledFont.familyNames
            lockLayoutHeightIfNeeded()
            grownCanvasHeight = max(grownCanvasHeight, neededCanvasHeight)
        }
        .onChange(of: neededCanvasHeight) { _, needed in
            grownCanvasHeight = max(grownCanvasHeight, needed)
        }
        .onChange(of: chrome.isViewing) { _, viewing in
            guard viewing else { return }
            menuExpanded = false
            placingOption = nil
            dismissBlockInteraction()
        }
        .toolbar(mosaicTabBarHidden ? .hidden : .visible, for: .tabBar)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
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
        .navigationDestination(item: $openedPursuitID) { pursuitID in
            MosaicComposerView(documentID: pursuitID)
        }
        .accessibilityIdentifier(documentID == nil ? "mosaic.screen" : "pursuit.screen")
        .photosPicker(
            isPresented: $showMediaPicker,
            selection: $pickedMediaItem,
            matching: .any(of: [.images, .videos])
        )
        .photosPicker(
            isPresented: $showCarouselPicker,
            selection: $pickedCarouselItems,
            maxSelectionCount: 12,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: pickedCarouselItems) { _, items in
            guard !items.isEmpty, let blockID = pendingCarouselBlockID else { return }
            pendingCarouselBlockID = nil
            let chosen = items
            pickedCarouselItems = []
            Task {
                await importCarousel(chosen, into: blockID)
            }
        }
        .onChange(of: showCarouselPicker) { _, isPresented in
            guard !isPresented else { return }
            let blockID = pendingCarouselBlockID
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard let blockID, pendingCarouselBlockID == blockID, pickedCarouselItems.isEmpty else { return }
                pendingCarouselBlockID = nil
                if store.block(with: blockID, in: documentID)?.carouselItems.isEmpty != false {
                    store.deleteBlock(blockID, in: documentID)
                }
            }
        }
        .sheet(item: $carouselEditRequest) { request in
            ComposerCarouselEditor(documentID: documentID, blockID: request.blockID)
        }
        .sheet(item: $socialEditRequest) { request in
            socialEditor(for: request)
        }
        .onChange(of: pickedMediaItem) { _, item in
            guard let item, let blockID = pendingMediaBlockID else { return }
            pendingMediaBlockID = nil
            Task {
                await importMedia(item, into: blockID)
                pickedMediaItem = nil
            }
        }
        .fullScreenCover(item: $mediaEditRequest) { request in
            mediaEditor(for: request)
        }
        .fullScreenCover(item: $pursuitEditRequest) { request in
            pursuitEditor(for: request)
        }
        .onChange(of: showMediaPicker) { _, isPresented in
            guard !isPresented else { return }
            let blockID = pendingMediaBlockID
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard let blockID, pendingMediaBlockID == blockID, pickedMediaItem == nil else { return }
                pendingMediaBlockID = nil
                if store.block(with: blockID, in: documentID)?.mediaFileName == nil {
                    store.deleteBlock(blockID, in: documentID)
                }
            }
        }
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
                pursuitImageURL: block.pursuitImageFileName.map { store.mediaURL(for: $0) },
                isMediaPaused: !playingMediaIDs.contains(block.id),
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
                },
                onStyleMenuChange: { isOpen in
                    if isOpen {
                        styleMenuBlockID = block.id
                    } else if styleMenuBlockID == block.id {
                        styleMenuBlockID = nil
                    }
                },
                showsMediaMenu: styleMenuBlockID == block.id,
                onOpenMediaMenu: {
                    handleMediaIconTap(block.id)
                },
                onCropMedia: {
                    openMediaFrameEditor(block.id)
                },
                showsPursuitPencil: !chrome.isViewing,
                onEditPursuit: {
                    beginPursuitEdit(block.id)
                },
                allowsCarouselControl: chrome.isViewing || selectedBlockID == block.id,
                onEditCarousel: {
                    beginCarouselEdit(block.id)
                },
                isViewing: chrome.isViewing,
                canvasSize: CGSize(width: canvasSize.width, height: layoutHeight),
                cornerResizing: $socialCornerResizing,
                onSelectTabs: {
                    selectedBlockID = block.id
                    editingBlockID = nil
                    focusedTextBlockID = nil
                },
                onEditSocial: {
                    beginSocialEdit(block.id)
                },
                onUngroup: {
                    ungroup(block.id)
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
                if isTextLikeKind(placingOption.blockKind) || placingOption.blockKind == .pursuit || placingOption.blockKind == .node {
                    placeTextAndBeginEditing(option: placingOption, at: point)
                } else if placingOption.blockKind == .media {
                    placeMedia(at: point)
                } else if placingOption.blockKind == .carousel {
                    placeCarousel(at: point)
                } else {
                    place(option: placingOption, at: point)
                }
                self.placingOption = nil
            }
    }

    private func beginPlacement(for option: BlockMenuOption) {
        guard option != .group else {
            menuExpanded = false
            beginGrouping()
            return
        }
        guard documentID == nil || option != .pursuit else { return }
        guard option != .tabs || !blocks.contains(where: { $0.kind == .tabs }) else { return }
        if option == .banner {
            guard !blocks.contains(where: { $0.kind == .banner }) else { return }
            menuExpanded = false
            let bannerID = store.addBlock(.banner, to: documentID)
            selectedBlockID = bannerID
            pendingMediaBlockID = bannerID
            showMediaPicker = true
            return
        }
        menuExpanded = false
        placingOption = option
        ghostLocation = clamped(
            point: CGPoint(
                x: canvasSize.width * 0.5,
                y: layoutHeight * 0.35
            )
        )
    }

    private func placeMedia(at point: CGPoint) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let position = normalizedPosition(from: point)
        let newID = store.addBlock(.media, at: position, to: documentID)
        pendingMediaBlockID = newID
        showMediaPicker = true
    }

    private func placeCarousel(at point: CGPoint) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let position = normalizedPosition(from: point)
        let newID = store.addBlock(.carousel, at: position, to: documentID)
        pendingCarouselBlockID = newID
        showCarouselPicker = true
    }

    private func importMedia(_ item: PhotosPickerItem, into blockID: ComposerBlockID) async {
        if let fileName = await ComposerMediaImport.save(item, to: store) {
            store.setMedia(fileName, for: blockID, in: documentID)
        } else if store.block(with: blockID, in: documentID)?.kind != .banner {
            store.deleteBlock(blockID, in: documentID)
        }
    }

    private func importCarousel(_ items: [PhotosPickerItem], into blockID: ComposerBlockID) async {
        let placeholders = items.map { _ in CarouselMediaItem(fileName: "") }
        guard var block = store.block(with: blockID, in: documentID) else { return }
        block.carouselItems.append(contentsOf: placeholders)
        store.updateBlock(block, in: documentID)
        selectedBlockID = blockID

        await ComposerMediaImport.importCarouselItems(
            items,
            ids: placeholders.map(\.id),
            store: store
        ) { id, fileName in
            guard var current = store.block(with: blockID, in: documentID) else { return }
            if let fileName, let index = current.carouselItems.firstIndex(where: { $0.id == id }) {
                current.carouselItems[index].fileName = fileName
            } else {
                current.carouselItems.removeAll { $0.id == id }
            }
            store.updateBlock(current, in: documentID)
        }

        guard var finished = store.block(with: blockID, in: documentID) else { return }
        finished.carouselItems.removeAll { $0.fileName.isEmpty }
        if finished.carouselItems.isEmpty {
            store.deleteBlock(blockID, in: documentID)
            return
        }
        store.updateBlock(finished, in: documentID)
        if finished.carouselItems.count < CarouselMotion.minimumCount {
            carouselEditRequest = CarouselEditRequest(blockID: blockID)
        }
    }

    private func place(option: BlockMenuOption, at point: CGPoint) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let position = normalizedPosition(from: point)
        let newID = store.addBlock(option.blockKind, at: position, to: documentID)
        if option.blockKind == .link {
            editingBlockID = newID
        } else if option.blockKind == .social {
            selectedBlockID = newID
            socialEditRequest = SocialEditRequest(blockID: newID)
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
        if let finishedID, blocks.contains(where: { $0.id == finishedID && (isTextLikeKind($0.kind) || $0.kind == .pursuit || $0.kind == .node) }) {
            selectedBlockID = finishedID
        }
    }

    private func dismissBlockInteraction() {
        editingBlockID = nil
        selectedBlockID = nil
        focusedTextBlockID = nil
        styleMenuBlockID = nil
        textDragSession.reset()
    }

    private func handleMediaIconTap(_ blockID: ComposerBlockID) {
        textDragSession.didHandleMediaIconTap = true
        selectedBlockID = blockID
        styleMenuBlockID = styleMenuBlockID == blockID ? nil : blockID
    }

    private func textPressGesture(for block: ComposerBlock) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("composerRoot"))
            .updating($textDragVisual) { value, visual, _ in
                if isGrouping {
                    visual = .inactive
                    return
                }
                let session = textDragSession
                if session.isPinching {
                    visual = .inactive
                    return
                }
                if session.blockID != block.id {
                    if touchHitsTextStyleIcon(block.id, at: value.startLocation) {
                        visual = .inactive
                        return
                    }
                    if touchHitsGraphResize(block.id, at: value.startLocation) || touchHitsSocialCorner(block.id, at: value.startLocation) {
                        session.graphResizing = true
                        session.blockID = block.id
                        visual = .inactive
                        return
                    }
                    session.blockID = block.id
                    session.started = Date()
                    session.baseline = nil
                    session.didHaptic = false
                    session.menuWasOpen = styleMenuBlockID == block.id
                    session.didHandleMediaIconTap = false
                    session.carouselPan = false
                }

                if session.graphResizing {
                    visual = .inactive
                    return
                }

                let elapsed = Date().timeIntervalSince(session.started)
                let horizontal = abs(value.translation.width) > 8 && abs(value.translation.width) > abs(value.translation.height) * 1.1
                if block.kind == .carousel, selectedBlockID == block.id, session.baseline == nil,
                   session.carouselPan || (horizontal && elapsed < 0.32) {
                    session.carouselPan = true
                    visual = .inactive
                    session.lastTranslation = .zero
                    session.hoveringTrash = false
                    return
                }

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
                    next.hoveringTrash = trashDropZoneFrame.width > 1
                        && trashDropZoneFrame.insetBy(dx: 12, dy: 12).contains(value.location)
                    session.lastTranslation = next.translation
                    session.hoveringTrash = next.hoveringTrash
                }

                visual = next
            }
            .onEnded { value in
                if isGrouping {
                    let distance = hypot(value.translation.width, value.translation.height)
                    if distance < 12 {
                        toggleGroupSelection(block.id)
                    }
                    textDragSession.reset()
                    return
                }
                if touchHitsTextStyleIcon(block.id, at: value.startLocation) || textDragSession.graphResizing || touchHitsGraphResize(block.id, at: value.startLocation) || touchHitsSocialCorner(block.id, at: value.startLocation) {
                    textDragSession.reset()
                    return
                }
                if textDragSession.carouselPan {
                    textDragSession.reset()
                    selectedBlockID = block.id
                    return
                }
                let elapsed = Date().timeIntervalSince(textDragSession.started)
                let distance = hypot(value.translation.width, value.translation.height)
                let didMove = textDragSession.baseline != nil && !textDragSession.isPinching
                let translation = textDragSession.lastTranslation
                let shouldDelete = textDragSession.hoveringTrash
                let iconAlreadyHandled = textDragSession.didHandleMediaIconTap
                let tappedPencil = pencilFrames[block.id].map { frame in
                    frame.width > 1 && frame.insetBy(dx: -12, dy: -12).contains(value.location)
                } ?? false
                textDragSession.lastEnded = Date()
                textDragSession.reset()

                if didMove {
                    editingBlockID = nil
                    focusedTextBlockID = nil
                    styleMenuBlockID = nil
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
                } else if distance < 12, elapsed < 0.32, isFolder(block.kind), editingBlockID != block.id, tappedPencil {
                    beginPursuitEdit(block.id)
                } else if distance < 12, elapsed < 0.32, isFolder(block.kind), editingBlockID != block.id, !iconAlreadyHandled {
                    openPursuit(block)
                } else if distance < 12, elapsed < 0.32, isTextLikeKind(block.kind), editingBlockID != block.id {
                    beginTextEditing(block.id)
                } else if distance < 12, elapsed < 0.32, block.kind == .media, !iconAlreadyHandled {
                    if selectedBlockID != block.id {
                        selectedBlockID = block.id
                    } else if styleMenuBlockID != block.id {
                        toggleMediaPlayback(block.id)
                    }
                } else if distance < 12, elapsed < 0.32, block.kind == .carousel, !iconAlreadyHandled {
                    selectedBlockID = block.id
                    styleMenuBlockID = nil
                } else if distance < 12, elapsed < 0.32, block.kind == .tabs || block.kind == .table {
                    selectedBlockID = block.id
                } else if distance < 12, elapsed < 0.32, block.kind == .social, tappedPencil {
                    beginSocialEdit(block.id)
                } else if distance < 12, elapsed < 0.32, block.kind == .social {
                    if selectedBlockID != block.id {
                        selectedBlockID = block.id
                    } else if ComposerSocialPlatform(rawValue: block.socialPlatform)?
                        .profileURL(from: block.linkURL ?? "") == nil {
                        beginSocialEdit(block.id)
                    } else {
                        openSocialLink(block)
                    }
                }
            }
    }

    private func textPinchGesture(for block: ComposerBlock) -> some Gesture {
        MagnificationGesture()
            .updating($textPinchVisual) { value, visual, _ in
                guard selectedBlockID == block.id else { return }
                textDragSession.isPinching = true
                textDragSession.baseline = nil
                visual = TextPinchVisual(blockID: block.id, scale: value)
            }
            .onEnded { value in
                textDragSession.isPinching = false
                textDragSession.baseline = nil
                guard selectedBlockID == block.id, var current = store.block(with: block.id, in: documentID) else { return }
                if current.kind == .graph {
                    let width = current.graphWidthScale * current.style.scale * Double(value)
                    let height = current.graphHeightScale * current.style.scale * Double(value)
                    current.graphWidthScale = ComposerGraphStretch.clamped(width)
                    current.graphHeightScale = ComposerGraphStretch.clamped(height)
                    current.style.scale = 1
                } else if current.kind == .media || current.kind == .pursuit || current.kind == .node || current.kind == .carousel || current.kind == .calendar || current.kind == .tabs || current.kind == .group {
                    let next = current.style.scale * Double(value)
                    current.style.scale = min(max(next, 0.45), 3.2)
                } else {
                    let next = current.style.fontSize * current.style.scale * Double(value)
                    current.style.fontSize = min(max(next, 12), 80)
                    current.style.scale = 1
                }
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
        kind == .text || kind == .heading || kind == .list
    }

    @ViewBuilder
    private func mediaEditor(for request: MediaEditRequest) -> some View {
        switch request {
        case .crop(let blockID):
            if let url = store.block(with: blockID, in: documentID)?.mediaFileName.map({ store.mediaURL(for: $0) }),
               let image = UIImage(contentsOfFile: url.path) {
                ComposerImageCropEditor(image: image) {
                    mediaEditRequest = nil
                } onChoose: { cropped in
                    if let data = cropped.jpegData(compressionQuality: 0.9),
                       let fileName = try? store.saveMediaData(data) {
                        store.setMedia(fileName, for: blockID, in: documentID)
                    }
                    mediaEditRequest = nil
                }
            }
        case .trim(let blockID, let url):
            ComposerVideoTrimEditor(url: url) {
                mediaEditRequest = nil
            } onSave: { editedURL in
                if let fileName = try? store.saveMediaFile(from: editedURL) {
                    store.setMedia(fileName, for: blockID, in: documentID)
                }
                mediaEditRequest = nil
            }
            .ignoresSafeArea()
        case .trimUnavailable:
            VStack(spacing: 12) {
                Text("This video can’t be trimmed on this device.")
                    .foregroundStyle(.white)
                Button("Close") { mediaEditRequest = nil }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        case .shape(let blockID):
            if let block = store.block(with: blockID, in: documentID),
               let fileName = block.mediaFileName {
                ComposerMediaFrameEditor(
                    mediaURL: store.mediaURL(for: fileName),
                    isVideo: composerMediaIsVideo(store.mediaURL(for: fileName)),
                    initialShape: block.mediaShape,
                    initialZoom: block.mediaZoom,
                    initialPanX: block.mediaPanX,
                    initialPanY: block.mediaPanY,
                    initialFrameAspect: block.mediaFrameAspect,
                    onCancel: { mediaEditRequest = nil },
                    onDone: { shape, zoom, panX, panY, frameAspect in
                        guard var current = store.block(with: blockID, in: documentID) else {
                            mediaEditRequest = nil
                            return
                        }
                        current.mediaShape = shape
                        current.mediaZoom = zoom
                        current.mediaPanX = panX
                        current.mediaPanY = panY
                        current.mediaFrameAspect = frameAspect
                        current.mediaWarp = nil
                        store.updateBlock(current, in: documentID)
                        mediaEditRequest = nil
                    },
                    onReplaceVideo: { editedURL in
                        guard let fileName = try? store.saveMediaFile(from: editedURL) else { return nil }
                        store.setMedia(fileName, for: blockID, in: documentID)
                        return store.mediaURL(for: fileName)
                    }
                )
            }
        }
    }

    private func openMediaFrameEditor(_ blockID: ComposerBlockID) {
        playingMediaIDs.remove(blockID)
        styleMenuBlockID = nil
        selectedBlockID = blockID
        mediaEditRequest = .shape(blockID)
    }

    private func claimsCanvasTouches(for block: ComposerBlock) -> Bool {
        if block.kind == .calendar || block.kind == .graph || block.kind == .tabs || block.kind == .table { return false }
        return selectedBlockID != block.id
    }

    private func touchHitsGraphResize(_ blockID: ComposerBlockID, at point: CGPoint) -> Bool {
        graphResizeFrames[blockID]?.contains(point) ?? false
    }

    private func touchHitsSocialCorner(_ blockID: ComposerBlockID, at point: CGPoint) -> Bool {
        socialCornerFrames[blockID]?.contains(point) ?? false
    }

    private func touchHitsTextStyleIcon(_ blockID: ComposerBlockID, at point: CGPoint) -> Bool {
        guard let frame = textStyleIconFrames[blockID], frame.width > 1 else { return false }
        return frame.insetBy(dx: -12, dy: -12).contains(point)
    }

    private func beginVideoTrim(_ blockID: ComposerBlockID) {
        guard let fileName = store.block(with: blockID, in: documentID)?.mediaFileName else { return }
        let sourceURL = store.mediaURL(for: fileName)
        playingMediaIDs.remove(blockID)
        Task {
            if let editableURL = await ComposerVideoCompatibility.editableURL(for: sourceURL) {
                mediaEditRequest = .trim(blockID, editableURL)
            } else {
                mediaEditRequest = .trimUnavailable
            }
        }
    }

    private func toggleMediaPlayback(_ blockID: ComposerBlockID) {
        if playingMediaIDs.contains(blockID) {
            playingMediaIDs.remove(blockID)
        } else {
            playingMediaIDs.insert(blockID)
        }
    }

    private func supportsCanvasGestures(_ kind: BlockKind) -> Bool {
        isTextLikeKind(kind) || kind == .media || isFolder(kind) || kind == .carousel || kind == .calendar || kind == .graph || kind == .tabs || kind == .table || kind == .social || kind == .group
    }

    private func beginCarouselEdit(_ blockID: ComposerBlockID) {
        textDragSession.didHandleMediaIconTap = true
        selectedBlockID = blockID
        styleMenuBlockID = nil
        playingMediaIDs.remove(blockID)
        carouselEditRequest = CarouselEditRequest(blockID: blockID)
    }

    private func handleViewingTap(on block: ComposerBlock) {
        if block.kind == .media {
            toggleMediaPlayback(block.id)
        } else if isFolder(block.kind) {
            openPursuit(block)
        } else if block.kind == .social {
            openSocialLink(block)
        }
    }

    private func beginSocialEdit(_ blockID: ComposerBlockID) {
        selectedBlockID = blockID
        socialEditRequest = SocialEditRequest(blockID: blockID)
    }

    private func openSocialLink(_ block: ComposerBlock) {
        guard let platform = ComposerSocialPlatform(rawValue: block.socialPlatform),
              let url = platform.profileURL(from: block.linkURL ?? "") else { return }
        openURL(url)
    }

    @ViewBuilder
    private func socialEditor(for request: SocialEditRequest) -> some View {
        let block = store.block(with: request.blockID, in: documentID)
        ComposerSocialEditor(
            platform: ComposerSocialPlatform(rawValue: block?.socialPlatform ?? "") ?? .instagram,
            link: block?.linkURL ?? "",
            onCancel: { socialEditRequest = nil },
            onSave: { platform, link in
                guard var current = store.block(with: request.blockID, in: documentID) else {
                    socialEditRequest = nil
                    return
                }
                current.socialPlatform = platform.rawValue
                current.linkURL = link
                store.updateBlock(current, in: documentID)
                socialEditRequest = nil
            }
        )
    }

    private func beginPursuitEdit(_ blockID: ComposerBlockID) {
        styleMenuBlockID = nil
        editingBlockID = nil
        focusedTextBlockID = nil
        pursuitEditRequest = PursuitEditRequest(blockID: blockID)
    }

    @ViewBuilder
    private func pursuitEditor(for request: PursuitEditRequest) -> some View {
        if let block = store.block(with: request.blockID, in: documentID) {
            PursuitWidgetEditor(
                name: block.text,
                layout: block.pursuitLayout,
                textX: block.pursuitTextX,
                textY: block.pursuitTextY,
                texts: block.pursuitTexts,
                style: block.style,
                fill: block.pursuitFill,
                image: block.pursuitImageFileName.flatMap { UIImage(contentsOfFile: store.mediaURL(for: $0).path) },
                imageZoom: block.pursuitImageZoom,
                imagePanX: block.pursuitImagePanX,
                imagePanY: block.pursuitImagePanY,
                screenTitle: block.kind == .node ? "Edit Node" : "Edit Pursuit",
                namePlaceholder: block.kind == .node ? "Node" : "Pursuit",
                onCancel: { pursuitEditRequest = nil },
                onDone: { edits in
                    applyPursuitEdits(edits, to: request.blockID)
                    pursuitEditRequest = nil
                }
            )
        }
    }

    private func applyPursuitEdits(_ edits: PursuitWidgetEdits, to blockID: ComposerBlockID) {
        guard var block = store.block(with: blockID, in: documentID) else { return }
        let scale = block.style.scale
        block.text = edits.name
        block.style = edits.nameStyle
        block.style.scale = scale
        block.pursuitTextX = edits.textX
        block.pursuitTextY = edits.textY
        block.pursuitLayout = edits.layout
        block.pursuitTexts = edits.texts
        block.pursuitImageZoom = edits.imageZoom
        block.pursuitImagePanX = edits.imagePanX
        block.pursuitImagePanY = edits.imagePanY
        if edits.removeImage {
            block.pursuitImageFileName = nil
        }
        if let imageData = edits.imageData, let fileName = try? store.saveMediaData(imageData) {
            block.pursuitImageFileName = fileName
        }
        store.updateBlock(block, in: documentID)
    }

    private func isFolder(_ kind: BlockKind) -> Bool {
        kind == .pursuit || kind == .node
    }

    private func openPursuit(_ block: ComposerBlock) {
        guard let pursuitID = block.pursuitID else { return }
        editingBlockID = nil
        focusedTextBlockID = nil
        styleMenuBlockID = nil
        openedPursuitID = pursuitID
    }

    private func liveOffset(for block: ComposerBlock) -> CGSize {
        var base = anchorOffset(for: block.position)
        if socialChromeInset(for: block) > 0 {
            base.width -= SocialLogoChrome.margin
            base.height -= SocialLogoChrome.margin
        }
        guard textDragVisual.blockID == block.id, textDragVisual.isMoving else { return base }
        return CGSize(
            width: base.width + textDragVisual.translation.width,
            height: base.height + textDragVisual.translation.height
        )
    }

    /// Selected logos add touch room around the mark. The offset keeps the mark on its saved spot.
    private func socialChromeInset(for block: ComposerBlock) -> CGFloat {
        guard block.kind == .social,
              selectedBlockID == block.id,
              !chrome.isViewing,
              !(textDragVisual.blockID == block.id && (textDragVisual.lifted || textDragVisual.isMoving))
        else { return 0 }
        return SocialLogoChrome.margin
    }

    private func anchorOffset(for position: BlockPosition) -> CGSize {
        let point = canvasPoint(for: position)
        return CGSize(width: point.x, height: point.y)
    }

    private func canvasPoint(for position: BlockPosition) -> CGPoint {
        CGPoint(
            x: canvasSize.width * position.x,
            y: layoutHeight * position.y
        )
    }

    private func normalizedPosition(from point: CGPoint) -> BlockPosition {
        let width = max(canvasSize.width, 1)
        let scale = max(layoutHeight, 1)
        let maxY = max(Double(canvasHeight / scale), 1)
        return BlockPosition(
            x: Double(min(max(point.x / width, 0), 1)),
            y: Double(min(max(point.y / scale, 0), maxY))
        )
    }

    private func clamped(point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 28), max(canvasSize.width - 28, 28)),
            y: min(max(point.y, 28), max(canvasHeight - 28, 28))
        )
    }

    private func lockLayoutHeightIfNeeded() {
        guard store.layoutHeight(for: documentID) == nil else { return }
        store.lockLayoutHeight(Double(proposedLayoutHeight), for: documentID)
    }

    private var undoButton: some View {
        let enabled = store.canUndo(in: documentID)
        return Button {
            store.undo(in: documentID)
            if let selectedBlockID, store.block(with: selectedBlockID, in: documentID) == nil {
                self.selectedBlockID = nil
            }
            editingBlockID = nil
            focusedTextBlockID = nil
            styleMenuBlockID = nil
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(MosaicBrand.inkBlack, in: Circle())
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("Undo")
        .accessibilityIdentifier("composer.undo")
    }

    private var groupingBar: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                isGrouping = false
                groupSelection = []
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            Spacer()
            Text("\(groupSelection.count) selected")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            Button("Group") {
                finishGrouping()
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(groupSelection.count >= 2 ? .white : .white.opacity(0.35))
            .disabled(groupSelection.count < 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Capsule())
        .accessibilityIdentifier("composer.group.bar")
    }

    private func blockOpacity(for block: ComposerBlock) -> Double {
        if isGrouping, block.kind != .banner {
            return groupSelection.contains(block.id) ? 1 : 0.35
        }
        if textDragVisual.blockID == block.id, textDragVisual.isMoving {
            return 0.96
        }
        return 1
    }

    private func beginGrouping() {
        editingBlockID = nil
        focusedTextBlockID = nil
        styleMenuBlockID = nil
        selectedBlockID = nil
        groupSelection = []
        isGrouping = true
    }

    private func toggleGroupSelection(_ blockID: ComposerBlockID) {
        guard store.block(with: blockID, in: documentID)?.kind != .banner else { return }
        if groupSelection.contains(blockID) {
            groupSelection.remove(blockID)
        } else {
            groupSelection.insert(blockID)
        }
    }

    private func finishGrouping() {
        let members = blocks.filter { groupSelection.contains($0.id) && $0.kind != .banner }
        let tabID = blocks.first(where: { $0.kind == .tabs })?.selectedTabID
        guard let group = ComposerGroupMath.groupedBlock(
            members: members,
            frames: blockFrames,
            canvasWidth: canvasSize.width,
            layoutHeight: layoutHeight,
            tabID: tabID
        ) else { return }
        var next = blocks
        next.removeAll { groupSelection.contains($0.id) }
        next.append(group)
        store.replacePage(next, in: documentID)
        isGrouping = false
        groupSelection = []
        selectedBlockID = group.id
    }

    private func ungroup(_ blockID: ComposerBlockID) {
        guard let group = store.block(with: blockID, in: documentID), group.kind == .group else { return }
        let restored = ComposerGroupMath.ungroupedMembers(
            of: group,
            canvasWidth: max(canvasSize.width, 1),
            layoutHeight: layoutHeight
        )
        var next = blocks
        next.removeAll { $0.id == blockID }
        next.append(contentsOf: restored)
        store.replacePage(next, in: documentID)
        selectedBlockID = restored.first?.id
    }

    private var viewEyeButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.28)) {
                chrome.isViewing.toggle()
            }
        } label: {
            Image(systemName: "eye")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(MosaicBrand.inkBlack, in: Circle())
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                .opacity(chrome.isViewing ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chrome.isViewing ? "Exit view" : "View Mosaic")
        .accessibilityIdentifier("composer.viewMode")
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

private func composerMediaIsVideo(_ url: URL) -> Bool {
    ["mov", "mp4", "m4v", "avi"].contains(url.pathExtension.lowercased())
}

private struct PursuitEditRequest: Identifiable {
    let blockID: ComposerBlockID
    var id: String { blockID.rawValue }
}

private struct CarouselEditRequest: Identifiable {
    let blockID: ComposerBlockID
    var id: String { blockID.rawValue }
}

private struct SocialEditRequest: Identifiable {
    let blockID: ComposerBlockID
    var id: String { blockID.rawValue }
}

private enum MediaEditRequest: Identifiable {
    case crop(ComposerBlockID)
    case trim(ComposerBlockID, URL)
    case trimUnavailable
    case shape(ComposerBlockID)

    var id: String {
        switch self {
        case .crop(let blockID): "crop-\(blockID.rawValue)"
        case .trim(let blockID, _): "trim-\(blockID.rawValue)"
        case .trimUnavailable: "trim-unavailable"
        case .shape(let blockID): "shape-\(blockID.rawValue)"
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
    var menuWasOpen = false
    var didHandleMediaIconTap = false
    var carouselPan = false
    var graphResizing = false
    var lastEnded = Date.distantPast

    func reset() {
        blockID = nil
        started = Date()
        baseline = nil
        lastTranslation = .zero
        hoveringTrash = false
        didHaptic = false
        isPinching = false
        menuWasOpen = false
        didHandleMediaIconTap = false
        carouselPan = false
        graphResizing = false
    }
}

private struct TextPinchVisual: Equatable {
    var blockID: ComposerBlockID?
    var scale: CGFloat

    static let inactive = TextPinchVisual(blockID: nil, scale: 1)
}

private struct ViewingMediaTapModifier: ViewModifier {
    var isEnabled: Bool
    var onTap: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.highPriorityGesture(TapGesture().onEnded { onTap() })
        } else {
            content
        }
    }
}

private struct RelocateGestureModifier<Drag: Gesture, Pinch: Gesture>: ViewModifier {
    let isEnabled: Bool
    let claimsTouches: Bool
    var pinchPriority: Bool = false
    var pinchEnabled: Bool = true
    let gesture: Drag
    let pinch: Pinch

    func body(content: Content) -> some View {
        if !isEnabled {
            content
        } else if !pinchEnabled {
            if claimsTouches {
                content.highPriorityGesture(gesture)
            } else {
                content.simultaneousGesture(gesture)
            }
        } else if claimsTouches {
            content
                .highPriorityGesture(gesture)
                .simultaneousGesture(pinch)
        } else if pinchPriority {
            content
                .simultaneousGesture(gesture)
                .highPriorityGesture(pinch)
        } else {
            content
                .simultaneousGesture(gesture)
                .simultaneousGesture(pinch)
        }
    }
}

/// Keeps the composer page at its normal scale. Pinching a block must not zoom the scroll view.
private struct ComposerCanvasZoomLock: UIViewRepresentable {
    func makeUIView(context: Context) -> ComposerCanvasZoomLockView {
        let view = ComposerCanvasZoomLockView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: ComposerCanvasZoomLockView, context: Context) {
        uiView.lockEnclosingScrollView()
    }
}

private final class ComposerCanvasZoomLockView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        lockEnclosingScrollView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        lockEnclosingScrollView()
    }

    func lockEnclosingScrollView() {
        var current: UIView? = superview
        while let view = current {
            if let scrollView = view as? UIScrollView {
                scrollView.minimumZoomScale = 1
                scrollView.maximumZoomScale = 1
                scrollView.bouncesZoom = false
                scrollView.alwaysBounceHorizontal = false
                scrollView.showsHorizontalScrollIndicator = false
                scrollView.isDirectionalLockEnabled = true
                if let systemPinch = scrollView.pinchGestureRecognizer,
                   systemPinch.name != "mosaic.table.pinch" {
                    systemPinch.isEnabled = false
                }
                if scrollView.zoomScale != 1 {
                    scrollView.setZoomScale(1, animated: false)
                }
                if scrollView.contentOffset.x != 0 {
                    scrollView.contentOffset.x = 0
                }
                return
            }
            current = view.superview
        }
    }
}

#Preview("Mosaic") {
    MosaicTabShell(persistToDisk: false)
}

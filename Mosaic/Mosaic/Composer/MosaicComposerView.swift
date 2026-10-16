import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MosaicComposerView: View {
    let documentID: ComposerDocumentID?
    var isBookPage = false

    @Environment(ComposerStore.self) private var store
    @Environment(MosaicChrome.self) private var chrome
    @Environment(MosaicVisit.self) private var visit: MosaicVisit?
    @Environment(\.composerMediaWaiting) private var ownerMediaWaiting
    @Environment(MosaicPursuitPrivacy.self) private var pursuitPrivacy: MosaicPursuitPrivacy?
    @Environment(\.mosaicAccount) private var account
    @Environment(\.mosaicTabBarHidden) private var mosaicTabBarHidden
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var visitMediaAttempt = 0
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
    @State private var pickedMediaItems: [PhotosPickerItem] = []
    @State private var mediaPickLimit = 1
    @State private var pendingMediaBlockID: ComposerBlockID?
    @State private var pendingMediaOrigin: CGPoint?
    @State private var playingMediaIDs: Set<ComposerBlockID> = []
    @State private var focusedMedia: FocusedComposerMedia?
    @State private var mediaEditRequest: MediaEditRequest?
    @State private var styleMenuBlockID: ComposerBlockID?
    @State private var viewportWidth: CGFloat = 0
    @State private var openedPursuitID: ComposerDocumentID?
    @State private var openScrapbookID: ComposerBlockID?
    @State private var pencilFrames: [ComposerBlockID: CGRect] = [:]
    @State private var textStyleIconFrames: [ComposerBlockID: CGRect] = [:]
    @State private var resizeCornerFrames: [ComposerBlockID: ComposerResizeCornerFrames] = [:]
    @State private var mediaChromeFrames: [ComposerBlockID: ComposerMediaChromeFrames] = [:]
    @State private var resizePreview: ComposerResizePreview?
    @State private var socialCornerFrames: [ComposerBlockID: ComposerSocialCornerFrames] = [:]
    @State private var socialCornerResizing = false
    @State private var isGrouping = false
    @State private var groupSelection: Set<ComposerBlockID> = []
    @State private var blockFrames: [ComposerBlockID: CGRect] = [:]
    @State private var pursuitEditRequest: PursuitEditRequest?
    @State private var carouselEditRequest: CarouselEditRequest?
    @State private var editedCarouselID: ComposerBlockID?
    @State private var socialEditRequest: SocialEditRequest?
    @State private var contentEditBlockID: ComposerBlockID?
    @State private var showsBackgroundEditor = false
    @State private var dragScrollRelay = ComposerDragScrollRelay()
    @State private var composerSpace = UUID().uuidString
    @State private var canvasScrollPosition = ScrollPosition()
    @State private var scrollBubbleRail = ComposerScrollBubbleRail()
    @State private var clipboardMenuBlockID: ComposerBlockID?
    @State private var pasteAnchor: CGPoint?
    @State private var clipboardPressTask: Task<Void, Never>?
    @State private var showsSettings = false
    @State private var profileRefresh = 0

    private var blocks: [ComposerBlock] {
        store.blocks(for: documentID)
    }

    private var visibleBlocks: [ComposerBlock] {
        guard let tabs = blocks.first(where: { $0.kind == .tabs }),
              let selected = tabs.selectedTabID else { return blocks }
        return blocks.filter { $0.kind == .tabs || $0.kind == .banner || $0.tabID == selected }
    }

    private var scrollingBlocks: [ComposerBlock] {
        let display = privacyDisplay
        return visibleBlocks.filter { $0.kind != .banner && display.look(of: $0) != .removed }
    }

    /// Only the owner's own boards show privacy, once the levels have loaded.
    private var privacyDisplay: MosaicPrivacyDisplay {
        guard !chrome.isVisiting, account != nil, let pursuitPrivacy, pursuitPrivacy.isLoaded else {
            return MosaicPrivacyDisplay()
        }
        let mode: MosaicPrivacyDisplay.Mode = !chrome.isViewing ? .badges : (chrome.viewAs == .user ? .visitor : .off)
        return MosaicPrivacyDisplay(mode: mode, levels: pursuitPrivacy.levels)
    }

    private var showsViewAs: Bool {
        chrome.isViewing && !chrome.isVisiting && documentID == nil && account != nil
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            // Sits over the board's content, so it is frosted glass rather than solid.
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: ComposerAddMenuMetrics.topControl, height: ComposerAddMenuMetrics.topControl)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
                .environment(\.colorScheme, .dark)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var settingsButton: some View {
        Button {
            showsSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: ComposerAddMenuMetrics.button, height: ComposerAddMenuMetrics.button)
                .background(MosaicBrand.inkBlack, in: Circle())
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("composer.settings")
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
                presentMediaLibrary(for: block.id, origin: nil, limit: 1)
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
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                presentClipboardMenu(for: block.id)
            }
        )
        .overlay(alignment: .top) {
            if clipboardMenuBlockID == block.id {
                clipboardActionMenu(for: block.id)
                    .padding(.top, 12)
            }
        }
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
    /// A journal page keeps a fixed paper length: it scrolls, but its top and bottom are hard edges.
    private var canvasHeight: CGFloat {
        if isBookPage { return layoutHeight }
        return max(grownCanvasHeight, neededCanvasHeight)
    }

    /// Height items are held inside. Zero means the board has no bottom edge.
    private var pageViewportHeight: CGFloat {
        isBookPage ? layoutHeight : 0
    }

    var body: some View {
        Group {
            if store.isWaitingForDocument(documentID) {
                VStack(spacing: 16) {
                    ProgressView().tint(.white)
                    Text("This board is still downloading.")
                    Button("Back to Mosaic") { dismiss() }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MosaicBrand.inkBlack)
                .accessibilityIdentifier("pursuit.loading")
            } else {
                measuredComposer
            }
        }
            .toolbar((mosaicTabBarHidden || openScrapbookID != nil) ? .hidden : .visible, for: .tabBar)
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
                // Destinations take the stack's environment, which is the owner's during a visit.
                MosaicComposerView(documentID: pursuitID)
                    .environment(store)
                    .environment(chrome)
                    .environment(visit)
            }
            .fullScreenCover(isPresented: $showsSettings, onDismiss: { profileRefresh += 1 }) {
                if let account {
                    MosaicSettingsView(account: account, store: store)
                }
            }
            .accessibilityIdentifier(documentID == nil ? "mosaic.screen" : "pursuit.screen")
            .environment(\.mosaicPrivacyDisplay, privacyDisplay)
            .task(id: chrome.isViewing) {
                guard documentID == nil, !chrome.isVisiting, let account, let pursuitPrivacy else { return }
                await pursuitPrivacy.refresh(account: account)
            }
            .environment(\.composerPaperPage, isBookPage)
            .environment(\.composerMediaVersions, store.mediaVersions)
            .environment(\.composerMediaWaiting, visit?.media?.waiting(for: documentID) ?? ownerMediaWaiting)
            .preference(key: ComposerGroupingPreferenceKey.self, value: isGrouping)
            .task(id: documentID) {
                visit?.recordVisit(to: documentID.flatMap(ComposerBoardSync.uuid))
            }
            .task(id: visitMediaAttempt) {
                guard let media = visit?.media else { return }
                guard let token = await account?.accessToken() else {
                    if !Task.isCancelled { media.needsRetry(documentID: documentID) }
                    return
                }
                await media.load(documentID: documentID, store: store, token: token)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let media = visit?.media {
                    let id = media.boardID(documentID)
                    if !media.loading.contains(id), media.failed.contains(id) {
                        HStack {
                            Text("Some media couldn’t load.").font(.caption)
                            Button("Retry") { visitMediaAttempt += 1 }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                    }
                }
            }
    }

    private var measuredComposer: some View {
        composerBody
            .coordinateSpace(name: composerSpace)
            .environment(\.composerCoordinateSpace, composerSpace)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                viewportWidth = width
            }
            .environment(\.composerViewportWidth, viewportWidth)
            .onPreferenceChange(ComposerPencilFrameKey.self) { pencilFrames = $0 }
            .onPreferenceChange(ComposerTextStyleIconFrameKey.self) { textStyleIconFrames = $0 }
            .onPreferenceChange(ComposerResizeCornerFrameKey.self) { resizeCornerFrames = $0 }
            .onPreferenceChange(ComposerMediaChromeFrameKey.self) { mediaChromeFrames = $0 }
            .onPreferenceChange(ComposerSocialCornerFrameKey.self) { socialCornerFrames = $0 }
            .onPreferenceChange(ComposerBlockFrameKey.self) { frames in
                let next = frames.mapValues { $0.integral }
                guard next != blockFrames else { return }
                blockFrames = next
                if isBookPage {
                    keepBlocksInsidePage(using: next)
                }
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
            .background {
                ComposerBoardBackdrop(
                    background: store.boardBackground(for: documentID),
                    mediaURL: store.boardBackground(for: documentID)?.mediaFileName.map { store.mediaURL(for: $0) },
                    fallback: isBookPage ? ScrapbookColors.paper : MosaicBrand.inkBlack
                )
                .ignoresSafeArea()
            }
            .preference(key: ComposerMediaObscuredKey.self, value: focusedMedia != nil)
            .background {
                if documentID != nil || chrome.isVisiting, !isBookPage {
                    ComposerBackSwipe(isEnabled: focusedMedia == nil && openScrapbookID == nil)
                }
            }
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
    }

    private var composerBody: some View {
        coveredBoard
            .photosPicker(
                isPresented: $showMediaPicker,
                selection: $pickedMediaItems,
                maxSelectionCount: mediaPickLimit,
                matching: .any(of: [.images, .videos])
            )
            .sheet(item: $carouselEditRequest, onDismiss: removeCarouselIfEmpty) { request in
                ComposerCarouselEditor(documentID: documentID, blockID: request.blockID)
            }
            .sheet(item: $socialEditRequest) { request in
                socialEditor(for: request)
            }
            .onChange(of: pickedMediaItems) { _, items in
                guard !items.isEmpty, let blockID = pendingMediaBlockID else { return }
                let chosen = items
                let origin = pendingMediaOrigin
                pendingMediaBlockID = nil
                pendingMediaOrigin = nil
                pickedMediaItems = []
                Task {
                    await importPlacedMedia(chosen, firstBlockID: blockID, origin: origin)
                }
            }
            .fullScreenCover(item: $mediaEditRequest) { request in
                mediaEditor(for: request)
            }
        .fullScreenCover(item: $pursuitEditRequest) { request in
            pursuitEditor(for: request)
        }
        .sheet(isPresented: $showsBackgroundEditor) {
            ComposerBackgroundEditor(
                documentID: documentID,
                starting: store.boardBackground(for: documentID),
                fallback: isBookPage
                    ? ComposerRGBColor(red: 0.976, green: 0.957, blue: 0.914)
                    : ComposerRGBColor(red: 0, green: 0, blue: 0),
                mediaURL: { store.mediaURL(for: $0) },
                saveImage: { try store.saveMediaData($0) },
                onChange: { store.setBoardBackground($0, for: documentID) },
                onClose: { showsBackgroundEditor = false }
            )
        }
            .onChange(of: showMediaPicker) { _, isPresented in
                guard !isPresented else { return }
                let blockID = pendingMediaBlockID
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let blockID, pendingMediaBlockID == blockID, pickedMediaItems.isEmpty else { return }
                    pendingMediaBlockID = nil
                    if store.block(with: blockID, in: documentID)?.mediaFileName == nil {
                        store.deleteBlock(blockID, in: documentID)
                    }
                }
            }
    }

    private var coveredBoard: some View {
        boardColumn
            .overlay(alignment: .bottomLeading) {
                if focusedMedia == nil, openScrapbookID == nil {
                    HStack(alignment: .bottom, spacing: 12) {
                        // Back lives top-leading on Mosaic / Pursuit; journal pages keep undo here only.
                        if !isBookPage, account != nil, !chrome.isViewing, !isGrouping {
                            settingsButton
                        }
                        // Journal keeps undo here in edit mode; Mosaic / Pursuit keep it beside settings.
                        if !chrome.isViewing, !isGrouping {
                            undoButton
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 20)
                }
            }
            .overlay(alignment: .topLeading) {
                if documentID != nil || chrome.isVisiting, !isBookPage, focusedMedia == nil, openScrapbookID == nil {
                    // The 44pt tap area centers the circle 12pt down, level with the scroll bubble's top.
                    backButton
                        .padding(.leading, 8)
                        .padding(.top, 6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if visit != nil, !isBookPage, focusedMedia == nil, openScrapbookID == nil,
                   let pursuitID = documentID.flatMap(ComposerBoardSync.uuid) {
                    MosaicVisitPursuitControls(pursuitID: pursuitID)
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                }
            }
            .overlay {
                if let openScrapbookID {
                    ScrapbookBookView(parentDocumentID: documentID, blockID: openScrapbookID) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                            self.openScrapbookID = nil
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.88), value: openScrapbookID)
            .overlay {
                if let focusedMedia {
                    ComposerMediaLightbox(url: focusedMedia.url, crop: focusedMedia.crop) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                            self.focusedMedia = nil
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.88), value: focusedMedia?.id)
            .onChange(of: chrome.isViewing) { _, viewing in
                if !viewing {
                    focusedMedia = nil
                }
            }
    }

    private var boardColumn: some View {
        VStack(spacing: 0) {
            if let banner = blocks.first(where: { $0.kind == .banner }) {
                bannerHeader(banner)
            }
            ZStack(alignment: .bottomTrailing) {
                canvasScroll
                ComposerDragScrollDriver(relay: dragScrollRelay, onOffset: { y in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        canvasScrollPosition.scrollTo(y: y)
                    }
                }) {
                    grownCanvasHeight = max(grownCanvasHeight, canvasHeight + 320)
                }
                .allowsHitTesting(false)
                ComposerScrollBubbleFinder(rail: scrollBubbleRail)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                if showsScrollBubble {
                    ComposerScrollBubble(rail: scrollBubbleRail)
                        .padding(.top, 12)
                        .padding(.trailing, 4)
                        .padding(.bottom, 20 + ComposerAddMenuMetrics.button + 16)
                        .transition(.opacity)
                }
                if isGrouping {
                    groupingBar
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                }
                if !chrome.isViewing, !isGrouping {
                    addMenu
                }
                if showsSelectionTrash {
                    selectionTrashButton
                        .padding(.trailing, 20 + ComposerAddMenuMetrics.button + 12)
                        .padding(.bottom, 20)
                }
                if !isGrouping, !chrome.isVisiting {
                    viewEyeButton
                        .padding(.trailing, eyeTrailingPadding)
                        .padding(.bottom, 20)
                    if chrome.isViewing, documentID == nil {
                        HStack(alignment: .bottom, spacing: 12) {
                            MosaicOwnProfileButton(size: ComposerAddMenuMetrics.button, refresh: profileRefresh)
                            if showsViewAs {
                                MosaicViewAsToggle(
                                    viewAs: Bindable(chrome).viewAs,
                                    isChecking: pursuitPrivacy?.isLoaded != true
                                )
                            }
                        }
                        .padding(.trailing, eyeTrailingPadding + ComposerAddMenuMetrics.button + 12)
                        .padding(.bottom, 20)
                        .transition(.opacity)
                    }
                }
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(composerSpace))
            } action: { frame in
                dragScrollRelay.viewportMinY = frame.minY
                dragScrollRelay.viewportHeight = frame.height
            }
        }
    }

    /// Edit mode only; visitors and view mode scroll the usual way.
    private var showsScrollBubble: Bool {
        !chrome.isViewing && !chrome.isVisiting && !isBookPage && !isGrouping && !textDragVisual.isMoving
    }

    private var showsSelectionTrash: Bool {
        selectedBlockID != nil && !textDragVisual.isMoving && !chrome.isViewing && !isGrouping
    }

    private var eyeTrailingPadding: CGFloat {
        let plusGap = ComposerAddMenuMetrics.button + 12
        let trashGap = showsSelectionTrash ? plusGap : 0
        return chrome.isViewing ? 20 : 20 + plusGap + trashGap
    }

    private var selectionTrashButton: some View {
        Button {
            guard let selectedBlockID else { return }
            deleteBlock(selectedBlockID)
        } label: {
            Image(systemName: "trash.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: ComposerAddMenuMetrics.button, height: ComposerAddMenuMetrics.button)
                .background(Color(red: 0.36, green: 0.18, blue: 0.18), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.20), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete")
        .accessibilityIdentifier("composer.selectionTrash")
    }

    private var addMenu: some View {
        // Journal pages stay simple: text tools, media, group, social, content, link, calendar.
        ComposerFloatingMenu(
            isExpanded: $menuExpanded,
            showsTrashDropZone: textDragVisual.isMoving,
            isTrashHighlighted: textDragVisual.hoveringTrash,
            includesPursuit: documentID == nil,
            includesCalendar: documentID != nil,
            includesGraph: documentID != nil && !isBookPage,
            includesNode: documentID != nil && !isBookPage,
            includesScrapbook: documentID != nil && !isBookPage,
            includesTabs: !isBookPage && !blocks.contains(where: { $0.kind == .tabs }),
            includesBanner: !isBookPage && !blocks.contains(where: { $0.kind == .banner }),
            includesTable: documentID != nil && !isBookPage,
            includesCarousel: !isBookPage,
            includesBackground: !isBookPage
        ) { option in
            beginPlacement(for: option)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    private var canvasScroll: some View {
        ScrollView(.vertical) {
            canvasPage
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
                .background(ComposerCanvasZoomLock(onOffset: { canvasScrollPosition.scrollTo(y: $0) }))
                .coordinateSpace(name: composerSpace + ".canvas")
                .modifier(
                    PlacementGestureModifier(
                        isActive: placingOption != nil,
                        gesture: placementDragGesture
                    )
                )
        }
        .scrollDisabled(textDragVisual.isMoving || socialCornerResizing)
        .scrollIndicators(.hidden, axes: .vertical)
        .scrollDismissesKeyboard(.interactively)
        .scrollPosition($canvasScrollPosition)
        .onScrollGeometryChange(for: ComposerScrollBubbleMetrics.self) { geometry in
            ComposerScrollBubbleMetrics(geometry)
        } action: { _, metrics in
            scrollBubbleRail.metrics = metrics
        }
    }

    private var canvasPage: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(coordinateSpace: .named(composerSpace + ".canvas"))
                        .onEnded { value in
                            handleEmptyCanvasTap(at: value.location)
                        }
                )

            if blocks.isEmpty, placingOption == nil, documentID == nil {
                emptyState
                    .padding(.horizontal, 24)
                    .padding(.top, 48)
            }

            ForEach(scrollingBlocks) { block in
                placedBlock(block)
            }

            if isGrouping {
                ComposerGroupingCatcher(
                    targets: scrollingBlocks.compactMap { block in
                        guard block.kind != .banner, let frame = blockFrames[block.id], frame.width > 1 else { return nil }
                        return (block.id, frame)
                    }
                ) { blockID in
                    toggleGroupSelection(blockID)
                }
                .frame(
                    width: canvasSize.width > 1 ? canvasSize.width : nil,
                    height: canvasHeight,
                    alignment: .topLeading
                )
            }

            if let placingOption {
                ComposerPlacementGhost(option: placingOption)
                    .offset(x: ghostLocation.x - 22, y: ghostLocation.y - 22)
                    .allowsHitTesting(false)
            }

            if let pasteAnchor, store.clipboard != nil, !chrome.isViewing {
                clipboardPasteButton
                    .fixedSize()
                    .offset(x: max(pasteAnchor.x - 8, 8), y: max(pasteAnchor.y - 52, 8))
                    .zIndex(4)
            }
        }
    }

    @ViewBuilder
    private func placedBlock(_ block: ComposerBlock) -> some View {
        let preview = resizePreview?.blockID == block.id ? resizePreview : nil
        ZStack(alignment: .topLeading) {
            blockView(for: block)
                .id(block.id)
                .scaleEffect(
                    x: preview?.scaleX ?? 1,
                    y: preview?.scaleY ?? 1,
                    anchor: preview?.corner.anchor ?? .topLeading
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ComposerBlockFrameKey.self,
                            value: [block.id: proxy.frame(in: .named(composerSpace + ".canvas")).integral]
                        )
                    }
                }
                .modifier(
                    RelocateGestureModifier(
                        isEnabled: relocateEnabled(for: block) && !isGrouping,
                        claimsTouches: claimsCanvasTouches(for: block),
                        // A priority pinch would sit above a selected tab bar's press and stop it moving.
                        pinchPriority: block.kind == .calendar || block.kind == .graph
                            || (block.kind == .tabs && selectedBlockID != block.id),
                        pinchEnabled: block.kind != .table && block.kind != .social,
                        gesture: textPressGesture(for: block),
                        pinch: textPinchGesture(for: block)
                    )
                )
                .modifier(
                    ViewingMediaTapModifier(
                        isEnabled: chrome.isViewing && (block.kind == .media || isFolder(block.kind) || block.kind == .social || block.kind == .scrapbook || block.isContent),
                        onTap: { handleViewingTap(on: block) }
                    )
                )
            if showsResizeChrome(for: block), let frame = blockFrames[block.id], frame.width > 1, frame.height > 1 {
                // Tables and tabs keep controls near their edges, so the grab sits
                // slightly outside the box instead of over those controls.
                let clearsEdgeControls = block.kind == .table || block.kind == .tabs
                ComposerResizeChrome(
                    blockID: block.id,
                    layout: frame.size,
                    scaleX: preview?.scaleX ?? 1,
                    scaleY: preview?.scaleY ?? 1,
                    anchor: preview?.corner.anchor ?? .topLeading,
                    grabPull: clearsEdgeControls ? -10 : 18,
                    catcherSide: clearsEdgeControls ? 36 : 52,
                    onChanged: { corner, translation in
                        updateResizePreview(for: block, corner: corner, translation: translation)
                    },
                    onEnded: { _, _ in
                        commitResizePreview()
                    }
                )
            }
            if clipboardMenuBlockID == block.id {
                clipboardActionMenu(for: block.id)
                    .fixedSize()
                    .offset(y: -46)
            }
        }
        .overlay(alignment: .topTrailing) {
            visitBadge(for: block)
        }
        .modifier(SelectedCornerPencil(
            isShown: showsResizeChrome(for: block) && isFolder(block.kind) && !chrome.isViewing,
            pencil: pursuitBoardPencil(block)
        ))
        .zIndex(clipboardMenuBlockID == block.id || styleMenuBlockID == block.id ? 2 : (block.kind == .tabs ? 1 : 0))
        .offset(liveOffset(for: block))
        .modifier(DragFollowOffset(
            relay: dragScrollRelay,
            enabled: textDragVisual.blockID == block.id && textDragVisual.isMoving
        ))
        .opacity(blockOpacity(for: block))
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
                actions: blockActions(for: block),
                showsMediaMenu: styleMenuBlockID == block.id,
                showsPursuitPencil: !chrome.isViewing,
                pencilCoveredByChrome: showsResizeChrome(for: block),
                allowsCarouselControl: chrome.isViewing || selectedBlockID == block.id,
                isViewing: chrome.isViewing,
                canvasSize: CGSize(width: canvasSize.width, height: layoutHeight),
                cornerResizing: $socialCornerResizing,
                mediaMenuBlockID: styleMenuBlockID
            )
        }
    }

    private func blockActions(for block: ComposerBlock) -> ComposerBlockActions {
        ComposerBlockActions(
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
            onClaimFormatTap: {
                textDragSession.didHandleStyleTap = true
            },
            onOpenMediaMenu: {
                handleMediaIconTap(block.id)
            },
            onCropMedia: {
                openMediaFrameEditor(block.id)
            },
            onEditPursuit: {
                beginPursuitEdit(block.id)
            },
            onEditCarousel: {
                beginCarouselEdit(block.id)
            },
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
            },
            onPresentMedia: chrome.isViewing ? { url, crop in
                presentMedia(at: url, crop: crop)
            } : nil,
            onBodyTap: nil,
            onOpenSocial: nil,
            onOpenFolder: { openPursuit($0) },
            onOpenScrapbook: { openScrapbook($0) },
            onOpenMemberMediaMenu: { handleMediaIconTap($0) },
            onCropMemberMedia: { openMediaFrameEditor($0) },
            onEditMemberPursuit: { beginPursuitEdit($0) },
            onEditMemberCarousel: { beginCarouselEdit($0) },
            onEditMemberSocial: { beginSocialEdit($0) },
            onOpenMemberSocial: { openSocialLink($0) },
            onReplaceMedia: chrome.isViewing || chrome.isVisiting ? nil : { replaceMedia(block.id) },
            onReplaceMemberMedia: chrome.isViewing || chrome.isVisiting ? nil : { replaceMedia($0) },
            opensContentEditor: contentEditBlockID == block.id,
            onContentEditorPresented: {
                if contentEditBlockID == block.id {
                    contentEditBlockID = nil
                }
            }
        )
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
        if option == .background {
            menuExpanded = false
            showsBackgroundEditor = true
            return
        }
        guard option != .group else {
            menuExpanded = false
            beginGrouping()
            return
        }
        guard documentID == nil || option != .pursuit else { return }
        if isBookPage {
            // Journal keeps a smaller set so page editing stays light.
            let journalOptions: Set<BlockMenuOption> = [
                .text, .media, .group, .social, .content, .list, .heading, .calendar
            ]
            guard journalOptions.contains(option) else { return }
        }
        if option == .scrapbook, isBookPage || documentID == nil { return }
        guard option != .tabs || !blocks.contains(where: { $0.kind == .tabs }) else { return }
        if option == .banner {
            guard !blocks.contains(where: { $0.kind == .banner }) else { return }
            menuExpanded = false
            let bannerID = store.addBlock(.banner, to: documentID)
            selectedBlockID = bannerID
            presentMediaLibrary(for: bannerID, origin: nil, limit: 1)
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
        let origin = placementOrigin(for: .media, at: point)
        let position = normalizedPosition(from: origin)
        let newID = store.addBlock(.media, at: position, to: documentID)
        presentMediaLibrary(for: newID, origin: origin, limit: 24)
    }

    private func presentMediaLibrary(for blockID: ComposerBlockID, origin: CGPoint?, limit: Int) {
        pendingMediaBlockID = blockID
        pendingMediaOrigin = origin
        mediaPickLimit = limit
        pickedMediaItems = []
        showMediaPicker = true
    }

    /// Spreads a batch of photos and videos so each one is its own piece, starting at the drop.
    private func mediaClusterPoint(index: Int, origin: CGPoint) -> CGPoint {
        let stepX: CGFloat = 220
        let stepY: CGFloat = 250
        let room = max(canvasSize.width - origin.x, stepX)
        let columns = max(Int(room / stepX), 1)
        let column = index % columns
        let row = index / columns
        return placementOrigin(
            for: .media,
            at: CGPoint(
                x: origin.x + CGFloat(column) * stepX,
                y: origin.y + CGFloat(row) * stepY
            )
        )
    }

    private func placeCarousel(at point: CGPoint) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let origin = placementOrigin(for: .carousel, at: point)
        let position = normalizedPosition(from: origin)
        let newID = store.addBlock(.carousel, at: position, to: documentID)
        selectedBlockID = newID
        openCarouselEditor(newID)
    }

    /// A carousel placed and closed before anything was added is removed.
    private func removeCarouselIfEmpty() {
        guard let blockID = editedCarouselID else { return }
        editedCarouselID = nil
        guard store.block(with: blockID, in: documentID)?.carouselItems.isEmpty == true else { return }
        store.deleteBlock(blockID, in: documentID)
    }

    private func importMedia(_ item: PhotosPickerItem, into blockID: ComposerBlockID) async {
        if let fileName = await ComposerMediaImport.save(item, to: store) {
            store.setMedia(fileName, for: blockID, in: documentID, resetsFraming: true)
        } else if let block = store.block(with: blockID, in: documentID),
                  block.kind != .banner, block.mediaFileName == nil {
            store.deleteBlock(blockID, in: documentID)
        }
    }

    private func importPlacedMedia(_ items: [PhotosPickerItem], firstBlockID: ComposerBlockID, origin: CGPoint?) async {
        guard let first = items.first else { return }
        await importMedia(first, into: firstBlockID)
        if store.block(with: firstBlockID, in: documentID) != nil {
            selectedBlockID = firstBlockID
        }
        guard let origin else { return }
        for (offset, item) in items.dropFirst().enumerated() {
            let point = mediaClusterPoint(index: offset + 1, origin: origin)
            let id = store.addBlock(.media, at: normalizedPosition(from: point), to: documentID)
            await importMedia(item, into: id)
        }
    }

    private func place(option: BlockMenuOption, at point: CGPoint) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let origin = placementOrigin(for: option, at: point)
        let position = normalizedPosition(from: origin)
        let newID = store.addBlock(option.blockKind, at: position, to: documentID)
        if option == .content {
            if var item = store.block(with: newID, in: documentID) {
                item.socialPlatform = "content:youtube"
                item.text = "Content"
                store.updateBlock(item, in: documentID)
            }
            selectedBlockID = newID
        } else if option.blockKind == .social {
            selectedBlockID = newID
            socialEditRequest = SocialEditRequest(blockID: newID)
        }
    }

    private func placeTextAndBeginEditing(option: BlockMenuOption, at point: CGPoint) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let origin = placementOrigin(for: option, at: point)
        let position = normalizedPosition(from: origin)
        let newID = store.addBlock(option.blockKind, at: position, to: documentID)
        beginTextEditing(newID)
    }

    /// Keeps a drop fully on a journal page; Mosaic / Pursuit still use the simple inset clamp.
    private func placementOrigin(for option: BlockMenuOption, at point: CGPoint) -> CGPoint {
        let inset = clamped(point: point)
        guard isBookPage, pageViewportHeight > 1 else { return inset }
        return ComposerTabEdge.clampedOrigin(
            inset,
            size: estimatedPlacementSize(for: option),
            viewportWidth: max(canvasSize.width, 1),
            viewportHeight: pageViewportHeight
        )
    }

    private func estimatedPlacementSize(for option: BlockMenuOption) -> CGSize {
        switch option {
        case .media: CGSize(width: 200, height: 200)
        case .calendar: CGSize(width: 332, height: 300)
        case .social: CGSize(width: 72, height: 72)
        case .content: CGSize(width: 220, height: 160)
        case .heading: CGSize(width: 180, height: 44)
        case .list: CGSize(width: 200, height: 120)
        case .text: CGSize(width: 160, height: 40)
        default: CGSize(width: 160, height: 80)
        }
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
        clipboardMenuBlockID = nil
        pasteAnchor = nil
        textDragSession.reset()
    }

    private func handleEmptyCanvasTap(at point: CGPoint) {
        guard placingOption == nil else { return }
        if menuExpanded {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                menuExpanded = false
            }
        }
        if editingBlockID != nil {
            commitTextEditing()
        } else {
            dismissBlockInteraction()
        }
        guard store.clipboard != nil, !chrome.isViewing, !isGrouping else { return }
        if let pasteAnchor, hypot(point.x - pasteAnchor.x, point.y - pasteAnchor.y) < 72 {
            performPaste(at: pasteAnchor)
            return
        }
        pasteAnchor = point
    }

    private func performPaste(at point: CGPoint) {
        if let pasted = store.pasteClipboard(at: normalizedPosition(from: point), in: documentID) {
            selectedBlockID = pasted
        }
        pasteAnchor = nil
    }

    private func armClipboardPress(for blockID: ComposerBlockID) {
        guard !chrome.isViewing, !isGrouping, textDragSession.pressID == nil else { return }
        let generation = UUID()
        textDragSession.pressID = generation
        clipboardPressTask?.cancel()
        clipboardPressTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled, textDragSession.pressID == generation else { return }
            guard textDragSession.blockID == blockID, textDragSession.baseline == nil else { return }
            presentClipboardMenu(for: blockID)
        }
    }

    private func cancelClipboardPress() {
        clipboardPressTask?.cancel()
        clipboardPressTask = nil
        textDragSession.pressID = nil
    }

    private func presentClipboardMenu(for blockID: ComposerBlockID) {
        guard !chrome.isViewing, !isGrouping else { return }
        clipboardMenuBlockID = blockID
        pasteAnchor = nil
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    private func clipboardActionMenu(for blockID: ComposerBlockID) -> some View {
        HStack(spacing: 0) {
            clipboardMenuButton("Copy") {
                store.copyBlock(blockID, in: documentID)
                clipboardMenuBlockID = nil
            }
            clipboardMenuButton("Cut") {
                store.copyBlock(blockID, in: documentID)
                deleteBlock(blockID)
                clipboardMenuBlockID = nil
            }
        }
        .fixedSize()
        .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func clipboardMenuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var clipboardPasteButton: some View {
        clipboardMenuButton("Paste") {
            guard let pasteAnchor else { return }
            performPaste(at: pasteAnchor)
        }
        .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .padding(18)
        .contentShape(Rectangle())
    }

    private func handleMediaIconTap(_ blockID: ComposerBlockID) {
        guard textDragSession.claimMediaChromeTap(blockID, action: "menu") else { return }
        textDragSession.didHandleMediaIconTap = true
        selectPageBlock(blockID)
        styleMenuBlockID = styleMenuBlockID == blockID ? nil : blockID
    }

    private func textPressGesture(for block: ComposerBlock) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(composerSpace))
            .updating($textDragVisual) { value, visual, _ in
                updateTextDrag(for: block, value: value, visual: &visual)
            }
            .onChanged { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if distance > 10 || textDragSession.resizeCorner != nil || textDragSession.graphResizing {
                    cancelClipboardPress()
                    if clipboardMenuBlockID == block.id {
                        clipboardMenuBlockID = nil
                    }
                } else {
                    armClipboardPress(for: block.id)
                }
                guard let corner = textDragSession.resizeCorner else { return }
                updateResizePreview(for: block, corner: corner, translation: value.translation)
            }
            .onEnded { value in
                finishTextDrag(for: block, value: value)
            }
    }

    private func updateTextDrag(for block: ComposerBlock, value: DragGesture.Value, visual: inout TextDragVisual) {
        dragScrollRelay.active = false
        if isGrouping {
            visual = .inactive
            return
        }
        let session = textDragSession
        if session.graphResizing, let corner = session.resizeCorner {
            visual = .inactive
            return
        }
        if session.isPinching || session.graphResizing || socialCornerResizing {
            visual = .inactive
            return
        }
        if session.didHandleStyleTap || touchHitsTextStyleIcon(block.id, at: value.startLocation) {
            visual = .inactive
            return
        }
        if touchHitsMediaCrop(block.id, at: value.startLocation) || touchHitsMediaMenu(block.id, at: value.startLocation)
            || touchHitsMediaReplace(block.id, at: value.startLocation) {
            session.didHandleMediaIconTap = true
            session.blockID = block.id
            visual = .inactive
            return
        }
        if session.baseline == nil, session.resizeCorner == nil,
           let corner = resizeCornerFrames[block.id]?.corner(at: value.startLocation),
           claimsCanvasTouches(for: block) {
            session.graphResizing = true
            session.resizeCorner = corner
            session.blockID = block.id
            visual = .inactive
            return
        }
        if session.blockID != block.id {
            if let corner = resizeCornerFrames[block.id]?.corner(at: value.startLocation) {
                session.graphResizing = true
                session.resizeCorner = claimsCanvasTouches(for: block) ? corner : nil
                session.blockID = block.id
                visual = .inactive
                return
            }
            if touchHitsSocialCorner(block.id, at: value.startLocation) {
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
        if (block.kind == .carousel || block.kind == .group), selectedBlockID == block.id, session.baseline == nil,
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
                session.dragFrame = blockFrames[block.id]
            }
            let baseline = session.baseline ?? .zero
            next.isMoving = true
            var translation = CGSize(
                width: value.translation.width - baseline.width,
                height: value.translation.height - baseline.height
            )
            if let frame = session.dragFrame {
                translation = ComposerTabEdge.clampedDrag(
                    translation: translation,
                    frameMinX: frame.minX,
                    frameWidth: frame.width,
                    viewportWidth: viewportWidth,
                    frameMinY: frame.minY,
                    frameHeight: frame.height,
                    viewportHeight: pageViewportHeight
                )
            }
            next.translation = translation
            next.hoveringTrash = trashDropZoneFrame.width > 1
                && trashDropZoneFrame.insetBy(dx: 12, dy: 12).contains(value.location)
            session.lastTranslation = next.translation
            session.hoveringTrash = next.hoveringTrash
            dragScrollRelay.active = true
            dragScrollRelay.fingerY = value.location.y - dragScrollRelay.viewportMinY
            if let frame = blockFrames[block.id], frame.height > 1 {
                let previous = dragScrollRelay.tracksItem ? dragScrollRelay.itemMinY - frame.minY : next.translation.height
                dragScrollRelay.dragDeltaY = next.translation.height - previous
                dragScrollRelay.itemMinY = frame.minY + next.translation.height
                dragScrollRelay.itemMaxY = frame.maxY + next.translation.height
                dragScrollRelay.tracksItem = true
            } else {
                dragScrollRelay.dragDeltaY = 0
                dragScrollRelay.tracksItem = false
            }
            dragScrollRelay.dragDeltaTime = Date()
        }

        visual = next
    }

    private func finishTextDrag(for block: ComposerBlock, value: DragGesture.Value) {
        if isGrouping {
            let distance = hypot(value.translation.width, value.translation.height)
            if distance < 12 {
                toggleGroupSelection(block.id)
            }
            textDragSession.reset()
            stopDragFollow()
            return
        }
        let tapDistance = hypot(value.translation.width, value.translation.height)
        if tapDistance < 14, touchHitsMediaCrop(block.id, at: value.startLocation) {
            openMediaFrameEditor(block.id)
            textDragSession.reset()
            stopDragFollow()
            return
        }
        if tapDistance < 14, touchHitsMediaMenu(block.id, at: value.startLocation) {
            handleMediaIconTap(block.id)
            textDragSession.reset()
            stopDragFollow()
            return
        }
        if tapDistance < 14, touchHitsMediaReplace(block.id, at: value.startLocation) {
            replaceMedia(block.id)
            textDragSession.reset()
            stopDragFollow()
            return
        }
        if textDragSession.resizeCorner != nil {
            commitResizePreview()
            textDragSession.reset()
            stopDragFollow()
            return
        }
        if textDragSession.didHandleStyleTap || touchHitsTextStyleIcon(block.id, at: value.startLocation) || textDragSession.graphResizing || touchHitsResizeCorner(block.id, at: value.startLocation) || touchHitsSocialCorner(block.id, at: value.startLocation) {
            textDragSession.reset()
            stopDragFollow()
            return
        }
        if textDragSession.carouselPan {
            textDragSession.reset()
            stopDragFollow()
            selectedBlockID = block.id
            return
        }
        let elapsed = Date().timeIntervalSince(textDragSession.started)
        let distance = hypot(value.translation.width, value.translation.height)
        let didMove = textDragSession.baseline != nil && !textDragSession.isPinching
        let translation = CGSize(
            width: textDragSession.lastTranslation.width,
            height: textDragSession.lastTranslation.height + stopDragFollow()
        )
        let shouldDelete = textDragSession.hoveringTrash
        let iconAlreadyHandled = textDragSession.didHandleMediaIconTap
        let tappedPencil = pencilFrames[block.id].map { frame in
            frame.width > 1 && frame.insetBy(dx: -12, dy: -12).contains(value.location)
        } ?? false
        textDragSession.lastEnded = Date()
        cancelClipboardPress()
        textDragSession.reset()
        handleTextTap(
            on: block,
            didMove: didMove,
            distance: distance,
            elapsed: elapsed,
            translation: translation,
            shouldDelete: shouldDelete,
            iconAlreadyHandled: iconAlreadyHandled,
            tappedPencil: tappedPencil
        )
    }

    private func handleTextTap(
        on block: ComposerBlock,
        didMove: Bool,
        distance: CGFloat,
        elapsed: TimeInterval,
        translation: CGSize,
        shouldDelete: Bool,
        iconAlreadyHandled: Bool,
        tappedPencil: Bool
    ) {
        let isTap = distance < 12 && elapsed < 0.32
        if didMove {
            editingBlockID = nil
            focusedTextBlockID = nil
            styleMenuBlockID = nil
            if shouldDelete {
                deleteBlock(block.id)
                selectedBlockID = nil
            } else {
                let origin = canvasPoint(for: block.position)
                moveBlock(block.id, to: CGPoint(x: origin.x + translation.width, y: origin.y + translation.height))
                selectedBlockID = block.id
            }
        } else if isTap, isFolder(block.kind), editingBlockID != block.id, tappedPencil {
            beginPursuitEdit(block.id)
        } else if isTap, isFolder(block.kind), editingBlockID != block.id, !iconAlreadyHandled {
            openPursuit(block)
        } else if isTap, isTextLikeKind(block.kind), editingBlockID != block.id {
            beginTextEditing(block.id)
        } else if isTap, block.kind == .media, !iconAlreadyHandled {
            if selectedBlockID != block.id {
                selectedBlockID = block.id
            } else if styleMenuBlockID != block.id {
                toggleMediaPlayback(block.id)
            }
        } else if isTap, block.isContent {
            selectedBlockID = block.id
            editingBlockID = nil
            focusedTextBlockID = nil
            contentEditBlockID = block.id
        } else if isTap, block.kind == .carousel, !iconAlreadyHandled {
            selectedBlockID = block.id
            styleMenuBlockID = nil
        } else if isTap, block.kind == .scrapbook {
            selectedBlockID = block.id
            openScrapbook(block)
        } else if isTap, block.kind == .tabs || block.kind == .table || block.kind == .group {
            selectedBlockID = block.id
        } else if isTap, block.kind == .social, tappedPencil {
            beginSocialEdit(block.id)
        } else if isTap, block.kind == .social {
            if selectedBlockID != block.id {
                selectedBlockID = block.id
            } else if ComposerSocialPlatform(rawValue: block.socialPlatform)?.profileURL(from: block.linkURL ?? "") == nil {
                beginSocialEdit(block.id)
            } else {
                openSocialLink(block)
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
                } else if current.isContent || current.kind == .media || current.kind == .pursuit || current.kind == .node || current.kind == .carousel || current.kind == .calendar || current.kind == .tabs || current.kind == .group || current.kind == .scrapbook {
                    let next = current.style.scale * Double(value)
                    current.style.scale = min(max(next, minimumScale(for: current)), 3.2)
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
        if styleMenuBlockID == blockID {
            styleMenuBlockID = nil
        }
        if clipboardMenuBlockID == blockID {
            clipboardMenuBlockID = nil
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func moveBlock(_ blockID: ComposerBlockID, to canvasPoint: CGPoint) {
        guard var block = blocks.first(where: { $0.id == blockID }) else { return }
        block.position = normalizedPosition(from: canvasPoint)
        store.updateBlock(block, in: documentID)
    }

    /// After layout, nudge anything that still hangs past a journal page edge (media size, etc.).
    private func keepBlocksInsidePage(using frames: [ComposerBlockID: CGRect]) {
        guard isBookPage, pageViewportHeight > 1 else { return }
        let pageWidth = max(viewportWidth > 1 ? viewportWidth : canvasSize.width, 1)
        let margin = ComposerTabEdge.dragMargin
        for block in blocks {
            guard let frame = frames[block.id], frame.width > 1, frame.height > 1 else { continue }
            var dx: CGFloat = 0
            var dy: CGFloat = 0
            if frame.maxX > pageWidth - margin { dx -= frame.maxX - (pageWidth - margin) }
            if frame.minX < margin { dx += margin - frame.minX }
            if frame.maxY > pageViewportHeight - margin { dy -= frame.maxY - (pageViewportHeight - margin) }
            if frame.minY < margin { dy += margin - frame.minY }
            guard abs(dx) > 1 || abs(dy) > 1 else { continue }
            let origin = canvasPoint(for: block.position)
            moveBlock(block.id, to: CGPoint(x: origin.x + dx, y: origin.y + dy))
        }
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
                    initialFrameAspect: contentCropAspect(for: block, fileName: fileName) ?? block.mediaFrameAspect,
                    showsShapes: !block.isContent,
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

    private func contentCropAspect(for block: ComposerBlock, fileName: String) -> Double? {
        guard let platform = block.contentPlatform else { return nil }
        let cover = UIImage(contentsOfFile: store.mediaURL(for: fileName).path)?.size
        let size = platform.cardSize(cover: cover, cropAspect: block.mediaFrameAspect)
        return Double(size.width / max(size.height, 1))
    }

    private func openMediaFrameEditor(_ blockID: ComposerBlockID) {
        guard textDragSession.claimMediaChromeTap(blockID, action: "crop") else { return }
        playingMediaIDs.remove(blockID)
        styleMenuBlockID = nil
        selectPageBlock(blockID)
        mediaEditRequest = .shape(blockID)
    }

    private func relocateEnabled(for block: ComposerBlock) -> Bool {
        guard !chrome.isViewing, (block.isContent || supportsCanvasGestures(block.kind)), placingOption == nil else { return false }
        if styleMenuBlockID == nil { return true }
        return block.kind == .media && styleMenuBlockID == block.id
    }

    private func claimsCanvasTouches(for block: ComposerBlock) -> Bool {
        if block.kind == .calendar || block.kind == .graph || block.kind == .group { return false }
        // A selected table or tab bar owns the press so a hold moves it instead of scrolling the board.
        if block.kind == .table || block.kind == .tabs { return selectedBlockID == block.id }
        if block.kind == .media { return true }
        return selectedBlockID != block.id
    }

    @discardableResult
    private func stopDragFollow() -> CGFloat {
        let boost = dragScrollRelay.boost
        if let followed = dragScrollRelay.intendedOffset {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                canvasScrollPosition.scrollTo(y: followed)
            }
        }
        dragScrollRelay.boost = 0
        dragScrollRelay.intendedOffset = nil
        dragScrollRelay.active = false
        dragScrollRelay.tracksItem = false
        return boost
    }

    private func touchHitsResizeCorner(_ blockID: ComposerBlockID, at point: CGPoint) -> Bool {
        resizeCornerFrames[blockID]?.contains(point) ?? false
    }

    private func showsResizeChrome(for block: ComposerBlock) -> Bool {
        guard !chrome.isViewing, selectedBlockID == block.id else { return false }
        guard textDragVisual.blockID != block.id || !textDragVisual.isMoving else { return false }
        switch block.kind {
        case .text, .heading, .list, .media, .pursuit, .node, .carousel, .calendar, .graph, .tabs, .table, .group, .scrapbook:
            return true
        case .link:
            return block.isContent
        case .social, .banner:
            return false
        }
    }

    private func updateResizePreview(for block: ComposerBlock, corner: ComposerResizeCorner, translation: CGSize) {
        let frame: CGRect
        if let preview = resizePreview, preview.blockID == block.id, preview.corner == corner {
            frame = preview.frame
        } else if let current = blockFrames[block.id], current.width > 1, current.height > 1 {
            frame = current
        } else {
            return
        }
        guard let current = store.block(with: block.id, in: documentID) else { return }
        let factors = resizeFactors(for: current, frame: frame, corner: corner, translation: translation)
        if !socialCornerResizing {
            socialCornerResizing = true
        }
        textDragSession.graphResizing = true
        resizePreview = ComposerResizePreview(
            blockID: block.id,
            corner: corner,
            scaleX: factors.x,
            scaleY: factors.y,
            frame: frame
        )
    }

    private func commitResizePreview() {
        guard let preview = resizePreview,
              abs(preview.scaleX - 1) > 0.01 || abs(preview.scaleY - 1) > 0.01,
              var block = store.block(with: preview.blockID, in: documentID) else {
            resizePreview = nil
            socialCornerResizing = false
            textDragSession.graphResizing = false
            return
        }
        if block.kind == .graph {
            block.graphWidthScale = ComposerGraphStretch.clamped(block.graphWidthScale * block.style.scale * Double(preview.scaleX))
            block.graphHeightScale = ComposerGraphStretch.clamped(block.graphHeightScale * block.style.scale * Double(preview.scaleY))
            block.style.scale = 1
        } else if block.kind == .text || block.kind == .heading || block.kind == .list {
            let next = block.style.fontSize * block.style.scale * Double(preview.scaleX)
            block.style.fontSize = min(max(next, 12), 80)
            block.style.scale = 1
        } else {
            block.style.scale = min(max(block.style.scale * Double(preview.scaleX), minimumScale(for: block)), 3.2)
        }
        let widthChange = preview.frame.width * (preview.scaleX - 1)
        let heightChange = preview.frame.height * (preview.scaleY - 1)
        var point = canvasPoint(for: block.position)
        if preview.corner.movesLeading {
            point.x -= widthChange
        }
        if preview.corner.movesTop {
            point.y -= heightChange
        }
        block.position = normalizedPosition(from: point)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            resizePreview = nil
            socialCornerResizing = false
            textDragSession.graphResizing = false
            store.updateBlock(block, in: documentID)
        }
    }

    private func resizeFactors(
        for block: ComposerBlock,
        frame: CGRect,
        corner: ComposerResizeCorner,
        translation: CGSize
    ) -> (x: CGFloat, y: CGFloat) {
        if block.kind == .graph {
            let signed = corner.signedGrowth(translation)
            var scaleX = (frame.width + signed.width) / max(frame.width, 1)
            var scaleY = (frame.height + signed.height) / max(frame.height, 1)
            let currentWidth = max(block.graphWidthScale * block.style.scale, 0.01)
            let currentHeight = max(block.graphHeightScale * block.style.scale, 0.01)
            scaleX = CGFloat(ComposerGraphStretch.clamped(currentWidth * Double(scaleX)) / currentWidth)
            scaleY = CGFloat(ComposerGraphStretch.clamped(currentHeight * Double(scaleY)) / currentHeight)
            return (finite(scaleX), finite(scaleY))
        }
        var scale = ComposerResizeMath.uniformScale(frame: frame, corner: corner, translation: translation)
        if block.kind == .text || block.kind == .heading || block.kind == .list {
            let current = max(block.style.fontSize * block.style.scale, 1)
            scale = CGFloat(min(max(current * Double(scale), 12), 80) / current)
        } else {
            let current = max(block.style.scale, 0.01)
            scale = CGFloat(min(max(current * Double(scale), minimumScale(for: block)), 3.2) / current)
        }
        let safe = finite(scale)
        return (safe, safe)
    }

    private func minimumScale(for block: ComposerBlock) -> Double {
        block.kind == .carousel ? CarouselLayout.minimumScale : 0.45
    }

    private func finite(_ value: CGFloat) -> CGFloat {
        value.isFinite ? value : 1
    }

    private func touchHitsSocialCorner(_ blockID: ComposerBlockID, at point: CGPoint) -> Bool {
        socialCornerFrames[blockID]?.contains(point) ?? false
    }

    private func touchHitsTextStyleIcon(_ blockID: ComposerBlockID, at point: CGPoint) -> Bool {
        guard let frame = textStyleIconFrames[blockID], frame.width > 1 else { return false }
        return frame.insetBy(dx: -12, dy: -12).contains(point)
    }

    private func touchHitsMediaMenu(_ blockID: ComposerBlockID, at point: CGPoint) -> Bool {
        mediaChromeFrames[blockID]?.hitsMenu(point) ?? false
    }

    private func touchHitsMediaCrop(_ blockID: ComposerBlockID, at point: CGPoint) -> Bool {
        mediaChromeFrames[blockID]?.hitsCrop(point) ?? false
    }

    private func touchHitsMediaReplace(_ blockID: ComposerBlockID, at point: CGPoint) -> Bool {
        mediaChromeFrames[blockID]?.hitsReplace(point) ?? false
    }

    private func replaceMedia(_ blockID: ComposerBlockID) {
        guard textDragSession.claimMediaChromeTap(blockID, action: "replace") else { return }
        textDragSession.didHandleMediaIconTap = true
        styleMenuBlockID = nil
        selectPageBlock(blockID)
        presentMediaLibrary(for: blockID, origin: nil, limit: 1)
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
        isTextLikeKind(kind) || kind == .media || isFolder(kind) || kind == .carousel || kind == .calendar || kind == .graph || kind == .tabs || kind == .table || kind == .social || kind == .group || kind == .scrapbook
    }

    private func beginCarouselEdit(_ blockID: ComposerBlockID) {
        textDragSession.didHandleMediaIconTap = true
        selectPageBlock(blockID)
        styleMenuBlockID = nil
        playingMediaIDs.remove(blockID)
        openCarouselEditor(blockID)
    }

    private func openCarouselEditor(_ blockID: ComposerBlockID) {
        editedCarouselID = blockID
        carouselEditRequest = CarouselEditRequest(blockID: blockID)
    }

    private func selectPageBlock(_ blockID: ComposerBlockID) {
        guard store.blocks(for: documentID).contains(where: { $0.id == blockID }) else { return }
        selectedBlockID = blockID
    }

    private func presentMedia(at url: URL, crop: ComposerMediaCrop?) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            focusedMedia = FocusedComposerMedia(url: url, crop: crop)
        }
    }

    private func handleViewingTap(on block: ComposerBlock) {
        if block.kind == .media {
            guard let name = block.mediaFileName, !name.isEmpty else { return }
            presentMedia(at: store.mediaURL(for: name), crop: ComposerMediaCrop(block: block))
        } else if isFolder(block.kind) {
            openPursuit(block)
        } else if block.kind == .social {
            openSocialLink(block)
        } else if block.isContent {
            if let target = ComposerContentPlatform.parse(block.linkURL ?? "") {
                openURL(target.url)
            }
        } else if block.kind == .scrapbook {
            openScrapbook(block)
        }
    }

    private func openScrapbook(_ block: ComposerBlock) {
        guard block.kind == .scrapbook else { return }
        editingBlockID = nil
        focusedTextBlockID = nil
        styleMenuBlockID = nil
        menuExpanded = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
            openScrapbookID = block.id
        }
    }

    private func beginSocialEdit(_ blockID: ComposerBlockID) {
        selectPageBlock(blockID)
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

    private func pursuitBoardPencil(_ block: ComposerBlock) -> some View {
        Button {
            beginPursuitEdit(block.id)
        } label: {
            Image(systemName: "pencil")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 26, height: 26)
                .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(block.kind == .node ? "Edit Node" : "Edit Pursuit")
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
                frameAspect: block.pursuitFrameAspect,
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
        block.pursuitFrameAspect = edits.frameAspect
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

    @ViewBuilder
    private func visitBadge(for block: ComposerBlock) -> some View {
        if let visit, block.kind == .pursuit,
           let id = block.pursuitID.flatMap(ComposerBoardSync.uuid),
           let pursuit = visit.pursuits[id], pursuit.isOpen {
            if !pursuit.following {
                Button {
                    Task { await visit.follow(id) }
                } label: {
                    visitBadgeGlyph("plus")
                }
                .buttonStyle(.plain)
                .disabled(visit.busy.contains(id))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .offset(x: 8, y: -8)
                .accessibilityLabel("Follow \(pursuit.title)")
                .accessibilityIdentifier("visit.follow.\(id.uuidString.lowercased())")
            }
        }
    }

    private func visitBadgeGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(MosaicBrand.inkBlack)
            .frame(width: 24, height: 24)
            .background(.white, in: Circle())
    }

    private func openPursuit(_ block: ComposerBlock) {
        if let visit, block.kind == .pursuit,
           let id = block.pursuitID.flatMap(ComposerBoardSync.uuid),
           visit.access(id) != .open {
            visit.askToRequest(id)
            return
        }
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
                .frame(width: ComposerAddMenuMetrics.button, height: ComposerAddMenuMetrics.button)
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
            Image(systemName: chrome.isViewing ? "pencil" : "eye")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: ComposerAddMenuMetrics.button, height: ComposerAddMenuMetrics.button)
                .background(MosaicBrand.inkBlack, in: Circle())
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chrome.isViewing ? "Edit Mosaic" : "View Mosaic")
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
    var didHandleStyleTap = false
    var carouselPan = false
    var graphResizing = false
    var resizeCorner: ComposerResizeCorner?
    var dragFrame: CGRect?
    var lastEnded = Date.distantPast
    var pressID: UUID?
    private var lastMediaChromeKey = ""
    private var lastMediaChromeTap = Date.distantPast

    /// Collapses a menu tap that both the button and the photo drag report.
    func claimMediaChromeTap(_ blockID: ComposerBlockID, action: String) -> Bool {
        let now = Date()
        let key = "\(blockID.rawValue).\(action)"
        if lastMediaChromeKey == key, now.timeIntervalSince(lastMediaChromeTap) < 0.3 {
            return false
        }
        lastMediaChromeKey = key
        lastMediaChromeTap = now
        return true
    }

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
        didHandleStyleTap = false
        carouselPan = false
        graphResizing = false
        resizeCorner = nil
        dragFrame = nil
        pressID = nil
    }
}

private struct TextPinchVisual: Equatable {
    var blockID: ComposerBlockID?
    var scale: CGFloat

    static let inactive = TextPinchVisual(blockID: nil, scale: 1)
}

private struct FocusedComposerMedia: Identifiable, Equatable {
    let url: URL
    var crop: ComposerMediaCrop?
    var id: String { url.absoluteString }
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

/// Hits only on block frames so empty paper still scrolls while grouping.
private struct ComposerGroupingCatcher: UIViewRepresentable {
    var targets: [(ComposerBlockID, CGRect)]
    var onTap: (ComposerBlockID) -> Void

    func makeUIView(context: Context) -> ComposerGroupingCatcherView {
        let view = ComposerGroupingCatcherView()
        view.isOpaque = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: ComposerGroupingCatcherView, context: Context) {
        uiView.targets = targets
        uiView.onTap = onTap
    }
}

private final class ComposerGroupingCatcherView: UIView {
    var targets: [(ComposerBlockID, CGRect)] = []
    var onTap: (ComposerBlockID) -> Void = { _ in }
    private var start: CGPoint?
    private var pressed: ComposerBlockID?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard blockID(at: point) != nil else { return nil }
        return self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        start = point
        pressed = blockID(at: point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            start = nil
            pressed = nil
        }
        guard let start, let pressed, let point = touches.first?.location(in: self) else { return }
        guard hypot(point.x - start.x, point.y - start.y) < 14 else { return }
        onTap(pressed)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        start = nil
        pressed = nil
    }

    private func blockID(at point: CGPoint) -> ComposerBlockID? {
        targets.reversed().first { $0.1.insetBy(dx: -4, dy: -4).contains(point) }?.0
    }
}

private struct SelectedCornerPencil<Pencil: View>: ViewModifier {
    var isShown: Bool
    var pencil: Pencil

    func body(content: Content) -> some View {
        if isShown {
            content.overlay(alignment: .bottomTrailing) {
                pencil.padding(8)
            }
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
        content
            .highPriorityGesture(gesture, isEnabled: isEnabled && claimsTouches)
            .simultaneousGesture(gesture, isEnabled: isEnabled && !claimsTouches)
            .simultaneousGesture(pinch, isEnabled: isEnabled && pinchEnabled && !pinchPriority)
            .highPriorityGesture(pinch, isEnabled: isEnabled && pinchEnabled && pinchPriority)
    }
}

/// Keeps the composer page at its normal scale. Pinching a block must not zoom the scroll view.
private struct ComposerCanvasZoomLock: UIViewRepresentable {
    var onOffset: (CGFloat) -> Void

    func makeUIView(context: Context) -> ComposerCanvasZoomLockView {
        let view = ComposerCanvasZoomLockView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: ComposerCanvasZoomLockView, context: Context) {
        uiView.onOffset = onOffset
        uiView.lockEnclosingScrollView()
    }
}

private final class ComposerCanvasZoomLockView: UIView {
    var onOffset: (CGFloat) -> Void = { _ in }

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
                scrollView.accessibilityIdentifier = ComposerCanvasScrollMark.id
                ComposerCanvasScrollMark.installSync(on: scrollView, onOffset)
                scrollView.minimumZoomScale = 1
                scrollView.maximumZoomScale = 1
                scrollView.bouncesZoom = false
                scrollView.alwaysBounceHorizontal = false
                scrollView.showsHorizontalScrollIndicator = false
                scrollView.showsVerticalScrollIndicator = false
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

/// Restores the system edge swipe that returns to the previous page while the navigation bar stays hidden.
private struct ComposerBackSwipe: UIViewRepresentable {
    var isEnabled: Bool

    func makeUIView(context: Context) -> ComposerBackSwipeView {
        let view = ComposerBackSwipeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: ComposerBackSwipeView, context: Context) {
        uiView.isEnabled = isEnabled
        uiView.installIfNeeded()
    }
}

private final class ComposerBackSwipeView: UIView {
    var isEnabled = false
    private weak var hookedScrollView: UIScrollView?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        installIfNeeded()
    }

    func installIfNeeded() {
        guard let navigation = enclosingNavigationController(),
              let pop = navigation.interactivePopGestureRecognizer else { return }
        let canPop = isEnabled && navigation.viewControllers.count > 1
        pop.isEnabled = canPop
        pop.delegate = ComposerBackSwipeRelay.shared
        guard canPop, let scrollView = enclosingScrollView(), hookedScrollView !== scrollView else { return }
        scrollView.panGestureRecognizer.require(toFail: pop)
        hookedScrollView = scrollView
    }

    private func enclosingNavigationController() -> UINavigationController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController, let navigation = controller.navigationController {
                return navigation
            }
            responder = current.next
        }
        return nil
    }

    private func enclosingScrollView() -> UIScrollView? {
        var current: UIView? = superview
        while let view = current {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }
}

private final class ComposerBackSwipeRelay: NSObject, UIGestureRecognizerDelegate {
    static let shared = ComposerBackSwipeRelay()

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        var responder: UIResponder? = gestureRecognizer.view
        while let current = responder {
            if let navigation = current as? UINavigationController {
                return navigation.viewControllers.count > 1
            }
            if let controller = current as? UIViewController, let navigation = controller.navigationController {
                return navigation.viewControllers.count > 1
            }
            responder = current.next
        }
        return false
    }
}

#Preview("Mosaic") {
    MosaicTabShell(persistToDisk: false)
}

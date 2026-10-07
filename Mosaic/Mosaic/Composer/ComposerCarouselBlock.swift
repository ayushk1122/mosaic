import AVFoundation
import PhotosUI
import SwiftUI

struct CarouselLayout {
    var width: CGFloat

    var height: CGFloat { width * 0.72 }
    var cardWidth: CGFloat { width * 0.56 }
    var cardHeight: CGFloat { height * 0.94 }
    var step: CGFloat { max(cardWidth * 0.84, 1) }

    func scale(for delta: CGFloat) -> CGFloat {
        1 - 0.24 * min(abs(delta), 1)
    }

    func opacity(for delta: CGFloat) -> Double {
        let distance = abs(delta)
        if distance >= 1.75 { return 0 }
        if distance <= 1 { return Double(1 - 0.34 * distance) }
        return Double(0.66 * (1 - (distance - 1) / 0.75))
    }
}

enum ComposerMediaStill {
    static func isVideo(_ url: URL) -> Bool {
        ["mov", "mp4", "m4v", "avi"].contains(url.pathExtension.lowercased())
    }

    static func image(at url: URL) async -> UIImage? {
        if isVideo(url) {
            return await videoPoster(at: url)
        }
        return UIImage(contentsOfFile: url.path)
    }

    private static func videoPoster(at url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let image = try? await generator.image(at: time).image else { return nil }
        return UIImage(cgImage: image)
    }
}

struct ComposerCarouselCanvasBlock: View {
    @Binding var block: ComposerBlock
    let scale: CGFloat
    let livePinchScale: CGFloat
    let isSelected: Bool
    let isLifted: Bool
    let isRelocating: Bool
    let allowsDirectControl: Bool
    var onEdit: () -> Void

    @Environment(ComposerStore.self) private var store
    @Environment(\.composerViewportWidth) private var viewportWidth

    @GestureState private var drag: CGFloat = 0
    @State private var settle: CGFloat = 0
    @State private var playing = false
    @State private var posters: [String: UIImage] = [:]
    @State private var itemFrame: CGRect = .zero
    @State private var editFrame: CGRect = .zero

    private var layout: CarouselLayout {
        CarouselLayout(width: max(220, 300 * scale * livePinchScale))
    }

    private var count: Int { block.carouselItems.count }
    private var ready: Bool { count >= CarouselMotion.minimumCount }

    private var centerIndex: Int {
        CarouselMotion.wrapped(block.carouselIndex, count: count)
    }

    private var pan: CGFloat {
        isLifted || isRelocating ? 0 : drag + settle
    }

    private var iconPlacement: ComposerChromePlacement {
        ComposerChromePlacement.resolve(itemFrame: itemFrame, viewportWidth: viewportWidth)
    }

    private var posterKey: String {
        block.carouselItems.map(\.fileName).joined(separator: "|")
    }

    var body: some View {
        face
            .overlay(alignment: .topLeading) {
                if isSelected, !isLifted, !isRelocating {
                    editButton
                        .offset(x: iconPlacement.x, y: -2)
                }
            }
            .shadow(color: .white.opacity(isLifted ? 0.85 : 0), radius: isLifted ? 3 : 0)
            .shadow(color: .white.opacity(isLifted ? 0.4 : 0), radius: isLifted ? 14 : 0)
            .animation(.easeOut(duration: 0.16), value: isLifted)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("composerRoot"))
            } action: { frame in
                itemFrame = frame
            }
            .task(id: posterKey) {
                await loadPosters()
            }
            .onChange(of: centerIndex) { _, _ in
                playing = false
            }
            .onChange(of: isSelected) { _, selected in
                if !selected { playing = false }
            }
            .onChange(of: isLifted) { _, lifted in
                guard lifted else { return }
                playing = false
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    settle = 0
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Carousel")
            .accessibilityIdentifier("composer.carousel")
    }

    @ViewBuilder
    private var face: some View {
        if ready {
            carousel
        } else {
            placeholder
        }
    }

    private var carousel: some View {
        ZStack {
            ForEach(Array(block.carouselItems.enumerated()), id: \.element.id) { index, item in
                let delta = CGFloat(CarouselMotion.shortestOffset(item: index, center: centerIndex, count: count)) + pan / layout.step
                card(item, delta: delta)
            }
        }
        .frame(width: layout.width, height: layout.height)
        .clipped()
        .contentShape(Rectangle())
        .modifier(CarouselScrollModifier(
            isEnabled: allowsDirectControl && !isLifted && !isRelocating,
            gesture: scrollGesture
        ))
    }

    private var placeholder: some View {
        HStack(spacing: 10) {
            ForEach(0..<CarouselMotion.minimumCount, id: \.self) { slot in
                placeholderSlot(slot)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: layout.width, height: layout.height)
    }

    private func placeholderSlot(_ slot: Int) -> some View {
        let item = slot < count ? block.carouselItems[slot] : nil
        return ZStack {
            if let item, let image = posters[item.fileName] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.06)
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: layout.cardHeight * 0.82)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    Color.white.opacity(item == nil ? 0.28 : 0.1),
                    style: StrokeStyle(lineWidth: 1, dash: item == nil ? [5, 4] : [CGFloat]())
                )
        }
    }

    private func card(_ item: CarouselMediaItem, delta: CGFloat) -> some View {
        let isCenter = abs(delta) < 0.35
        let url = store.mediaURL(for: item.fileName)
        let isVideo = ComposerMediaStill.isVideo(url)
        return ZStack {
            if isCenter, isVideo, playing {
                ComposerInlineVideo(url: url, isPaused: false, fillsFrame: true)
            } else if let image = posters[item.fileName] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.08)
            }
            if isCenter, isVideo, !playing {
                Image(systemName: "play.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.4), in: Circle())
                    .allowsHitTesting(false)
            }
        }
        .frame(width: layout.cardWidth, height: layout.cardHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(isCenter ? 0.16 : 0.06), lineWidth: 1)
        }
        .scaleEffect(layout.scale(for: delta))
        .opacity(layout.opacity(for: delta))
        .offset(x: delta * layout.step)
        .zIndex(2 - Double(min(abs(delta), 2)))
        .allowsHitTesting(isCenter && allowsDirectControl && !isLifted)
        .onTapGesture {
            guard isCenter, isVideo else { return }
            playing.toggle()
        }
    }

    private var scrollGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($drag) { value, state, _ in
                guard !isLifted, !isRelocating else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = min(max(value.translation.width, -layout.step), layout.step)
            }
            .onChanged { _ in
                if playing { playing = false }
            }
            .onEnded { value in
                let step = layout.step
                let translation = min(max(value.translation.width, -step), step)
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let shift = CarouselMotion.shift(
                    drag: translation,
                    predicted: value.predictedEndTranslation.width,
                    step: step
                )
                let fraction = translation / max(step, 1)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    settle = (fraction + CGFloat(shift)) * step
                    if shift != 0 {
                        block.carouselIndex = CarouselMotion.wrapped(centerIndex + shift, count: count)
                    }
                }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    settle = 0
                }
                if shift != 0 {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
    }

    private var editButton: some View {
        Image(systemName: "rectangle.stack")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 32, height: 32)
            .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Circle())
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("composerRoot"))
            } action: { frame in
                editFrame = frame
            }
            .preference(key: ComposerTextStyleIconFrameKey.self, value: [block.id: editFrame])
            .highPriorityGesture(TapGesture().onEnded { onEdit() })
            .accessibilityLabel("Edit carousel")
            .accessibilityAddTraits(.isButton)
    }

    private func loadPosters() async {
        for item in block.carouselItems {
            if posters[item.fileName] != nil { continue }
            let url = store.mediaURL(for: item.fileName)
            if let image = await ComposerMediaStill.image(at: url) {
                posters[item.fileName] = image
            }
        }
    }
}

private struct CarouselScrollModifier<G: Gesture>: ViewModifier {
    let isEnabled: Bool
    let gesture: G

    func body(content: Content) -> some View {
        if isEnabled {
            content.highPriorityGesture(gesture)
        } else {
            content
        }
    }
}

struct ComposerCarouselEditor: View {
    let documentID: ComposerDocumentID?
    let blockID: ComposerBlockID

    @Environment(ComposerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var posters: [String: UIImage] = [:]
    @State private var showPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var replacingID: String?
    @State private var isImporting = false

    private var block: ComposerBlock? {
        store.block(with: blockID, in: documentID)
    }

    private var items: [CarouselMediaItem] {
        block?.carouselItems ?? []
    }

    private var canRemove: Bool {
        items.count > CarouselMotion.minimumCount
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("At least \(CarouselMotion.minimumCount) photos or videos. The center one is larger, and a video there can play.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(items) { item in
                            itemCard(item)
                        }
                        addCard
                    }
                    .padding(.vertical, 8)
                    .padding(.trailing, 8)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(MosaicBrand.inkBlack)
            .navigationTitle("Carousel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(MosaicBrand.inkBlack)
        .photosPicker(
            isPresented: $showPicker,
            selection: $pickerItems,
            maxSelectionCount: replacingID == nil ? 12 : 1,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: pickerItems) { _, picked in
            guard !picked.isEmpty else { return }
            let chosen = picked
            let replacing = replacingID
            pickerItems = []
            replacingID = nil
            Task { await importPicked(chosen, replacing: replacing) }
        }
        .task(id: items.map(\.fileName).joined(separator: "|")) {
            await loadPosters()
        }
    }

    private func itemCard(_ item: CarouselMediaItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                replacingID = item.id
                showPicker = true
            } label: {
                thumbnail(item)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Replace item")

            if canRemove {
                Button {
                    remove(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(.black.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityLabel("Remove item")
            }
        }
    }

    private func thumbnail(_ item: CarouselMediaItem) -> some View {
        ZStack {
            if let image = posters[item.fileName] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.08)
                ProgressView()
                    .tint(.white)
            }
            if ComposerMediaStill.isVideo(store.mediaURL(for: item.fileName)) {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(.black.opacity(0.4), in: Circle())
            }
        }
        .frame(width: 96, height: 128)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var addCard: some View {
        Button {
            replacingID = nil
            showPicker = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                Text("Add")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.white.opacity(0.86))
            .frame(width: 96, height: 128)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .buttonStyle(.plain)
        .disabled(isImporting)
        .accessibilityLabel("Add media")
    }

    private func remove(_ item: CarouselMediaItem) {
        guard canRemove, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            update { block in
                let current = CarouselMotion.wrapped(block.carouselIndex, count: block.carouselItems.count)
                block.carouselItems.removeAll { $0.id == item.id }
                block.carouselIndex = CarouselMotion.indexAfterRemoval(
                    index: current,
                    removedAt: index,
                    countAfter: block.carouselItems.count
                )
            }
        }
    }

    private func importPicked(_ picked: [PhotosPickerItem], replacing: String?) async {
        isImporting = true
        defer { isImporting = false }
        var saved: [String] = []
        for item in picked {
            if let fileName = await ComposerMediaImport.save(item, to: store) {
                saved.append(fileName)
            }
        }
        guard !saved.isEmpty else { return }
        update { block in
            if let replacing, let index = block.carouselItems.firstIndex(where: { $0.id == replacing }), let fileName = saved.first {
                block.carouselItems[index].fileName = fileName
            } else {
                block.carouselItems.append(contentsOf: saved.map { CarouselMediaItem(fileName: $0) })
            }
        }
    }

    private func update(_ body: (inout ComposerBlock) -> Void) {
        guard var block = store.block(with: blockID, in: documentID) else { return }
        body(&block)
        if block.carouselItems.isEmpty {
            block.carouselIndex = 0
        } else {
            block.carouselIndex = CarouselMotion.wrapped(block.carouselIndex, count: block.carouselItems.count)
        }
        store.updateBlock(block, in: documentID)
    }

    private func loadPosters() async {
        for item in items {
            if posters[item.fileName] != nil { continue }
            if let image = await ComposerMediaStill.image(at: store.mediaURL(for: item.fileName)) {
                posters[item.fileName] = image
            }
        }
    }
}

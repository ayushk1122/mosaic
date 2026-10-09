import PhotosUI
import SwiftUI
import UIKit

struct PursuitWidgetEdits {
    var name: String
    var nameStyle: TextBlockStyle
    var textX: Double
    var textY: Double
    var layout: PursuitWidgetShape
    var texts: [PursuitTextItem]
    var imageZoom: Double
    var imagePanX: Double
    var imagePanY: Double
    var imageData: Data?
    var removeImage: Bool
}

private struct PursuitNameWeight: ViewModifier {
    var keepsSemibold: Bool

    func body(content: Content) -> some View {
        if keepsSemibold {
            content.fontWeight(.semibold)
        } else {
            content
        }
    }
}

struct PursuitWidgetFace: View {
    @Binding var text: String
    var textX: Double
    var textY: Double
    var style: TextBlockStyle
    var liveScale: CGFloat
    var fill: ComposerRGBColor?
    var image: UIImage?
    var imageZoom: Double = 1
    var imagePanX: Double = 0
    var imagePanY: Double = 0
    @Binding var textItems: [PursuitTextItem]
    var selectedTextID: String? = nil
    var onSelectText: ((String) -> Void)? = nil
    var showsField: Bool
    var focusBlockID: FocusState<ComposerBlockID?>.Binding
    var focusID: ComposerBlockID
    var onSubmit: () -> Void = {}
    var onTapBackground: () -> Void = {}
    var namePlaceholder: String = "Pursuit"
    var nameIsSelected: Bool = false
    var onSelectName: (() -> Void)? = nil
    var activeDrag: PursuitTextDrag = .inactive
    var textDrag: ((String, CGSize, Double, Double) -> AnyGesture<DragGesture.Value>)? = nil

    @FocusState private var textFocus: ComposerBlockID?

    var body: some View {
        GeometryReader { proxy in
            let frameSize = proxy.size
            let radius = min(proxy.size.width, proxy.size.height) * 0.16
            let clip = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack(alignment: .topLeading) {
                background(in: proxy.size)
                    .onTapGesture(perform: onTapBackground)
                if showsName {
                    nameContent(travel: frameSize)
                        .offset(x: textX * frameSize.width, y: textY * frameSize.height)
                        .opacity(nameIsLifted ? 0 : 1)
                        .onChange(of: nameIsSelected) { _, selected in
                            guard selected else { return }
                            focusBlockID.wrappedValue = focusID
                        }
                }
                ForEach($textItems) { item in
                    placedText(item, travel: frameSize)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(clip)
            .overlay {
                clip.stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func placedText(_ item: Binding<PursuitTextItem>, travel: CGSize) -> some View {
        let id = item.wrappedValue.id
        let selected = selectedTextID == id && onSelectText != nil
        let dragging = activeDrag.id == id
        let lifted = dragging && activeDrag.lifted
        let text = ComposerTextCanvasBlock(
            block: Binding(
                get: { item.wrappedValue.canvasBlock() },
                set: { item.wrappedValue.adopt($0) }
            ),
            isEditing: selected,
            isSelected: selected,
            isLifted: false,
            isRelocating: false,
            livePinchScale: liveScale,
            focusBlockID: $textFocus,
            onCommit: {},
            onStyleChange: {},
            showsFormatButton: false
        )
        .offset(x: item.wrappedValue.x * travel.width, y: item.wrappedValue.y * travel.height)
        .opacity(lifted ? 0 : 1)

        if let textDrag, onSelectText != nil {
            text
                .contentShape(Rectangle())
                .modifier(PursuitTextDragModifier(
                    claimsTouches: !selected,
                    gesture: textDrag(id, travel, item.wrappedValue.x, item.wrappedValue.y)
                ))
        } else {
            text
        }
    }

    private var showsName: Bool {
        let hasName = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if onSelectName != nil {
            return nameIsSelected || hasName
        }
        return showsField || hasName
    }

    private var nameIsLifted: Bool {
        activeDrag.id == PursuitTextDrag.nameID && activeDrag.lifted
    }

    @ViewBuilder
    private func background(in frame: CGSize) -> some View {
        if let image {
            framedPhoto(image, in: frame)
                .overlay(Color.black.opacity(0.28))
        } else if let fill {
            Color(red: fill.red, green: fill.green, blue: fill.blue, opacity: fill.opacity)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.white.opacity(0.08))
        }
    }

    private func framedPhoto(_ image: UIImage, in frame: CGSize) -> some View {
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        let zoom = CGFloat(min(max(imageZoom, 1), 4))
        let filled = MediaFraming.fillSize(contentAspect: aspect, in: frame)
        let pan = MediaFraming.clampedPan(
            CGSize(width: imagePanX * frame.width, height: imagePanY * frame.height),
            limits: MediaFraming.panLimits(contentAspect: aspect, frame: frame, zoom: zoom)
        )
        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: filled.width * zoom, height: filled.height * zoom)
            .offset(pan)
            .frame(width: frame.width, height: frame.height)
            .clipped()
    }

    @ViewBuilder
    private func nameContent(travel: CGSize) -> some View {
        if onSelectName != nil {
            let nameText = ComposerTextCanvasBlock(
                block: nameBlock,
                isEditing: nameIsSelected,
                isSelected: nameIsSelected,
                isLifted: false,
                isRelocating: false,
                livePinchScale: liveScale,
                focusBlockID: focusBlockID,
                onCommit: onSubmit,
                onStyleChange: {},
                showsFormatButton: false
            )
            if let textDrag {
                nameText
                    .contentShape(Rectangle())
                    .modifier(PursuitTextDragModifier(
                        claimsTouches: !nameIsSelected,
                        gesture: textDrag(PursuitTextDrag.nameID, travel, textX, textY)
                    ))
            } else {
                nameText
            }
        } else if showsField {
            TextField(
                "",
                text: $text,
                prompt: Text(namePlaceholder).foregroundStyle(titleColor.opacity(0.45)),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(displayFont)
            .modifier(PursuitNameWeight(keepsSemibold: !style.isBold && !style.isItalic))
            .foregroundStyle(titleColor)
            .tint(titleColor)
            .focused(focusBlockID, equals: focusID)
            .submitLabel(.done)
            .onSubmit(onSubmit)
        } else {
            let shown = text.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(shown.isEmpty ? namePlaceholder : text)
                .font(displayFont)
                .modifier(PursuitNameWeight(keepsSemibold: !style.isBold && !style.isItalic))
                .underline(style.isUnderlined && !shown.isEmpty, color: titleColor)
                .foregroundStyle(titleColor.opacity(shown.isEmpty ? 0.45 : 1))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nameBlock: Binding<ComposerBlock> {
        Binding(
            get: {
                ComposerBlock(
                    id: focusID,
                    kind: .text,
                    text: text,
                    style: style,
                    position: BlockPosition(x: textX, y: textY)
                )
            },
            set: { updated in
                text = updated.text
            }
        )
    }

    private var displayFont: Font {
        let size = style.fontSize * style.scale * Double(liveScale)
        return style.displayFont(at: size)
    }

    private var titleColor: Color {
        if let custom = style.customColor {
            return Color(red: custom.red, green: custom.green, blue: custom.blue, opacity: custom.opacity)
        }
        guard image == nil, let fill else { return .white }
        let luminance = (0.299 * fill.red) + (0.587 * fill.green) + (0.114 * fill.blue)
        return luminance > 0.72 ? MosaicBrand.inkBlack : .white
    }
}

private enum PursuitEditorPanel: Equatable {
    case tools
    case shape
    case text(String)
    case name
    case media
}

struct PursuitWidgetEditor: View {
    var onCancel: () -> Void
    var onDone: (PursuitWidgetEdits) -> Void

    @State private var name: String
    @State private var layout: PursuitWidgetShape
    @State private var textX: Double
    @State private var textY: Double
    @State private var texts: [PursuitTextItem]
    @State private var image: UIImage?
    @State private var imageZoom: Double
    @State private var imagePanX: Double
    @State private var imagePanY: Double
    @State private var imageData: Data?
    @State private var removeImage = false
    @State private var panel: PursuitEditorPanel = .tools
    @State private var controlsFrame: CGRect = .zero
    @State private var stageFrame: CGRect = .zero
    @State private var dragSession = PursuitTextDragSession()
    @GestureState private var textDragVisual = PursuitTextDrag.inactive
    @State private var pickedImage: PhotosPickerItem?
    @State private var dragOrigin: (x: Double, y: Double)?
    @State private var pinchOrigin: Double = 1
    @FocusState private var nameFocus: ComposerBlockID?

    private let fill: ComposerRGBColor?
    private let screenTitle: String
    private let namePlaceholder: String
    @State private var nameStyle: TextBlockStyle
    private let editorFocusID = ComposerBlockID(rawValue: "pursuit-widget-editor")

    init(
        name: String,
        layout: PursuitWidgetShape,
        textX: Double,
        textY: Double,
        texts: [PursuitTextItem],
        style: TextBlockStyle,
        fill: ComposerRGBColor?,
        image: UIImage?,
        imageZoom: Double,
        imagePanX: Double,
        imagePanY: Double,
        screenTitle: String = "Edit Pursuit",
        namePlaceholder: String = "Pursuit",
        onCancel: @escaping () -> Void,
        onDone: @escaping (PursuitWidgetEdits) -> Void
    ) {
        self.onCancel = onCancel
        self.onDone = onDone
        self.fill = fill
        self.screenTitle = screenTitle
        self.namePlaceholder = namePlaceholder
        _nameStyle = State(initialValue: style)
        _name = State(initialValue: name)
        _layout = State(initialValue: layout)
        _textX = State(initialValue: textX)
        _textY = State(initialValue: textY)
        _texts = State(initialValue: texts)
        _image = State(initialValue: image)
        _imageZoom = State(initialValue: imageZoom)
        _imagePanX = State(initialValue: imagePanX)
        _imagePanY = State(initialValue: imagePanY)
        _pinchOrigin = State(initialValue: imageZoom)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if panel == .media, image != nil, !textDragVisual.isMoving {
                    Text("Drag to move the photo · Pinch to zoom")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.bottom, 8)
                }
                controls
            }
            .coordinateSpace(name: "pursuitEditor")
            .onPreferenceChange(PursuitEditorTrashKey.self) { controlsFrame = $0 }
            .onPreferenceChange(PursuitStageFrameKey.self) { stageFrame = $0 }
            .overlay(alignment: .topLeading) {
                floatingDraggedText
            }
            .background(Color.black)
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: commit)
                        .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: panel) { previous, _ in
            guard case .text(let id) = previous else { return }
            guard let item = texts.first(where: { $0.id == id }) else { return }
            guard item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            deleteText(id: id)
        }
        .onChange(of: pickedImage) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    imageData = data
                    image = UIImage(data: data)
                    removeImage = false
                }
                pickedImage = nil
            }
        }
    }

    private var moduleSize: CGSize {
        layout.moduleSize(scale: CGFloat(nameStyle.scale))
    }

    /// Same zoom the pursuit face uses, so a dragged label stays the size the owner is looking at.
    private var editorDisplayScale: CGFloat {
        let moduleWidth = moduleSize.width
        guard moduleWidth > 0, stageFrame.width > 1 else { return 1 }
        return stageFrame.width / moduleWidth
    }

    private var stage: some View {
        GeometryReader { proxy in
            let module = moduleSize
            let fitted = previewFrame(in: proxy.size)
            let displayScale = module.width > 0 ? fitted.width / module.width : 1
            PursuitWidgetFace(
                text: $name,
                textX: textX,
                textY: textY,
                style: nameStyle,
                liveScale: 1,
                fill: fill,
                image: image,
                imageZoom: imageZoom,
                imagePanX: imagePanX,
                imagePanY: imagePanY,
                textItems: $texts,
                selectedTextID: selectedTextID,
                onSelectText: { id in
                    panel = .text(id)
                },
                showsField: false,
                focusBlockID: $nameFocus,
                focusID: editorFocusID,
                onTapBackground: {
                    if case .media = panel { return }
                    if textDragVisual.isMoving { return }
                    panel = .tools
                },
                namePlaceholder: namePlaceholder,
                nameIsSelected: nameIsSelected,
                onSelectName: {
                    panel = .name
                },
                activeDrag: textDragVisual,
                textDrag: { id, travel, originX, originY in
                    self.itemDrag(id: id, travel: travel, originX: originX, originY: originY)
                }
            )
            .frame(width: module.width, height: module.height)
            .scaleEffect(displayScale)
            .frame(width: fitted.width, height: fitted.height)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PursuitStageFrameKey.self,
                        value: proxy.frame(in: .named("pursuitEditor"))
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(mediaDrag(in: module, displayScale: displayScale), including: canFrameMedia ? .all : .none)
            .simultaneousGesture(mediaPinch(in: module), including: canFrameMedia ? .all : .none)
        }
    }

    private var nameIsSelected: Bool {
        if case .name = panel { return true }
        return false
    }

    private var selectedTextID: String? {
        if case .text(let id) = panel { return id }
        return nil
    }

    private var canFrameMedia: Bool {
        panel == .media && image != nil
    }

    private var controls: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                switch panel {
                case .tools:
                    rootTools
                case .shape:
                    shapeTools
                case .text:
                    textTools
                case .name:
                    nameTools
                case .media:
                    mediaTools
                }
            }
            .opacity(textDragVisual.isMoving ? 0 : 1)
            .allowsHitTesting(!textDragVisual.isMoving)

            if textDragVisual.isMoving {
                trashBar
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.20, green: 0.21, blue: 0.23))
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PursuitEditorTrashKey.self,
                    value: proxy.frame(in: .named("pursuitEditor"))
                )
            }
        }
    }

    private var trashBar: some View {
        Image(systemName: "trash.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(
                textDragVisual.hoveringTrash ? Color.red.opacity(0.92) : Color(red: 0.36, green: 0.18, blue: 0.18),
                in: Circle()
            )
            .overlay(Circle().stroke(Color.white.opacity(textDragVisual.hoveringTrash ? 0.45 : 0.14), lineWidth: textDragVisual.hoveringTrash ? 2 : 1))
            .scaleEffect(textDragVisual.hoveringTrash ? 1.1 : 1)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Drop here to delete")
    }

    private var rootTools: some View {
        HStack(spacing: 28) {
            toolButton("Shape", systemImage: "square.on.circle", isActive: false) {
                panel = .shape
            }
            toolButton("Text", systemImage: "textformat", isActive: false) {
                addTextBox()
            }
            toolButton("Background", systemImage: "photo", isActive: image != nil) {
                panel = .media
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    private var shapeTools: some View {
        HStack(spacing: 4) {
            backButton
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PursuitWidgetShape.allCases, id: \.self) { option in
                        Button {
                            layout = option
                        } label: {
                            PursuitShapeGlyph(layout: option, isSelected: layout == option)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.label)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var textTools: some View {
        Group {
            if let index = selectedTextIndex {
                styleTools(style: $texts[index].style) {
                    deleteText(id: texts[index].id)
                }
            }
        }
    }

    private var nameTools: some View {
        styleTools(style: $nameStyle, onDelete: nil)
    }

    private func styleTools(style: Binding<TextBlockStyle>, onDelete: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 4) {
            backButton
            ComposerTextStylePanel(
                style: style,
                onChange: {},
                showsSize: true,
                onDelete: onDelete,
                fillsBar: true
            )
            .padding(.trailing, 12)
        }
    }

    private var mediaTools: some View {
        HStack(spacing: 12) {
            backButton
            PhotosPicker(selection: $pickedImage, matching: .images) {
                toolLabel(image == nil ? "Add photo" : "Change photo", systemImage: "photo", isActive: image != nil)
            }
            .buttonStyle(.plain)
            if image != nil {
                Button {
                    image = nil
                    imageData = nil
                    removeImage = true
                    imageZoom = 1
                    imagePanX = 0
                    imagePanY = 0
                } label: {
                    toolLabel("Remove photo", systemImage: "xmark", isActive: false)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var backButton: some View {
        Button {
            panel = .tools
        } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .padding(.leading, 8)
    }

    private var selectedTextIndex: Int? {
        guard case .text(let id) = panel else { return nil }
        return texts.firstIndex(where: { $0.id == id })
    }

    private func addTextBox() {
        let y = min(0.42 + Double(texts.count) * 0.14, 0.78)
        let item = PursuitTextItem(text: "text", x: 0.08, y: y)
        texts.append(item)
        panel = .text(item.id)
    }

    private func deleteText(id: String) {
        texts.removeAll { $0.id == id }
        if case .text(let selected) = panel, selected == id {
            panel = .tools
        }
    }

    private var trashHitRect: CGRect {
        controlsFrame.insetBy(dx: -20, dy: -20)
    }

    private func itemDrag(id: String, travel: CGSize, originX: Double, originY: Double) -> AnyGesture<DragGesture.Value> {
        AnyGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("pursuitEditor"))
            .updating($textDragVisual) { value, visual, _ in
                if dragSession.id != id {
                    dragSession.id = id
                    dragSession.started = Date()
                    dragSession.originX = originX
                    dragSession.originY = originY
                    dragSession.travel = travel
                    dragSession.baseline = nil
                    dragSession.didHaptic = false
                    dragSession.hoveringTrash = false
                }

                let elapsed = Date().timeIntervalSince(dragSession.started)
                let distance = hypot(value.translation.width, value.translation.height)
                var next = PursuitTextDrag.inactive
                next.id = id

                if elapsed >= 0.28 {
                    next.lifted = true
                    if !dragSession.didHaptic {
                        dragSession.didHaptic = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }

                if elapsed >= 0.32, distance > 6 {
                    if dragSession.baseline == nil {
                        dragSession.baseline = value.translation
                    }
                    let baseline = dragSession.baseline ?? .zero
                    next.isMoving = true
                    next.translation = CGSize(
                        width: value.translation.width - baseline.width,
                        height: value.translation.height - baseline.height
                    )
                    let hit = controlsFrame.width > 1 && trashHitRect.contains(value.location)
                    next.hoveringTrash = hit
                    dragSession.hoveringTrash = hit
                    dragSession.lastTranslation = next.translation
                }

                visual = next
            }
            .onEnded { value in
                let elapsed = Date().timeIntervalSince(dragSession.started)
                let distance = hypot(value.translation.width, value.translation.height)
                let didMove = dragSession.baseline != nil
                let translation = dragSession.lastTranslation
                let shouldDelete = dragSession.hoveringTrash
                let originX = dragSession.originX
                let originY = dragSession.originY
                dragSession.reset()

                if didMove {
                    if shouldDelete {
                        if id == PursuitTextDrag.nameID {
                            name = ""
                            panel = .tools
                        } else {
                            deleteText(id: id)
                        }
                    } else {
                        let width = max(stageFrame.width, 1)
                        let height = max(stageFrame.height, 1)
                        let nextX = min(max(originX + Double(translation.width) / Double(width), 0), 1)
                        let nextY = min(max(originY + Double(translation.height) / Double(height), 0), 1)
                        if id == PursuitTextDrag.nameID {
                            textX = nextX
                            textY = nextY
                        } else if let index = texts.firstIndex(where: { $0.id == id }) {
                            texts[index].x = nextX
                            texts[index].y = nextY
                        }
                    }
                } else if distance < 12, elapsed < 0.32 {
                    panel = id == PursuitTextDrag.nameID ? .name : .text(id)
                }
            }
        )
    }

    private func previewFrame(in size: CGSize) -> CGSize {
        let maxWidth = max(size.width - 40, 120)
        let maxHeight = max(size.height - 24, 120)
        let aspect = layout.aspect
        var width = maxWidth
        var height = width / aspect
        if height > maxHeight {
            height = maxHeight
            width = height * aspect
        }
        return CGSize(width: width, height: height)
    }

    private func mediaDrag(in module: CGSize, displayScale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("pursuitEditor"))
            .onChanged { value in
                guard image != nil else { return }
                let scale = max(displayScale, 0.01)
                let origin = dragOrigin ?? (imagePanX, imagePanY)
                if dragOrigin == nil {
                    dragOrigin = origin
                }
                let aspect = imageAspect
                let zoom = CGFloat(min(max(imageZoom, 1), 4))
                let proposed = CGSize(
                    width: origin.x * module.width + value.translation.width / scale,
                    height: origin.y * module.height + value.translation.height / scale
                )
                let clamped = MediaFraming.clampedPan(
                    proposed,
                    limits: MediaFraming.panLimits(contentAspect: aspect, frame: module, zoom: zoom)
                )
                imagePanX = module.width > 0 ? clamped.width / module.width : 0
                imagePanY = module.height > 0 ? clamped.height / module.height : 0
            }
            .onEnded { _ in
                dragOrigin = nil
            }
    }

    private func mediaPinch(in frame: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                imageZoom = min(max(pinchOrigin * Double(value), 1), 4)
            }
            .onEnded { _ in
                pinchOrigin = imageZoom
            }
    }

    private var imageAspect: CGFloat {
        guard let image, image.size.height > 0 else { return 1 }
        return image.size.width / image.size.height
    }

    private func commit() {
        onDone(PursuitWidgetEdits(
            name: name,
            nameStyle: nameStyle,
            textX: textX,
            textY: textY,
            layout: layout,
            texts: texts.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            imageZoom: imageZoom,
            imagePanX: imagePanX,
            imagePanY: imagePanY,
            imageData: imageData,
            removeImage: removeImage
        ))
    }

    @ViewBuilder
    private var floatingDraggedText: some View {
        if textDragVisual.lifted, let id = textDragVisual.id, stageFrame.width > 1 {
            let origin = floatingOrigin(for: id)
            floatingPiece(id: id)
                .scaleEffect(editorDisplayScale, anchor: .topLeading)
                .offset(
                    x: origin.x + textDragVisual.translation.width,
                    y: origin.y + textDragVisual.translation.height
                )
                .opacity(0.96)
                .allowsHitTesting(false)
        }
    }

    private func floatingOrigin(for id: String) -> CGPoint {
        let fractionX: Double
        let fractionY: Double
        if id == PursuitTextDrag.nameID {
            fractionX = textX
            fractionY = textY
        } else if let item = texts.first(where: { $0.id == id }) {
            fractionX = item.x
            fractionY = item.y
        } else {
            fractionX = 0
            fractionY = 0
        }
        return CGPoint(
            x: stageFrame.minX + fractionX * stageFrame.width,
            y: stageFrame.minY + fractionY * stageFrame.height
        )
    }

    private func floatingPiece(id: String) -> some View {
        let block = floatingBlock(id: id)
        return ComposerTextCanvasBlock(
            block: Binding(get: { block }, set: { _ in }),
            isEditing: false,
            isSelected: false,
            isLifted: true,
            isRelocating: textDragVisual.isMoving,
            livePinchScale: 1,
            focusBlockID: $nameFocus,
            onCommit: {},
            onStyleChange: {},
            showsFormatButton: false
        )
    }

    private func floatingBlock(id: String) -> ComposerBlock {
        if id == PursuitTextDrag.nameID {
            return ComposerBlock(
                id: editorFocusID,
                kind: .text,
                text: name,
                style: nameStyle,
                position: BlockPosition(x: textX, y: textY)
            )
        }
        if let item = texts.first(where: { $0.id == id }) {
            return item.canvasBlock()
        }
        return ComposerBlock(
            id: ComposerBlockID(rawValue: id),
            kind: .text,
            text: "",
            style: .bodyDefault,
            position: BlockPosition(x: 0, y: 0)
        )
    }

    private func toolButton(_ title: String, systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolLabel(title, systemImage: systemImage, isActive: isActive)
        }
        .buttonStyle(.plain)
    }

    private func toolLabel(_ title: String, systemImage: String, isActive: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(isActive ? 0.2 : 0.08), in: Circle())
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.92))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

struct PursuitTextDrag: Equatable {
    static let nameID = "pursuit-name"

    var id: String?
    var lifted: Bool
    var isMoving: Bool
    var translation: CGSize
    var hoveringTrash: Bool

    static let inactive = PursuitTextDrag(
        id: nil,
        lifted: false,
        isMoving: false,
        translation: .zero,
        hoveringTrash: false
    )
}

private final class PursuitTextDragSession {
    var id: String?
    var started = Date()
    var originX: Double = 0
    var originY: Double = 0
    var travel: CGSize = CGSize(width: 1, height: 1)
    var baseline: CGSize?
    var didHaptic = false
    var hoveringTrash = false
    var lastTranslation: CGSize = .zero

    func reset() {
        id = nil
        baseline = nil
        didHaptic = false
        hoveringTrash = false
        lastTranslation = .zero
    }
}

private struct PursuitStageFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct PursuitTextDragModifier<Drag: Gesture>: ViewModifier {
    var claimsTouches: Bool
    var gesture: Drag

    func body(content: Content) -> some View {
        if claimsTouches {
            content.highPriorityGesture(gesture)
        } else {
            content.simultaneousGesture(gesture)
        }
    }
}

private struct PursuitEditorTrashKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct PursuitShapeGlyph: View {
    var layout: PursuitWidgetShape
    var isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .stroke(isSelected ? MosaicBrand.inkBlack : Color.white.opacity(0.92), lineWidth: 1.5)
            .frame(width: glyphSize.width, height: glyphSize.height)
            .frame(width: 44, height: 44)
            .background(isSelected ? MosaicBrand.cream : Color.white.opacity(0.08), in: Circle())
    }

    private var glyphSize: CGSize {
        let aspect = layout.aspect
        if aspect >= 1 {
            return CGSize(width: 26, height: max(10, 26 / aspect))
        }
        return CGSize(width: max(10, 26 * aspect), height: 26)
    }
}

extension PursuitWidgetShape {
    /// Resting size of the pursuit widget on the Mosaic board.
    func moduleSize(scale: CGFloat) -> CGSize {
        size(base: max(96, 168 * scale))
    }

    func size(base: CGFloat) -> CGSize {
        let aspect = self.aspect
        if aspect >= 1 {
            return CGSize(width: base * aspect, height: base)
        }
        return CGSize(width: base, height: base / aspect)
    }
}

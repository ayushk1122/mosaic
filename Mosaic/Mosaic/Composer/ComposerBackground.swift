import PhotosUI
import SwiftUI

extension ComposerRGBColor {
    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct ComposerBoardBackdrop: View {
    @Environment(\.composerMediaVersions) private var mediaVersions

    var background: ComposerBoardBackground?
    var mediaURL: URL?
    var fallback: Color

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            fallback
            backdrop
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .task(id: ComposerMediaLoadKey(mediaURL, versions: mediaVersions)) {
            let url = mediaURL
            let loaded = await Task.detached(priority: .userInitiated) {
                url.flatMap(ComposerAnimatedImage.image(contentsOf:))
            }.value
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        if let background {
            switch background.kind {
            case .solid:
                background.color.color
            case .gradient:
                LinearGradient(
                    colors: [background.color.color, background.secondaryColor.color],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .media:
                if let image {
                    ComposerPicture(image: image)
                }
            }
        }
    }
}

struct ComposerBackgroundEditor: View {
    let documentID: ComposerDocumentID?
    var starting: ComposerBoardBackground?
    var fallback: ComposerRGBColor
    var mediaURL: (String) -> URL
    var saveImage: (Data) throws -> String
    var onChange: (ComposerBoardBackground?) -> Void
    var onClose: () -> Void

    @State private var draft: ComposerBoardBackground
    @State private var isCustom: Bool
    @State private var pickedItem: PhotosPickerItem?

    init(
        documentID: ComposerDocumentID?,
        starting: ComposerBoardBackground?,
        fallback: ComposerRGBColor,
        mediaURL: @escaping (String) -> URL,
        saveImage: @escaping (Data) throws -> String,
        onChange: @escaping (ComposerBoardBackground?) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.documentID = documentID
        self.starting = starting
        self.fallback = fallback
        self.mediaURL = mediaURL
        self.saveImage = saveImage
        self.onChange = onChange
        self.onClose = onClose
        _draft = State(initialValue: starting ?? .solid(fallback))
        _isCustom = State(initialValue: starting != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ComposerBoardBackdrop(
                        background: isCustom ? draft : nil,
                        mediaURL: draft.mediaFileName.map(mediaURL),
                        fallback: fallback.color
                    )
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Picker("Style", selection: kindBinding) {
                        Text("Color").tag(ComposerBoardBackground.Kind.solid)
                        Text("Gradient").tag(ComposerBoardBackground.Kind.gradient)
                        Text("Photo").tag(ComposerBoardBackground.Kind.media)
                    }
                    .pickerStyle(.segmented)

                    if draft.kind == .media {
                        photoControls
                    } else if draft.kind == .gradient {
                        colorWell("Top", color: draft.color) { draft.color = $0 }
                        colorWell("Bottom", color: draft.secondaryColor) { draft.secondaryColor = $0 }
                    } else {
                        colorWell("Color", color: draft.color) { picked in
                            draft.color = picked
                            draft.secondaryColor = picked
                        }
                    }

                    Button("Use the original background") {
                        isCustom = false
                        onChange(nil)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(20)
            }
            .background(MosaicBrand.inkBlack)
            .navigationTitle("Background")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let fileName = try? saveImage(data) else { return }
                draft.kind = .media
                draft.mediaFileName = fileName
                publish()
            }
        }
    }

    private var kindBinding: Binding<ComposerBoardBackground.Kind> {
        Binding(
            get: { draft.kind },
            set: { kind in
                draft.kind = kind
                if kind == .gradient, draft.color == draft.secondaryColor {
                    draft.secondaryColor = ComposerRGBColor(
                        red: min(draft.color.red + 0.35, 1),
                        green: min(draft.color.green + 0.35, 1),
                        blue: min(draft.color.blue + 0.35, 1)
                    )
                }
                publish()
            }
        )
    }

    private var photoControls: some View {
        PhotosPicker(selection: $pickedItem, matching: .images) {
            Label(draft.mediaFileName == nil ? "Choose a photo" : "Replace photo", systemImage: "photo")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func colorWell(_ title: String, color: ComposerRGBColor, onPick: @escaping (ComposerRGBColor) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            ComposerColorSquare(color: color.color) { red, green, blue in
                onPick(ComposerRGBColor(red: red, green: green, blue: blue))
                publish()
            }
        }
    }

    private func publish() {
        isCustom = true
        onChange(draft)
    }
}

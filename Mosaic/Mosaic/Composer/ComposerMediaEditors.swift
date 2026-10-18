import AVFoundation
import SwiftUI
import UIKit

struct ComposerImageCropEditor: View {
    let image: UIImage
    var onCancel: () -> Void
    var onChoose: (UIImage) -> Void

    @State private var aspect: CropAspect = .original
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                cropStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Picker("Aspect", selection: $aspect) {
                    ForEach(CropAspect.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .background(Color.black)
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Choose") {
                        if let cropped = renderedCrop() {
                            onChoose(cropped)
                        } else {
                            onCancel()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var cropStage: some View {
        GeometryReader { proxy in
            let cropSize = aspect.size(fitting: image, in: proxy.size)
            ZStack {
                Color.black
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: cropSize.width, height: cropSize.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .frame(width: cropSize.width, height: cropSize.height)
                    .clipped()
                    .overlay {
                        Rectangle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 4)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    @MainActor
    private func renderedCrop() -> UIImage? {
        let cropSize = CGSize(width: 900, height: 900 / aspect.ratio(for: image))
        let content = Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: cropSize.width, height: cropSize.height)
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: cropSize.width, height: cropSize.height)
            .clipped()
        let renderer = ImageRenderer(content: content)
        renderer.scale = image.scale
        return renderer.uiImage
    }
}

private enum CropAspect: String, CaseIterable, Identifiable {
    case original
    case square
    case fourFive
    case widescreen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: "Original"
        case .square: "Square"
        case .fourFive: "4:5"
        case .widescreen: "16:9"
        }
    }

    func ratio(for image: UIImage) -> CGFloat {
        switch self {
        case .original:
            image.size.width / max(image.size.height, 1)
        case .square:
            1
        case .fourFive:
            4.0 / 5.0
        case .widescreen:
            16.0 / 9.0
        }
    }

    func size(fitting image: UIImage, in container: CGSize) -> CGSize {
        let available = CGSize(
            width: max(container.width - 48, 40),
            height: max(container.height - 48, 40)
        )
        return fittedSize(ratio: ratio(for: image), in: available)
    }

    private func fittedSize(ratio: CGFloat, in container: CGSize) -> CGSize {
        var width = container.width
        var height = width / max(ratio, 0.2)
        if height > container.height {
            height = container.height
            width = height * ratio
        }
        return CGSize(width: width, height: height)
    }
}

enum ComposerVideoCompatibility {
    static func editableURL(for url: URL) async -> URL? {
        if UIVideoEditorController.canEditVideo(atPath: url.path) {
            return url
        }
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            return nil
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mp4")
        do {
            try await export.export(to: output, as: .mp4)
        } catch {
            return nil
        }
        guard UIVideoEditorController.canEditVideo(atPath: output.path) else {
            try? FileManager.default.removeItem(at: output)
            return nil
        }
        return output
    }

    /// Removes the temporary copy `editableURL` exported, never the board's own file.
    static func discardExport(_ exported: URL, source: URL) {
        guard exported.standardizedFileURL != source.standardizedFileURL,
              exported.path.hasPrefix(FileManager.default.temporaryDirectory.path) else { return }
        try? FileManager.default.removeItem(at: exported)
    }
}

struct ComposerVideoTrimEditor: UIViewControllerRepresentable {
    let url: URL
    var maximumDuration: TimeInterval = 600
    var onCancel: () -> Void
    var onSave: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCancel: onCancel, onSave: onSave)
    }

    func makeUIViewController(context: Context) -> UIVideoEditorController {
        let editor = UIVideoEditorController()
        editor.videoPath = url.path
        editor.videoMaximumDuration = max(maximumDuration, 1)
        editor.delegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ uiViewController: UIVideoEditorController, context: Context) {}

    final class Coordinator: NSObject, UIVideoEditorControllerDelegate, UINavigationControllerDelegate {
        let onCancel: () -> Void
        let onSave: (URL) -> Void

        init(onCancel: @escaping () -> Void, onSave: @escaping (URL) -> Void) {
            self.onCancel = onCancel
            self.onSave = onSave
        }

        func videoEditorController(_ editor: UIVideoEditorController, didSaveEditedVideoToPath editedVideoPath: String) {
            onSave(URL(fileURLWithPath: editedVideoPath))
        }

        func videoEditorControllerDidCancel(_ editor: UIVideoEditorController) {
            onCancel()
        }

        func videoEditorController(_ editor: UIVideoEditorController, didFailWithError error: Error) {
            onCancel()
        }
    }
}

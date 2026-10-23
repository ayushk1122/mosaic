import CoreImage
import ImageIO
import SwiftUI
import UIKit
import Vision

/// Lifts subjects out of a photo with Vision's foreground instance masks, the same subject lifting
/// Photos uses. Runs on the phone; Vision's work happens off the main thread.
nonisolated final class ComposerCutoutSession: @unchecked Sendable {
    /// The photo, upright, that the subjects were found in.
    let image: UIImage
    private let handler: VNImageRequestHandler
    private let observation: VNInstanceMaskObservation
    /// Vision's handler and observation aren't safe to use from several threads at once; the
    /// editor asks for previews and taps from different tasks, so every use takes turns.
    private let lock = NSLock()

    var subjects: IndexSet { observation.allInstances }

    private init(image: UIImage, handler: VNImageRequestHandler, observation: VNInstanceMaskObservation) {
        self.image = image
        self.handler = handler
        self.observation = observation
    }

    /// Nil when the photo has no clear subject (or this device can't lift one).
    static func find(in photo: UIImage) -> ComposerCutoutSession? {
        guard let upright = ComposerStickerArt.upright(photo, maxPixel: 3000), let cgImage = upright.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
        return ComposerCutoutSession(image: upright, handler: handler, observation: observation)
    }

    /// The subject under a point given as a fraction of the photo (0…1, top-left origin).
    func subject(at point: CGPoint) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        let mask = observation.instanceMask
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        guard let base = CVPixelBufferGetBaseAddress(mask), width > 0, height > 0,
              (0...1).contains(point.x), (0...1).contains(point.y) else { return nil }
        let x = min(Int(point.x * CGFloat(width)), width - 1)
        let y = min(Int(point.y * CGFloat(height)), height - 1)
        let row = base.advanced(by: y * CVPixelBufferGetBytesPerRow(mask))
        let label = Int(row.assumingMemoryBound(to: UInt8.self)[x])
        return label == 0 ? nil : label
    }

    /// The chosen subjects on a transparent background, either the full photo's size (to lay over
    /// it as a preview) or cropped to the subjects.
    func lifted(_ instances: IndexSet, cropped: Bool) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        guard !instances.isEmpty,
              let buffer = try? observation.generateMaskedImage(
                  ofInstances: instances,
                  from: handler,
                  croppedToInstancesExtent: cropped
              ) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = ComposerStickerArt.context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

nonisolated enum ComposerStickerArt {
    static let context = CIContext()
    /// Longest side of a saved sticker, in pixels.
    static let maxPixel: CGFloat = 2048
    /// Transparent room around the subject, as a share of the sticker's longest side, so the border fits.
    static let paddingShare: CGFloat = 0.03
    static let borderShare: CGFloat = 0.024
    /// Longest side a new sticker starts at on the board, in points.
    static let placedLongSide: CGFloat = 220

    static func upright(_ image: UIImage, maxPixel: CGFloat) -> UIImage? {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longest = max(pixels.width, pixels.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxPixel / longest)
        if image.imageOrientation == .up, scale == 1, image.cgImage != nil { return image }
        let size = CGSize(width: (pixels.width * scale).rounded(), height: (pixels.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// The cut-out subject as a PNG, no larger than `maxPixel`, with transparent room for its border.
    static func stickerPNG(from cutout: UIImage) -> (data: Data, size: CGSize)? {
        let pixels = CGSize(width: cutout.size.width * cutout.scale, height: cutout.size.height * cutout.scale)
        let subjectLongest = max(pixels.width, pixels.height)
        guard subjectLongest > 0 else { return nil }
        // The canvas's longest side L holds the subject plus padding on both sides: L = s + 2 · share · L.
        let canvasLongest = min(subjectLongest / (1 - 2 * paddingShare), maxPixel)
        let padding = (canvasLongest * paddingShare).rounded(.up)
        let fit = (canvasLongest - 2 * padding) / subjectLongest
        let subject = CGSize(width: (pixels.width * fit).rounded(), height: (pixels.height * fit).rounded())
        let canvas = CGSize(width: subject.width + 2 * padding, height: subject.height + 2 * padding)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            cutout.draw(in: CGRect(x: padding, y: padding, width: subject.width, height: subject.height))
        }
        guard let data = image.pngData() else { return nil }
        return (data, canvas)
    }

    /// Board size for a new sticker: its own shape, `placedLongSide` on the longest side.
    static func placedSize(for pixels: CGSize) -> CGSize {
        let longest = max(pixels.width, pixels.height)
        guard longest > 0 else { return CGSize(width: placedLongSide, height: placedLongSide) }
        let scale = placedLongSide / longest
        return CGSize(width: (pixels.width * scale).rounded(), height: (pixels.height * scale).rounded())
    }

    /// The classic white sticker border: the subject's silhouette grown outward in white, under it.
    static func bordered(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        let radius = max(CGFloat(max(cgImage.width, cgImage.height)) * borderShare, 3)
        let silhouette = input.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
        ])
        let border = silhouette
            .applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": radius])
            .cropped(to: input.extent)
        let combined = input.composited(over: border)
        guard let output = context.createCGImage(combined, from: input.extent) else { return nil }
        return UIImage(cgImage: output, scale: image.scale, orientation: .up)
    }

    /// Longest side an emoji sticker starts at on the board, in points.
    static let emojiPlacedSide: CGFloat = 120

    /// The first emoji in some text, so typing or pasting into the emoji field places just that.
    static func firstEmoji(in text: String) -> String? {
        text.first { character in
            let scalars = character.unicodeScalars
            guard let first = scalars.first else { return false }
            return first.properties.isEmojiPresentation || (first.properties.isEmoji && scalars.count > 1)
        }.map(String.init)
    }

    /// An emoji drawn large on a transparent square, with room for the border like a cutout.
    static func emojiImage(_ emoji: String, side: CGFloat = 360) -> UIImage? {
        guard !emoji.isEmpty else { return nil }
        let padding = (side * paddingShare).rounded(.up)
        let room = side - 2 * padding
        let probe = UIFont.systemFont(ofSize: 100)
        let measured = (emoji as NSString).size(withAttributes: [.font: probe])
        guard measured.width > 0, measured.height > 0 else { return nil }
        let font = UIFont.systemFont(ofSize: 100 * min(room / measured.width, room / measured.height))
        let drawn = (emoji as NSString).size(withAttributes: [.font: font])
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            (emoji as NSString).draw(
                at: CGPoint(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2),
                withAttributes: [.font: font]
            )
        }
    }

    static func emojiArt(_ emoji: String, bordered wantsBorder: Bool) -> UIImage? {
        let key = "emoji#\(emoji)#\(wantsBorder)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = emojiImage(emoji) else { return nil }
        let art = wantsBorder ? (bordered(image) ?? image) : image
        cache.setObject(art, forKey: key, cost: cost(of: art))
        return art
    }

    /// Bounded by decoded pixel bytes, so a library of large stickers can't grow memory without limit.
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 160 * 1024 * 1024
        return cache
    }()

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }

    /// A small copy for the Stickers sheet's tiles, decoded at tile size rather than full size.
    static func thumbnail(at url: URL, version: Int, maxPixel: CGFloat = 256) -> UIImage? {
        let key = "thumb#\(url.lastPathComponent)#\(version)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                  kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let small = UIImage(cgImage: cgImage)
        let art = bordered(small) ?? small
        cache.setObject(art, forKey: key, cost: cost(of: art))
        return art
    }

    /// The sticker image ready to draw, bordered or not, cached by file and version.
    static func art(at url: URL, bordered wantsBorder: Bool, version: Int) -> UIImage? {
        let key = "\(url.lastPathComponent)#\(version)#\(wantsBorder)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        let art = wantsBorder ? (bordered(image) ?? image) : image
        cache.setObject(art, forKey: key, cost: cost(of: art))
        return art
    }
}

struct ComposerStickerCanvasBlock: View {
    let block: ComposerBlock
    let mediaURL: URL?
    var livePinchScale: CGFloat

    @Environment(\.composerMediaVersions) private var mediaVersions
    @State private var art: UIImage?

    var body: some View {
        let scale = CGFloat(max(block.style.scale, 0.05)) * livePinchScale
        let size = CGSize(
            width: max(block.stickerWidth, 20) * scale,
            height: max(block.stickerHeight, 20) * scale
        )
        let version = block.mediaFileName.map { mediaVersions[$0] ?? 0 } ?? 0
        ZStack {
            if let art {
                Image(uiImage: art)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("Sticker")
        .task(id: "\(mediaURL?.lastPathComponent ?? block.text)#\(version)#\(block.stickerBorder)") {
            let wantsBorder = block.stickerBorder
            let emoji = block.text
            let loaded: UIImage?
            if let mediaURL {
                loaded = await Task.detached(priority: .userInitiated) {
                    ComposerStickerArt.art(at: mediaURL, bordered: wantsBorder, version: version)
                }.value
            } else if !emoji.isEmpty {
                loaded = await Task.detached(priority: .userInitiated) {
                    ComposerStickerArt.emojiArt(emoji, bordered: wantsBorder)
                }.value
            } else {
                loaded = nil
            }
            guard !Task.isCancelled else { return }
            art = loaded
        }
    }
}

/// Lifts the subject out of a photo: shows the photo dimmed with the subject bright, lets the
/// person tap subjects in or out when there are several, then hands back the sticker PNG.
struct ComposerCutoutEditor: View {
    let photo: UIImage
    var onCancel: () -> Void
    var onDone: (_ png: Data, _ pixelSize: CGSize) -> Void

    private enum Phase {
        case finding
        case none
        case ready(ComposerCutoutSession)
    }

    @State private var phase = Phase.finding
    @State private var chosen = IndexSet()
    @State private var preview: UIImage?
    @State private var isSaving = false
    /// Cancelled with the editor, so a cutout still being made isn't placed after Cancel.
    @State private var saveTask: Task<Void, Never>?
    /// The photo at screen size; drawing a 48-megapixel original would take hundreds of MB.
    @State private var shownPhoto: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Button("Cancel") {
                        saveTask?.cancel()
                        onCancel()
                    }
                    .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 0)
                stage
                Spacer(minLength: 0)

                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    save()
                } label: {
                    Text(isSaving ? "Adding…" : "Add sticker")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MosaicBrand.inkBlack)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.4)
                .padding(.bottom, 24)
                .accessibilityIdentifier("cutout.add")
            }
        }
        .onDisappear { saveTask?.cancel() }
        .task {
            let image = photo
            shownPhoto = await image.byPreparingThumbnail(ofSize: Self.shownSize(of: image.size))
            let session = await Task.detached(priority: .userInitiated) {
                ComposerCutoutSession.find(in: image)
            }.value
            guard let session else {
                phase = .none
                return
            }
            chosen = session.subjects
            phase = .ready(session)
            await refreshPreview(session)
        }
    }

    private var canSave: Bool {
        if case .ready = phase { return !chosen.isEmpty && !isSaving }
        return false
    }

    private var hint: String {
        switch phase {
        case .finding: "Finding the subject…"
        case .none: "No clear subject in this photo. Try one with a person, pet, or object in front."
        case .ready(let session):
            session.subjects.count > 1 ? "Tap a subject to leave it out or bring it back." : "The subject is lifted out of the photo."
        }
    }

    @ViewBuilder
    private var stage: some View {
        GeometryReader { proxy in
            let fitted = fittedSize(of: photo.size, in: proxy.size)
            ZStack {
                Image(uiImage: shownPhoto ?? photo)
                    .resizable()
                    .opacity(isReady ? 0.3 : 1)
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .shadow(color: .white.opacity(0.35), radius: 8)
                        .transition(.opacity)
                }
                if case .finding = phase {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: fitted.width, height: fitted.height)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    toggleSubject(at: CGPoint(x: value.location.x / fitted.width, y: value.location.y / fitted.height))
                }
            )
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .padding(.horizontal, 16)
    }

    private var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    private func fittedSize(of size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let scale = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func toggleSubject(at point: CGPoint) {
        guard case .ready(let session) = phase, session.subjects.count > 1,
              let subject = session.subject(at: point) else { return }
        if chosen.contains(subject) {
            guard chosen.count > 1 else { return }
            chosen.remove(subject)
        } else {
            chosen.insert(subject)
        }
        UISelectionFeedbackGenerator().selectionChanged()
        Task { await refreshPreview(session) }
    }

    private func refreshPreview(_ session: ComposerCutoutSession) async {
        let instances = chosen
        let image = await Task.detached(priority: .userInitiated) {
            session.lifted(instances, cropped: false)
        }.value
        // Quick taps can finish out of order; only the preview for the current choice is shown.
        guard instances == chosen else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            preview = image
        }
    }

    private func save() {
        guard case .ready(let session) = phase, !chosen.isEmpty else { return }
        isSaving = true
        let instances = chosen
        saveTask = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (Data, CGSize)? in
                guard let cutout = session.lifted(instances, cropped: true) else { return nil }
                return ComposerStickerArt.stickerPNG(from: cutout).map { ($0.data, $0.size) }
            }.value
            isSaving = false
            guard !Task.isCancelled else { return }
            if let result {
                onDone(result.0, result.1)
            }
        }
    }

    /// At most 2048 pixels on the long side, in the photo's proportions.
    private static func shownSize(of size: CGSize) -> CGSize {
        let longest = max(size.width, size.height)
        guard longest > 2048 else { return size }
        let scale = 2048 / longest
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}

/// The Sticker sheet: "Your stickers" (saved cutouts, synced with the account) and emoji.
struct ComposerStickerSheet: View {
    enum Tab: String, CaseIterable, Identifiable {
        case yours = "Your stickers"
        case emoji = "Emoji"

        var id: String { rawValue }
    }

    let saved: [ComposerSavedSticker]
    let mediaURL: (String) -> URL
    var onFromPhoto: () -> Void
    var onPlaceSaved: (ComposerSavedSticker) -> Void
    var onPlaceEmoji: (String) -> Void
    var onRemove: (ComposerSavedSticker) -> Void
    var onClose: () -> Void

    @State private var tab = Tab.yours
    @State private var typed = ""

    /// Everyday, sport, and journal emoji to start from; any emoji can be typed or pasted too.
    static let suggestedEmoji = [
        "⛳️", "🏌️", "🏌️‍♀️", "🏆", "🥇", "🎯", "🔥", "💪", "⭐️", "✨", "❤️", "😍",
        "😂", "🥳", "🙌", "👏", "👀", "💯", "🎉", "☀️", "🌈", "🌿", "🌸", "🍀",
        "🌊", "⛰️", "🏖️", "✈️", "📍", "📸", "🎵", "🎨", "📚", "✏️", "☕️", "🍕",
        "🐶", "🐱", "⚽️", "🏀", "🎾", "🏃‍♀️", "🚴‍♂️", "🧘‍♀️", "🌙", "💡", "✅", "🙏"
    ]

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Stickers", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                ScrollView {
                    switch tab {
                    case .yours: yours
                    case .emoji: emoji
                    }
                }
            }
            .padding(.top, 8)
            .navigationTitle("Stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
    }

    private var yours: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: columns, spacing: 12) {
                Button(action: onFromPhoto) {
                    VStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.title2)
                        Text("From a photo")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stickers.fromPhoto")

                ForEach(saved) { sticker in
                    Button {
                        onPlaceSaved(sticker)
                    } label: {
                        ComposerSavedStickerTile(url: mediaURL(sticker.fileName))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove from Your stickers", systemImage: "trash", role: .destructive) {
                            onRemove(sticker)
                        }
                    }
                    .accessibilityLabel("Saved sticker")
                }
            }
            if saved.isEmpty {
                Text("Stickers you cut out of photos are saved here to use again, on any of your devices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }

    private var emoji: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Type or paste any emoji", text: $typed)
                .textFieldStyle(.roundedBorder)
                .onSubmit(placeTyped)
                .onChange(of: typed) { _, _ in placeTyped() }
                .accessibilityIdentifier("stickers.emojiField")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 10) {
                ForEach(Self.suggestedEmoji, id: \.self) { emoji in
                    Button {
                        onPlaceEmoji(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 34))
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Emoji \(emoji)")
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func placeTyped() {
        guard let emoji = ComposerStickerArt.firstEmoji(in: typed) else { return }
        typed = ""
        onPlaceEmoji(emoji)
    }
}

private struct ComposerSavedStickerTile: View {
    let url: URL
    @Environment(\.composerMediaVersions) private var mediaVersions
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                Image(systemName: "icloud.and.arrow.down")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 84)
        .task(id: "\(url.lastPathComponent)#\(mediaVersions[url.lastPathComponent] ?? 0)") {
            let target = url
            let version = mediaVersions[url.lastPathComponent] ?? 0
            image = await Task.detached(priority: .userInitiated) {
                ComposerStickerArt.thumbnail(at: target, version: version)
            }.value
        }
    }
}

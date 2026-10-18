import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// GIFs play on boards. Their frames are decoded smaller, and thinned when there are many,
/// so one GIF stays near `frameBudgetBytes` however large the file is.
enum ComposerAnimatedImage {
    nonisolated static let maxPixel = 540
    nonisolated static let frameBudgetBytes = 32 * 1024 * 1024
    /// Stills are decoded no larger than this: sharp full screen, without a 24 MP photo costing ~96 MB.
    nonisolated static let stillMaxPixel = 2400

    nonisolated static func isGIF(_ data: Data) -> Bool {
        data.starts(with: Array("GIF8".utf8))
    }

    /// An animated image for a GIF with more than one frame, otherwise the still image.
    nonisolated static func image(contentsOf url: URL) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        if let source = CGImageSourceCreateWithURL(url as CFURL, options) {
            if let animated = animated(from: source) { return animated }
            if let still = still(from: source) { return still }
        }
        return UIImage(contentsOfFile: url.path)
    }

    nonisolated static func image(data: Data) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        if let source = CGImageSourceCreateWithData(data as CFData, options) {
            if let animated = animated(from: source) { return animated }
            if let still = still(from: source) { return still }
        }
        return UIImage(data: data)
    }

    /// Decodes at display size (never upscaled) with the photo's orientation applied.
    nonisolated static func still(from source: CGImageSource) -> UIImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: stillMaxPixel
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: image)
    }

    nonisolated static func animated(from source: CGImageSource) -> UIImage? {
        guard CGImageSourceGetType(source) as String? == UTType.gif.identifier else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let first = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let frameBytes = max(first.width * first.height * 4, 1)
        var frames: [UIImage] = []
        for index in frameIndices(count: count, limit: max(2, frameBudgetBytes / frameBytes)) {
            let frame = index == 0 ? first : CGImageSourceCreateThumbnailAtIndex(source, index, options)
            if let frame { frames.append(UIImage(cgImage: frame)) }
        }
        let duration = (0..<count).reduce(0) { $0 + delay(in: source, at: $1) }
        guard frames.count > 1 else { return nil }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    /// Every frame, or `limit` frames spread evenly when there are more. The GIF keeps its full length.
    nonisolated static func frameIndices(count: Int, limit: Int) -> [Int] {
        guard count > limit else { return Array(0..<count) }
        return (0..<limit).map { $0 * count / limit }
    }

    /// Browsers play delays under 0.02 seconds at 0.1 seconds, and many GIFs are made for that.
    nonisolated static func delay(in source: CGImageSource, at index: Int) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
            ?? 0.1
        return delay < 0.02 ? 0.1 : delay
    }
}

/// A board image sized like `Image(uiImage:).resizable()` with the content mode. A GIF plays.
struct ComposerPicture: View {
    let image: UIImage
    var contentMode: ContentMode = .fill

    var body: some View {
        if image.images != nil {
            ComposerAnimatedImageView(image: image)
                .aspectRatio(image.size, contentMode: contentMode)
        } else {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        }
    }
}

private struct ComposerAnimatedImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleToFill
        view.clipsToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        guard view.image !== image else { return }
        view.image = image
        view.startAnimating()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: image.size)
    }
}

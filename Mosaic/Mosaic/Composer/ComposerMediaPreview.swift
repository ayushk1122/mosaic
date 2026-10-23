import AVFoundation
import ImageIO
import SwiftUI
import UIKit

/// A photo or video squeezed to a few colored pixels and its exact shape, saved with the board
/// (about 200 characters). Visitors see it blurred, at the right size, while the real file
/// downloads, so a board shows its look at once instead of spinners.
nonisolated struct ComposerMediaPreview: Equatable, Sendable {
    /// Width over height of the original.
    var aspect: Double
    var width: Int
    var height: Int
    /// `width * height` RGB triples, row by row.
    var pixels: Data

    static let longEdge = 8

    /// "aspect|WxH|base64", for example "1.500|8x5|…".
    var encoded: String {
        "\(String(format: "%.3f", aspect))|\(width)x\(height)|\(pixels.base64EncodedString())"
    }

    init(aspect: Double, width: Int, height: Int, pixels: Data) {
        self.aspect = aspect
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3, let aspect = Double(parts[0]), aspect.isFinite, aspect > 0.05, aspect < 20 else { return nil }
        let size = parts[1].split(separator: "x")
        guard size.count == 2, let width = Int(size[0]), let height = Int(size[1]),
              (1...Self.longEdge).contains(width), (1...Self.longEdge).contains(height),
              let pixels = Data(base64Encoded: String(parts[2])), pixels.count == width * height * 3
        else { return nil }
        self.init(aspect: aspect, width: width, height: height, pixels: pixels)
    }

    /// Nil for pictures with see-through parts (stickers): a blurred box would show around them.
    static func make(imageAt url: URL) -> ComposerMediaPreview? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return make(from: image)
    }

    /// From the video's first frame, which is what a visitor sees before pressing play.
    static func make(videoAt url: URL) async -> ComposerMediaPreview? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 64, height: 64)
        guard let frame = try? await generator.image(at: .zero).image else { return nil }
        return make(from: frame)
    }

    static func make(from image: CGImage) -> ComposerMediaPreview? {
        guard image.width > 0, image.height > 0 else { return nil }
        let aspect = Double(image.width) / Double(image.height)
        let width = aspect >= 1 ? longEdge : max(1, Int((Double(longEdge) * aspect).rounded()))
        let height = aspect >= 1 ? max(1, Int((Double(longEdge) / aspect).rounded())) : longEdge
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var rgb = Data(capacity: width * height * 3)
        for pixel in 0..<(width * height) {
            guard rgba[pixel * 4 + 3] > 245 else { return nil }
            rgb.append(contentsOf: rgba[(pixel * 4)..<(pixel * 4 + 3)])
        }
        return ComposerMediaPreview(aspect: aspect, width: width, height: height, pixels: rgb)
    }

    /// The pixels as a tiny image, to be stretched and blurred on screen.
    var image: UIImage? {
        guard let provider = CGDataProvider(data: pixels as CFData),
              let cgImage = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                bytesPerRow: width * 3, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private struct ComposerMediaPreviewsKey: EnvironmentKey {
    static let defaultValue: [String: ComposerMediaPreview] = [:]
}

extension EnvironmentValues {
    /// Blurred stand-ins by file name, for media still downloading on a visited board.
    var composerMediaPreviews: [String: ComposerMediaPreview] {
        get { self[ComposerMediaPreviewsKey.self] }
        set { self[ComposerMediaPreviewsKey.self] = newValue }
    }
}

/// A preview stretched over the space the photo will fill, blurred so its few pixels read as
/// soft color rather than squares.
struct ComposerMediaPlaceholder: View {
    let preview: ComposerMediaPreview
    var showsProgress = true

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = preview.image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        // Grown before blurring so the soft edge stays outside the frame.
                        .scaleEffect(1.15)
                        .blur(radius: min(proxy.size.width, proxy.size.height) / 14)
                }
                if showsProgress {
                    ProgressView()
                        .tint(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

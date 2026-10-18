import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import Mosaic

@Suite
struct ComposerMediaEdgeCaseTests {
    @Test
    func socialLinksOnlyLeadToThePlatformsOwnSite() {
        #expect(ComposerSocialPlatform.instagram.profileURL(from: "http://instagram.com.evil.example/login") == nil)
        #expect(ComposerSocialPlatform.instagram.profileURL(from: "https://evil.example/instagram.com") == nil)
        #expect(ComposerSocialPlatform.instagram.profileURL(from: "https://user@instagram.com/ada") == nil)
        #expect(ComposerSocialPlatform.youtube.profileURL(from: "https://youtube.com:8443/@ada") == nil)
        #expect(ComposerSocialPlatform.instagram.profileURL(from: "http://www.instagram.com/ada")?.absoluteString
                == "https://www.instagram.com/ada")
        #expect(ComposerSocialPlatform.twitter.profileURL(from: "https://x.com/ada")?.absoluteString == "https://x.com/ada")
        #expect(ComposerSocialPlatform.youtube.profileURL(from: "youtu.be/abc")?.absoluteString == "https://youtu.be/abc")
        #expect(ComposerSocialPlatform.twitch.profileURL(from: "https://m.twitch.tv/ada")?.absoluteString == "https://m.twitch.tv/ada")
    }

    @Test
    func dottedUsernamesStayUsernames() {
        #expect(ComposerSocialPlatform.instagram.profileURL(from: "maria.studio")?.absoluteString
                == "https://instagram.com/maria.studio")
        #expect(ComposerSocialPlatform.tiktok.profileURL(from: "ada.golf")?.absoluteString
                == "https://www.tiktok.com/@ada.golf")
        #expect(ComposerSocialPlatform.instagram.profileURL(from: "instagram.com/ada")?.absoluteString
                == "https://instagram.com/ada")
        #expect(ComposerSocialPlatform.instagram.profileURL(from: "evil.example/ada") == nil)
    }

    @Test
    func boardPhotosAreStoredAtABoundedSize() throws {
        let big = try #require(Self.png(width: 4000, height: 3000))
        let stored = ComposerImagePreparation.boardImage(from: big)
        #expect(stored.fileExtension == "jpg")
        let size = try #require(Self.pixelSize(stored.data))
        #expect(max(size.width, size.height) <= ComposerImagePreparation.boardMaxPixel)

        let small = try #require(Self.png(width: 400, height: 300))
        let kept = ComposerImagePreparation.boardImage(from: small)
        #expect(kept.fileExtension == "png")
        #expect(kept.data == small)

        let gif = Data("GIF89a".utf8) + Data(repeating: 0, count: 16)
        #expect(ComposerImagePreparation.boardImage(from: gif).fileExtension == "gif")
    }

    @Test
    func boardAndCropEditorAgreeOnTheFrameShape() {
        var block = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0, y: 0))
        block.mediaFrameAspect = 0
        let crop = ComposerMediaCrop(block: block)
        #expect(crop.aspect(contentAspect: 6) == MediaFrameShape.maximumAspect)
        #expect(crop.aspect(contentAspect: 0.1) == 0.4)
        #expect(crop.aspect(contentAspect: 1.5) == 1.5)
        #expect(ComposerMediaCrop.originalShape(contentAspect: 6) == crop.aspect(contentAspect: 6))
    }

    @Test
    func gifsUploadTheirOriginalFirst() throws {
        let frame = try #require(Self.png(width: 8, height: 8))
        let gif = try #require(Self.gif(from: frame))
        let payloads = ComposerMediaPreparer.photoPayloads(from: gif)
        #expect(payloads.first?.contentType == "image/gif")
        #expect(payloads.first?.original == gif)
    }

    private static func png(width: Int, height: Int) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.pngData()
    }

    private static func gif(from png: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.gif.identifier as CFString, 2, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func pixelSize(_ data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        return CGSize(width: width, height: height)
    }
}

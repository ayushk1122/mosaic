import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import Mosaic

@MainActor
@Suite
struct ComposerStickerTests {
    /// A filled circle on a transparent square, like a lifted subject.
    private func subject(size: CGFloat = 400) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size * 0.75), format: format).image { context in
            UIColor.systemOrange.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size * 0.75))
        }
    }

    private func alpha(in image: UIImage, at point: CGPoint) -> CGFloat {
        guard let cgImage = image.cgImage else { return 0 }
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.translateBy(x: -point.x, y: -(CGFloat(cgImage.height) - point.y))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        }
        return CGFloat(pixel[3]) / 255
    }

    @Test
    func newStickersHaveABorderAndASize() {
        let sticker = ComposerBlock.make(kind: .sticker, position: BlockPosition(x: 0, y: 0))
        #expect(sticker.stickerBorder)
        #expect(sticker.stickerWidth > 0 && sticker.stickerHeight > 0)
        #expect(sticker.canRotate)
    }

    @Test
    func stickersSurviveSavingAndOtherPiecesDontChange() throws {
        var sticker = ComposerBlock.make(kind: .sticker, position: BlockPosition(x: 0.2, y: 0.3))
        sticker.mediaFileName = "cutout.png"
        sticker.stickerWidth = 180
        sticker.stickerHeight = 240
        sticker.stickerBorder = false
        #expect(try JSONDecoder().decode(ComposerBlock.self, from: JSONEncoder().encode(sticker)) == sticker)

        let text = ComposerBlock.make(kind: .text, position: BlockPosition(x: 0, y: 0))
        let saved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(text)) as? [String: Any])
        #expect(saved["stickerWidth"] == nil && saved["stickerBorder"] == nil)
    }

    @Test
    func savedStickersArePaddedPNGsNoLargerThanTheLimit() throws {
        let big = subject(size: 3000)
        let (data, size) = try #require(ComposerStickerArt.stickerPNG(from: big))
        #expect(max(size.width, size.height) <= ComposerStickerArt.maxPixel)
        let image = try #require(UIImage(data: data))
        #expect(image.cgImage?.alphaInfo != CGImageAlphaInfo.none)
        // The corner is transparent padding; the middle is the subject.
        #expect(alpha(in: image, at: CGPoint(x: 2, y: 2)) < 0.05)
        #expect(alpha(in: image, at: CGPoint(x: size.width / 2, y: size.height / 2)) > 0.95)
    }

    @Test
    func theBorderGrowsOutsideTheSubject() throws {
        let (data, size) = try #require(ComposerStickerArt.stickerPNG(from: subject()))
        let plain = try #require(UIImage(data: data))
        let bordered = try #require(ComposerStickerArt.bordered(plain))
        // Just outside the subject's left edge, inside the padding.
        let padding = (max(size.width, size.height) * ComposerStickerArt.paddingShare).rounded(.up)
        let justOutside = CGPoint(x: padding - 3, y: size.height / 2)
        #expect(alpha(in: plain, at: justOutside) < 0.05)
        #expect(alpha(in: bordered, at: justOutside) > 0.5)
        #expect(bordered.size == plain.size)
    }

    @Test
    func newStickersKeepTheirShape() {
        let wide = ComposerStickerArt.placedSize(for: CGSize(width: 800, height: 400))
        #expect(wide.width == ComposerStickerArt.placedLongSide)
        #expect(abs(wide.height - ComposerStickerArt.placedLongSide / 2) <= 1)
    }

    @Test
    func findingSubjectsNeverCrashes() {
        // Subject lifting needs the Neural Engine; the simulator may find none. Either way it returns quietly.
        let session = ComposerCutoutSession.find(in: subject())
        if let session {
            #expect(!session.subjects.isEmpty)
            #expect(session.subject(at: CGPoint(x: 2, y: 2)) == nil)
        }
    }

    @Test
    func visitorsGetTransparentOriginalsForStickers() {
        let owner = UUID()
        let paths = MosaicVisitClient.objectPaths(ownerID: owner, assetID: "asset", fileName: "cutout.png", isSticker: true)
        #expect(paths.count == 1)
        #expect(paths.first?.hasSuffix("/original") == true)
        let photo = MosaicVisitClient.objectPaths(ownerID: owner, assetID: "asset", fileName: "photo.jpg")
        #expect(photo.first?.hasSuffix("/display") == true)
        // A PNG photo that isn't a sticker gets the smaller display copy.
        let screenshot = MosaicVisitClient.objectPaths(ownerID: owner, assetID: "asset", fileName: "screenshot.png")
        #expect(screenshot.first?.hasSuffix("/display") == true)
    }

    @Test
    func visitorsFindStickersInsideGroups() {
        var sticker = ComposerBlock.make(kind: .sticker, position: BlockPosition(x: 0.2, y: 0.2))
        sticker.mediaFileName = "cutout.png"
        var photo = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0.4, y: 0.4))
        photo.mediaFileName = "photo.png"
        var group = ComposerBlock.make(kind: .group, position: BlockPosition(x: 0.5, y: 0.5))
        group.groupMembers = [sticker, photo]
        #expect(MosaicVisitMedia.stickerFiles(in: [group]) == ["cutout.png"])
    }

    // MARK: Your stickers

    @Test
    func savedStickersAreNewestFirstWithoutRepeats() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        store.saveToStickerLibrary(fileName: "a.png", size: CGSize(width: 100, height: 80))
        store.saveToStickerLibrary(fileName: "b.png", size: CGSize(width: 90, height: 120))
        store.saveToStickerLibrary(fileName: "a.png", size: CGSize(width: 100, height: 80))
        #expect(store.snapshot.stickerLibrary.map(\.fileName) == ["a.png", "b.png"])

        store.removeFromStickerLibrary("a.png")
        #expect(store.snapshot.stickerLibrary.map(\.fileName) == ["b.png"])
        // Not part of a board's undo history.
        #expect(!store.canUndo(in: nil))

        for index in 0..<(ComposerSavedSticker.limit + 5) {
            store.saveToStickerLibrary(fileName: "\(index).png", size: CGSize(width: 10, height: 10))
        }
        #expect(store.snapshot.stickerLibrary.count == ComposerSavedSticker.limit)
        #expect(store.snapshot.stickerLibrary.first?.fileName == "\(ComposerSavedSticker.limit + 4).png")
    }

    @Test
    func savedStickersOnlySaveWhenThereAreSome() throws {
        let empty = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ComposerSnapshot.empty)) as? [String: Any])
        #expect(empty["stickerLibrary"] == nil)

        var snapshot = ComposerSnapshot.empty
        snapshot.stickerLibrary = [ComposerSavedSticker(fileName: "a.png", width: 100, height: 80)]
        let decoded = try JSONDecoder().decode(ComposerSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.stickerLibrary == snapshot.stickerLibrary)
    }

    @Test
    func savedStickersSyncWithTheMosaicBoardOnly() throws {
        let mosaicID = UUID()
        let pursuitID = ComposerDocumentID(rawValue: UUID().uuidString)
        var pursuitBlock = ComposerBlock.make(kind: .pursuit, position: BlockPosition(x: 0, y: 0))
        pursuitBlock.pursuitID = pursuitID
        var snapshot = ComposerSnapshot(
            mosaicTitle: "Mosaic",
            mosaicBlocks: [pursuitBlock],
            pursuits: [ComposerPursuit(id: pursuitID, title: "Golf", blocks: [])]
        )
        snapshot.stickerLibrary = [ComposerSavedSticker(fileName: "saved.png", width: 120, height: 90)]

        let documents = ComposerBoardSync.split(snapshot: snapshot, mosaicID: mosaicID)
        let mosaic = try #require(documents.first { $0.id == mosaicID })
        #expect(mosaic.body.stickerLibrary == snapshot.stickerLibrary)
        #expect(documents.filter { $0.id != mosaicID }.allSatisfy { $0.body.stickerLibrary == nil })

        // Uploaded with the Mosaic board, and its cloud copy recorded there for other devices.
        let references = ComposerMediaCatalog.references(snapshot: snapshot, mosaicID: mosaicID)
        #expect(references.contains { $0.fileName == "saved.png" && $0.documentID == mosaicID })
        let stamped = ComposerMediaCatalog.stamped(documents, assets: ["saved.png": "asset-1"])
        #expect(stamped.first { $0.id == mosaicID }?.body.mediaAssets == ["saved.png": "asset-1"])

        // A new device gets the list back.
        let restored = try #require(ComposerBoardSync.assemble(mosaicID: mosaicID, documents: documents))
        #expect(restored.stickerLibrary == snapshot.stickerLibrary)
    }

    @Test
    func oneDamagedSavedStickerDoesntEmptyTheList() throws {
        var snapshot = ComposerSnapshot.empty
        snapshot.stickerLibrary = [
            ComposerSavedSticker(fileName: "a.png", width: 100, height: 80),
            ComposerSavedSticker(fileName: "b.png", width: 90, height: 120)
        ]
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        var entries = try #require(json["stickerLibrary"] as? [[String: Any]])
        entries.insert(["fileName": 42], at: 1)
        json["stickerLibrary"] = entries
        let decoded = try JSONDecoder().decode(ComposerSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.stickerLibrary.map(\.fileName) == ["a.png", "b.png"])
    }

    @Test
    func boardsANewerPieceOwnsKeepTheirPlaceInSync() throws {
        let pageID = ComposerDocumentID(rawValue: UUID().uuidString)
        let page = ComposerPursuit(id: pageID, title: "Page", blocks: [], role: .page)
        var future = ComposerBlock.make(kind: .unsupported, position: BlockPosition(x: 0, y: 0))
        future.preserved = .object([
            "kind": .string("hologram"),
            "pages": .array([.string(pageID.rawValue.lowercased())])
        ])
        let snapshot = ComposerSnapshot(mosaicTitle: "M", mosaicBlocks: [future], pursuits: [page])
        let documents = ComposerBoardSync.split(snapshot: snapshot, mosaicID: UUID())
        // The page is part of the sync rather than orphaned, and cleanup keeps it.
        #expect(documents.contains { $0.id == UUID(uuidString: pageID.rawValue) })
        #expect(ComposerBoardSync.referencedIDs(in: snapshot).contains(pageID.rawValue))
    }

    // MARK: Emoji

    @Test
    func theEmojiFieldTakesTheFirstEmoji() {
        #expect(ComposerStickerArt.firstEmoji(in: "⛳️") == "⛳️")
        #expect(ComposerStickerArt.firstEmoji(in: "go 🏌️‍♀️ go") == "🏌️‍♀️")
        #expect(ComposerStickerArt.firstEmoji(in: "👍🏽") == "👍🏽")
        #expect(ComposerStickerArt.firstEmoji(in: "hello 123") == nil)
        #expect(ComposerStickerArt.firstEmoji(in: "") == nil)
    }

    @Test
    func emojiStickersDrawLargeWithABorderAndNeedNoFile() throws {
        let image = try #require(ComposerStickerArt.emojiImage("⛳️"))
        #expect(alpha(in: image, at: CGPoint(x: image.size.width / 2, y: image.size.height / 2)) > 0.1)
        #expect(alpha(in: image, at: CGPoint(x: 1, y: 1)) < 0.05)
        #expect(ComposerStickerArt.emojiArt("⛳️", bordered: true) != nil)

        var sticker = ComposerBlock.make(kind: .sticker, position: BlockPosition(x: 0, y: 0))
        sticker.text = "⛳️"
        #expect(try JSONDecoder().decode(ComposerBlock.self, from: JSONEncoder().encode(sticker)).text == "⛳️")
        let snapshot = ComposerSnapshot(mosaicTitle: "M", mosaicBlocks: [sticker], pursuits: [])
        #expect(ComposerMediaCatalog.references(snapshot: snapshot, mosaicID: UUID()).isEmpty)
    }

    @Test
    func stickersGoOnJournalPagesAndKeepTheirBorderSetting() throws {
        let sticker = ComposerBlock.make(kind: .sticker, position: BlockPosition(x: 0, y: 0))
        #expect(ComposerStore.allowsPlacement(of: sticker, onMosaic: false, onJournalPage: true))

        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let id = store.addBlock(.sticker, to: nil)
        store.setLook(stickerBorder: false, for: id, in: nil)
        #expect(store.block(with: id, in: nil)?.stickerBorder == false)
        store.undo(in: nil)
        #expect(store.block(with: id, in: nil)?.stickerBorder == true)

        // Only stickers have a border.
        let text = store.addBlock(.text, to: nil)
        store.setLook(stickerBorder: false, for: text, in: nil)
        #expect(store.block(with: text, in: nil)?.stickerBorder == true)
    }
}

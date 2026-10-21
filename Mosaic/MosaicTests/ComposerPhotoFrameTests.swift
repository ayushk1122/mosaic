import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import Mosaic

@MainActor
@Suite
struct ComposerPhotoFrameTests {
    private func json(_ block: ComposerBlock) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? [String: Any])
    }

    @Test
    func unframedPhotosSaveExactlyAsBefore() throws {
        let photo = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0, y: 0))
        let saved = try json(photo)
        #expect(saved["frameStyle"] == nil)
        #expect(saved["frameCaption"] == nil)
    }

    @Test
    func framesAndCaptionsSurviveSavingAndLoading() throws {
        var photo = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0, y: 0))
        photo.frameStyle = .polaroid
        photo.frameCaption = "First birdie"
        #expect(try JSONDecoder().decode(ComposerBlock.self, from: JSONEncoder().encode(photo)) == photo)

        var fields = try json(photo)
        fields["frameStyle"] = "gold-leaf"
        let decoded = try JSONDecoder().decode(ComposerBlock.self, from: JSONSerialization.data(withJSONObject: fields))
        #expect(decoded.frameStyle == .none)
        #expect(decoded.frameCaption == "First birdie")
    }

    @Test
    func framesApplyToPhotosAndVideosOnly() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let photo = store.addBlock(.media, to: nil)
        store.setLook(frameStyle: .tape, for: photo, in: nil)
        #expect(store.block(with: photo, in: nil)?.frameStyle == .tape)

        let text = store.addBlock(.text, to: nil)
        store.setLook(frameStyle: .polaroid, frameCaption: "Hi", photoShape: .circle, for: text, in: nil)
        let unchanged = try #require(store.block(with: text, in: nil))
        #expect(unchanged.frameStyle == .none && unchanged.frameCaption.isEmpty && unchanged.mediaShape == .rectangle)
    }

    @Test
    func aCircleIsSquareAndCaptionsStayShort() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let photo = store.addBlock(.media, to: nil)
        store.setLook(photoShape: .circle, for: photo, in: nil)
        let circle = try #require(store.block(with: photo, in: nil))
        #expect(circle.mediaShape == .circle)
        #expect(circle.mediaFrameAspect == 1)

        store.setLook(frameCaption: String(repeating: "a", count: 90), for: photo, in: nil)
        #expect(store.block(with: photo, in: nil)?.frameCaption.count == ComposerFrameStyle.captionLimit)
    }

    @Test
    func typingACaptionIsOneUndoStep() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let photo = store.addBlock(.media, to: nil)
        store.setLook(frameStyle: .polaroid, for: photo, in: nil)
        for prefix in ["P", "Pa", "Par", "Par 3"] {
            store.setLook(frameCaption: prefix, for: photo, in: nil)
        }
        #expect(store.block(with: photo, in: nil)?.frameCaption == "Par 3")
        store.undo(in: nil)
        let undone = try #require(store.block(with: photo, in: nil))
        #expect(undone.frameCaption.isEmpty)
        #expect(undone.frameStyle == .none)
    }

    @Test
    func aTornEdgeIsTheSameEveryTime() {
        let rect = CGRect(x: 0, y: 0, width: 240, height: 180)
        let id = ComposerBlockID(rawValue: "photo-1")
        let seed = ComposerPhotoFrameModifier.seed(for: id)
        #expect(seed == ComposerPhotoFrameModifier.seed(for: ComposerBlockID(rawValue: "photo-1")))
        let first = ComposerTornPaperShape(seed: seed, roughness: 4, step: 8).path(in: rect)
        let again = ComposerTornPaperShape(seed: seed, roughness: 4, step: 8).path(in: rect)
        let other = ComposerTornPaperShape(seed: ComposerPhotoFrameModifier.seed(for: ComposerBlockID(rawValue: "photo-2")), roughness: 4, step: 8).path(in: rect)
        #expect(first.description == again.description)
        #expect(first.description != other.description)
        // The tear stays inside the paper's box.
        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(first.boundingRect))
        // No roughness is a plain rectangle.
        #expect(ComposerTornPaperShape(seed: seed, roughness: 0, step: 8).path(in: rect).boundingRect == rect)
    }

    @Test
    func aPolaroidHasRoomForItsCaption() {
        let polaroid = ComposerPhotoFrameModifier.insets(for: .polaroid, width: 200)
        #expect(polaroid.bottom > polaroid.top * 3)
        #expect(ComposerPhotoFrameModifier.insets(for: .none, width: 200) == .init(top: 0, side: 0, bottom: 0))
        #expect(ComposerPhotoFrameModifier.insets(for: .tape, width: 200) == .init(top: 0, side: 0, bottom: 0))
    }
}

import Foundation
import Testing

@testable import Mosaic

@MainActor
@Suite
struct ComposerPieceLookTests {
    private func json(_ block: ComposerBlock) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? [String: Any])
    }

    @Test
    func untouchedPiecesSaveExactlyAsBefore() throws {
        let text = ComposerBlock.make(kind: .text, position: BlockPosition(x: 0, y: 0))
        let saved = try json(text)
        #expect(saved["opacity"] == nil)
        #expect(saved["shadow"] == nil)
        let decoded = try JSONDecoder().decode(ComposerBlock.self, from: JSONEncoder().encode(text))
        #expect(decoded.opacity == 1)
        #expect(decoded.shadow == .none)
    }

    @Test
    func opacityAndShadowSurviveSavingAndLoading() throws {
        var photo = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0.2, y: 0.3))
        photo.opacity = 0.55
        photo.shadow = .lifted
        let saved = try json(photo)
        #expect(saved["opacity"] as? Double == 0.55)
        #expect(saved["shadow"] as? String == "lifted")
        #expect(try JSONDecoder().decode(ComposerBlock.self, from: JSONEncoder().encode(photo)) == photo)
    }

    @Test
    func oddSavedValuesFallBackSafely() throws {
        var fields = try json(ComposerBlock.make(kind: .text, position: BlockPosition(x: 0, y: 0)))
        fields["opacity"] = -3
        fields["shadow"] = "neon-glow"
        let decoded = try JSONDecoder().decode(ComposerBlock.self, from: JSONSerialization.data(withJSONObject: fields))
        #expect(decoded.opacity == ComposerPieceLook.minimumOpacity)
        #expect(decoded.shadow == .none)

        fields["opacity"] = 7
        let tooHigh = try JSONDecoder().decode(ComposerBlock.self, from: JSONSerialization.data(withJSONObject: fields))
        #expect(tooHigh.opacity == 1)
    }

    @Test
    func whiteShadowsSaveAndBlackStaysTheDefault() throws {
        var photo = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0, y: 0))
        photo.shadow = .soft
        #expect(try json(photo)["shadowColor"] == nil)

        photo.shadowColor = .white
        #expect(try json(photo)["shadowColor"] as? String == "white")
        #expect(try JSONDecoder().decode(ComposerBlock.self, from: JSONEncoder().encode(photo)).shadowColor == .white)

        var fields = try json(photo)
        fields["shadowColor"] = "ultraviolet"
        let decoded = try JSONDecoder().decode(ComposerBlock.self, from: JSONSerialization.data(withJSONObject: fields))
        #expect(decoded.shadowColor == .black)
    }

    @Test
    func aSliderDragIsOneUndoStep() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let id = store.addBlock(.text, to: nil)
        for value in [0.95, 0.85, 0.7, 0.6, 0.5, 0.4] {
            store.setLook(opacity: value, for: id, in: nil)
        }
        #expect(abs((store.block(with: id, in: nil)?.opacity ?? 0) - 0.4) < 0.001)

        store.undo(in: nil)
        #expect(store.block(with: id, in: nil)?.opacity == 1)
    }

    @Test
    func shadowAndOpacityChangeIndependently() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let id = store.addBlock(.text, to: nil)
        store.setLook(opacity: 0.5, for: id, in: nil)
        store.setLook(shadow: .soft, for: id, in: nil)
        let block = try #require(store.block(with: id, in: nil))
        #expect(block.opacity == 0.5)
        #expect(block.shadow == .soft)

        store.setLook(opacity: 0.01, for: id, in: nil)
        #expect(store.block(with: id, in: nil)?.opacity == ComposerPieceLook.minimumOpacity)
    }

    @Test
    func copiesKeepTheirLook() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let id = store.addBlock(.text, to: nil)
        store.setLook(opacity: 0.6, shadow: .lifted, for: id, in: nil)
        store.copyBlock(id, in: nil)
        let pasted = try #require(store.pasteClipboard(at: BlockPosition(x: 0.5, y: 0.5), in: nil))
        let copy = try #require(store.block(with: pasted, in: nil))
        #expect(copy.opacity == 0.6)
        #expect(copy.shadow == .lifted)
    }
}

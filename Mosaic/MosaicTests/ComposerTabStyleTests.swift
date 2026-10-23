import Foundation
import SwiftUI
import Testing
@testable import Mosaic

@MainActor
struct ComposerTabStyleTests {
    @Test
    func existingTabBarsKeepTheirLookAndSaveNothingNew() throws {
        let tabs = ComposerBlock.make(kind: .tabs, position: BlockPosition(x: 0.1, y: 0.1))
        #expect(tabs.tabStyle == .pill)
        #expect(tabs.tabColor == nil)
        #expect(tabs.tabShape == .capsule)
        #expect(tabs.tabWidth == .fit)
        let json = String(decoding: try JSONEncoder().encode(tabs), as: UTF8.self)
        #expect(!tabs.tabSticky)
        for key in ["tabStyle", "tabColor", "tabShape", "tabWidth", "tabSticky"] {
            #expect(!json.contains(key), "\(key)")
        }
    }

    @Test
    func lookRoundTrips() throws {
        var tabs = ComposerBlock.make(kind: .tabs, position: BlockPosition(x: 0.1, y: 0.1))
        tabs.tabStyle = .segmented
        tabs.tabColor = ComposerRGBColor(red: 0.8, green: 0.45, blue: 0.33)
        tabs.tabShape = .rounded
        tabs.tabWidth = .full
        tabs.tabSticky = true
        let decoded = try JSONDecoder().decode(ComposerBlock.self, from: JSONEncoder().encode(tabs))
        #expect(decoded.tabStyle == .segmented)
        #expect(decoded.tabColor == tabs.tabColor)
        #expect(decoded.tabShape == .rounded)
        #expect(decoded.tabWidth == .full)
        #expect(decoded.tabSticky)
    }

    @Test
    func valuesFromNewerVersionsFallBackToTheDefaults() throws {
        let tabs = ComposerBlock.make(kind: .tabs, position: BlockPosition(x: 0.1, y: 0.1))
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(tabs)) as? [String: Any])
        object["tabStyle"] = "folder"
        object["tabShape"] = "star"
        object["tabWidth"] = "custom"
        object["tabColor"] = "neon"
        let decoded = try JSONDecoder().decode(ComposerBlock.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.tabStyle == .pill)
        #expect(decoded.tabShape == .capsule)
        #expect(decoded.tabWidth == .fit)
        #expect(decoded.tabColor == nil)
    }

    @Test
    func onlyTabBarsTakeATabLookAndColorCanBeReset() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let tabs = store.addBlock(.tabs, to: nil)
        let text = store.addBlock(.text, to: nil)
        let clay = ComposerRGBColor(red: 0.8, green: 0.45, blue: 0.33)
        store.setLook(tabStyle: .segmented, tabColor: clay, tabShape: .rounded, tabWidth: .full, for: tabs, in: nil)
        store.setLook(tabStyle: .underline, tabSticky: true, for: text, in: nil)
        #expect(store.block(with: text, in: nil)?.tabSticky == false)
        store.setLook(tabSticky: true, for: tabs, in: nil)
        #expect(store.block(with: tabs, in: nil)?.tabSticky == true)
        let styled = try #require(store.block(with: tabs, in: nil))
        #expect(styled.tabStyle == .segmented && styled.tabColor == clay)
        #expect(styled.tabShape == .rounded && styled.tabWidth == .full)
        #expect(store.block(with: text, in: nil)?.tabStyle == .pill)
        store.setLook(resetsTabColor: true, for: tabs, in: nil)
        #expect(store.block(with: tabs, in: nil)?.tabColor == nil)
        store.undo(in: nil)
        #expect(store.block(with: tabs, in: nil)?.tabStyle == .pill)
    }

    @Test
    func titlesStayReadableOnTheChosenColor() {
        #expect(ComposerTabPaint(color: nil).onFill == ComposerTabPaint(color: ComposerRGBColor(red: 1, green: 0.9, blue: 0.4)).onFill)
        #expect(ComposerTabPaint(color: ComposerRGBColor(red: 0.1, green: 0.2, blue: 0.5)).onFill == .white)
    }
}

import Foundation
import Testing

@testable import Mosaic

@MainActor
@Suite
struct ComposerStoreUndoTests {
    @Test
    func undoOnAPursuitBringsBackADeletedNodeWithItsContent() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let pursuitBlock = store.addBlock(.pursuit, to: nil)
        let pursuitID = try #require(store.block(with: pursuitBlock, in: nil)?.pursuitID)
        let nodeBlock = store.addBlock(.node, to: pursuitID)
        let nodeID = try #require(store.block(with: nodeBlock, in: pursuitID)?.pursuitID)
        store.addBlock(.text, to: nodeID)

        store.deleteBlock(nodeBlock, in: pursuitID)
        #expect(store.pursuit(for: nodeID) == nil)

        store.undo(in: pursuitID)
        #expect(store.block(with: nodeBlock, in: pursuitID) != nil)
        #expect(store.blocks(for: nodeID).contains { $0.kind == .text })
    }

    @Test
    func undoOnAPursuitBringsBackScrapbookPages() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let pursuitID = try #require(store.block(with: store.addBlock(.pursuit, to: nil), in: nil)?.pursuitID)
        let scrapbook = store.addBlock(.scrapbook, to: pursuitID)
        let firstPage = try #require(store.block(with: scrapbook, in: pursuitID)?.scrapbookPageIDs.first)
        store.addBlock(.text, to: firstPage)

        store.deleteBlock(scrapbook, in: pursuitID)
        store.undo(in: pursuitID)
        #expect(store.blocks(for: firstPage).contains { $0.kind == .text })
    }

    @Test
    func mosaicUndoKeepsEditsMadeInsideOtherPursuits() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let golf = try #require(store.block(with: store.addBlock(.pursuit, to: nil), in: nil)?.pursuitID)
        let second = store.addBlock(.pursuit, to: nil)
        let secondID = try #require(store.block(with: second, in: nil)?.pursuitID)
        store.addBlock(.text, to: golf)
        store.addBlock(.node, to: golf)

        // Undoing the second widget removes only that widget's board.
        store.undo(in: nil)
        #expect(store.block(with: second, in: nil) == nil)
        #expect(store.pursuit(for: secondID) == nil)
        #expect(store.blocks(for: golf).count == 2)
        #expect(store.snapshot.pursuits.contains { $0.role == .node })
    }

    @Test
    func undoingACutTurnsTheClipboardIntoACopy() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let pursuitBlock = store.addBlock(.pursuit, to: nil)
        let pursuitID = try #require(store.block(with: pursuitBlock, in: nil)?.pursuitID)

        store.cutBlock(pursuitBlock, in: nil)
        store.undo(in: nil)
        #expect(store.clipboard?.isCut == false)
        #expect(store.detachedClipboardDocumentIDs.isEmpty)

        let pasted = try #require(store.pasteClipboard(at: BlockPosition(x: 0.5, y: 0.5), in: nil))
        #expect(pasted != pursuitBlock)
        let copy = try #require(store.block(with: pasted, in: nil))
        #expect(copy.pursuitID != pursuitID)
        #expect(store.blocks(for: nil).filter { $0.id == pursuitBlock }.count == 1)
    }

    @Test
    func pastingATabsBarKeepsTheRestOfThePageVisible() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let text = store.addBlock(.text, to: nil)
        let tabs = store.addBlock(.tabs, to: nil)
        store.cutBlock(tabs, in: nil)
        #expect(store.block(with: text, in: nil)?.tabID == nil)

        let pasted = try #require(store.pasteClipboard(at: BlockPosition(x: 0.1, y: 0.1), in: nil))
        let bar = try #require(store.block(with: pasted, in: nil))
        #expect(bar.selectedTabID != nil)
        #expect(store.block(with: text, in: nil)?.tabID == bar.selectedTabID)
    }

    @Test
    func pasteFollowsTheAddMenusPlacementRules() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let pursuitID = try #require(store.block(with: store.addBlock(.pursuit, to: nil), in: nil)?.pursuitID)
        let scrapbook = store.addBlock(.scrapbook, to: pursuitID)
        let page = try #require(store.block(with: scrapbook, in: pursuitID)?.scrapbookPageIDs.first)
        let table = store.addBlock(.table, to: pursuitID)

        store.copyBlock(scrapbook, in: pursuitID)
        #expect(store.pasteClipboard(at: BlockPosition(x: 0.2, y: 0.2), in: nil) == nil)

        store.copyBlock(table, in: pursuitID)
        #expect(store.pasteClipboard(at: BlockPosition(x: 0.2, y: 0.2), in: page) == nil)
        #expect(store.pasteClipboard(at: BlockPosition(x: 0.2, y: 0.2), in: pursuitID) != nil)
    }

    @Test
    func editsThatChangeNothingAddNoUndoStep() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let pursuitID = try #require(store.block(with: store.addBlock(.pursuit, to: nil), in: nil)?.pursuitID)
        let bar = store.addBlock(.tabs, to: pursuitID)
        for _ in 0..<20 {
            store.addComposerTab(to: bar, in: pursuitID, longestSide: 402)
        }
        let atLimit = try #require(store.block(with: bar, in: pursuitID)).tabs.count

        // At the limit the tap changes nothing, so Undo removes the last real tab.
        store.addComposerTab(to: bar, in: pursuitID, longestSide: 402)
        store.updateBlock(try #require(store.block(with: bar, in: pursuitID)), in: pursuitID)
        store.undo(in: pursuitID)
        #expect(store.block(with: bar, in: pursuitID)?.tabs.count == atLimit - 1)
    }

    @Test
    func tableStructureIsItsOwnUndoStepAfterTyping() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let pursuitID = try #require(store.block(with: store.addBlock(.pursuit, to: nil), in: nil)?.pursuitID)
        let tableID = store.addBlock(.table, to: pursuitID)
        store.addTableRow(to: tableID, in: pursuitID)
        var typed = try #require(store.block(with: tableID, in: pursuitID))
        typed.text = "Scores"
        store.updateBlock(typed, in: pursuitID)
        let columns = try #require(store.block(with: tableID, in: pursuitID)).tableColumns.count
        store.addTableColumn(to: tableID, in: pursuitID)

        store.undo(in: pursuitID)
        let after = try #require(store.block(with: tableID, in: pursuitID))
        #expect(after.tableColumns.count == columns)
        #expect(after.text == "Scores")
    }

    @Test
    func aCancelledPlaceholderLeavesNothingToUndo() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let text = store.addBlock(.text, to: nil)
        let media = store.addBlock(.media, to: nil)
        store.discardPlaceholder(media, in: nil)
        #expect(store.block(with: media, in: nil) == nil)

        // The next Undo reverts the text block, not an invisible "re-add the empty photo".
        store.undo(in: nil)
        #expect(store.block(with: media, in: nil) == nil)
        #expect(store.block(with: text, in: nil) == nil)
    }

    @Test
    func contentIsPlacedInOneUndoStep() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let id = store.addBlock(.link, at: BlockPosition(x: 0.2, y: 0.2), to: nil) { block in
            block.socialPlatform = "content:youtube"
        }
        #expect(store.block(with: id, in: nil)?.isContent == true)
        store.undo(in: nil)
        #expect(store.block(with: id, in: nil) == nil)
    }

    @Test
    func boardBackgroundChangesCanBeUndone() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        store.addBlock(.text, to: nil)
        var dark = ComposerBoardBackground.solid(ComposerRGBColor(red: 0.1, green: 0.1, blue: 0.1))
        store.setBoardBackground(dark, for: nil)
        dark.color = ComposerRGBColor(red: 0.2, green: 0.2, blue: 0.2)
        store.setBoardBackground(dark, for: nil)

        // The two quick changes are one step; Undo returns to the default and keeps the text block.
        store.undo(in: nil)
        #expect(store.boardBackground(for: nil) == nil)
        #expect(store.blocks(for: nil).count == 1)
    }

    @Test
    func layerOrderMovesAPieceToTheFrontOrBack() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let a = store.addBlock(.text, to: nil)
        let b = store.addBlock(.media, to: nil)
        let c = store.addBlock(.social, to: nil)

        store.sendToBack(c, in: nil)
        #expect(store.blocks(for: nil).map(\.id) == [c, a, b])
        store.bringToFront(a, in: nil)
        #expect(store.blocks(for: nil).map(\.id) == [c, b, a])

        // Already in front: nothing changes, so Undo reverts the previous move.
        store.bringToFront(a, in: nil)
        store.undo(in: nil)
        #expect(store.blocks(for: nil).map(\.id) == [c, a, b])
    }

    @Test
    func lockingIsAnUndoableEditThatKeepsContent() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let id = store.addBlock(.text, to: nil)
        store.setLocked(true, for: id, in: nil)
        #expect(store.block(with: id, in: nil)?.isLocked == true)

        var edited = try #require(store.block(with: id, in: nil))
        edited.text = "Still editable"
        store.updateBlock(edited, in: nil)
        #expect(store.block(with: id, in: nil)?.text == "Still editable")
        #expect(store.block(with: id, in: nil)?.isLocked == true)

        store.undo(in: nil)
        store.undo(in: nil)
        #expect(store.block(with: id, in: nil)?.isLocked == false)
    }

    @Test
    func rotationIsUndoableAndRespectsLockAndKind() throws {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let photo = store.addBlock(.media, to: nil)
        store.setRotation(372, for: photo, in: nil)
        #expect(store.block(with: photo, in: nil)?.rotation == 12)
        store.undo(in: nil)
        #expect(store.block(with: photo, in: nil)?.rotation == 0)

        store.setLocked(true, for: photo, in: nil)
        store.setRotation(30, for: photo, in: nil)
        #expect(store.block(with: photo, in: nil)?.rotation == 0)

        let pursuitID = try #require(store.block(with: store.addBlock(.pursuit, to: nil), in: nil)?.pursuitID)
        let table = store.addBlock(.table, to: pursuitID)
        store.setRotation(30, for: table, in: pursuitID)
        #expect(store.block(with: table, in: pursuitID)?.rotation == 0)
    }

    @Test
    func olderBlocksDecodeUnrotatedAndUnlocked() throws {
        let block = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0.1, y: 0.1))
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? [String: Any])
        json.removeValue(forKey: "rotation")
        json.removeValue(forKey: "isLocked")
        let decoded = try JSONDecoder().decode(ComposerBlock.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.rotation == 0)
        #expect(!decoded.isLocked)
    }

    @Test
    func anUnreadableSnapshotIsKeptAsABackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let location = ComposerStorageLocation(root: root)
        try FileManager.default.createDirectory(
            at: location.snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let unreadable = Data(#"{"mosaicBlocks":[{"kind":"hologram"}]}"#.utf8)
        try unreadable.write(to: location.snapshotURL)

        _ = ComposerStore(persistToDisk: true, location: location)

        let siblings = try FileManager.default.contentsOfDirectory(
            at: location.snapshotURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        let backup = try #require(siblings.first { $0.lastPathComponent.contains("unreadable") })
        #expect(try Data(contentsOf: backup) == unreadable)
    }
}

import Foundation
import Observation

struct ComposerClipboardItem: Equatable {
    var block: ComposerBlock
    var documents: [ComposerPursuit]
    /// Cut keeps document ids; copy mints new ones on paste.
    var isCut: Bool
}

@MainActor
@Observable
final class ComposerStore {
    private(set) var snapshot: ComposerSnapshot
    private(set) var isRestoringDocuments = false
    private(set) var mediaVersions: [String: Int] = [:]
    /// True while the latest edit could not be written to this phone (usually a full disk).
    private(set) var saveFailed = false
    private var undoStacks: [String: [ComposerUndoEntry]] = [:]
    private var undoCoalesce: ComposerUndoCoalesce?
    private var isApplyingUndo = false
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    private let fileManager: FileManager
    private let persistToDisk: Bool
    let location: ComposerStorageLocation
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Called after a successful local save. Sync uses this to push the board.
    var onPersisted: (() -> Void)?

    init(
        fileManager: FileManager = .default,
        seedSnapshot: ComposerSnapshot? = nil,
        persistToDisk: Bool? = nil,
        location: ComposerStorageLocation? = nil
    ) {
        self.fileManager = fileManager
        self.persistToDisk = persistToDisk ?? !ProcessInfo.processInfo.arguments.contains("UITestSkipLaunchAnimation")
        self.location = location ?? .shared(fileManager: fileManager)
        isRestoringDocuments = (try? Data(contentsOf: self.location.syncStateURL))
            .flatMap { try? JSONDecoder().decode(ComposerSyncState.self, from: $0) }?.pendingRestore ?? false
        var shouldPersistPrune = false
        if let seedSnapshot {
            snapshot = seedSnapshot
        } else if !self.persistToDisk {
            snapshot = .empty
        } else if let loaded = Self.loadSnapshot(at: self.location.snapshotURL, fileManager: fileManager, decoder: decoder) {
            snapshot = loaded
            shouldPersistPrune = !isRestoringDocuments && !ComposerBoardSync.pruneUnreferenced(&snapshot).isEmpty
            shouldPersistPrune = Self.refreshPursuitTitles(&snapshot) || shouldPersistPrune
        } else {
            snapshot = .empty
        }
        if shouldPersistPrune {
            persist()
        }
    }

    func isWaitingForDocument(_ id: ComposerDocumentID?) -> Bool {
        guard let id else { return false }
        return isRestoringDocuments && !snapshot.pursuits.contains { $0.id == id }
    }

    /// Preserve every edit made on the landing board while adding the downloaded children.
    /// The pending flag stays set until both local files have been saved successfully.
    func finishRestoring(snapshot remote: ComposerSnapshot, state: ComposerSyncState) throws {
        var merged = snapshot
        let existing = Set(merged.pursuits.map(\.id))
        merged.pursuits.append(contentsOf: remote.pursuits.filter { !existing.contains($0.id) })
        // A widget whose board never reached the server (a push that failed partway) gets an empty
        // board instead of blocking the restore, and with it every upload, forever.
        merged.pursuits.append(contentsOf: ComposerBoardSync.missingReferences(in: merged).map { id, role in
            ComposerPursuit(id: id, title: "", blocks: [], role: role)
        })
        ComposerBoardSync.pruneUnreferenced(
            &merged,
            protecting: Set(detachedClipboardDocumentIDs.map(\.rawValue))
        )
        Self.refreshPursuitTitles(&merged)
        if persistToDisk {
            try encoder.encode(merged).write(to: location.snapshotURL, options: .atomic)
            try encoder.encode(state).write(to: location.syncStateURL, options: .atomic)
        }
        snapshot = merged
        // An undo that brings back a widget deleted mid-download also needs that widget's
        // downloaded boards. Undo only restores saved boards that are referenced and missing,
        // so adding them to every entry changes nothing else.
        for key in Array(undoStacks.keys) {
            guard var entries = undoStacks[key] else { continue }
            for index in entries.indices {
                var saved = entries[index].pursuits ?? []
                let savedIDs = Set(saved.map(\.id))
                saved.append(contentsOf: remote.pursuits.filter { !savedIDs.contains($0.id) })
                entries[index].pursuits = saved
            }
            undoStacks[key] = entries
        }
        isRestoringDocuments = false
        onPersisted?()
    }

    func mediaDidDownload(_ fileName: String) {
        mediaVersions[fileName, default: 0] += 1
    }

    func canUndo(in documentID: ComposerDocumentID?) -> Bool {
        !(undoStacks[Self.undoKey(documentID)]?.isEmpty ?? true)
    }

    func undo(in documentID: ComposerDocumentID?) {
        let key = Self.undoKey(documentID)
        guard var stack = undoStacks[key], let entry = stack.popLast() else { return }
        undoStacks[key] = stack
        undoCoalesce = nil
        isApplyingUndo = true
        mutateBlocks(for: documentID) { blocks in
            blocks = entry.blocks
        }
        applyBackground(entry.background, for: documentID)
        if let clipboard, clipboard.isCut, containsBlockAnywhere(clipboard.block.id) {
            // The cut was undone, so its block is back on a board; pasting must not duplicate it.
            self.clipboard?.isCut = false
            detachedClipboardDocumentIDs = []
        }
        restoreDocuments(from: entry.pursuits)
        Self.refreshPursuitTitles(&snapshot)
        isApplyingUndo = false
        persist()
    }

    /// Brings back boards the restored blocks point to again, and drops boards nothing reaches.
    /// Boards that still exist keep their live content; each board's own edits undo on its own stack.
    private func restoreDocuments(from saved: [ComposerPursuit]?) {
        if let saved {
            var liveIDs = Set(snapshot.pursuits.map(\.id))
            var addedAny = true
            while addedAny {
                addedAny = false
                let referenced = ComposerBoardSync.referencedIDs(in: snapshot)
                for document in saved where !liveIDs.contains(document.id) && referenced.contains(document.id.rawValue) {
                    snapshot.pursuits.append(document)
                    liveIDs.insert(document.id)
                    addedAny = true
                }
            }
        }
        guard !isRestoringDocuments else { return }
        ComposerBoardSync.pruneUnreferenced(
            &snapshot,
            protecting: Set(detachedClipboardDocumentIDs.map(\.rawValue))
        )
    }

    private func containsBlockAnywhere(_ id: ComposerBlockID) -> Bool {
        func contains(_ blocks: [ComposerBlock]) -> Bool {
            blocks.contains { $0.id == id || contains($0.groupMembers) }
        }
        return contains(snapshot.mosaicBlocks) || snapshot.pursuits.contains { contains($0.blocks) }
    }

    func replacePage(_ blocks: [ComposerBlock], in documentID: ComposerDocumentID?) {
        captureUndo(in: documentID)
        mutateBlocks(for: documentID) { existing in
            existing = blocks
        }
        persist()
    }

    func boardBackground(for documentID: ComposerDocumentID?) -> ComposerBoardBackground? {
        if let documentID {
            return snapshot.pursuits.first(where: { $0.id == documentID })?.background
        }
        return snapshot.mosaicBackground
    }

    func setBoardBackground(_ background: ComposerBoardBackground?, for documentID: ComposerDocumentID?) {
        if let documentID {
            guard snapshot.pursuits.contains(where: { $0.id == documentID }) else { return }
        }
        guard boardBackground(for: documentID) != background else { return }
        // Dragging a color or gradient merges into one step, like typing in a block.
        captureUndo(in: documentID, coalesce: Self.backgroundUndoKey)
        applyBackground(background, for: documentID)
        persist()
    }

    private static let backgroundUndoKey = ComposerBlockID(rawValue: "board-background")

    private func applyBackground(_ background: ComposerBoardBackground?, for documentID: ComposerDocumentID?) {
        if let documentID {
            guard let index = snapshot.pursuits.firstIndex(where: { $0.id == documentID }) else { return }
            snapshot.pursuits[index].background = background
        } else {
            snapshot.mosaicBackground = background
        }
    }

    func layoutHeight(for documentID: ComposerDocumentID?) -> Double? {
        if let documentID {
            return snapshot.pursuits.first(where: { $0.id == documentID })?.layoutHeight
        }
        return snapshot.mosaicLayoutHeight
    }

    /// Records the page’s vertical scale once. Later moves keep using it, so other blocks stay put.
    func lockLayoutHeight(_ height: Double, for documentID: ComposerDocumentID?) {
        guard height > 1 else { return }
        if let documentID {
            guard let index = snapshot.pursuits.firstIndex(where: { $0.id == documentID }),
                  snapshot.pursuits[index].layoutHeight == nil else { return }
            snapshot.pursuits[index].layoutHeight = height
        } else {
            guard snapshot.mosaicLayoutHeight == nil else { return }
            snapshot.mosaicLayoutHeight = height
        }
        persist()
    }

    func blocks(for documentID: ComposerDocumentID?) -> [ComposerBlock] {
        if let documentID {
            return snapshot.pursuits.first(where: { $0.id == documentID })?.blocks ?? []
        }
        return snapshot.mosaicBlocks
    }

    func block(with id: ComposerBlockID, in documentID: ComposerDocumentID?) -> ComposerBlock? {
        let page = blocks(for: documentID)
        if let block = page.first(where: { $0.id == id }) {
            return block
        }
        for block in page where block.kind == .group {
            if let member = block.groupMembers.first(where: { $0.id == id }) {
                return member
            }
        }
        return nil
    }

    /// Turns the fixed Mosaic title into a heading on the board, once.
    func placeMosaicTitleIfNeeded() {
        guard !snapshot.mosaicTitlePlaced else { return }
        var block = ComposerBlock.make(kind: .heading, position: BlockPosition(x: 0.06, y: 0.03))
        block.text = "Mosaic"
        block.style.fontSize = 34
        snapshot.mosaicBlocks.insert(block, at: 0)
        snapshot.mosaicTitle = "Mosaic"
        snapshot.mosaicTitlePlaced = true
        persist()
    }

    /// Clears anything already saved inside Pursuit pages, once, so each page opens empty.
    /// Journal pages are documents too, and their blocks are the owner's content.
    func blankPursuitPagesIfNeeded() {
        guard !snapshot.pursuitPagesBlanked else { return }
        for index in snapshot.pursuits.indices where snapshot.pursuits[index].role != .page {
            snapshot.pursuits[index].blocks.removeAll()
        }
        snapshot.pursuitPagesBlanked = true
        persist()
    }

    func title(for documentID: ComposerDocumentID?) -> String {
        if let documentID {
            let title = snapshot.pursuits.first(where: { $0.id == documentID })?.title ?? ""
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let role = snapshot.pursuits.first(where: { $0.id == documentID })?.role
            let fallback = role == .node ? "Node" : (role == .page ? "Page" : "Pursuit")
            return trimmed.isEmpty ? fallback : trimmed
        }
        return snapshot.mosaicTitle
    }

    func pursuit(for id: ComposerDocumentID) -> ComposerPursuit? {
        snapshot.pursuits.first(where: { $0.id == id })
    }

    @discardableResult
    func addBlock(_ kind: BlockKind, to documentID: ComposerDocumentID?) -> ComposerBlockID {
        let position = BlockPosition.defaultPosition(index: blocks(for: documentID).count)
        return addBlock(kind, at: position, to: documentID)
    }

    /// Removes a block that never became anything (picker cancelled, nothing added) together with
    /// the undo step that added it, so Undo doesn't bring back an empty placeholder.
    func discardPlaceholder(_ blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        let key = Self.undoKey(documentID)
        let remaining = blocks(for: documentID).filter { $0.id != blockID }
        guard remaining.count < blocks(for: documentID).count else { return }
        if let last = undoStacks[key]?.last, last.blocks == remaining {
            undoStacks[key]?.removeLast()
            undoCoalesce = nil
            mutateBlocks(for: documentID) { $0 = remaining }
            persist()
        } else {
            deleteBlock(blockID, in: documentID)
        }
    }

    @discardableResult
    func addBlock(
        _ kind: BlockKind,
        at position: BlockPosition,
        to documentID: ComposerDocumentID?,
        configure: ((inout ComposerBlock) -> Void)? = nil
    ) -> ComposerBlockID {
        if kind == .tabs, let existing = blocks(for: documentID).first(where: { $0.kind == .tabs }) {
            return existing.id
        }
        if kind == .banner, let existing = blocks(for: documentID).first(where: { $0.kind == .banner }) {
            return existing.id
        }
        captureUndo(in: documentID, includePursuits: kind == .pursuit || kind == .node || kind == .scrapbook)
        var block = ComposerBlock.make(kind: kind, position: position)
        configure?(&block)
        if kind == .scrapbook {
            let pages = (1...2).map { _ in ComposerDocumentID() }
            block.scrapbookPageIDs = pages
            for (offset, pageID) in pages.enumerated() {
                snapshot.pursuits.append(
                    ComposerPursuit(id: pageID, title: "Page \(offset + 1)", blocks: [], role: .page)
                )
            }
        }
        if kind == .pursuit || kind == .node, let pursuitID = block.pursuitID {
            let document = ComposerPursuit(
                id: pursuitID,
                title: block.text,
                blocks: [],
                role: kind == .node ? .node : .pursuit
            )
            snapshot.pursuits.append(document)
        }
        if kind == .tabs {
            let firstID = block.tabs.first?.id
            block.selectedTabID = firstID
            mutateBlocks(for: documentID) { blocks in
                for index in blocks.indices where blocks[index].kind != .banner {
                    blocks[index].tabID = firstID
                }
                blocks.append(block)
            }
        } else {
            if kind != .banner, let selected = blocks(for: documentID).first(where: { $0.kind == .tabs })?.selectedTabID {
                block.tabID = selected
            }
            mutateBlocks(for: documentID) { blocks in
                blocks.append(block)
            }
        }
        persist()
        return block.id
    }

    func updateBlock(_ block: ComposerBlock, in documentID: ComposerDocumentID?) {
        guard let current = self.block(with: block.id, in: documentID), current != block else { return }
        var inkChanged = current
        inkChanged.drawingData = block.drawingData
        let isInkOnly = block.kind == .drawing && inkChanged == block
        // The first ink on a just-placed drawing joins the step that placed it, so Undo never
        // brings back an empty drawing box.
        let joinsPlacement = isInkOnly && current.drawingData == nil
            && undoStacks[Self.undoKey(documentID)]?.last?.blocks == blocks(for: documentID).filter { $0.id != block.id }
        if !joinsPlacement {
            captureUndo(in: documentID, coalesce: block.id)
        }
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(block.id, in: &blocks) { current in
                current = block
            }
        }
        // Title lives on the pursuit document, outside the block array this method just borrowed.
        if (block.kind == .pursuit || block.kind == .node), let pursuitID = block.pursuitID,
           let pursuitIndex = snapshot.pursuits.firstIndex(where: { $0.id == pursuitID }) {
            snapshot.pursuits[pursuitIndex].title = block.pursuitDisplayName
        }
        // Strokes come quickly and the whole snapshot is rewritten each save, so ink saves in a batch.
        if isInkOnly {
            persistSoon()
        } else {
            persist()
        }
    }

    /// Removes a drawing whose ink was all erased, without an undo step of its own: Undo then
    /// returns to the drawing as it was before the last erase. A drawing placed and never drawn
    /// in goes away with the step that placed it.
    func discardEmptyDrawing(_ blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        guard let block = blocks(for: documentID).first(where: { $0.id == blockID }),
              block.kind == .drawing, block.drawingData == nil else { return }
        let key = Self.undoKey(documentID)
        let remaining = blocks(for: documentID).filter { $0.id != blockID }
        if undoStacks[key]?.last?.blocks == remaining {
            undoStacks[key]?.removeLast()
        }
        undoCoalesce = nil
        mutateBlocks(for: documentID) { $0 = remaining }
        persist()
    }

    /// Changes a drawing's box (and shifts its strokes to match) outside the undo history: the ink
    /// stays where it is on the board, so there is nothing for Undo to take back.
    func reshapeDrawing(_ block: ComposerBlock, in documentID: ComposerDocumentID?) {
        guard block.kind == .drawing,
              let current = blocks(for: documentID).first(where: { $0.id == block.id }), current != block else { return }
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(block.id, in: &blocks) { $0 = block }
        }
        persist()
    }

    /// Adds a cutout to "Your stickers", newest first. Not an undo step: the list isn't a board.
    func saveToStickerLibrary(fileName: String, size: CGSize) {
        guard !fileName.isEmpty else { return }
        var library = snapshot.stickerLibrary.filter { $0.fileName != fileName }
        library.insert(
            ComposerSavedSticker(fileName: fileName, width: Double(size.width), height: Double(size.height)),
            at: 0
        )
        snapshot.stickerLibrary = Array(library.prefix(ComposerSavedSticker.limit))
        persist()
    }

    /// Takes a sticker out of "Your stickers". Copies already placed on boards stay.
    func removeFromStickerLibrary(_ fileName: String) {
        let library = snapshot.stickerLibrary.filter { $0.fileName != fileName }
        guard library.count != snapshot.stickerLibrary.count else { return }
        snapshot.stickerLibrary = library
        persist()
    }

    /// Writes a batched save now, for example when drawing ends or the app leaves the screen.
    func flushPendingSave() {
        guard pendingSave != nil else { return }
        persist()
    }

    private func persistSoon() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    func deleteBlock(_ blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        guard let removed = blocks(for: documentID).first(where: { $0.id == blockID }) else { return }
        let owned = ownedDocuments(of: removed)
        captureUndo(in: documentID, includePursuits: !owned.isEmpty)
        mutateBlocks(for: documentID) { blocks in
            blocks.removeAll { $0.id == blockID }
            if removed.kind == .tabs {
                for index in blocks.indices {
                    blocks[index].tabID = nil
                }
            }
        }
        if !owned.isEmpty {
            let ownedIDs = Set(owned.map(\.id))
            snapshot.pursuits.removeAll { ownedIDs.contains($0.id) }
        }
        persist()
    }

    /// Inserts an empty board after the current scrapbook page. Returns the new page index.
    @discardableResult
    func insertScrapbookPage(after index: Int, on blockID: ComposerBlockID, in documentID: ComposerDocumentID?) -> Int? {
        guard var block = block(with: blockID, in: documentID),
              block.kind == .scrapbook,
              block.scrapbookPageIDs.count < 30 else { return nil }
        captureUndo(in: documentID, includePursuits: true)
        let pageID = ComposerDocumentID()
        let insertAt = min(max(index, -1) + 1, block.scrapbookPageIDs.count)
        block.scrapbookPageIDs.insert(pageID, at: insertAt)
        block.scrapbookIndex = insertAt
        snapshot.pursuits.append(
            ComposerPursuit(id: pageID, title: "Page \(insertAt + 1)", blocks: [], role: .page)
        )
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { current in
                current.scrapbookPageIDs = block.scrapbookPageIDs
                current.scrapbookIndex = insertAt
            }
        }
        persist()
        return insertAt
    }

    /// Removes one scrapbook page when another remains. Returns the page now showing.
    @discardableResult
    func removeScrapbookPage(at index: Int, on blockID: ComposerBlockID, in documentID: ComposerDocumentID?) -> Int? {
        guard var block = block(with: blockID, in: documentID),
              block.kind == .scrapbook,
              block.scrapbookPageIDs.count > 1,
              block.scrapbookPageIDs.indices.contains(index) else { return nil }
        captureUndo(in: documentID, includePursuits: true)
        let removed = block.scrapbookPageIDs.remove(at: index)
        let nextIndex = min(index, block.scrapbookPageIDs.count - 1)
        block.scrapbookIndex = nextIndex
        snapshot.pursuits.removeAll { $0.id == removed }
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { current in
                current.scrapbookPageIDs = block.scrapbookPageIDs
                current.scrapbookIndex = nextIndex
            }
        }
        persist()
        return nextIndex
    }

    func rememberScrapbookPage(_ index: Int, on blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        guard let block = block(with: blockID, in: documentID),
              block.kind == .scrapbook,
              block.scrapbookPageIDs.indices.contains(index),
              block.scrapbookIndex != index else { return }
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { current in
                current.scrapbookIndex = index
            }
        }
        persist()
    }

    func addComposerTab(to blockID: ComposerBlockID, in documentID: ComposerDocumentID?, longestSide: CGFloat) {
        let edit = beginEdit(in: documentID)
        mutateBlocks(for: documentID) { blocks in
            guard let index = blocks.firstIndex(where: { $0.id == blockID }),
                  blocks[index].kind == .tabs,
                  blocks[index].tabs.count < ComposerTabSet.maximumCount(longestSide: longestSide) else { return }
            let tab = ComposerTab(title: "Tab \(blocks[index].tabs.count + 1)")
            blocks[index].tabs.append(tab)
            blocks[index].selectedTabID = tab.id
        }
        finishEdit(edit)
    }

    func removeComposerTab(_ tabID: String, from blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        let edit = beginEdit(in: documentID)
        mutateBlocks(for: documentID) { blocks in
            guard let index = blocks.firstIndex(where: { $0.id == blockID }),
                  blocks[index].kind == .tabs,
                  blocks[index].tabs.count > ComposerTabSet.minimumCount,
                  let tabIndex = blocks[index].tabs.firstIndex(where: { $0.id == tabID }) else { return }
            blocks[index].tabs.remove(at: tabIndex)
            let fallback = blocks[index].tabs[min(tabIndex, blocks[index].tabs.count - 1)].id
            if blocks[index].selectedTabID == tabID {
                blocks[index].selectedTabID = fallback
            }
            for item in blocks.indices where blocks[item].tabID == tabID {
                blocks[item].tabID = fallback
            }
        }
        finishEdit(edit)
    }

    func addTableColumn(to blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        let edit = beginEdit(in: documentID)
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { block in
                guard block.kind == .table else { return }
                ComposerTable.ensure(&block)
                guard let next = ComposerTable.addingColumn(to: block.tableColumns, rows: block.tableRows) else { return }
                block.tableColumns = next.columns
                block.tableRows = next.rows
                block.tableEntries = ComposerTable.appendingColumnCell(to: block.tableEntries)
                rememberVisibleTableRows(&block)
            }
        }
        finishEdit(edit)
    }

    func removeLastTableColumn(from blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        let edit = beginEdit(in: documentID)
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { block in
                guard block.kind == .table else { return }
                ComposerTable.ensure(&block)
                guard let next = ComposerTable.removingLastColumn(from: block.tableColumns, rows: block.tableRows) else { return }
                block.tableColumns = next.columns
                block.tableRows = next.rows
                block.tableEntries = ComposerTable.removingLastColumnCell(from: block.tableEntries)
                rememberVisibleTableRows(&block)
            }
        }
        finishEdit(edit)
    }

    func addTableRow(to blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        let edit = beginEdit(in: documentID)
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { block in
                guard block.kind == .table else { return }
                ComposerTable.ensure(&block)
                guard let next = ComposerTable.addingRow(to: block.tableRows, columnCount: block.tableColumns.count) else { return }
                block.tableRows = next
                rememberVisibleTableRows(&block)
            }
        }
        finishEdit(edit)
    }

    func removeLastTableRow(from blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        let edit = beginEdit(in: documentID)
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { block in
                guard block.kind == .table else { return }
                ComposerTable.ensure(&block)
                guard let next = ComposerTable.removingLastRow(from: block.tableRows) else { return }
                block.tableRows = next
                rememberVisibleTableRows(&block)
            }
        }
        finishEdit(edit)
    }

    func startTableEntry(on blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        let edit = beginEdit(in: documentID)
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { block in
                guard block.kind == .table else { return }
                ComposerTable.ensure(&block)
                rememberVisibleTableRows(&block)
                guard block.tableEntries.count < ComposerTable.maximumEntries else { return }
                let blank = ComposerTable.blankRows(
                    rowCount: block.tableRows.count,
                    columnCount: block.tableColumns.count
                )
                let entry = ComposerTableEntry(rows: blank)
                block.tableEntries.append(entry)
                block.selectedTableEntryID = entry.id
                block.tableRows = blank
            }
        }
        finishEdit(edit)
    }

    func showTableEntry(_ entryID: String, on blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        let edit = beginEdit(in: documentID)
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { block in
                guard block.kind == .table,
                      let entry = block.tableEntries.first(where: { $0.id == entryID }) else { return }
                ComposerTable.ensure(&block)
                rememberVisibleTableRows(&block)
                block.selectedTableEntryID = entryID
                block.tableRows = entry.rows
            }
        }
        finishEdit(edit)
    }

    private func rememberVisibleTableRows(_ block: inout ComposerBlock) {
        guard let entryIndex = block.tableEntries.firstIndex(where: { $0.id == block.selectedTableEntryID }) else { return }
        block.tableEntries[entryIndex].rows = block.tableRows
    }

    /// Draw order is the page's block order: the last block is on top.
    func bringToFront(_ blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        reorder(blockID, toFront: true, in: documentID)
    }

    func sendToBack(_ blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        reorder(blockID, toFront: false, in: documentID)
    }

    private func reorder(_ blockID: ComposerBlockID, toFront: Bool, in documentID: ComposerDocumentID?) {
        let edit = beginEdit(in: documentID)
        mutateBlocks(for: documentID) { blocks in
            guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
            let block = blocks.remove(at: index)
            if toFront {
                blocks.append(block)
            } else {
                blocks.insert(block, at: 0)
            }
        }
        finishEdit(edit)
    }

    func setRotation(_ degrees: Double, for blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        let angle = ComposerRotation.normalized(degrees)
        let edit = beginEdit(in: documentID)
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { block in
                guard block.canRotate, !block.isLocked else { return }
                block.rotation = angle
            }
        }
        finishEdit(edit)
    }

    func setLocked(_ locked: Bool, for blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        let edit = beginEdit(in: documentID)
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { $0.isLocked = locked }
        }
        finishEdit(edit)
    }

    /// Opacity and shadow. A slider drag arrives as many small changes; they join one undo step
    /// and save in a batch.
    func setLook(
        opacity: Double? = nil,
        shadow: ComposerPieceShadow? = nil,
        shadowColor: ComposerShadowColor? = nil,
        stickerBorder: Bool? = nil,
        frameStyle: ComposerFrameStyle? = nil,
        frameCaption: String? = nil,
        photoShape: MediaFrameShape? = nil,
        for blockID: ComposerBlockID,
        in documentID: ComposerDocumentID?
    ) {
        guard var block = self.block(with: blockID, in: documentID) else { return }
        let current = block
        if block.kind == .media {
            if let frameStyle { block.frameStyle = frameStyle }
            if let frameCaption { block.frameCaption = String(frameCaption.prefix(ComposerFrameStyle.captionLimit)) }
            if let photoShape, photoShape != block.mediaShape {
                // A circle is round only on a square frame. Leaving one returns to the photo's own
                // shape, rather than keeping it square.
                if photoShape == .circle {
                    block.mediaFrameAspect = 1
                } else if block.mediaShape == .circle {
                    block.mediaFrameAspect = 0
                }
                block.mediaShape = photoShape
                block.mediaWarp = nil
            }
        }
        if let opacity { block.opacity = ComposerPieceLook.clampedOpacity(opacity) }
        if let shadow { block.shadow = shadow }
        if let shadowColor { block.shadowColor = shadowColor }
        if let stickerBorder, block.kind == .sticker { block.stickerBorder = stickerBorder }
        guard block != current else { return }
        captureUndo(in: documentID, coalesce: blockID)
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { $0 = block }
        }
        persistSoon()
    }

    func moveBlock(_ blockID: ComposerBlockID, direction: MoveDirection, in documentID: ComposerDocumentID?) {
        let edit = beginEdit(in: documentID)
        mutateBlocks(for: documentID) { blocks in
            guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
            let target: Int
            switch direction {
            case .up:
                target = index - 1
            case .down:
                target = index + 1
            }
            guard blocks.indices.contains(target) else { return }
            blocks.swapAt(index, target)
        }
        finishEdit(edit)
    }

    /// A different photo or video doesn't fit the old zoom and pan, so `resetsFraming` clears them; the frame shape stays.
    func setMedia(
        _ fileName: String,
        for blockID: ComposerBlockID,
        in documentID: ComposerDocumentID?,
        resetsFraming: Bool = false
    ) {
        let edit = beginEdit(in: documentID)
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { block in
                if resetsFraming {
                    block.mediaZoom = 1
                    block.mediaPanX = 0
                    block.mediaPanY = 0
                    block.mediaWarp = nil
                }
                block.mediaFileName = fileName
            }
        }
        finishEdit(edit)
    }

    /// A GIF keeps its own extension, so it uploads as a GIF and visitors download the animation.
    func saveMediaData(_ data: Data, fileExtension: String? = nil) throws -> String {
        let directory = location.mediaDirectory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = fileExtension ?? (ComposerAnimatedImage.isGIF(data) ? "gif" : "jpg")
        let fileName = "\(UUID().uuidString).\(ext)"
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return fileName
    }

    func saveMediaFile(from source: URL, removeSource: Bool = false) throws -> String {
        let directory = location.mediaDirectory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let destination = directory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        if removeSource {
            do {
                try fileManager.moveItem(at: source, to: destination)
                return fileName
            } catch {
                try fileManager.copyItem(at: source, to: destination)
                try? fileManager.removeItem(at: source)
                return fileName
            }
        }
        try fileManager.copyItem(at: source, to: destination)
        return fileName
    }

    func storePreparedCarouselMedia(_ prepared: PreparedCarouselMedia) throws -> String {
        if let videoURL = prepared.videoURL {
            return try saveMediaFile(from: videoURL, removeSource: true)
        }
        if let imageData = prepared.imageData {
            return try saveMediaData(imageData)
        }
        throw CocoaError(.fileWriteUnknown)
    }

    /// The component most recently copied or cut. Shared across the board, Pursuit pages, and journal pages.
    var clipboard: ComposerClipboardItem?
    /// Document ids held by a cut that has not been pasted yet. Sync must not delete them.
    private(set) var detachedClipboardDocumentIDs: Set<ComposerDocumentID> = []

    /// UUID form of detached cut documents for remote sync.
    var syncProtectedDocumentUUIDs: Set<UUID> {
        Set(detachedClipboardDocumentIDs.compactMap { UUID(uuidString: $0.rawValue) })
    }

    func copyBlock(_ blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        guard let block = block(with: blockID, in: documentID) else { return }
        releaseDetachedClipboard()
        clipboard = ComposerClipboardItem(block: block, documents: ownedDocuments(of: block), isCut: false)
    }

    /// Removes the block from the board but keeps its documents until paste or clipboard replace.
    func cutBlock(_ blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        guard let block = blocks(for: documentID).first(where: { $0.id == blockID }) else { return }
        releaseDetachedClipboard()
        let owned = ownedDocuments(of: block)
        clipboard = ComposerClipboardItem(block: block, documents: owned, isCut: true)
        detachedClipboardDocumentIDs = Set(owned.map(\.id))
        captureUndo(in: documentID, includePursuits: !owned.isEmpty)
        mutateBlocks(for: documentID) { blocks in
            blocks.removeAll { $0.id == blockID }
            if block.kind == .tabs {
                for index in blocks.indices {
                    blocks[index].tabID = nil
                }
            }
        }
        persist()
    }

    /// Places the clipboard on this page and clears it.
    /// Folder widgets become Pursuits on the Mosaic and Nodes inside a Pursuit or Node.
    @discardableResult
    func pasteClipboard(at position: BlockPosition, in documentID: ComposerDocumentID?) -> ComposerBlockID? {
        guard let clipboard else { return nil }
        let page = blocks(for: documentID)
        if clipboard.block.kind == .banner, page.contains(where: { $0.kind == .banner }) { return nil }
        if clipboard.block.kind == .tabs, page.contains(where: { $0.kind == .tabs }) { return nil }
        let folderRole = Self.folderRole(forPasteInto: documentID, pursuits: snapshot.pursuits)
        if folderRole == nil, Self.containsFolder(clipboard.block) { return nil }
        let isJournalPage = documentID.flatMap { id in snapshot.pursuits.first(where: { $0.id == id })?.role } == .page
        guard Self.allowsPlacement(of: clipboard.block, onMosaic: documentID == nil, onJournalPage: isJournalPage)
        else { return nil }
        // Drawings are saved inside the board; past the budget it would be too large to sync.
        let pastedInk = ComposerDrawingMetrics.bytes(in: [clipboard.block])
        guard pastedInk == 0 || ComposerDrawingMetrics.bytes(in: page) + pastedInk <= ComposerDrawingMetrics.boardBudget
        else { return nil }

        let placedBlock: ComposerBlock
        let documents: [ComposerPursuit]
        if clipboard.isCut {
            placedBlock = clipboard.block
            documents = clipboard.documents
        } else {
            (placedBlock, documents) = Self.reidentified(block: clipboard.block, documents: clipboard.documents)
        }
        var placed = placedBlock
        var adaptedDocuments = documents
        if let folderRole {
            Self.adaptFolderRoles(block: &placed, documents: &adaptedDocuments, role: folderRole)
        }
        placed.position = position
        if placed.kind != .banner, placed.kind != .tabs,
           let selected = page.first(where: { $0.kind == .tabs })?.selectedTabID {
            placed.tabID = selected
        }
        captureUndo(
            in: documentID,
            includePursuits: !adaptedDocuments.isEmpty
                || placed.kind == .pursuit
                || placed.kind == .node
                || placed.kind == .scrapbook
        )
        if clipboard.isCut {
            for document in adaptedDocuments {
                if let index = snapshot.pursuits.firstIndex(where: { $0.id == document.id }) {
                    snapshot.pursuits[index].role = document.role
                    snapshot.pursuits[index].title = document.title
                } else {
                    snapshot.pursuits.append(document)
                }
            }
            detachedClipboardDocumentIDs = []
        } else {
            snapshot.pursuits.append(contentsOf: adaptedDocuments)
        }
        mutateBlocks(for: documentID) { blocks in
            if placed.kind == .tabs {
                // Same as adding a tabs bar: everything already on the page starts on the selected tab.
                let tabIDs = Set(placed.tabs.map(\.id))
                let selected = placed.selectedTabID.flatMap { tabIDs.contains($0) ? $0 : nil } ?? placed.tabs.first?.id
                placed.selectedTabID = selected
                for index in blocks.indices where blocks[index].kind != .banner {
                    if blocks[index].tabID.map({ !tabIDs.contains($0) }) ?? true {
                        blocks[index].tabID = selected
                    }
                }
            }
            blocks.append(placed)
        }
        self.clipboard = nil
        persist()
        return placed.id
    }

    /// The same rules as the add menu: the Mosaic has no scrapbooks, calendars, graphs, or tables,
    /// and journal pages only take simple pieces. Group members follow the same rule.
    static func allowsPlacement(of block: ComposerBlock, onMosaic: Bool, onJournalPage: Bool) -> Bool {
        let allowed: Bool
        if onMosaic {
            allowed = ![.scrapbook, .calendar, .graph, .table].contains(block.kind)
        } else if onJournalPage {
            allowed = [.group, .text, .heading, .list, .media, .social, .link, .calendar, .drawing, .sticker].contains(block.kind)
        } else {
            allowed = true
        }
        return allowed && block.groupMembers.allSatisfy {
            allowsPlacement(of: $0, onMosaic: onMosaic, onJournalPage: onJournalPage)
        }
    }

    /// Drops cut documents that never got pasted once the clipboard moves on.
    private func releaseDetachedClipboard() {
        let protected = detachedClipboardDocumentIDs
        detachedClipboardDocumentIDs = []
        guard !protected.isEmpty else { return }
        let keep = ComposerBoardSync.referencedIDs(in: snapshot)
        let dropKeys = Set(protected.map(\.rawValue).filter { !keep.contains($0) })
        guard !dropKeys.isEmpty else { return }
        snapshot.pursuits.removeAll { dropKeys.contains($0.id.rawValue) }
    }

    /// Mosaic → Pursuit. Inside a Pursuit or Node → Node. Journal / scrapbook pages refuse folders.
    private static func folderRole(
        forPasteInto documentID: ComposerDocumentID?,
        pursuits: [ComposerPursuit]
    ) -> ComposerDocumentRole? {
        guard let documentID else { return .pursuit }
        guard let role = pursuits.first(where: { $0.id == documentID })?.role else { return nil }
        switch role {
        case .pursuit, .node: return .node
        case .page: return nil
        }
    }

    private static func containsFolder(_ block: ComposerBlock) -> Bool {
        if block.kind == .pursuit || block.kind == .node { return true }
        return block.groupMembers.contains(where: containsFolder)
    }

    /// Rewrites only the pasted folder roots (and group members). Nested boards stay as they are.
    private static func adaptFolderRoles(
        block: inout ComposerBlock,
        documents: inout [ComposerPursuit],
        role: ComposerDocumentRole
    ) {
        let kind: BlockKind = role == .pursuit ? .pursuit : .node
        func adapt(_ block: inout ComposerBlock) {
            if block.kind == .pursuit || block.kind == .node {
                block.kind = kind
                if let id = block.pursuitID,
                   let index = documents.firstIndex(where: { $0.id == id }) {
                    documents[index].role = role
                }
                return
            }
            for index in block.groupMembers.indices {
                adapt(&block.groupMembers[index])
            }
        }
        adapt(&block)
    }

    func mediaURL(for fileName: String) -> URL {
        location.mediaDirectory.appendingPathComponent(fileName)
    }

    enum MoveDirection {
        case up
        case down
    }

    private struct PendingEdit {
        var documentID: ComposerDocumentID?
        var blocks: [ComposerBlock]
        var depth: Int
        var coalesce: ComposerUndoCoalesce?
    }

    /// Records an undo step for a structural edit. `finishEdit` drops it again when nothing changed.
    private func beginEdit(in documentID: ComposerDocumentID?) -> PendingEdit {
        let edit = PendingEdit(
            documentID: documentID,
            blocks: blocks(for: documentID),
            depth: undoStacks[Self.undoKey(documentID)]?.count ?? 0,
            coalesce: undoCoalesce
        )
        captureUndo(in: documentID)
        return edit
    }

    private func finishEdit(_ edit: PendingEdit) {
        guard blocks(for: edit.documentID) == edit.blocks else {
            persist()
            return
        }
        let key = Self.undoKey(edit.documentID)
        if let stack = undoStacks[key], stack.count > edit.depth {
            undoStacks[key]?.removeLast()
        }
        undoCoalesce = edit.coalesce
    }

    private func captureUndo(
        in documentID: ComposerDocumentID?,
        coalesce blockID: ComposerBlockID? = nil,
        includePursuits: Bool = false
    ) {
        guard !isApplyingUndo else { return }
        let key = Self.undoKey(documentID)
        let now = Date()
        if let blockID,
           let undoCoalesce,
           undoCoalesce.documentKey == key,
           undoCoalesce.blockID == blockID,
           now.timeIntervalSince(undoCoalesce.at) < 0.75 {
            self.undoCoalesce?.at = now
            return
        }
        var stack = undoStacks[key] ?? []
        stack.append(
            ComposerUndoEntry(
                blocks: blocks(for: documentID),
                pursuits: includePursuits ? snapshot.pursuits : nil,
                background: boardBackground(for: documentID)
            )
        )
        if stack.count > 40 {
            stack.removeFirst(stack.count - 40)
        }
        undoStacks[key] = stack
        undoCoalesce = blockID.map { ComposerUndoCoalesce(documentKey: key, blockID: $0, at: now) }
    }

    /// Sets each Pursuit and node title from its widget, on every board. Returns true when a title changed.
    @discardableResult
    static func refreshPursuitTitles(_ snapshot: inout ComposerSnapshot) -> Bool {
        var names: [ComposerDocumentID: String] = [:]
        func collect(_ blocks: [ComposerBlock]) {
            for block in blocks {
                if block.kind == .pursuit || block.kind == .node, let id = block.pursuitID {
                    names[id] = block.pursuitDisplayName
                }
                collect(block.groupMembers)
            }
        }
        collect(snapshot.mosaicBlocks)
        for pursuit in snapshot.pursuits {
            collect(pursuit.blocks)
        }
        var changed = false
        for index in snapshot.pursuits.indices {
            if let name = names[snapshot.pursuits[index].id], snapshot.pursuits[index].title != name {
                snapshot.pursuits[index].title = name
                changed = true
            }
        }
        return changed
    }

    private static func undoKey(_ documentID: ComposerDocumentID?) -> String {
        documentID?.rawValue ?? "mosaic"
    }

    private func updateOwnedBlock(
        _ blockID: ComposerBlockID,
        in blocks: inout [ComposerBlock],
        _ body: (inout ComposerBlock) -> Void
    ) {
        if let index = blocks.firstIndex(where: { $0.id == blockID }) {
            body(&blocks[index])
            return
        }
        for index in blocks.indices where blocks[index].kind == .group {
            if let member = blocks[index].groupMembers.firstIndex(where: { $0.id == blockID }) {
                body(&blocks[index].groupMembers[member])
                return
            }
        }
    }

    private func ownedDocuments(of block: ComposerBlock) -> [ComposerPursuit] {
        var result: [ComposerPursuit] = []
        var seen = Set<String>()
        func walk(_ block: ComposerBlock) {
            var ids: [ComposerDocumentID] = []
            if block.kind == .scrapbook {
                ids.append(contentsOf: block.scrapbookPageIDs)
            }
            if block.kind == .pursuit || block.kind == .node, let pursuitID = block.pursuitID {
                ids.append(pursuitID)
            }
            if block.kind == .unsupported {
                let mentioned = Set(block.preservedStrings.map { $0.lowercased() })
                ids.append(contentsOf: snapshot.pursuits.map(\.id).filter { mentioned.contains($0.rawValue.lowercased()) })
            }
            for id in ids where seen.insert(id.rawValue).inserted {
                guard let document = snapshot.pursuits.first(where: { $0.id == id }) else { continue }
                result.append(document)
                for child in document.blocks {
                    walk(child)
                }
            }
            for member in block.groupMembers {
                walk(member)
            }
        }
        walk(block)
        return result
    }

    private static func reidentified(
        block: ComposerBlock,
        documents: [ComposerPursuit]
    ) -> (ComposerBlock, [ComposerPursuit]) {
        var replacements: [String: String] = [:]
        func noteBlock(_ block: ComposerBlock) {
            replacements[block.id.rawValue] = UUID().uuidString
            for member in block.groupMembers {
                noteBlock(member)
            }
        }
        func noteDocument(_ document: ComposerPursuit) {
            replacements[document.id.rawValue] = UUID().uuidString
            for child in document.blocks {
                noteBlock(child)
            }
        }
        noteBlock(block)
        for document in documents {
            noteDocument(document)
        }
        let copy = rewrite(block, replacements: replacements)
        let pages = documents.map { rewrite($0, replacements: replacements) }
        return (copy, pages)
    }

    private static func rewrite<T: Codable>(_ value: T, replacements: [String: String]) -> T {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        guard var json = (try? encoder.encode(value)).flatMap({ String(data: $0, encoding: .utf8) }) else {
            return value
        }
        for (old, new) in replacements {
            json = json.replacingOccurrences(of: old, with: new)
        }
        guard let data = json.data(using: .utf8), let decoded = try? decoder.decode(T.self, from: data) else {
            return value
        }
        return decoded
    }

    private func mutateBlocks(for documentID: ComposerDocumentID?, _ update: (inout [ComposerBlock]) -> Void) {
        if let documentID {
            guard let index = snapshot.pursuits.firstIndex(where: { $0.id == documentID }) else { return }
            update(&snapshot.pursuits[index].blocks)
        } else {
            update(&snapshot.mosaicBlocks)
        }
    }

    private func persist() {
        pendingSave?.cancel()
        pendingSave = nil
        guard persistToDisk else { return }
        do {
            let url = location.snapshotURL
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
            if saveFailed { saveFailed = false }
            onPersisted?()
        } catch {
            // Edits stay in memory and every later edit tries again; the shell tells the person.
            saveFailed = true
        }
    }

    /// A file that exists but can't be read (for example, written by a newer build) is copied aside
    /// before the empty board that replaces it is saved, so its content can still be recovered.
    private static func loadSnapshot(at url: URL, fileManager: FileManager, decoder: JSONDecoder) -> ComposerSnapshot? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        if let data = try? Data(contentsOf: url),
           let snapshot = try? decoder.decode(ComposerSnapshot.self, from: data) {
            return snapshot
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        try? fileManager.copyItem(at: url, to: backup)
        return nil
    }

    private struct ComposerUndoEntry {
        var blocks: [ComposerBlock]
        var pursuits: [ComposerPursuit]?
        /// Every background change records its own step, so restoring this is always correct.
        var background: ComposerBoardBackground?
    }

    private struct ComposerUndoCoalesce {
        var documentKey: String
        var blockID: ComposerBlockID
        var at: Date
    }
}

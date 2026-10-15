import Foundation
import Observation

struct ComposerClipboardItem: Equatable {
    var block: ComposerBlock
    var documents: [ComposerPursuit]
}

@MainActor
@Observable
final class ComposerStore {
    private(set) var snapshot: ComposerSnapshot
    private(set) var isRestoringDocuments = false
    private(set) var mediaVersions: [String: Int] = [:]
    private var undoStacks: [String: [ComposerUndoEntry]] = [:]
    private var undoCoalesce: ComposerUndoCoalesce?
    private var isApplyingUndo = false

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
        let ids = Set(merged.pursuits.map { $0.id.rawValue })
        guard ComposerBoardSync.referencedIDs(in: merged).isSubset(of: ids) else {
            throw ComposerRestoreError.incompleteBoards
        }
        ComposerBoardSync.pruneUnreferenced(&merged)
        Self.refreshPursuitTitles(&merged)
        if persistToDisk {
            try encoder.encode(merged).write(to: location.snapshotURL, options: .atomic)
            try encoder.encode(state).write(to: location.syncStateURL, options: .atomic)
        }
        snapshot = merged
        // Undoing a landing-board edit must also recover children that were still downloading.
        for key in Array(undoStacks.keys) {
            guard var entries = undoStacks[key] else { continue }
            for index in entries.indices {
                guard key == Self.undoKey(nil) || entries[index].pursuits != nil else { continue }
                var saved = entries[index].pursuits ?? merged.pursuits
                let savedIDs = Set(saved.map(\.id))
                saved.append(contentsOf: remote.pursuits.filter { !savedIDs.contains($0.id) })
                if key == Self.undoKey(nil) {
                    var before = merged
                    before.mosaicBlocks = entries[index].blocks
                    before.pursuits = saved
                    ComposerBoardSync.pruneUnreferenced(&before)
                    saved = before.pursuits
                }
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
        if let documentID {
            if let index = snapshot.pursuits.firstIndex(where: { $0.id == documentID }) {
                snapshot.pursuits[index].blocks = entry.blocks
            }
        } else {
            snapshot.mosaicBlocks = entry.blocks
            if let pursuits = entry.pursuits {
                snapshot.pursuits = pursuitsKeepingPageEdits(from: pursuits)
            } else {
                syncPursuitTitlesFromMosaicBlocks()
            }
        }
        isApplyingUndo = false
        persist()
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
            guard let index = snapshot.pursuits.firstIndex(where: { $0.id == documentID }) else { return }
            snapshot.pursuits[index].background = background
        } else {
            snapshot.mosaicBackground = background
        }
        persist()
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

    @discardableResult
    func addBlock(_ kind: BlockKind, at position: BlockPosition, to documentID: ComposerDocumentID?) -> ComposerBlockID {
        if kind == .tabs, let existing = blocks(for: documentID).first(where: { $0.kind == .tabs }) {
            return existing.id
        }
        if kind == .banner, let existing = blocks(for: documentID).first(where: { $0.kind == .banner }) {
            return existing.id
        }
        captureUndo(in: documentID, includePursuits: kind == .pursuit || kind == .node || kind == .scrapbook)
        var block = ComposerBlock.make(kind: kind, position: position)
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
        captureUndo(in: documentID, coalesce: block.id)
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
        persist()
    }

    func deleteBlock(_ blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        let removed = blocks(for: documentID).first(where: { $0.id == blockID })
        let owned = removed.map { ownedDocuments(of: $0) } ?? []
        captureUndo(in: documentID, includePursuits: !owned.isEmpty)
        mutateBlocks(for: documentID) { blocks in
            blocks.removeAll { $0.id == blockID }
            if removed?.kind == .tabs {
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
        captureUndo(in: documentID, coalesce: blockID)
        mutateBlocks(for: documentID) { blocks in
            guard let index = blocks.firstIndex(where: { $0.id == blockID }),
                  blocks[index].kind == .tabs,
                  blocks[index].tabs.count < ComposerTabSet.maximumCount(longestSide: longestSide) else { return }
            let tab = ComposerTab(title: "Tab \(blocks[index].tabs.count + 1)")
            blocks[index].tabs.append(tab)
            blocks[index].selectedTabID = tab.id
        }
        persist()
    }

    func removeComposerTab(_ tabID: String, from blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        captureUndo(in: documentID, coalesce: blockID)
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
        persist()
    }

    func addTableColumn(to blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        captureUndo(in: documentID, coalesce: blockID)
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
        persist()
    }

    func removeLastTableColumn(from blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        captureUndo(in: documentID, coalesce: blockID)
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
        persist()
    }

    func addTableRow(to blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        captureUndo(in: documentID, coalesce: blockID)
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { block in
                guard block.kind == .table else { return }
                ComposerTable.ensure(&block)
                guard let next = ComposerTable.addingRow(to: block.tableRows, columnCount: block.tableColumns.count) else { return }
                block.tableRows = next
                rememberVisibleTableRows(&block)
            }
        }
        persist()
    }

    func removeLastTableRow(from blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        captureUndo(in: documentID, coalesce: blockID)
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { block in
                guard block.kind == .table else { return }
                ComposerTable.ensure(&block)
                guard let next = ComposerTable.removingLastRow(from: block.tableRows) else { return }
                block.tableRows = next
                rememberVisibleTableRows(&block)
            }
        }
        persist()
    }

    func startTableEntry(on blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        captureUndo(in: documentID, coalesce: blockID)
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
        persist()
    }

    func showTableEntry(_ entryID: String, on blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        captureUndo(in: documentID, coalesce: blockID)
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
        persist()
    }

    private func rememberVisibleTableRows(_ block: inout ComposerBlock) {
        guard let entryIndex = block.tableEntries.firstIndex(where: { $0.id == block.selectedTableEntryID }) else { return }
        block.tableEntries[entryIndex].rows = block.tableRows
    }

    func moveBlock(_ blockID: ComposerBlockID, direction: MoveDirection, in documentID: ComposerDocumentID?) {
        captureUndo(in: documentID)
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
        persist()
    }

    /// A different photo or video doesn't fit the old zoom and pan, so `resetsFraming` clears them; the frame shape stays.
    func setMedia(
        _ fileName: String,
        for blockID: ComposerBlockID,
        in documentID: ComposerDocumentID?,
        resetsFraming: Bool = false
    ) {
        captureUndo(in: documentID, coalesce: blockID)
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
        persist()
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

    func copyBlock(_ blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        guard let block = block(with: blockID, in: documentID) else { return }
        clipboard = ComposerClipboardItem(block: block, documents: ownedDocuments(of: block))
    }

    /// Places the clipboard on this page and clears it.
    @discardableResult
    func pasteClipboard(at position: BlockPosition, in documentID: ComposerDocumentID?) -> ComposerBlockID? {
        guard let clipboard else { return nil }
        let page = blocks(for: documentID)
        if clipboard.block.kind == .banner, page.contains(where: { $0.kind == .banner }) { return nil }
        if clipboard.block.kind == .tabs, page.contains(where: { $0.kind == .tabs }) { return nil }
        let (copy, documents) = Self.reidentified(block: clipboard.block, documents: clipboard.documents)
        var placed = copy
        placed.position = position
        if placed.kind != .banner, placed.kind != .tabs,
           let selected = page.first(where: { $0.kind == .tabs })?.selectedTabID {
            placed.tabID = selected
        }
        captureUndo(
            in: documentID,
            includePursuits: !documents.isEmpty
                || placed.kind == .pursuit
                || placed.kind == .node
                || placed.kind == .scrapbook
        )
        snapshot.pursuits.append(contentsOf: documents)
        mutateBlocks(for: documentID) { blocks in
            blocks.append(placed)
        }
        self.clipboard = nil
        persist()
        return placed.id
    }

    func mediaURL(for fileName: String) -> URL {
        location.mediaDirectory.appendingPathComponent(fileName)
    }

    enum MoveDirection {
        case up
        case down
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
                pursuits: includePursuits ? snapshot.pursuits : nil
            )
        )
        if stack.count > 40 {
            stack.removeFirst(stack.count - 40)
        }
        undoStacks[key] = stack
        undoCoalesce = blockID.map { ComposerUndoCoalesce(documentKey: key, blockID: $0, at: now) }
    }

    /// A board undo remembers the scrapbook structure. Pieces added on a journal page after that
    /// snapshot stay on the page instead of being replaced by the older empty copy.
    private func pursuitsKeepingPageEdits(from saved: [ComposerPursuit]) -> [ComposerPursuit] {
        let live = snapshot.pursuits
        return saved.map { savedPursuit in
            guard savedPursuit.role == .page,
                  let current = live.first(where: { $0.id == savedPursuit.id }) else {
                return savedPursuit
            }
            var kept = savedPursuit
            kept.blocks = current.blocks
            kept.background = current.background
            kept.layoutHeight = current.layoutHeight
            return kept
        }
    }
    private func syncPursuitTitlesFromMosaicBlocks() {
        for block in snapshot.mosaicBlocks where block.kind == .pursuit || block.kind == .node {
            guard let pursuitID = block.pursuitID,
                  let index = snapshot.pursuits.firstIndex(where: { $0.id == pursuitID }) else { continue }
            snapshot.pursuits[index].title = block.pursuitDisplayName
        }
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
        guard persistToDisk else { return }
        do {
            let url = location.snapshotURL
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
            onPersisted?()
        } catch {
            // Local-only persistence; surface in a later iteration.
        }
    }

    private static func loadSnapshot(at url: URL, fileManager: FileManager, decoder: JSONDecoder) -> ComposerSnapshot? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(ComposerSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    private struct ComposerUndoEntry {
        var blocks: [ComposerBlock]
        var pursuits: [ComposerPursuit]?
    }

    private struct ComposerUndoCoalesce {
        var documentKey: String
        var blockID: ComposerBlockID
        var at: Date
    }
}

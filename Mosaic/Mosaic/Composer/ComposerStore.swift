import Foundation
import Observation

@MainActor
@Observable
final class ComposerStore {
    private(set) var snapshot: ComposerSnapshot
    private var undoStacks: [String: [ComposerUndoEntry]] = [:]
    private var undoCoalesce: ComposerUndoCoalesce?
    private var isApplyingUndo = false

    private let fileManager: FileManager
    private let persistToDisk: Bool
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        seedSnapshot: ComposerSnapshot? = nil,
        persistToDisk: Bool? = nil
    ) {
        self.fileManager = fileManager
        self.persistToDisk = persistToDisk ?? !ProcessInfo.processInfo.arguments.contains("UITestSkipLaunchAnimation")
        if let seedSnapshot {
            snapshot = seedSnapshot
        } else if !self.persistToDisk {
            snapshot = .empty
        } else if let loaded = Self.loadSnapshot(fileManager: fileManager, decoder: decoder) {
            snapshot = loaded
        } else {
            snapshot = .empty
        }
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
                snapshot.pursuits = pursuits
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
    func blankPursuitPagesIfNeeded() {
        guard !snapshot.pursuitPagesBlanked else { return }
        for index in snapshot.pursuits.indices {
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
            snapshot.pursuits[pursuitIndex].title = block.text
        }
        persist()
    }

    func deleteBlock(_ blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        let removed = blocks(for: documentID).first(where: { $0.id == blockID })
        captureUndo(
            in: documentID,
            includePursuits: removed?.kind == .pursuit || removed?.kind == .node || removed?.kind == .scrapbook
        )
        mutateBlocks(for: documentID) { blocks in
            blocks.removeAll { $0.id == blockID }
            if removed?.kind == .tabs {
                for index in blocks.indices {
                    blocks[index].tabID = nil
                }
            }
        }
        if (removed?.kind == .pursuit || removed?.kind == .node), let pursuitID = removed?.pursuitID {
            snapshot.pursuits.removeAll { $0.id == pursuitID }
        }
        if removed?.kind == .scrapbook {
            let pageIDs = Set(removed?.scrapbookPageIDs ?? [])
            snapshot.pursuits.removeAll { pageIDs.contains($0.id) }
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

    func setMedia(_ fileName: String, for blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        captureUndo(in: documentID, coalesce: blockID)
        mutateBlocks(for: documentID) { blocks in
            updateOwnedBlock(blockID, in: &blocks) { block in
                block.mediaFileName = fileName
            }
        }
        persist()
    }

    func saveMediaData(_ data: Data, fileExtension: String = "jpg") throws -> String {
        let directory = Self.mediaDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return fileName
    }

    func saveMediaFile(from source: URL, removeSource: Bool = false) throws -> String {
        let directory = Self.mediaDirectory(fileManager: fileManager)
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
        if let jpegData = prepared.jpegData {
            return try saveMediaData(jpegData)
        }
        throw CocoaError(.fileWriteUnknown)
    }

    func mediaURL(for fileName: String) -> URL {
        Self.mediaDirectory(fileManager: fileManager).appendingPathComponent(fileName)
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

    private func syncPursuitTitlesFromMosaicBlocks() {
        for block in snapshot.mosaicBlocks where block.kind == .pursuit || block.kind == .node {
            guard let pursuitID = block.pursuitID,
                  let index = snapshot.pursuits.firstIndex(where: { $0.id == pursuitID }) else { continue }
            snapshot.pursuits[index].title = block.text
        }
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
            let url = Self.snapshotURL(fileManager: fileManager)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            // Local-only persistence; surface in a later iteration.
        }
    }

    private static func loadSnapshot(fileManager: FileManager, decoder: JSONDecoder) -> ComposerSnapshot? {
        let url = snapshotURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(ComposerSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    private static func snapshotURL(fileManager: FileManager) -> URL {
        documentsDirectory(fileManager: fileManager).appendingPathComponent("composer.json")
    }

    private static func mediaDirectory(fileManager: FileManager) -> URL {
        documentsDirectory(fileManager: fileManager).appendingPathComponent("Media", isDirectory: true)
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

    private static func documentsDirectory(fileManager: FileManager) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

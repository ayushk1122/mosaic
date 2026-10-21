import Foundation

/// A board both this device and another device changed before syncing. Per ADR 0003 the server's
/// version is shown and this device's version is kept here until the person keeps or discards it.
struct ComposerSyncConflict: Codable, Equatable, Identifiable, Sendable {
    /// The board's id.
    var id: UUID
    var title: String
    /// This device's version of the board, as it was when the other version arrived.
    var local: ComposerSyncDocument
    var savedAt: Date
    /// Set when the other device deleted the board: what "Keep my version" needs to put it back.
    var deleted: ComposerDeletedBoard?
}

struct ComposerDeletedBoard: Codable, Equatable, Sendable {
    /// The board's parent and the piece in it that opened the board.
    var parentID: UUID
    var reference: ComposerBlock?
    /// Boards inside the deleted one (pages, nodes), deleted with it.
    var inside: [ComposerSyncDocument]
}

struct ComposerPullResult: Equatable {
    var snapshot: ComposerSnapshot
    var state: ComposerSyncState
    var conflicts: [ComposerSyncConflict]
    /// Boards whose content was replaced; their undo history no longer applies.
    var replaced: Set<ComposerDocumentID?>
}

/// Brings boards changed on another device into this device's copy. Pure, so every case can be
/// tested without a server.
enum ComposerPull {
    /// Boards the server has a newer revision of than this device last saw, including new ones.
    static func changedIDs(remote: [UUID: Int64], state: ComposerSyncState) -> [UUID] {
        remote
            .filter { id, revision in revision > (state.revisions[id.uuidString.lowercased()] ?? 0) }
            .map(\.key)
            .sorted { $0.uuidString < $1.uuidString }
    }

    /// Boards this device synced before that are gone from the server: deleted on another device.
    static func removedIDs(remote: [UUID: Int64], state: ComposerSyncState) -> [UUID] {
        state.revisions.keys
            .compactMap(UUID.init(uuidString:))
            .filter { $0 != state.mosaicID && remote[$0] == nil }
            .sorted { $0.uuidString < $1.uuidString }
    }

    static func merge(
        rows: [ComposerRestoredDocument],
        removed: [UUID],
        snapshot: ComposerSnapshot,
        state: ComposerSyncState,
        mosaicID: UUID,
        now: Date
    ) -> ComposerPullResult {
        var snapshot = snapshot
        var state = state
        var conflicts: [ComposerSyncConflict] = []
        var replaced: Set<ComposerDocumentID?> = []
        let local = Dictionary(
            ComposerMediaCatalog.stamped(ComposerBoardSync.split(snapshot: snapshot, mosaicID: mosaicID), assets: state.mediaAssets)
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for row in rows {
            let key = row.id.uuidString.lowercased()
            if let mine = local[row.id], hasUnsyncedEdits(mine, state: state), !sameContent(mine, row.document) {
                conflicts.append(ComposerSyncConflict(
                    id: row.id,
                    title: mine.role == .mosaic ? "Your Mosaic" : (mine.title.isEmpty ? row.title : mine.title),
                    local: mine,
                    savedAt: now
                ))
            }
            snapshot = applying(row.document, to: snapshot, mosaicID: mosaicID)
            state.revisions[key] = row.revision
            if let hash = ComposerSyncState.contentHash(of: row.document) {
                state.pushedHashes[key] = hash
            }
            state.mediaAssets.merge(row.body.mediaAssets ?? [:]) { _, remote in remote }
            replaced.insert(row.id == mosaicID ? nil : localID(row.id, in: snapshot))
        }

        // Deleted on another device. Like any conflict, the server's version (deleted) is shown; a
        // board edited here, or with a board inside it edited here, is kept as a conflict copy.
        let removedSet = Set(removed)
        let edited = Set(local.values.filter { hasUnsyncedEdits($0, state: state) }.map(\.id))
        for id in removed {
            guard let mine = local[id] else { continue }
            let parentID = mine.parentID ?? mosaicID
            guard !removedSet.contains(parentID) else { continue }
            let inside = descendants(of: id, in: Array(local.values))
            guard edited.contains(id) || inside.contains(where: { edited.contains($0.id) }) else { continue }
            conflicts.append(ComposerSyncConflict(
                id: id,
                title: mine.title,
                local: mine,
                savedAt: now,
                deleted: ComposerDeletedBoard(
                    parentID: parentID,
                    reference: local[parentID].flatMap { referencingBlock(in: $0.body.blocks, target: id) },
                    inside: inside
                )
            ))
        }
        for id in removed {
            let key = id.uuidString.lowercased()
            state.revisions[key] = nil
            state.pushedHashes[key] = nil
            replaced.insert(localID(id, in: snapshot))
            snapshot.pursuits.removeAll { ComposerBoardSync.uuid($0.id) == id }
        }
        return ComposerPullResult(snapshot: snapshot, state: state, conflicts: conflicts, replaced: replaced)
    }

    /// Puts one board's saved form into the snapshot, replacing this device's copy of it. Used for
    /// a board from the server and for "Keep my version" with a conflict copy.
    static func applying(_ document: ComposerSyncDocument, to snapshot: ComposerSnapshot, mosaicID: UUID) -> ComposerSnapshot {
        var snapshot = snapshot
        let blocks = ComposerBoardSync.normalizedReferences(document.body.blocks)
        if document.id == mosaicID || document.role == .mosaic {
            snapshot.mosaicTitle = document.title
            snapshot.mosaicBlocks = blocks
            snapshot.mosaicLayoutHeight = document.body.layoutHeight
            snapshot.mosaicBackground = document.body.background
            snapshot.mosaicTitlePlaced = document.body.mosaicTitlePlaced ?? snapshot.mosaicTitlePlaced
            snapshot.pursuitPagesBlanked = document.body.pursuitPagesBlanked ?? snapshot.pursuitPagesBlanked
            // Saving a cutout on two devices isn't a conflict: both lists are kept.
            snapshot.stickerLibrary = mergedLibrary(document.body.stickerLibrary ?? [], snapshot.stickerLibrary)
            return snapshot
        }
        let existing = snapshot.pursuits.firstIndex { ComposerBoardSync.uuid($0.id) == document.id }
        let board = ComposerPursuit(
            id: existing.map { snapshot.pursuits[$0].id } ?? ComposerDocumentID(rawValue: document.id.uuidString),
            title: document.title,
            blocks: blocks,
            role: ComposerDocumentRole(rawValue: document.role.rawValue) ?? .pursuit,
            layoutHeight: document.body.layoutHeight,
            background: document.body.background
        )
        if let index = existing {
            snapshot.pursuits[index] = board
        } else {
            snapshot.pursuits.append(board)
        }
        return snapshot
    }

    /// "Keep my version" for a board deleted on another device: the board, the boards inside it,
    /// and the piece that opens it all go back.
    static func restoring(_ conflict: ComposerSyncConflict, to snapshot: ComposerSnapshot, mosaicID: UUID) -> ComposerSnapshot {
        guard let deleted = conflict.deleted else { return applying(conflict.local, to: snapshot, mosaicID: mosaicID) }
        var snapshot = ([conflict.local] + deleted.inside).reduce(snapshot) { applying($1, to: $0, mosaicID: mosaicID) }
        guard let reference = deleted.reference.map({ ComposerBoardSync.normalizedReferences([$0])[0] }) else { return snapshot }
        func reattach(_ blocks: inout [ComposerBlock]) {
            guard !blocks.contains(where: { ComposerBoardSync.references($0, target: conflict.id) }) else { return }
            if let index = blocks.firstIndex(where: { $0.id == reference.id }), reference.kind == .scrapbook {
                // A deleted page: the scrapbook is still there, so only the page goes back in.
                let missing = reference.scrapbookPageIDs.filter { !blocks[index].scrapbookPageIDs.contains($0) }
                blocks[index].scrapbookPageIDs.append(contentsOf: missing)
            } else {
                blocks.append(reference)
            }
        }
        if deleted.parentID == mosaicID {
            reattach(&snapshot.mosaicBlocks)
        } else if let index = snapshot.pursuits.firstIndex(where: { ComposerBoardSync.uuid($0.id) == deleted.parentID }) {
            reattach(&snapshot.pursuits[index].blocks)
        }
        return snapshot
    }

    /// The innermost piece that opens the board, looking inside groups.
    static func referencingBlock(in blocks: [ComposerBlock], target: UUID) -> ComposerBlock? {
        for block in blocks {
            if let member = referencingBlock(in: block.groupMembers, target: target) { return member }
            if block.groupMembers.isEmpty, ComposerBoardSync.references(block, target: target) { return block }
        }
        return nil
    }

    /// Every board below this one, through any depth of pages and nodes.
    static func descendants(of id: UUID, in documents: [ComposerSyncDocument]) -> [ComposerSyncDocument] {
        var found: [ComposerSyncDocument] = []
        var parents: Set<UUID> = [id]
        while true {
            let next = documents.filter { document in
                document.parentID.map(parents.contains) == true && !found.contains { $0.id == document.id }
            }
            guard !next.isEmpty else { return found }
            found += next
            parents = Set(next.map(\.id))
        }
    }

    static func localID(_ id: UUID, in snapshot: ComposerSnapshot) -> ComposerDocumentID {
        snapshot.pursuits.first { ComposerBoardSync.uuid($0.id) == id }?.id ?? ComposerDocumentID(rawValue: id.uuidString)
    }

    /// Edited here since this device last saved the board (or never saved it).
    static func hasUnsyncedEdits(_ document: ComposerSyncDocument, state: ComposerSyncState) -> Bool {
        guard let pushed = state.pushedHashes[document.id.uuidString.lowercased()] else { return true }
        return ComposerSyncState.contentHash(of: document) != pushed
    }

    /// The same board content, ignoring media links and saved stickers (both merge on their own).
    static func sameContent(_ first: ComposerSyncDocument, _ second: ComposerSyncDocument) -> Bool {
        first.title == second.title
            && first.body.blocks == ComposerBoardSync.normalizedReferences(second.body.blocks)
            && first.body.layoutHeight == second.body.layoutHeight
            && first.body.background == second.body.background
    }

    /// Newest first: the incoming list, then this device's stickers it doesn't have.
    static func mergedLibrary(_ incoming: [ComposerSavedSticker], _ mine: [ComposerSavedSticker]) -> [ComposerSavedSticker] {
        var seen = Set<String>()
        return Array((incoming + mine).filter { seen.insert($0.fileName).inserted }.prefix(ComposerSavedSticker.limit))
    }
}

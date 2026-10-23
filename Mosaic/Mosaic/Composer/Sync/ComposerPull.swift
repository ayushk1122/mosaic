import Foundation

struct ComposerPullResult: Equatable {
    var snapshot: ComposerSnapshot
    var state: ComposerSyncState
    /// This device's versions of boards it had changed that a newer edit or a deletion replaced.
    /// Nothing shows them; they're kept on the phone for a while in case they're needed.
    var replacedLocal: [ComposerSyncDocument]
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

    /// Whole boards, newest edit wins (ADR 0004): a board changed only on the server is replaced; a
    /// board changed on both keeps whichever was edited last; a board deleted elsewhere is removed.
    static func merge(
        rows: [ComposerRestoredDocument],
        removed: [UUID],
        snapshot: ComposerSnapshot,
        state: ComposerSyncState,
        editTimes: ComposerEditTimes,
        mosaicID: UUID,
        now: Date
    ) -> ComposerPullResult {
        var snapshot = snapshot
        var state = state
        var replacedLocal: [ComposerSyncDocument] = []
        var replaced: Set<ComposerDocumentID?> = []
        let local = Dictionary(
            ComposerMediaCatalog.stamped(
                ComposerBoardSync.split(snapshot: snapshot, mosaicID: mosaicID),
                assets: state.mediaAssets,
                previews: state.mediaPreviews
            )
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for row in rows {
            let key = row.id.uuidString.lowercased()
            state.mediaAssets.merge(row.body.mediaAssets ?? [:]) { _, remote in remote }
            state.mediaPreviews.merge(row.body.mediaPreviews ?? [:]) { _, remote in remote }
            if let mine = local[row.id], hasUnsyncedEdits(mine, state: state), !sameContent(mine, row.document) {
                if editTimes.localIsNewer(mine, than: row, now: now) {
                    // Edited here after the server saved: this version stays, and the next push
                    // replaces the server's, now that this device knows its revision.
                    state.revisions[key] = row.revision
                    continue
                }
                replacedLocal.append(mine)
            }
            snapshot = applying(row.document, to: snapshot, mosaicID: mosaicID)
            state.revisions[key] = row.revision
            if let hash = ComposerSyncState.contentHash(of: row.document) {
                state.pushedHashes[key] = hash
            }
            replaced.insert(row.id == mosaicID ? nil : localID(row.id, in: snapshot))
        }

        // Deleted on another device: deleting wins. Boards edited here, the deleted one or ones
        // inside it, are kept only as replaced copies.
        var edited = Set(local.values.filter { hasUnsyncedEdits($0, state: state) }.map(\.id))
        for id in removed {
            guard let mine = local[id] else { continue }
            let inside = descendants(of: id, in: Array(local.values))
            // A page and the Pursuit it's in can both be in the list; each copy is kept once.
            for document in [mine] + inside where edited.remove(document.id) != nil {
                replacedLocal.append(document)
            }
            let key = id.uuidString.lowercased()
            state.revisions[key] = nil
            state.pushedHashes[key] = nil
            replaced.insert(localID(id, in: snapshot))
            snapshot.pursuits.removeAll { ComposerBoardSync.uuid($0.id) == id }
        }
        return ComposerPullResult(snapshot: snapshot, state: state, replacedLocal: replacedLocal, replaced: replaced)
    }

    /// Puts one board's saved form into the snapshot, replacing this device's copy of it.
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

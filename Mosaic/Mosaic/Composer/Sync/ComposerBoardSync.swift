import Foundation

/// One board as it is stored in `documents`.
struct ComposerSyncDocument: Equatable, Sendable {
    var id: UUID
    var parentID: UUID?
    var role: ComposerSyncRole
    var title: String
    var visibility: String
    var body: ComposerBoardBody
}

enum ComposerSyncRole: String, Codable, Equatable, Sendable {
    case mosaic
    case pursuit
    case node
    case page
}

/// The JSON stored in `documents.body`.
struct ComposerBoardBody: Codable, Equatable, Sendable {
    var blocks: [ComposerBlock]
    var layoutHeight: Double?
    var background: ComposerBoardBackground?
    var mosaicTitlePlaced: Bool?
    var pursuitPagesBlanked: Bool?
    /// Local file name to the private Storage asset. Blocks keep their file names.
    var mediaAssets: [String: String]?
    /// Only on the Mosaic board. The server drops it from visitors' copy (`viewer_board_body`).
    var stickerLibrary: [ComposerSavedSticker]?

    init(
        blocks: [ComposerBlock],
        layoutHeight: Double?,
        background: ComposerBoardBackground?,
        mosaicTitlePlaced: Bool?,
        pursuitPagesBlanked: Bool?,
        mediaAssets: [String: String]? = nil,
        stickerLibrary: [ComposerSavedSticker]? = nil
    ) {
        self.stickerLibrary = stickerLibrary
        self.blocks = blocks
        self.layoutHeight = layoutHeight
        self.background = background
        self.mosaicTitlePlaced = mosaicTitlePlaced
        self.pursuitPagesBlanked = pursuitPagesBlanked
        self.mediaAssets = mediaAssets
    }

    enum CodingKeys: String, CodingKey {
        case blocks, layoutHeight, background, mosaicTitlePlaced, pursuitPagesBlanked, mediaAssets, stickerLibrary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blocks = try container.decode([ComposerBlock].self, forKey: .blocks)
        layoutHeight = try container.decodeIfPresent(Double.self, forKey: .layoutHeight)
        background = try container.decodeIfPresent(ComposerBoardBackground.self, forKey: .background)
        mosaicTitlePlaced = try container.decodeIfPresent(Bool.self, forKey: .mosaicTitlePlaced)
        pursuitPagesBlanked = try container.decodeIfPresent(Bool.self, forKey: .pursuitPagesBlanked)
        mediaAssets = try container.decodeIfPresent([String: String].self, forKey: .mediaAssets)
        let library = ComposerSavedSticker.lenientList(from: container, forKey: .stickerLibrary)
        stickerLibrary = container.contains(.stickerLibrary) ? library : nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(blocks, forKey: .blocks)
        try container.encodeIfPresent(layoutHeight, forKey: .layoutHeight)
        try container.encodeIfPresent(background, forKey: .background)
        try container.encodeIfPresent(mosaicTitlePlaced, forKey: .mosaicTitlePlaced)
        try container.encodeIfPresent(pursuitPagesBlanked, forKey: .pursuitPagesBlanked)
        try container.encodeIfPresent(mediaAssets, forKey: .mediaAssets)
        try container.encodeIfPresent(stickerLibrary, forKey: .stickerLibrary)
    }
}

/// A push of one board. Revision `0` means the server has not seen this id yet.
struct ComposerDocumentPush: Equatable, Sendable {
    var document: ComposerSyncDocument
    var expectedRevision: Int64
}

enum ComposerBoardSync {
    static let privateVisibility = "private"

    /// Document ids still reachable from the Mosaic board through Pursuit, node, scrapbook, and group links.
    static func referencedIDs(in snapshot: ComposerSnapshot) -> Set<String> {
        var seen = Set<String>()
        func walkBlocks(_ blocks: [ComposerBlock]) {
            for block in blocks {
                if block.kind == .scrapbook {
                    for pageID in block.scrapbookPageIDs {
                        guard seen.insert(pageID.rawValue).inserted,
                              let page = snapshot.pursuits.first(where: { $0.id == pageID })
                        else { continue }
                        walkBlocks(page.blocks)
                    }
                }
                if (block.kind == .pursuit || block.kind == .node), let documentID = block.pursuitID {
                    guard seen.insert(documentID.rawValue).inserted,
                          let document = snapshot.pursuits.first(where: { $0.id == documentID })
                    else { continue }
                    walkBlocks(document.blocks)
                }
                // A piece from a newer version may own boards this version can't name; any board
                // it mentions is kept.
                if block.kind == .unsupported {
                    // Ids are matched without regard to case: the server stores them lowercase.
                    let mentioned = Set(block.preservedStrings.map { $0.lowercased() })
                    for document in snapshot.pursuits
                    where mentioned.contains(document.id.rawValue.lowercased()) && seen.insert(document.id.rawValue).inserted {
                        walkBlocks(document.blocks)
                    }
                }
                walkBlocks(block.groupMembers)
            }
        }
        walkBlocks(snapshot.mosaicBlocks)
        return seen
    }

    /// Boards a widget points to that are not in the snapshot, with the role the widget implies.
    static func missingReferences(in snapshot: ComposerSnapshot) -> [(ComposerDocumentID, ComposerDocumentRole)] {
        let present = Set(snapshot.pursuits.map(\.id))
        var missing: [(ComposerDocumentID, ComposerDocumentRole)] = []
        var seen = Set<ComposerDocumentID>()
        func note(_ id: ComposerDocumentID, _ role: ComposerDocumentRole) {
            guard !present.contains(id), seen.insert(id).inserted else { return }
            missing.append((id, role))
        }
        func walk(_ blocks: [ComposerBlock]) {
            for block in blocks {
                if block.kind == .scrapbook {
                    block.scrapbookPageIDs.forEach { note($0, .page) }
                }
                if let id = block.pursuitID, block.kind == .pursuit || block.kind == .node {
                    note(id, block.kind == .node ? .node : .pursuit)
                }
                walk(block.groupMembers)
            }
        }
        walk(snapshot.mosaicBlocks)
        snapshot.pursuits.forEach { walk($0.blocks) }
        return missing
    }

    /// Drops Pursuit, node, and page rows that no board still points to. Returns the removed ids.
    /// `protecting` keeps cut-but-not-pasted documents alive until the clipboard moves on.
    @discardableResult
    static func pruneUnreferenced(
        _ snapshot: inout ComposerSnapshot,
        protecting: Set<String> = []
    ) -> [ComposerDocumentID] {
        let keep = referencedIDs(in: snapshot).union(protecting)
        let removed = snapshot.pursuits.filter { !keep.contains($0.id.rawValue) }.map(\.id)
        guard !removed.isEmpty else { return [] }
        let removedKeys = Set(removed.map(\.rawValue))
        snapshot.pursuits.removeAll { removedKeys.contains($0.id.rawValue) }
        return removed
    }

    /// Remote rows the phone no longer owns. The Mosaic id is never listed.
    /// `protecting` keeps cut-but-not-pasted documents from being deleted mid-move.
    static func deadIDs(
        live: [UUID],
        remote: [UUID],
        mosaicID: UUID,
        protecting: Set<UUID> = []
    ) -> [UUID] {
        let liveSet = Set(live).union(protecting)
        return remote.filter { $0 != mosaicID && !liveSet.contains($0) }
    }

    /// Splits a local snapshot into server rows.
    /// Top-level Pursuits have no parent. Nodes and scrapbook pages parent to the board that contains them.
    static func split(snapshot: ComposerSnapshot, mosaicID: UUID) -> [ComposerSyncDocument] {
        var documents: [ComposerSyncDocument] = [
            ComposerSyncDocument(
                id: mosaicID,
                parentID: nil,
                role: .mosaic,
                title: snapshot.mosaicTitle,
                visibility: privateVisibility,
                body: ComposerBoardBody(
                    blocks: snapshot.mosaicBlocks,
                    layoutHeight: snapshot.mosaicLayoutHeight,
                    background: snapshot.mosaicBackground,
                    mosaicTitlePlaced: snapshot.mosaicTitlePlaced,
                    pursuitPagesBlanked: snapshot.pursuitPagesBlanked,
                    stickerLibrary: snapshot.stickerLibrary.isEmpty ? nil : snapshot.stickerLibrary
                )
            )
        ]

        var pending = snapshot.pursuits
        let attemptLimit = snapshot.pursuits.count + 1
        var guardCount = 0
        while !pending.isEmpty, guardCount < attemptLimit {
            guardCount += 1
            var remainder: [ComposerPursuit] = []
            var placed = false
            for pursuit in pending {
                guard let id = uuid(pursuit.id) else { continue }
                let known = Set(documents.map(\.id))
                switch container(of: pursuit, in: snapshot) {
                case .board(let parent) where !known.contains(parent):
                    remainder.append(pursuit)
                    continue
                case .board, .mosaic, .none:
                    break
                }
                let parent = placedParent(of: pursuit, in: snapshot)
                documents.append(
                    ComposerSyncDocument(
                        id: id,
                        parentID: parent,
                        role: ComposerSyncRole(rawValue: pursuit.role.rawValue) ?? .pursuit,
                        title: pursuit.title,
                        visibility: privateVisibility,
                        body: ComposerBoardBody(
                            blocks: pursuit.blocks,
                            layoutHeight: pursuit.layoutHeight,
                            background: pursuit.background,
                            mosaicTitlePlaced: nil,
                            pursuitPagesBlanked: nil
                        )
                    )
                )
                placed = true
            }
            if !placed {
                for pursuit in remainder {
                    guard let id = uuid(pursuit.id) else { continue }
                    documents.append(
                        ComposerSyncDocument(
                            id: id,
                            parentID: nil,
                            role: ComposerSyncRole(rawValue: pursuit.role.rawValue) ?? .pursuit,
                            title: pursuit.title,
                            visibility: privateVisibility,
                            body: ComposerBoardBody(
                                blocks: pursuit.blocks,
                                layoutHeight: pursuit.layoutHeight,
                                background: pursuit.background,
                                mosaicTitlePlaced: nil,
                                pursuitPagesBlanked: nil
                            )
                        )
                    )
                }
                break
            }
            pending = remainder
        }

        return documents
    }

    static func assemble(mosaicID: UUID, documents: [ComposerSyncDocument]) -> ComposerSnapshot? {
        guard let mosaic = documents.first(where: { $0.id == mosaicID && $0.role == .mosaic }) else {
            return nil
        }
        let pursuits = documents
            .filter { $0.id != mosaicID }
            .map { document in
                ComposerPursuit(
                    id: ComposerDocumentID(rawValue: document.id.uuidString),
                    title: document.title,
                    blocks: normalizedReferences(document.body.blocks),
                    role: ComposerDocumentRole(rawValue: document.role.rawValue) ?? .pursuit,
                    layoutHeight: document.body.layoutHeight,
                    background: document.body.background
                )
            }
        return ComposerSnapshot(
            mosaicTitle: mosaic.title,
            mosaicBlocks: normalizedReferences(mosaic.body.blocks),
            pursuits: pursuits,
            mosaicTitlePlaced: mosaic.body.mosaicTitlePlaced ?? false,
            pursuitPagesBlanked: mosaic.body.pursuitPagesBlanked ?? false,
            mosaicLayoutHeight: mosaic.body.layoutHeight,
            mosaicBackground: mosaic.body.background,
            stickerLibrary: mosaic.body.stickerLibrary ?? []
        )
    }

    /// PostgreSQL UUIDs are lowercase; local document identities use UUID.uuidString.
    private static func normalizedReferences(_ blocks: [ComposerBlock]) -> [ComposerBlock] {
        blocks.map { block in
            var block = block
            if let id = block.pursuitID, let uuid = UUID(uuidString: id.rawValue) {
                block.pursuitID = ComposerDocumentID(rawValue: uuid.uuidString)
            }
            block.scrapbookPageIDs = block.scrapbookPageIDs.map { id in
                UUID(uuidString: id.rawValue).map { ComposerDocumentID(rawValue: $0.uuidString) } ?? id
            }
            block.groupMembers = normalizedReferences(block.groupMembers)
            return block
        }
    }

    static func uuid(_ id: ComposerDocumentID) -> UUID? {
        UUID(uuidString: id.rawValue)
    }

    private enum BoardContainer {
        case mosaic
        case board(UUID)
        case none
    }

    /// A top-level Pursuit is referenced from the Mosaic and has no parent row.
    private static func placedParent(of pursuit: ComposerPursuit, in snapshot: ComposerSnapshot) -> UUID? {
        switch container(of: pursuit, in: snapshot) {
        case .board(let id):
            return id
        case .mosaic, .none:
            return nil
        }
    }

    private static func container(of pursuit: ComposerPursuit, in snapshot: ComposerSnapshot) -> BoardContainer {
        guard let target = uuid(pursuit.id) else { return .none }
        if containsReference(to: target, in: snapshot.mosaicBlocks) {
            return .mosaic
        }
        for container in snapshot.pursuits {
            guard let containerID = uuid(container.id), containerID != target else { continue }
            if containsReference(to: target, in: container.blocks) {
                return .board(containerID)
            }
        }
        return .none
    }

    private static func containsReference(to target: UUID, in blocks: [ComposerBlock]) -> Bool {
        blocks.contains { block in
            references(block, target: target)
        }
    }

    private static func references(_ block: ComposerBlock, target: UUID) -> Bool {
        if (block.kind == .pursuit || block.kind == .node),
           let pursuitID = block.pursuitID,
           uuid(pursuitID) == target {
            return true
        }
        if block.kind == .scrapbook,
           block.scrapbookPageIDs.contains(where: { uuid($0) == target }) {
            return true
        }
        // A piece from a newer version may own boards; one it mentions is placed under it.
        if block.kind == .unsupported,
           block.preservedStrings.contains(where: { UUID(uuidString: $0) == target }) {
            return true
        }
        return block.groupMembers.contains { references($0, target: target) }
    }
}

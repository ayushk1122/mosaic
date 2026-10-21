import Foundation

struct ComposerMediaReference: Equatable, Sendable {
    var fileName: String
    var documentID: UUID
}

enum ComposerMediaScale {
    static let displayLongEdge = 2560
    static let thumbLongEdge = 480
    static let videoLimitMilliseconds = 10_000

    /// Shrinks so the longer side is `longEdge`. A smaller image stays at its own size.
    static func fitted(width: Int, height: Int, longEdge: Int) -> (width: Int, height: Int) {
        let long = max(width, height)
        guard width > 0, height > 0, long > longEdge else {
            return (max(width, 0), max(height, 0))
        }
        let scale = Double(longEdge) / Double(long)
        return (
            max(1, Int((Double(width) * scale).rounded())),
            max(1, Int((Double(height) * scale).rounded()))
        )
    }

    /// Milliseconds for a video already within the cap. A longer video has to be trimmed before upload.
    static func videoMilliseconds(seconds: Double) -> Int? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let milliseconds = Int((seconds * 1000).rounded())
        guard milliseconds >= 1, milliseconds <= videoLimitMilliseconds else { return nil }
        return milliseconds
    }
}

enum ComposerMediaCatalog {
    /// One row per local file. The same file on two boards is uploaded once, for the first board.
    static func references(snapshot: ComposerSnapshot, mosaicID: UUID) -> [ComposerMediaReference] {
        var seen: Set<String> = []
        var found: [ComposerMediaReference] = []
        func add(_ name: String?, documentID: UUID) {
            guard let name, !name.isEmpty, seen.insert(name).inserted else { return }
            found.append(ComposerMediaReference(fileName: name, documentID: documentID))
        }
        func walk(_ blocks: [ComposerBlock], documentID: UUID) {
            for block in blocks {
                add(block.mediaFileName, documentID: documentID)
                add(block.pursuitImageFileName, documentID: documentID)
                for item in block.carouselItems {
                    add(item.fileName, documentID: documentID)
                }
                for entry in block.calendarEntries {
                    for item in entry.media {
                        add(item.fileName, documentID: documentID)
                    }
                }
                for name in possibleFileNames(in: block) {
                    add(name, documentID: documentID)
                }
                walk(block.groupMembers, documentID: documentID)
            }
        }
        add(snapshot.mosaicBackground?.mediaFileName, documentID: mosaicID)
        walk(snapshot.mosaicBlocks, documentID: mosaicID)
        // Saved stickers upload with the Mosaic board so every device can restore them.
        for sticker in snapshot.stickerLibrary {
            add(sticker.fileName, documentID: mosaicID)
        }
        for pursuit in snapshot.pursuits {
            guard let documentID = ComposerBoardSync.uuid(pursuit.id) else { continue }
            add(pursuit.background?.mediaFileName, documentID: documentID)
            walk(pursuit.blocks, documentID: documentID)
        }
        return found
    }

    /// Copies asset ids, and the previews visitors see while files download, onto each board that
    /// uses those file names.
    static func stamped(
        _ documents: [ComposerSyncDocument],
        assets: [String: String],
        previews: [String: String] = [:]
    ) -> [ComposerSyncDocument] {
        documents.map { document in
            var copy = document
            let names = fileNames(in: document.body)
            let used = assets.filter { names.contains($0.key) }
            copy.body.mediaAssets = used.isEmpty ? nil : used
            // Only files that already have a cloud copy: a preview is a stand-in while one downloads.
            let shown = previews.filter { !$0.value.isEmpty && used[$0.key] != nil }
            copy.body.mediaPreviews = shown.isEmpty ? nil : shown
            return copy
        }
    }

    static func objectPath(ownerID: UUID, assetID: UUID, name: String) -> String {
        "\(ownerID.uuidString.lowercased())/\(assetID.uuidString.lowercased())/\(name)"
    }

    /// Text in a newer piece that could be one of its media files, so its cloud copy stays linked.
    /// Names that aren't files on this phone are skipped by uploads.
    private static func possibleFileNames(in block: ComposerBlock) -> [String] {
        guard block.kind == .unsupported else { return [] }
        return block.preservedStrings.filter { name in
            name.count < 200 && name.contains(".") && !name.contains(" ") && !name.contains("/")
        }.sorted()
    }

    private static func fileNames(in body: ComposerBoardBody) -> Set<String> {
        var names: Set<String> = []
        func walk(_ blocks: [ComposerBlock]) {
            for block in blocks {
                if let name = block.mediaFileName, !name.isEmpty { names.insert(name) }
                if let name = block.pursuitImageFileName, !name.isEmpty { names.insert(name) }
                for item in block.carouselItems where !item.fileName.isEmpty {
                    names.insert(item.fileName)
                }
                for entry in block.calendarEntries {
                    for item in entry.media where !item.fileName.isEmpty {
                        names.insert(item.fileName)
                    }
                }
                names.formUnion(possibleFileNames(in: block))
                walk(block.groupMembers)
            }
        }
        if let name = body.background?.mediaFileName, !name.isEmpty {
            names.insert(name)
        }
        walk(body.blocks)
        names.formUnion((body.stickerLibrary ?? []).map(\.fileName))
        return names
    }
}

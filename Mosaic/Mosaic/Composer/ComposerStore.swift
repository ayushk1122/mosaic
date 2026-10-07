import Foundation
import Observation

@MainActor
@Observable
final class ComposerStore {
    private(set) var snapshot: ComposerSnapshot

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

    func blocks(for documentID: ComposerDocumentID?) -> [ComposerBlock] {
        if let documentID {
            return snapshot.pursuits.first(where: { $0.id == documentID })?.blocks ?? []
        }
        return snapshot.mosaicBlocks
    }

    func block(with id: ComposerBlockID, in documentID: ComposerDocumentID?) -> ComposerBlock? {
        blocks(for: documentID).first(where: { $0.id == id })
    }

    func title(for documentID: ComposerDocumentID?) -> String {
        if let documentID {
            return snapshot.pursuits.first(where: { $0.id == documentID })?.title ?? "Pursuit"
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
        let block = ComposerBlock.make(kind: kind, position: position)
        if kind == .pursuit, let pursuitID = block.pursuitID {
            let pursuit = ComposerPursuit(id: pursuitID, title: block.text, blocks: [])
            snapshot.pursuits.append(pursuit)
        }
        mutateBlocks(for: documentID) { blocks in
            blocks.append(block)
        }
        persist()
        return block.id
    }

    func updateBlock(_ block: ComposerBlock, in documentID: ComposerDocumentID?) {
        mutateBlocks(for: documentID) { blocks in
            guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return }
            blocks[index] = block
            if block.kind == .pursuit, let pursuitID = block.pursuitID {
                if let pursuitIndex = snapshot.pursuits.firstIndex(where: { $0.id == pursuitID }) {
                    snapshot.pursuits[pursuitIndex].title = block.text
                }
            }
        }
        persist()
    }

    func deleteBlock(_ blockID: ComposerBlockID, in documentID: ComposerDocumentID?) {
        mutateBlocks(for: documentID) { blocks in
            blocks.removeAll { $0.id == blockID }
        }
        persist()
    }

    func moveBlock(_ blockID: ComposerBlockID, direction: MoveDirection, in documentID: ComposerDocumentID?) {
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
        mutateBlocks(for: documentID) { blocks in
            guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
            blocks[index].mediaFileName = fileName
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

    func saveMediaFile(from source: URL) throws -> String {
        let directory = Self.mediaDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let destination = directory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        return fileName
    }

    func mediaURL(for fileName: String) -> URL {
        Self.mediaDirectory(fileManager: fileManager).appendingPathComponent(fileName)
    }

    enum MoveDirection {
        case up
        case down
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

    private static func documentsDirectory(fileManager: FileManager) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

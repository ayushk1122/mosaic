import Foundation

struct ComposerDocumentID: Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }
}

struct ComposerBlockID: Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }
}

enum BlockKind: String, Codable, CaseIterable, Sendable {
    case text
    case heading
    case media
    case link
    case pursuit
}

enum BlockMenuOption: String, CaseIterable, Identifiable {
    case text
    case heading
    case media
    case link
    case pursuit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text"
        case .heading: "Heading"
        case .media: "Media"
        case .link: "Link"
        case .pursuit: "Pursuit"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "textformat"
        case .heading: "textformat.size.larger"
        case .media: "photo"
        case .link: "link"
        case .pursuit: "square.grid.2x2"
        }
    }

    var placementLabel: String {
        switch self {
        case .text: "T"
        case .heading: "H"
        case .media: "▣"
        case .link: "🔗"
        case .pursuit: "P"
        }
    }

    var blockKind: BlockKind {
        switch self {
        case .text: .text
        case .heading: .heading
        case .media: .media
        case .link: .link
        case .pursuit: .pursuit
        }
    }

    /// Lowercased tokens for add-menu search (extend as options grow).
    var searchTokens: String {
        switch self {
        case .text: "text paragraph write"
        case .heading: "heading title headline"
        case .media: "media photo image picture"
        case .link: "link url web"
        case .pursuit: "pursuit project goal"
        }
    }

    static func menuOptions(matching query: String) -> [BlockMenuOption] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ordered = Array(allCases.reversed())
        guard !trimmed.isEmpty else { return ordered }
        return ordered.filter { $0.searchTokens.contains(trimmed) }
    }
}

enum TextBlockSize: String, Codable, CaseIterable, Sendable {
    case body
    case large
    case title

    var label: String {
        switch self {
        case .body: "Body"
        case .large: "Large"
        case .title: "Title"
        }
    }
}

enum TextBlockColor: String, Codable, CaseIterable, Sendable {
    case canvas
    case ink
    case charcoal
    case forest
    case clay

    var label: String {
        switch self {
        case .canvas: "White"
        case .ink: "Black"
        case .charcoal: "Charcoal"
        case .forest: "Forest"
        case .clay: "Clay"
        }
    }
}

enum TextAlignmentOption: String, Codable, CaseIterable, Sendable {
    case leading
    case center

    var label: String {
        switch self {
        case .leading: "Left"
        case .center: "Center"
        }
    }
}

struct TextBlockStyle: Codable, Equatable, Sendable {
    var size: TextBlockSize
    var color: TextBlockColor
    var alignment: TextAlignmentOption
    /// Pinch-to-resize multiplier persisted with the block.
    var scale: Double

    init(
        size: TextBlockSize,
        color: TextBlockColor,
        alignment: TextAlignmentOption,
        scale: Double = 1
    ) {
        self.size = size
        self.color = color
        self.alignment = alignment
        self.scale = scale
    }

    enum CodingKeys: String, CodingKey {
        case size, color, alignment, scale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decode(TextBlockSize.self, forKey: .size)
        color = try container.decode(TextBlockColor.self, forKey: .color)
        alignment = try container.decode(TextAlignmentOption.self, forKey: .alignment)
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
    }

    static let bodyDefault = TextBlockStyle(size: .body, color: .canvas, alignment: .leading)
    static let headingDefault = TextBlockStyle(size: .title, color: .canvas, alignment: .leading)
}

struct BlockPosition: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    static func defaultPosition(index: Int) -> BlockPosition {
        BlockPosition(x: 0.08, y: 0.06 + Double(index) * 0.12)
    }
}

struct ComposerBlock: Identifiable, Codable, Equatable, Sendable {
    let id: ComposerBlockID
    var kind: BlockKind
    var text: String
    var style: TextBlockStyle
    var position: BlockPosition
    var mediaFileName: String?
    var linkURL: String?
    var pursuitID: ComposerDocumentID?

    enum CodingKeys: String, CodingKey {
        case id, kind, text, style, position, mediaFileName, linkURL, pursuitID
    }

    init(
        id: ComposerBlockID,
        kind: BlockKind,
        text: String,
        style: TextBlockStyle,
        position: BlockPosition,
        mediaFileName: String? = nil,
        linkURL: String? = nil,
        pursuitID: ComposerDocumentID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.style = style
        self.position = position
        self.mediaFileName = mediaFileName
        self.linkURL = linkURL
        self.pursuitID = pursuitID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ComposerBlockID.self, forKey: .id)
        kind = try container.decode(BlockKind.self, forKey: .kind)
        text = try container.decode(String.self, forKey: .text)
        style = try container.decode(TextBlockStyle.self, forKey: .style)
        position = try container.decodeIfPresent(BlockPosition.self, forKey: .position)
            ?? BlockPosition(x: 0.08, y: 0.08)
        mediaFileName = try container.decodeIfPresent(String.self, forKey: .mediaFileName)
        linkURL = try container.decodeIfPresent(String.self, forKey: .linkURL)
        pursuitID = try container.decodeIfPresent(ComposerDocumentID.self, forKey: .pursuitID)
    }

    static func make(kind: BlockKind, position: BlockPosition) -> ComposerBlock {
        switch kind {
        case .text:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .text,
                text: "",
                style: .bodyDefault,
                position: position
            )
        case .heading:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .heading,
                text: "",
                style: .headingDefault,
                position: position
            )
        case .media:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .media,
                text: "",
                style: .bodyDefault,
                position: position
            )
        case .link:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .link,
                text: "",
                style: .bodyDefault,
                position: position,
                linkURL: ""
            )
        case .pursuit:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .pursuit,
                text: "Pursuit",
                style: .headingDefault,
                position: position,
                pursuitID: ComposerDocumentID()
            )
        }
    }
}

struct ComposerPursuit: Identifiable, Codable, Equatable, Sendable {
    let id: ComposerDocumentID
    var title: String
    var blocks: [ComposerBlock]
}

struct ComposerSnapshot: Codable, Equatable, Sendable {
    var mosaicTitle: String
    var mosaicBlocks: [ComposerBlock]
    var pursuits: [ComposerPursuit]

    static let empty = ComposerSnapshot(
        mosaicTitle: "My Mosaic",
        mosaicBlocks: [],
        pursuits: []
    )
}

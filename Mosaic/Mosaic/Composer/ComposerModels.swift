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

    var pointSize: Double {
        switch self {
        case .body: 17
        case .large: 22
        case .title: 28
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

enum ComposerFontChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case rounded
    case serif
    case mono
    case avenir
    case georgia
    case futura

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .rounded: "Rounded"
        case .serif: "Serif"
        case .mono: "Mono"
        case .avenir: "Avenir"
        case .georgia: "Georgia"
        case .futura: "Futura"
        }
    }
}

struct ComposerRGBColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double = 1
}

struct TextBlockStyle: Codable, Equatable, Sendable {
    var size: TextBlockSize
    var color: TextBlockColor
    var alignment: TextAlignmentOption
    /// Legacy pinch multiplier. New pinches bake this into `fontSize`.
    var scale: Double
    var fontSize: Double
    var fontChoice: ComposerFontChoice
    /// Installed font family. When set, this overrides `fontChoice`.
    var fontFamilyName: String?
    var customColor: ComposerRGBColor?

    init(
        size: TextBlockSize,
        color: TextBlockColor,
        alignment: TextAlignmentOption,
        scale: Double = 1,
        fontSize: Double? = nil,
        fontChoice: ComposerFontChoice = .system,
        fontFamilyName: String? = nil,
        customColor: ComposerRGBColor? = nil
    ) {
        self.size = size
        self.color = color
        self.alignment = alignment
        self.scale = scale
        self.fontSize = fontSize ?? size.pointSize
        self.fontChoice = fontChoice
        self.fontFamilyName = fontFamilyName
        self.customColor = customColor
    }

    enum CodingKeys: String, CodingKey {
        case size, color, alignment, scale, fontSize, fontChoice, fontFamilyName, customColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decode(TextBlockSize.self, forKey: .size)
        color = try container.decode(TextBlockColor.self, forKey: .color)
        alignment = try container.decode(TextAlignmentOption.self, forKey: .alignment)
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? size.pointSize
        fontChoice = try container.decodeIfPresent(ComposerFontChoice.self, forKey: .fontChoice) ?? .system
        fontFamilyName = try container.decodeIfPresent(String.self, forKey: .fontFamilyName)
        customColor = try container.decodeIfPresent(ComposerRGBColor.self, forKey: .customColor)
    }

    static let bodyDefault = TextBlockStyle(size: .body, color: .canvas, alignment: .leading, fontSize: 17)
    static let headingDefault = TextBlockStyle(size: .title, color: .canvas, alignment: .leading, fontSize: 28)
}

enum MediaFrameShape: String, Codable, CaseIterable, Sendable {
    case rectangle
    case square
    case rounded
    case circle
    case oval
    case capsule
    case triangle
    case diamond
    case pentagon
    case hexagon
    case octagon
    case star
    case heart

    var label: String {
        switch self {
        case .rectangle: "Rectangle"
        case .square: "Square"
        case .rounded: "Rounded"
        case .circle: "Circle"
        case .oval: "Oval"
        case .capsule: "Capsule"
        case .triangle: "Triangle"
        case .diamond: "Diamond"
        case .pentagon: "Pentagon"
        case .hexagon: "Hexagon"
        case .octagon: "Octagon"
        case .star: "Star"
        case .heart: "Heart"
        }
    }

    var systemImage: String {
        switch self {
        case .rectangle: "rectangle"
        case .square: "square"
        case .rounded: "rectangle.roundedtop"
        case .circle: "circle"
        case .oval: "oval"
        case .capsule: "capsule"
        case .triangle: "triangle"
        case .diamond: "diamond"
        case .pentagon: "pentagon"
        case .hexagon: "hexagon"
        case .octagon: "octagon"
        case .star: "star"
        case .heart: "heart"
        }
    }

    var usesSquareFrame: Bool {
        switch self {
        case .square, .circle, .triangle, .diamond, .pentagon, .hexagon, .octagon, .star, .heart:
            true
        case .rectangle, .rounded, .oval, .capsule:
            false
        }
    }
}

struct MediaGridPoint: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
}

struct MediaEdgeGrid: Codable, Equatable, Hashable, Sendable {
    static let columns = 4
    static let rows = 4

    var points: [MediaGridPoint]

    static var straight: MediaEdgeGrid {
        var points: [MediaGridPoint] = []
        for row in 0..<rows {
            for column in 0..<columns {
                points.append(MediaGridPoint(
                    x: Double(column) / Double(columns - 1),
                    y: Double(row) / Double(rows - 1)
                ))
            }
        }
        return MediaEdgeGrid(points: points)
    }

    var isStraight: Bool {
        let base = Self.straight.points
        guard points.count == base.count else { return false }
        return zip(points, base).allSatisfy { point, origin in
            abs(point.x - origin.x) < 0.004 && abs(point.y - origin.y) < 0.004
        }
    }

    func point(column: Int, row: Int) -> MediaGridPoint {
        points[row * Self.columns + column]
    }

    mutating func setPoint(_ point: MediaGridPoint, column: Int, row: Int) {
        points[row * Self.columns + column] = point
    }
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
    var mediaShape: MediaFrameShape
    var mediaWarp: MediaEdgeGrid?
    var mediaZoom: Double
    var mediaPanX: Double
    var mediaPanY: Double
    var linkURL: String?
    var pursuitID: ComposerDocumentID?

    enum CodingKeys: String, CodingKey {
        case id, kind, text, style, position, mediaFileName, mediaShape, mediaWarp, mediaZoom, mediaPanX, mediaPanY, linkURL, pursuitID
    }

    init(
        id: ComposerBlockID,
        kind: BlockKind,
        text: String,
        style: TextBlockStyle,
        position: BlockPosition,
        mediaFileName: String? = nil,
        mediaShape: MediaFrameShape = .rectangle,
        mediaWarp: MediaEdgeGrid? = nil,
        mediaZoom: Double = 1,
        mediaPanX: Double = 0,
        mediaPanY: Double = 0,
        linkURL: String? = nil,
        pursuitID: ComposerDocumentID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.style = style
        self.position = position
        self.mediaFileName = mediaFileName
        self.mediaShape = mediaShape
        self.mediaWarp = mediaWarp
        self.mediaZoom = mediaZoom
        self.mediaPanX = mediaPanX
        self.mediaPanY = mediaPanY
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
        mediaShape = try container.decodeIfPresent(MediaFrameShape.self, forKey: .mediaShape) ?? .rectangle
        mediaWarp = try container.decodeIfPresent(MediaEdgeGrid.self, forKey: .mediaWarp)
        mediaZoom = try container.decodeIfPresent(Double.self, forKey: .mediaZoom) ?? 1
        mediaPanX = try container.decodeIfPresent(Double.self, forKey: .mediaPanX) ?? 0
        mediaPanY = try container.decodeIfPresent(Double.self, forKey: .mediaPanY) ?? 0
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

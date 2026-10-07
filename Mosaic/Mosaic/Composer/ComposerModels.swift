import Foundation
import UIKit

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
    case carousel
    case link
    case pursuit
}

enum BlockMenuOption: String, CaseIterable, Identifiable {
    case text
    case heading
    case media
    case carousel
    case link
    case pursuit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text"
        case .heading: "Heading"
        case .media: "Media"
        case .carousel: "Carousel"
        case .link: "Link"
        case .pursuit: "Pursuit"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "textformat"
        case .heading: "textformat.size.larger"
        case .media: "photo"
        case .carousel: "rectangle.stack"
        case .link: "link"
        case .pursuit: "square.grid.2x2"
        }
    }

    var placementLabel: String {
        switch self {
        case .text: "T"
        case .heading: "H"
        case .media: "▣"
        case .carousel: "◎"
        case .link: "🔗"
        case .pursuit: "P"
        }
    }

    var blockKind: BlockKind {
        switch self {
        case .text: .text
        case .heading: .heading
        case .media: .media
        case .carousel: .carousel
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
        case .carousel: "carousel carosoul slider"
        case .link: "link url web"
        case .pursuit: "pursuit project goal"
        }
    }

    static func menuOptions(matching query: String, includingPursuit: Bool = true) -> [BlockMenuOption] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var ordered = Array(allCases.reversed())
        if !includingPursuit {
            ordered.removeAll { $0 == .pursuit }
        }
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

struct PursuitTextItem: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var text: String
    var style: TextBlockStyle
    var x: Double
    var y: Double

    init(
        id: String = UUID().uuidString,
        text: String,
        style: TextBlockStyle = .bodyDefault,
        x: Double = 0.08,
        y: Double = 0.42
    ) {
        self.id = id
        self.text = text
        self.style = style
        self.x = x
        self.y = y
    }

    enum CodingKeys: String, CodingKey {
        case id, text, style, x, y
        case fontSize, fontChoice, color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        x = try container.decodeIfPresent(Double.self, forKey: .x) ?? 0.08
        y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0.42
        if let style = try container.decodeIfPresent(TextBlockStyle.self, forKey: .style) {
            self.style = style
        } else {
            let fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 22
            let fontChoice = try container.decodeIfPresent(ComposerFontChoice.self, forKey: .fontChoice) ?? .system
            let color = try container.decodeIfPresent(ComposerRGBColor.self, forKey: .color)
            self.style = TextBlockStyle(
                size: .body,
                color: .canvas,
                alignment: .leading,
                fontSize: fontSize,
                fontChoice: fontChoice,
                customColor: color
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(style, forKey: .style)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }

    func canvasBlock() -> ComposerBlock {
        ComposerBlock(
            id: ComposerBlockID(rawValue: id),
            kind: .text,
            text: text,
            style: style,
            position: BlockPosition(x: x, y: y)
        )
    }

    mutating func adopt(_ block: ComposerBlock) {
        text = block.text
        style = block.style
    }
}

enum PursuitWidgetShape: String, Codable, CaseIterable, Sendable {
    case square
    case landscape
    case wide
    case banner
    case portrait
    case tall
    case story

    var label: String {
        switch self {
        case .square: "Square"
        case .landscape: "Landscape"
        case .wide: "Wide"
        case .banner: "Banner"
        case .portrait: "Portrait"
        case .tall: "Tall"
        case .story: "Story"
        }
    }

    /// Width divided by height.
    var aspect: CGFloat {
        switch self {
        case .square: 1
        case .landscape: 4.0 / 3.0
        case .wide: 16.0 / 9.0
        case .banner: 2.35
        case .portrait: 3.0 / 4.0
        case .tall: 9.0 / 16.0
        case .story: 9.0 / 19.0
        }
    }
}

enum MediaFrameShape: String, Codable, CaseIterable, Sendable {
    case rectangle
    case square
    case rounded
    case roundedRectangle
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
        case .roundedRectangle: "Rounded rectangle"
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
        case .roundedRectangle: "app"
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
        case .rectangle, .rounded, .roundedRectangle, .oval, .capsule:
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

struct CarouselMediaItem: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var fileName: String

    init(id: String = UUID().uuidString, fileName: String) {
        self.id = id
        self.fileName = fileName
    }
}

/// How a carousel turns. One swipe moves a single step, and the strip wraps.
enum CarouselMotion {
    static let minimumCount = 3

    static func wrapped(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let remainder = index % count
        return remainder >= 0 ? remainder : remainder + count
    }

    /// Shortest signed steps from the centered item to `item`.
    static func shortestOffset(item: Int, center: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var delta = item - center
        delta %= count
        if delta > count / 2 {
            delta -= count
        } else if delta <= -(count / 2) {
            delta += count
        }
        return delta
    }

    /// Finger moving right (`drag` > 0) reveals the previous item.
    static func shift(drag: CGFloat, predicted: CGFloat, step: CGFloat) -> Int {
        guard step > 1 else { return 0 }
        let fraction = drag / step
        let predictedFraction = predicted / step
        let useFlick = abs(predictedFraction) > abs(fraction) && abs(predictedFraction) > 0.45
        let amount = useFlick ? predictedFraction : fraction
        if amount > 0.22 { return -1 }
        if amount < -0.22 { return 1 }
        return 0
    }

    static func indexAfterRemoval(index: Int, removedAt: Int, countAfter: Int) -> Int {
        guard countAfter > 0 else { return 0 }
        var next = index
        if removedAt < index {
            next -= 1
        } else if removedAt == index {
            next = min(index, countAfter - 1)
        }
        return wrapped(next, count: countAfter)
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
    var pursuitShape: MediaFrameShape
    var pursuitLayout: PursuitWidgetShape
    var pursuitTextX: Double
    var pursuitTextY: Double
    var pursuitTexts: [PursuitTextItem]
    var pursuitImageZoom: Double
    var pursuitImagePanX: Double
    var pursuitImagePanY: Double
    var pursuitFill: ComposerRGBColor?
    var pursuitImageFileName: String?
    var carouselItems: [CarouselMediaItem]
    var carouselIndex: Int

    enum CodingKeys: String, CodingKey {
        case id, kind, text, style, position, mediaFileName, mediaShape, mediaWarp, mediaZoom, mediaPanX, mediaPanY, linkURL, pursuitID, pursuitShape, pursuitLayout, pursuitTextX, pursuitTextY, pursuitTexts, pursuitImageZoom, pursuitImagePanX, pursuitImagePanY, pursuitFill, pursuitImageFileName, carouselItems, carouselIndex
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
        pursuitID: ComposerDocumentID? = nil,
        pursuitShape: MediaFrameShape = .rounded,
        pursuitLayout: PursuitWidgetShape = .square,
        pursuitTextX: Double = 0,
        pursuitTextY: Double = 0,
        pursuitTexts: [PursuitTextItem] = [],
        pursuitImageZoom: Double = 1,
        pursuitImagePanX: Double = 0,
        pursuitImagePanY: Double = 0,
        pursuitFill: ComposerRGBColor? = nil,
        pursuitImageFileName: String? = nil,
        carouselItems: [CarouselMediaItem] = [],
        carouselIndex: Int = 0
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
        self.pursuitShape = pursuitShape
        self.pursuitLayout = pursuitLayout
        self.pursuitTextX = pursuitTextX
        self.pursuitTextY = pursuitTextY
        self.pursuitTexts = pursuitTexts
        self.pursuitImageZoom = pursuitImageZoom
        self.pursuitImagePanX = pursuitImagePanX
        self.pursuitImagePanY = pursuitImagePanY
        self.pursuitFill = pursuitFill
        self.pursuitImageFileName = pursuitImageFileName
        self.carouselItems = carouselItems
        self.carouselIndex = carouselIndex
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
        pursuitShape = try container.decodeIfPresent(MediaFrameShape.self, forKey: .pursuitShape) ?? .rounded
        pursuitLayout = try container.decodeIfPresent(PursuitWidgetShape.self, forKey: .pursuitLayout) ?? .square
        pursuitTextX = try container.decodeIfPresent(Double.self, forKey: .pursuitTextX) ?? 0
        pursuitTextY = try container.decodeIfPresent(Double.self, forKey: .pursuitTextY) ?? 0
        pursuitTexts = try container.decodeIfPresent([PursuitTextItem].self, forKey: .pursuitTexts) ?? []
        pursuitImageZoom = try container.decodeIfPresent(Double.self, forKey: .pursuitImageZoom) ?? 1
        pursuitImagePanX = try container.decodeIfPresent(Double.self, forKey: .pursuitImagePanX) ?? 0
        pursuitImagePanY = try container.decodeIfPresent(Double.self, forKey: .pursuitImagePanY) ?? 0
        pursuitFill = try container.decodeIfPresent(ComposerRGBColor.self, forKey: .pursuitFill)
        pursuitImageFileName = try container.decodeIfPresent(String.self, forKey: .pursuitImageFileName)
        carouselItems = try container.decodeIfPresent([CarouselMediaItem].self, forKey: .carouselItems) ?? []
        carouselIndex = try container.decodeIfPresent(Int.self, forKey: .carouselIndex) ?? 0
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
        case .carousel:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .carousel,
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
            newPursuitBlock(at: position)
        }
    }

    /// A new Pursuit widget with the name placeholder centered on the square.
    private static func newPursuitBlock(at position: BlockPosition) -> ComposerBlock {
        let style = TextBlockStyle.headingDefault
        let module = PursuitWidgetShape.square.moduleSize(scale: CGFloat(style.scale))
        let font = UIFont.systemFont(ofSize: style.fontSize * style.scale, weight: .semibold)
        let textSize = (NSString(string: "Pursuit")).size(withAttributes: [.font: font])
        let width = max(module.width, 1)
        let height = max(module.height, 1)
        let textX = min(max(Double((width - textSize.width) / 2 / width), 0), 1)
        let textY = min(max(Double((height - textSize.height) / 2 / height), 0), 1)
        return ComposerBlock(
            id: ComposerBlockID(),
            kind: .pursuit,
            text: "",
            style: style,
            position: position,
            pursuitID: ComposerDocumentID(),
            pursuitTextX: textX,
            pursuitTextY: textY
        )
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
    /// True after the board title has been placed as canvas text. Deleting that text does not restore a fixed title.
    var mosaicTitlePlaced: Bool
    /// True after existing Pursuit pages were cleared to an empty composer.
    var pursuitPagesBlanked: Bool

    static let empty = ComposerSnapshot(
        mosaicTitle: "My Mosaic",
        mosaicBlocks: [],
        pursuits: [],
        mosaicTitlePlaced: false,
        pursuitPagesBlanked: false
    )

    init(
        mosaicTitle: String,
        mosaicBlocks: [ComposerBlock],
        pursuits: [ComposerPursuit],
        mosaicTitlePlaced: Bool = false,
        pursuitPagesBlanked: Bool = false
    ) {
        self.mosaicTitle = mosaicTitle
        self.mosaicBlocks = mosaicBlocks
        self.pursuits = pursuits
        self.mosaicTitlePlaced = mosaicTitlePlaced
        self.pursuitPagesBlanked = pursuitPagesBlanked
    }

    enum CodingKeys: String, CodingKey {
        case mosaicTitle, mosaicBlocks, pursuits, mosaicTitlePlaced, pursuitPagesBlanked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mosaicTitle = try container.decode(String.self, forKey: .mosaicTitle)
        mosaicBlocks = try container.decode([ComposerBlock].self, forKey: .mosaicBlocks)
        pursuits = try container.decode([ComposerPursuit].self, forKey: .pursuits)
        mosaicTitlePlaced = try container.decodeIfPresent(Bool.self, forKey: .mosaicTitlePlaced) ?? false
        pursuitPagesBlanked = try container.decodeIfPresent(Bool.self, forKey: .pursuitPagesBlanked) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mosaicTitle, forKey: .mosaicTitle)
        try container.encode(mosaicBlocks, forKey: .mosaicBlocks)
        try container.encode(pursuits, forKey: .pursuits)
        try container.encode(mosaicTitlePlaced, forKey: .mosaicTitlePlaced)
        try container.encode(pursuitPagesBlanked, forKey: .pursuitPagesBlanked)
    }
}

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
    case group
    case text
    case heading
    case list
    case media
    case carousel
    case calendar
    case graph
    case link
    case node
    case scrapbook
    case tabs
    case banner
    case table
    case social
    case pursuit
    case drawing
    /// A picture with no background, such as a subject cut out of a photo. The file is `mediaFileName`.
    case sticker
    /// A piece from a newer version of the app. It is kept exactly as saved and not shown.
    case unsupported

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BlockKind(rawValue: raw) ?? .unsupported
    }
}

enum BlockMenuOption: String, CaseIterable, Identifiable {
    case group
    case text
    case heading
    case list
    case drawing
    case sticker
    case media
    case carousel
    case calendar
    case graph
    case link
    case content
    case node
    case scrapbook
    case tabs
    case banner
    case table
    case social
    case pursuit
    case background

    var id: String { rawValue }

    var title: String {
        switch self {
        case .group: "Group"
        case .text: "Text"
        case .heading: "Heading"
        case .list: "List"
        case .drawing: "Draw"
        case .sticker: "Sticker"
        case .media: "Media"
        case .carousel: "Carousel"
        case .calendar: "Calendar"
        case .graph: "Graph"
        case .content: "Content"
        case .link: "Link"
        case .node: "Node"
        case .scrapbook: "Scrapbook"
        case .tabs: "Tabs"
        case .banner: "Banner"
        case .table: "Table"
        case .social: "Socials"
        case .pursuit: "Pursuit"
        case .background: "Background"
        }
    }

    var systemImage: String {
        switch self {
        case .group: "square.on.square"
        case .text: "textformat"
        case .heading: "textformat.size.larger"
        case .list: "list.bullet"
        case .drawing: "scribble.variable"
        case .sticker: "wand.and.stars"
        case .media: "photo"
        case .carousel: "rectangle.stack"
        case .calendar: "calendar"
        case .graph: "chart.xyaxis.line"
        case .content: "play.rectangle"
        case .link: "link"
        case .node: "folder"
        case .scrapbook: "book.closed"
        case .tabs: "rectangle.split.3x1"
        case .banner: "rectangle.topthird.inset.filled"
        case .table: "tablecells"
        case .social: "at"
        case .pursuit: "square.grid.2x2"
        case .background: "paintpalette"
        }
    }

    var placementLabel: String {
        switch self {
        case .group: "G"
        case .text: "T"
        case .heading: "H"
        case .list: "•"
        case .drawing: "✎"
        case .sticker: "✦"
        case .media: "▣"
        case .carousel: "◎"
        case .calendar: "▦"
        case .graph: "↗"
        case .content: "▶"
        case .link: "🔗"
        case .node: "N"
        case .scrapbook: "Bk"
        case .tabs: "☰"
        case .banner: "B"
        case .table: "⊞"
        case .social: "@"
        case .pursuit: "P"
        case .background: "Bg"
        }
    }

    var blockKind: BlockKind {
        switch self {
        case .group: .group
        case .text: .text
        case .heading: .heading
        case .list: .list
        case .drawing: .drawing
        case .sticker: .sticker
        case .media: .media
        case .carousel: .carousel
        case .calendar: .calendar
        case .graph: .graph
        case .content: .link
        case .link: .link
        case .node: .node
        case .scrapbook: .scrapbook
        case .tabs: .tabs
        case .banner: .banner
        case .table: .table
        case .social: .social
        case .pursuit: .pursuit
        case .background: .text
        }
    }

    /// Lowercased tokens for add-menu search (extend as options grow).
    var searchTokens: String {
        switch self {
        case .text: "text paragraph write"
        case .heading: "heading title headline"
        case .list: "list bullet number numbered checkbox todo task dash letter"
        case .drawing: "draw drawing sketch pencil pen ink arrow circle underline annotate markup"
        case .sticker: "sticker cutout cut out subject lift remove background stamp"
        case .media: "media photo image picture"
        case .carousel: "carousel carosoul slider"
        case .calendar: "calendar date day month year schedule"
        case .graph: "graph chart line plot axis"
        case .content: "content video post reel youtube instagram tiktok twitch"
        case .link: "link url web"
        case .group: "group selection multi select cluster"
        case .node: "node folder organize"
        case .scrapbook: "scrapbook journal book pages"
        case .tabs: "tabs tab set"
        case .banner: "banner header cover"
        case .table: "table spreadsheet grid columns rows"
        case .social: "social instagram tiktok twitter youtube twitch"
        case .pursuit: "pursuit project goal"
        case .background: "background color gradient photo image"
        }
    }

    static func menuOptions(
        matching query: String,
        includingPursuit: Bool = true,
        includingCalendar: Bool = true,
        includingGraph: Bool = true,
        includingNode: Bool = true,
        includingScrapbook: Bool = true,
        includingTabs: Bool = true,
        includingBanner: Bool = true,
        includingTable: Bool = true,
        includingCarousel: Bool = true,
        includingBackground: Bool = true
    ) -> [BlockMenuOption] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Alphabetical by the name people see, in every composer, so pieces are easy to find.
        var ordered = allCases.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        // Plain Link is retired from every composer; Content covers URL embeds.
        ordered.removeAll { $0 == .link }
        if !includingPursuit {
            ordered.removeAll { $0 == .pursuit }
        }
        if !includingCalendar {
            ordered.removeAll { $0 == .calendar }
        }
        if !includingGraph {
            ordered.removeAll { $0 == .graph }
        }
        if !includingNode {
            ordered.removeAll { $0 == .node }
        }
        if !includingScrapbook {
            ordered.removeAll { $0 == .scrapbook }
        }
        if !includingTabs {
            ordered.removeAll { $0 == .tabs }
        }
        if !includingBanner {
            ordered.removeAll { $0 == .banner }
        }
        if !includingTable {
            ordered.removeAll { $0 == .table }
        }
        if !includingCarousel {
            ordered.removeAll { $0 == .carousel }
        }
        if !includingBackground {
            ordered.removeAll { $0 == .background }
        }
        guard !trimmed.isEmpty else { return ordered }
        return ordered.filter { $0.searchTokens.contains(trimmed) }
    }
}

struct ComposerListItem: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var text: String
    var isChecked: Bool

    init(id: String = UUID().uuidString, text: String = "", isChecked: Bool = false) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
    }
}

enum ComposerListMarker: String, Codable, CaseIterable, Identifiable, Sendable {
    case bullet
    case number
    case checkbox
    case dash
    case letter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bullet: "Bulleted"
        case .number: "Numbered"
        case .checkbox: "Checkbox"
        case .dash: "Dashed"
        case .letter: "Lettered"
        }
    }

    var systemImage: String {
        switch self {
        case .bullet: "list.bullet"
        case .number: "list.number"
        case .checkbox: "checklist"
        case .dash: "list.dash"
        case .letter: "textformat.abc"
        }
    }

    func marker(at index: Int) -> String {
        switch self {
        case .bullet: "•"
        case .number: "\(index + 1)."
        case .checkbox: ""
        case .dash: "–"
        case .letter: Self.letters(for: index) + "."
        }
    }

    /// Spreadsheet-style letters: a, b, … z, aa.
    private static func letters(for index: Int) -> String {
        var value = max(index, 0) + 1
        var result = ""
        while value > 0 {
            value -= 1
            let remainder = value % 26
            guard let scalar = UnicodeScalar(97 + remainder) else { break }
            result = String(scalar) + result
            value /= 26
        }
        return result
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

/// Fixed backdrop for a Mosaic board or a Pursuit page. It is not a placed component.
struct ComposerBoardBackground: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case solid
        case gradient
        case media
    }

    var kind: Kind
    var color: ComposerRGBColor
    var secondaryColor: ComposerRGBColor
    var mediaFileName: String?

    static func solid(_ color: ComposerRGBColor) -> ComposerBoardBackground {
        ComposerBoardBackground(kind: .solid, color: color, secondaryColor: color, mediaFileName: nil)
    }
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
    var isBold: Bool
    var isItalic: Bool
    var isUnderlined: Bool

    init(
        size: TextBlockSize,
        color: TextBlockColor,
        alignment: TextAlignmentOption,
        scale: Double = 1,
        fontSize: Double? = nil,
        fontChoice: ComposerFontChoice = .system,
        fontFamilyName: String? = nil,
        customColor: ComposerRGBColor? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false
    ) {
        self.size = size
        self.color = color
        self.alignment = alignment
        self.scale = scale
        self.fontSize = fontSize ?? size.pointSize
        self.fontChoice = fontChoice
        self.fontFamilyName = fontFamilyName
        self.customColor = customColor
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
    }

    enum CodingKeys: String, CodingKey {
        case size, color, alignment, scale, fontSize, fontChoice, fontFamilyName, customColor, isBold, isItalic, isUnderlined
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
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        isUnderlined = try container.decodeIfPresent(Bool.self, forKey: .isUnderlined) ?? false
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
    case landscape
    case wide
    case banner
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
        case .landscape: "Landscape"
        case .wide: "Wide"
        case .banner: "Banner"
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
        case .landscape: "rectangle.ratio.4.to.3"
        case .wide: "rectangle.ratio.16.to.9"
        case .banner: "pano"
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

    /// Width divided by height. Nil means the frame follows the photo or video until the owner sets one.
    var presetAspect: CGFloat? {
        switch self {
        case .square, .circle, .triangle, .diamond, .pentagon, .hexagon, .octagon, .star, .heart:
            1
        case .landscape:
            4.0 / 3.0
        case .wide:
            16.0 / 9.0
        case .banner:
            2.35
        case .rectangle, .rounded, .roundedRectangle, .oval, .capsule:
            nil
        }
    }

    static let minimumAspect: CGFloat = 0.35
    static let maximumAspect: CGFloat = 3.2
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

enum CarouselItemKind: String, Codable, Sendable {
    case media
    case social
    case content
}

/// One card in a carousel or a calendar day. Items saved before kinds existed are media.
struct CarouselMediaItem: Codable, Equatable, Identifiable, Sendable {
    var id: String
    /// The photo or video, or a content card's cover. Empty for socials, and while a photo imports.
    var fileName: String
    var kind: CarouselItemKind
    /// A `ComposerSocialPlatform` or `ComposerContentPlatform` raw value.
    var platform: String
    /// A social profile link or username, or a content post's link.
    var link: String
    var title: String

    init(
        id: String = UUID().uuidString,
        fileName: String,
        kind: CarouselItemKind = .media,
        platform: String = "",
        link: String = "",
        title: String = ""
    ) {
        self.id = id
        self.fileName = fileName
        self.kind = kind
        self.platform = platform
        self.link = link
        self.title = title
    }

    /// A photo or video still importing.
    var isPending: Bool { kind == .media && fileName.isEmpty }

    var hasContent: Bool {
        switch kind {
        case .media: !fileName.isEmpty
        case .social, .content: !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var socialPlatform: ComposerSocialPlatform? {
        kind == .social ? ComposerSocialPlatform(rawValue: platform) ?? .instagram : nil
    }

    var contentPlatform: ComposerContentPlatform? {
        kind == .content ? ComposerContentPlatform(rawValue: platform) ?? .youtube : nil
    }

    /// Where tapping a social or content card goes.
    var linkURL: URL? {
        switch kind {
        case .media: nil
        case .social: socialPlatform?.profileURL(from: link)
        case .content: ComposerContentPlatform.parse(link)?.url
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, fileName, kind, platform, link, title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        let rawKind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        kind = CarouselItemKind(rawValue: rawKind) ?? .media
        platform = try container.decodeIfPresent(String.self, forKey: .platform) ?? ""
        link = try container.decodeIfPresent(String.self, forKey: .link) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fileName, forKey: .fileName)
        guard kind != .media else { return }
        try container.encode(kind, forKey: .kind)
        try container.encode(platform, forKey: .platform)
        try container.encode(link, forKey: .link)
        try container.encode(title, forKey: .title)
    }
}

/// How a carousel turns. One swipe moves a single step, and the strip wraps.
enum CarouselMotion {
    static let minimumCount = 1

    static func wrapped(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let remainder = index % count
        return remainder >= 0 ? remainder : remainder + count
    }

    /// Shortest signed steps from the centered item to `item`.
    static func shortestOffset(item: Int, center: Int, count: Int) -> Int {
        guard count > 1 else { return 0 }
        var delta = item - center
        delta %= count
        if delta > count / 2 {
            delta -= count
        } else if delta <= -(count / 2) {
            delta += count
        }
        return delta
    }

    /// Every place, in steps from the center, where `item` may show while the strip turns. A
    /// swipe moves at most one step and cards fade out before two, so only offsets within two
    /// matter. Two items wrap onto both sides of the center; a lone item stays centered.
    static func offsets(item: Int, center: Int, count: Int) -> [Int] {
        let offset = shortestOffset(item: item, center: center, count: count)
        guard count > 1 else { return [offset] }
        return [offset - count, offset, offset + count].filter { abs($0) <= 2 }
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

struct CalendarDayEntry: Codable, Equatable, Identifiable, Sendable {
    var year: Int
    var month: Int
    var day: Int
    var note: String
    var media: [CarouselMediaItem]
    var mediaIndex: Int

    var id: String { String(format: "%04d-%02d-%02d", year, month, day) }

    var hasContent: Bool {
        media.contains(where: \.hasContent) || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        year: Int,
        month: Int,
        day: Int,
        note: String,
        media: [CarouselMediaItem] = [],
        mediaIndex: Int = 0
    ) {
        self.year = year
        self.month = month
        self.day = day
        self.note = note
        self.media = media
        self.mediaIndex = mediaIndex
    }

    private enum CodingKeys: String, CodingKey {
        case year, month, day, note, media, mediaIndex, mediaFileName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        year = try container.decode(Int.self, forKey: .year)
        month = try container.decode(Int.self, forKey: .month)
        day = try container.decode(Int.self, forKey: .day)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        mediaIndex = try container.decodeIfPresent(Int.self, forKey: .mediaIndex) ?? 0
        if let media = try container.decodeIfPresent([CarouselMediaItem].self, forKey: .media) {
            self.media = media
        } else if let fileName = try container.decodeIfPresent(String.self, forKey: .mediaFileName) {
            self.media = [CarouselMediaItem(fileName: fileName)]
        } else {
            self.media = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(year, forKey: .year)
        try container.encode(month, forKey: .month)
        try container.encode(day, forKey: .day)
        try container.encode(note, forKey: .note)
        try container.encode(media, forKey: .media)
        try container.encode(mediaIndex, forKey: .mediaIndex)
    }
}

struct ComposerGraphPoint: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var x: Date
    var y: Int

    init(id: String = UUID().uuidString, x: Date, y: Int) {
        self.id = id
        self.x = x
        self.y = y
    }
}

enum ComposerGraphKind: String, Codable, Sendable {
    case line
}

enum ComposerGraphAxis: String, Codable, Sendable {
    case date
    case integer
}

/// Places line-graph points in date order. `nx` and `ny` run from 0 to 1, with 1 at the top.
enum ComposerLineGraph {
    struct Placed: Equatable {
        var id: String
        var nx: CGFloat
        var ny: CGFloat
    }

    static func placed(_ points: [ComposerGraphPoint]) -> [Placed] {
        let ordered = points.sorted { lhs, rhs in
            if lhs.x != rhs.x { return lhs.x < rhs.x }
            return lhs.id < rhs.id
        }
        guard !ordered.isEmpty else { return [] }
        let minX = ordered.map(\.x.timeIntervalSinceReferenceDate).min() ?? 0
        let maxX = ordered.map(\.x.timeIntervalSinceReferenceDate).max() ?? 0
        // Doubles, not Int: two saved values far enough apart would overflow and crash on every draw.
        let minY = Double(ordered.map(\.y).min() ?? 0)
        let maxY = Double(ordered.map(\.y).max() ?? 0)
        let xSpan = maxX - minX
        let ySpan = maxY - minY
        return ordered.map { point in
            let nx: CGFloat = xSpan == 0 ? 0.5 : CGFloat((point.x.timeIntervalSinceReferenceDate - minX) / xSpan)
            let ny: CGFloat = ySpan == 0 ? 0.5 : CGFloat((Double(point.y) - minY) / ySpan)
            return Placed(id: point.id, nx: nx, ny: ny)
        }
    }

    /// The picked calendar day at noon UTC, so the point keeps its day for viewers in other
    /// time zones and same-day points don't drift apart by time of entry.
    static func day(_ date: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12)) ?? date
    }

    static func dateLabel(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMM d" : "MMM d yyyy")
        return formatter.string(from: date)
    }
}

enum ComposerGraphStretch {
    static let minimum = 0.35
    static let maximum = 4.0
    static let baseWidth: CGFloat = 320
    static let baseHeight: CGFloat = 236

    static func clamped(_ value: Double) -> Double {
        min(max(value, minimum), maximum)
    }

    /// `leadingOrTop` means dragging toward the start of that axis grows the graph.
    static func resized(base: Double, translation: CGFloat, span: CGFloat, leadingOrTop: Bool) -> Double {
        let delta = Double(translation / max(span, 1))
        return clamped(base + (leadingOrTop ? -delta : delta))
    }
}

struct ComposerTab: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String

    init(id: String = UUID().uuidString, title: String) {
        self.id = id
        self.title = title
    }
}

/// How many tabs fit on a page. The cap is how many 72-point tabs fit on the longer screen side.
enum ComposerTabSet {
    static let minimumCount = 2
    static let defaultCount = 3
    static let minimumTabWidth: CGFloat = 72
    static let absoluteMaximum = 12

    static func maximumCount(longestSide: CGFloat) -> Int {
        let side = longestSide > 1 ? longestSide : 874
        let usable = side - 32
        let fitted = Int((usable / minimumTabWidth).rounded(.down))
        return min(max(fitted, minimumCount), absoluteMaximum)
    }

    static func longestScreenSide() -> CGFloat {
        let screen = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen
        let bounds = screen?.bounds ?? CGRect(x: 0, y: 0, width: 390, height: 844)
        return max(bounds.width, bounds.height)
    }

    static func defaultTabs() -> [ComposerTab] {
        (1...defaultCount).map { ComposerTab(title: "Tab \($0)") }
    }
}

struct ComposerTableColumn: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var header: String

    init(id: String = UUID().uuidString, header: String) {
        self.id = id
        self.header = header
    }
}

struct ComposerTableRow: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var cells: [String]

    init(id: String = UUID().uuidString, cells: [String]) {
        self.id = id
        self.cells = cells
    }
}

struct ComposerTableEntry: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var stampedAt: Date
    var rows: [ComposerTableRow]

    init(id: String = UUID().uuidString, stampedAt: Date = .now, rows: [ComposerTableRow]) {
        self.id = id
        self.stampedAt = stampedAt
        self.rows = rows
    }
}

enum ComposerTable {
    static let minimumColumns = 1
    static let minimumRows = 1
    static let maximumColumns = 8
    static let maximumRows = 24
    static let maximumEntries = 400
    static let defaultColumnCount = 3
    static let defaultRowCount = 3

    static func defaultColumns() -> [ComposerTableColumn] {
        (1...defaultColumnCount).map { ComposerTableColumn(header: "Column \($0)") }
    }

    static func defaultRows(columnCount: Int) -> [ComposerTableRow] {
        let count = max(columnCount, minimumColumns)
        return (0..<defaultRowCount).map { _ in
            ComposerTableRow(cells: Array(repeating: "", count: count))
        }
    }

    static func addingColumn(
        to columns: [ComposerTableColumn],
        rows: [ComposerTableRow]
    ) -> (columns: [ComposerTableColumn], rows: [ComposerTableRow])? {
        guard columns.count < maximumColumns else { return nil }
        var columns = columns
        var rows = rows
        columns.append(ComposerTableColumn(header: "Column \(columns.count + 1)"))
        for index in rows.indices {
            rows[index].cells.append("")
        }
        return (columns, rows)
    }

    static func removingLastColumn(
        from columns: [ComposerTableColumn],
        rows: [ComposerTableRow]
    ) -> (columns: [ComposerTableColumn], rows: [ComposerTableRow])? {
        guard columns.count > minimumColumns else { return nil }
        var columns = columns
        var rows = rows
        columns.removeLast()
        for index in rows.indices where !rows[index].cells.isEmpty {
            rows[index].cells.removeLast()
        }
        return (columns, rows)
    }

    static func addingRow(
        to rows: [ComposerTableRow],
        columnCount: Int
    ) -> [ComposerTableRow]? {
        guard rows.count < maximumRows else { return nil }
        var rows = rows
        rows.append(ComposerTableRow(cells: Array(repeating: "", count: max(columnCount, minimumColumns))))
        return rows
    }

    static func removingLastRow(from rows: [ComposerTableRow]) -> [ComposerTableRow]? {
        guard rows.count > minimumRows else { return nil }
        var rows = rows
        rows.removeLast()
        return rows
    }

    static func ordered(_ entries: [ComposerTableEntry]) -> [ComposerTableEntry] {
        entries.sorted { lhs, rhs in
            if lhs.stampedAt != rhs.stampedAt { return lhs.stampedAt < rhs.stampedAt }
            return lhs.id < rhs.id
        }
    }

    static func blankRows(rowCount: Int, columnCount: Int) -> [ComposerTableRow] {
        (0..<max(rowCount, minimumRows)).map { _ in
            ComposerTableRow(cells: Array(repeating: "", count: max(columnCount, minimumColumns)))
        }
    }

    /// A table always has the entry currently on screen. Older tables gain one from their rows.
    static func ensure(_ block: inout ComposerBlock) {
        if block.tableEntries.isEmpty {
            let entry = ComposerTableEntry(rows: block.tableRows)
            block.tableEntries = [entry]
            block.selectedTableEntryID = entry.id
            return
        }
        if block.selectedTableEntryID == nil || !block.tableEntries.contains(where: { $0.id == block.selectedTableEntryID }) {
            block.selectedTableEntryID = ordered(block.tableEntries).last?.id
        }
    }

    static func appendingColumnCell(to entries: [ComposerTableEntry]) -> [ComposerTableEntry] {
        entries.map { entry in
            var entry = entry
            for index in entry.rows.indices {
                entry.rows[index].cells.append("")
            }
            return entry
        }
    }

    static func removingLastColumnCell(from entries: [ComposerTableEntry]) -> [ComposerTableEntry] {
        entries.map { entry in
            var entry = entry
            for index in entry.rows.indices where !entry.rows[index].cells.isEmpty {
                entry.rows[index].cells.removeLast()
            }
            return entry
        }
    }

    static func stampLabel(for date: Date, among entries: [ComposerTableEntry], now: Date = .now, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        let sharesDay = entries.filter { calendar.isDate($0.stampedAt, inSameDayAs: date) }.count > 1
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        if sharesDay {
            formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMM d, h:mm a" : "MMM d yyyy, h:mm a")
        } else {
            formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMM d" : "MMM d yyyy")
        }
        return formatter.string(from: date)
    }
}

/// Tilting pieces. Angles are degrees, clockwise, kept in (-180, 180].
enum ComposerRotation {
    static let snapAngles: [Double] = [-180, -90, -45, -15, 0, 15, 45, 90, 180]
    static let snapTolerance: Double = 4

    static func normalized(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        var angle = degrees.truncatingRemainder(dividingBy: 360)
        if angle > 180 { angle -= 360 }
        if angle <= -180 { angle += 360 }
        return angle
    }

    /// Settles near 0°, ±15°, ±45°, ±90°, and 180° so pieces straighten easily.
    static func snapped(_ degrees: Double) -> (angle: Double, didSnap: Bool) {
        let angle = normalized(degrees)
        guard let target = snapAngles.first(where: { abs($0 - angle) <= snapTolerance }) else {
            return (angle, false)
        }
        return (normalized(target), true)
    }

    /// The handle sits straight above the piece's center, so its direction from the center is the angle.
    static func handleAngle(fromCenterTo vector: CGSize) -> Double {
        guard vector.width != 0 || vector.height != 0 else { return 0 }
        return normalized(atan2(Double(vector.height), Double(vector.width)) * 180 / .pi + 90)
    }
}

extension ComposerBlock {
    /// Visual pieces tilt. Grids (tables, calendars, graphs) stay straight so they remain easy to use,
    /// and the tabs bar and banner are pinned to the page.
    var canRotate: Bool {
        switch kind {
        case .media, .text, .heading, .list, .social, .pursuit, .node, .carousel, .scrapbook, .group, .drawing, .sticker:
            true
        case .link:
            isContent
        case .calendar, .graph, .tabs, .banner, .table, .unsupported:
            false
        }
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
    /// Width divided by height. Zero uses the chosen shape until the owner crops it.
    var pursuitFrameAspect: Double
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
    var calendarEntries: [CalendarDayEntry]
    var listItems: [ComposerListItem]
    var listMarker: ComposerListMarker
    var graphTitle: String
    var graphKind: ComposerGraphKind
    var graphXAxis: ComposerGraphAxis
    var graphYAxis: ComposerGraphAxis
    var graphXUnitName: String
    var graphYUnitName: String
    var graphPoints: [ComposerGraphPoint]
    var graphWidthScale: Double
    var graphHeightScale: Double
    var tabs: [ComposerTab]
    var selectedTabID: String?
    /// Which tab’s page this block belongs to. The tabs bar itself stays unset so it remains visible.
    var tabID: String?
    /// Width divided by height for a cropped photo or video. Zero keeps the older frame until the owner sets one.
    var mediaFrameAspect: Double
    /// Full-width header height. The banner does not change width.
    var bannerHeight: Double
    var tableColumns: [ComposerTableColumn]
    var tableRows: [ComposerTableRow]
    var tableEntries: [ComposerTableEntry]
    var selectedTableEntryID: String?
    /// Instagram, TikTok, Twitter, YouTube, or Twitch. Empty on blocks that are not a social.
    var socialPlatform: String
    /// Components held inside a group, positioned within the group box.
    var groupMembers: [ComposerBlock]
    var groupWidth: Double
    var groupHeight: Double
    /// Boards bound into this scrapbook, in page order.
    var scrapbookPageIDs: [ComposerDocumentID]
    /// Page shown the last time the book was open.
    var scrapbookIndex: Int
    /// Tilt in degrees, clockwise, around the piece's center. Older boards decode as 0.
    var rotation: Double
    /// A locked piece can't be moved, resized, rotated, or deleted; its content can still be edited.
    var isLocked: Bool
    /// PencilKit strokes, in the drawing's own points. Empty until something is drawn.
    var drawingData: Data?
    /// The drawing area's size before `style.scale`, so resizing scales the strokes with it.
    var drawingWidth: Double
    var drawingHeight: Double
    /// The saved form of an `.unsupported` piece, written back unchanged so newer content survives.
    var preserved: ComposerJSONValue?
    /// How see-through the whole piece is, from `ComposerPieceLook.minimumOpacity` to 1.
    var opacity: Double
    var shadow: ComposerPieceShadow
    var shadowColor: ComposerShadowColor
    /// A sticker's size before `style.scale`, in points, in the picture's own shape.
    var stickerWidth: Double
    var stickerHeight: Double
    /// The white border around a sticker's outline.
    var stickerBorder: Bool
    /// Decoration around a photo or video: Polaroid, tape, or torn paper.
    var frameStyle: ComposerFrameStyle
    /// Handwritten line under a Polaroid.
    var frameCaption: String

    enum CodingKeys: String, CodingKey {
        case id, kind, text, style, position, mediaFileName, mediaShape, mediaWarp, mediaZoom, mediaPanX, mediaPanY, linkURL, pursuitID, pursuitShape, pursuitLayout, pursuitFrameAspect, pursuitTextX, pursuitTextY, pursuitTexts, pursuitImageZoom, pursuitImagePanX, pursuitImagePanY, pursuitFill, pursuitImageFileName, carouselItems, carouselIndex, calendarEntries, listItems, listMarker, graphTitle, graphKind, graphXAxis, graphYAxis, graphXUnitName, graphYUnitName, graphPoints, graphWidthScale, graphHeightScale, tabs, selectedTabID, tabID, mediaFrameAspect, bannerHeight, tableColumns, tableRows, tableEntries, selectedTableEntryID, socialPlatform, groupMembers, groupWidth, groupHeight, scrapbookPageIDs, scrapbookIndex, rotation, isLocked, drawingData, drawingWidth, drawingHeight, opacity, shadow, shadowColor, stickerWidth, stickerHeight, stickerBorder, frameStyle, frameCaption
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
        pursuitFrameAspect: Double = 0,
        pursuitTextX: Double = 0,
        pursuitTextY: Double = 0,
        pursuitTexts: [PursuitTextItem] = [],
        pursuitImageZoom: Double = 1,
        pursuitImagePanX: Double = 0,
        pursuitImagePanY: Double = 0,
        pursuitFill: ComposerRGBColor? = nil,
        pursuitImageFileName: String? = nil,
        carouselItems: [CarouselMediaItem] = [],
        carouselIndex: Int = 0,
        calendarEntries: [CalendarDayEntry] = [],
        listItems: [ComposerListItem] = [],
        listMarker: ComposerListMarker = .bullet,
        graphTitle: String = "",
        graphKind: ComposerGraphKind = .line,
        graphXAxis: ComposerGraphAxis = .date,
        graphYAxis: ComposerGraphAxis = .integer,
        graphXUnitName: String = "Date",
        graphYUnitName: String = "Value",
        graphPoints: [ComposerGraphPoint] = [],
        graphWidthScale: Double = 1,
        graphHeightScale: Double = 1,
        tabs: [ComposerTab] = [],
        selectedTabID: String? = nil,
        tabID: String? = nil,
        mediaFrameAspect: Double = 0,
        bannerHeight: Double = ComposerBannerMetrics.defaultHeight,
        tableColumns: [ComposerTableColumn] = [],
        tableRows: [ComposerTableRow] = [],
        tableEntries: [ComposerTableEntry] = [],
        selectedTableEntryID: String? = nil,
        socialPlatform: String = "",
        groupMembers: [ComposerBlock] = [],
        groupWidth: Double = 0,
        groupHeight: Double = 0,
        scrapbookPageIDs: [ComposerDocumentID] = [],
        scrapbookIndex: Int = 0,
        rotation: Double = 0,
        isLocked: Bool = false,
        drawingData: Data? = nil,
        drawingWidth: Double = 0,
        drawingHeight: Double = 0,
        opacity: Double = 1,
        shadow: ComposerPieceShadow = .none,
        shadowColor: ComposerShadowColor = .black,
        stickerWidth: Double = 0,
        stickerHeight: Double = 0,
        stickerBorder: Bool = true,
        frameStyle: ComposerFrameStyle = .none,
        frameCaption: String = ""
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
        self.pursuitFrameAspect = pursuitFrameAspect
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
        self.calendarEntries = calendarEntries
        self.listItems = listItems
        self.listMarker = listMarker
        self.graphTitle = graphTitle
        self.graphKind = graphKind
        self.graphXAxis = graphXAxis
        self.graphYAxis = graphYAxis
        self.graphXUnitName = graphXUnitName
        self.graphYUnitName = graphYUnitName
        self.graphPoints = graphPoints
        self.graphWidthScale = graphWidthScale
        self.graphHeightScale = graphHeightScale
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.tabID = tabID
        self.mediaFrameAspect = mediaFrameAspect
        self.bannerHeight = bannerHeight
        self.tableColumns = tableColumns
        self.tableRows = tableRows
        self.tableEntries = tableEntries
        self.selectedTableEntryID = selectedTableEntryID
        self.socialPlatform = socialPlatform
        self.groupMembers = groupMembers
        self.groupWidth = groupWidth
        self.groupHeight = groupHeight
        self.scrapbookPageIDs = scrapbookPageIDs
        self.scrapbookIndex = scrapbookIndex
        self.rotation = rotation
        self.isLocked = isLocked
        self.drawingData = drawingData
        self.drawingWidth = drawingWidth
        self.drawingHeight = drawingHeight
        self.preserved = nil
        self.opacity = opacity
        self.shadow = shadow
        self.shadowColor = shadowColor
        self.stickerWidth = stickerWidth
        self.stickerHeight = stickerHeight
        self.stickerBorder = stickerBorder
        self.frameStyle = frameStyle
        self.frameCaption = frameCaption
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(ComposerBlockID.self, forKey: .id)
        let kind = try container.decode(BlockKind.self, forKey: .kind)
        if kind == .unsupported {
            var block = ComposerBlock(
                id: id,
                kind: .unsupported,
                text: "",
                style: .bodyDefault,
                position: ((try? container.decodeIfPresent(BlockPosition.self, forKey: .position)) ?? nil)
                    ?? BlockPosition(x: 0, y: 0),
                tabID: (try? container.decodeIfPresent(String.self, forKey: .tabID)) ?? nil
            )
            block.preserved = try ComposerJSONValue(from: decoder)
            self = block
            return
        }
        self.id = id
        self.kind = kind
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
        pursuitFrameAspect = try container.decodeIfPresent(Double.self, forKey: .pursuitFrameAspect) ?? 0
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
        calendarEntries = try container.decodeIfPresent([CalendarDayEntry].self, forKey: .calendarEntries) ?? []
        listItems = try container.decodeIfPresent([ComposerListItem].self, forKey: .listItems) ?? []
        listMarker = try container.decodeIfPresent(ComposerListMarker.self, forKey: .listMarker) ?? .bullet
        graphTitle = try container.decodeIfPresent(String.self, forKey: .graphTitle) ?? ""
        graphKind = try container.decodeIfPresent(ComposerGraphKind.self, forKey: .graphKind) ?? .line
        graphXAxis = try container.decodeIfPresent(ComposerGraphAxis.self, forKey: .graphXAxis) ?? .date
        graphYAxis = try container.decodeIfPresent(ComposerGraphAxis.self, forKey: .graphYAxis) ?? .integer
        graphXUnitName = try container.decodeIfPresent(String.self, forKey: .graphXUnitName) ?? "Date"
        graphYUnitName = try container.decodeIfPresent(String.self, forKey: .graphYUnitName) ?? "Value"
        graphPoints = try container.decodeIfPresent([ComposerGraphPoint].self, forKey: .graphPoints) ?? []
        graphWidthScale = try container.decodeIfPresent(Double.self, forKey: .graphWidthScale) ?? 1
        graphHeightScale = try container.decodeIfPresent(Double.self, forKey: .graphHeightScale) ?? 1
        tabs = try container.decodeIfPresent([ComposerTab].self, forKey: .tabs) ?? []
        selectedTabID = try container.decodeIfPresent(String.self, forKey: .selectedTabID)
        tabID = try container.decodeIfPresent(String.self, forKey: .tabID)
        mediaFrameAspect = try container.decodeIfPresent(Double.self, forKey: .mediaFrameAspect) ?? 0
        bannerHeight = try container.decodeIfPresent(Double.self, forKey: .bannerHeight) ?? ComposerBannerMetrics.defaultHeight
        tableColumns = try container.decodeIfPresent([ComposerTableColumn].self, forKey: .tableColumns) ?? []
        tableRows = try container.decodeIfPresent([ComposerTableRow].self, forKey: .tableRows) ?? []
        tableEntries = try container.decodeIfPresent([ComposerTableEntry].self, forKey: .tableEntries) ?? []
        selectedTableEntryID = try container.decodeIfPresent(String.self, forKey: .selectedTableEntryID)
        socialPlatform = try container.decodeIfPresent(String.self, forKey: .socialPlatform) ?? ""
        groupMembers = try container.decodeIfPresent([ComposerBlock].self, forKey: .groupMembers) ?? []
        groupWidth = try container.decodeIfPresent(Double.self, forKey: .groupWidth) ?? 0
        groupHeight = try container.decodeIfPresent(Double.self, forKey: .groupHeight) ?? 0
        scrapbookPageIDs = try container.decodeIfPresent([ComposerDocumentID].self, forKey: .scrapbookPageIDs) ?? []
        scrapbookIndex = try container.decodeIfPresent(Int.self, forKey: .scrapbookIndex) ?? 0
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        drawingData = try container.decodeIfPresent(Data.self, forKey: .drawingData)
        drawingWidth = try container.decodeIfPresent(Double.self, forKey: .drawingWidth) ?? 0
        drawingHeight = try container.decodeIfPresent(Double.self, forKey: .drawingHeight) ?? 0
        opacity = ComposerPieceLook.clampedOpacity(((try? container.decodeIfPresent(Double.self, forKey: .opacity)) ?? nil) ?? 1)
        // A shadow style from a newer version shows as none here rather than failing the board.
        shadow = (try? container.decodeIfPresent(String.self, forKey: .shadow))
            .flatMap { $0 }
            .flatMap(ComposerPieceShadow.init(rawValue:)) ?? .none
        shadowColor = (try? container.decodeIfPresent(String.self, forKey: .shadowColor))
            .flatMap { $0 }
            .flatMap(ComposerShadowColor.init(rawValue:)) ?? .black
        stickerWidth = try container.decodeIfPresent(Double.self, forKey: .stickerWidth) ?? 0
        stickerHeight = try container.decodeIfPresent(Double.self, forKey: .stickerHeight) ?? 0
        stickerBorder = try container.decodeIfPresent(Bool.self, forKey: .stickerBorder) ?? true
        // A frame from a newer version shows as none here rather than failing the board.
        frameStyle = (try? container.decodeIfPresent(String.self, forKey: .frameStyle))
            .flatMap { $0 }
            .flatMap(ComposerFrameStyle.init(rawValue:)) ?? .none
        frameCaption = try container.decodeIfPresent(String.self, forKey: .frameCaption) ?? ""
        preserved = nil
        if kind == .table {
            ComposerTable.ensure(&self)
        }
    }

    func encode(to encoder: Encoder) throws {
        if kind == .unsupported, let preserved {
            try preservedWithBoardChanges(preserved).encode(to: encoder)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(text, forKey: .text)
        try container.encode(style, forKey: .style)
        try container.encode(position, forKey: .position)
        try container.encodeIfPresent(mediaFileName, forKey: .mediaFileName)
        try container.encode(mediaShape, forKey: .mediaShape)
        try container.encodeIfPresent(mediaWarp, forKey: .mediaWarp)
        try container.encode(mediaZoom, forKey: .mediaZoom)
        try container.encode(mediaPanX, forKey: .mediaPanX)
        try container.encode(mediaPanY, forKey: .mediaPanY)
        try container.encodeIfPresent(linkURL, forKey: .linkURL)
        try container.encodeIfPresent(pursuitID, forKey: .pursuitID)
        try container.encode(pursuitShape, forKey: .pursuitShape)
        try container.encode(pursuitLayout, forKey: .pursuitLayout)
        try container.encode(pursuitFrameAspect, forKey: .pursuitFrameAspect)
        try container.encode(pursuitTextX, forKey: .pursuitTextX)
        try container.encode(pursuitTextY, forKey: .pursuitTextY)
        try container.encode(pursuitTexts, forKey: .pursuitTexts)
        try container.encode(pursuitImageZoom, forKey: .pursuitImageZoom)
        try container.encode(pursuitImagePanX, forKey: .pursuitImagePanX)
        try container.encode(pursuitImagePanY, forKey: .pursuitImagePanY)
        try container.encodeIfPresent(pursuitFill, forKey: .pursuitFill)
        try container.encodeIfPresent(pursuitImageFileName, forKey: .pursuitImageFileName)
        try container.encode(carouselItems, forKey: .carouselItems)
        try container.encode(carouselIndex, forKey: .carouselIndex)
        try container.encode(calendarEntries, forKey: .calendarEntries)
        try container.encode(listItems, forKey: .listItems)
        try container.encode(listMarker, forKey: .listMarker)
        try container.encode(graphTitle, forKey: .graphTitle)
        try container.encode(graphKind, forKey: .graphKind)
        try container.encode(graphXAxis, forKey: .graphXAxis)
        try container.encode(graphYAxis, forKey: .graphYAxis)
        try container.encode(graphXUnitName, forKey: .graphXUnitName)
        try container.encode(graphYUnitName, forKey: .graphYUnitName)
        try container.encode(graphPoints, forKey: .graphPoints)
        try container.encode(graphWidthScale, forKey: .graphWidthScale)
        try container.encode(graphHeightScale, forKey: .graphHeightScale)
        try container.encode(tabs, forKey: .tabs)
        try container.encodeIfPresent(selectedTabID, forKey: .selectedTabID)
        try container.encodeIfPresent(tabID, forKey: .tabID)
        try container.encode(mediaFrameAspect, forKey: .mediaFrameAspect)
        try container.encode(bannerHeight, forKey: .bannerHeight)
        try container.encode(tableColumns, forKey: .tableColumns)
        try container.encode(tableRows, forKey: .tableRows)
        try container.encode(tableEntries, forKey: .tableEntries)
        try container.encodeIfPresent(selectedTableEntryID, forKey: .selectedTableEntryID)
        try container.encode(socialPlatform, forKey: .socialPlatform)
        try container.encode(groupMembers, forKey: .groupMembers)
        try container.encode(groupWidth, forKey: .groupWidth)
        try container.encode(groupHeight, forKey: .groupHeight)
        try container.encode(scrapbookPageIDs, forKey: .scrapbookPageIDs)
        try container.encode(scrapbookIndex, forKey: .scrapbookIndex)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encodeIfPresent(drawingData, forKey: .drawingData)
        // Only drawings have a drawing area; leaving it off other pieces keeps their saved form unchanged.
        if kind == .drawing {
            try container.encode(drawingWidth, forKey: .drawingWidth)
            try container.encode(drawingHeight, forKey: .drawingHeight)
        }
        // Written only when changed, so pieces that keep the defaults save exactly as before.
        if opacity < 1 {
            try container.encode(opacity, forKey: .opacity)
        }
        if shadow != .none {
            try container.encode(shadow.rawValue, forKey: .shadow)
        }
        if shadowColor != .black {
            try container.encode(shadowColor.rawValue, forKey: .shadowColor)
        }
        if frameStyle != .none {
            try container.encode(frameStyle.rawValue, forKey: .frameStyle)
        }
        if !frameCaption.isEmpty {
            try container.encode(frameCaption, forKey: .frameCaption)
        }
        if kind == .sticker {
            try container.encode(stickerWidth, forKey: .stickerWidth)
            try container.encode(stickerHeight, forKey: .stickerHeight)
            try container.encode(stickerBorder, forKey: .stickerBorder)
        }
    }

    /// The board can still move a newer piece (ungrouping) or change its tab (deleting the tabs
    /// bar), so those two fields are written over the saved form; everything else stays as saved.
    private func preservedWithBoardChanges(_ preserved: ComposerJSONValue) -> ComposerJSONValue {
        guard case .object(var fields) = preserved else { return preserved }
        let movedFromSaved = fields["position"] != nil || position != BlockPosition(x: 0, y: 0)
        if movedFromSaved {
            fields["position"] = .object(["x": .number(position.x), "y": .number(position.y)])
        }
        if let tabID {
            fields["tabID"] = .string(tabID)
        } else {
            fields["tabID"] = nil
        }
        return .object(fields)
    }

    /// Every text value inside a newer piece. Ids of boards and media it uses are among them, so
    /// cleanup keeps those instead of treating them as unused.
    var preservedStrings: Set<String> {
        preserved?.strings ?? []
    }

    static func make(kind: BlockKind, position: BlockPosition) -> ComposerBlock {
        switch kind {
        case .group:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .group,
                text: "",
                style: .bodyDefault,
                position: position
            )
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
        case .list:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .list,
                text: "",
                style: .bodyDefault,
                position: position,
                listItems: [ComposerListItem()],
                listMarker: .bullet
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
        case .calendar:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .calendar,
                text: "",
                style: .bodyDefault,
                position: position
            )
        case .graph:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .graph,
                text: "",
                style: .bodyDefault,
                position: position,
                graphKind: .line,
                graphXAxis: .date,
                graphYAxis: .integer,
                graphXUnitName: "Date",
                graphYUnitName: "Value"
            )
        case .tabs:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .tabs,
                text: "",
                style: .bodyDefault,
                position: position,
                tabs: ComposerTabSet.defaultTabs()
            )
        case .banner:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .banner,
                text: "",
                style: TextBlockStyle(
                    size: .title,
                    color: .canvas,
                    alignment: .leading,
                    fontSize: 28,
                    isBold: true
                ),
                position: position,
                bannerHeight: ComposerBannerMetrics.defaultHeight
            )
        case .table:
            tableBlock(at: position)
        case .link:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .link,
                text: "",
                style: .bodyDefault,
                position: position,
                linkURL: ""
            )
        case .social:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .social,
                text: "",
                style: .bodyDefault,
                position: position,
                linkURL: "",
                socialPlatform: ComposerSocialPlatform.instagram.rawValue
            )
        case .node:
            newFolderBlock(kind: .node, placeholder: "Node", at: position)
        case .scrapbook:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .scrapbook,
                text: "Scrapbook",
                style: .headingDefault,
                position: position
            )
        case .pursuit:
            newFolderBlock(kind: .pursuit, placeholder: "Pursuit", at: position)
        case .drawing:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .drawing,
                text: "",
                style: .bodyDefault,
                position: position,
                drawingWidth: Double(ComposerDrawingMetrics.defaultSize.width),
                drawingHeight: Double(ComposerDrawingMetrics.defaultSize.height)
            )
        case .sticker:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .sticker,
                text: "",
                style: .bodyDefault,
                position: position,
                stickerWidth: Double(ComposerStickerArt.placedLongSide),
                stickerHeight: Double(ComposerStickerArt.placedLongSide)
            )
        case .unsupported:
            ComposerBlock(
                id: ComposerBlockID(),
                kind: .unsupported,
                text: "",
                style: .bodyDefault,
                position: position
            )
        }
    }

    private static func tableBlock(at position: BlockPosition) -> ComposerBlock {
        let rows = ComposerTable.defaultRows(columnCount: ComposerTable.defaultColumnCount)
        let entry = ComposerTableEntry(rows: rows)
        return ComposerBlock(
            id: ComposerBlockID(),
            kind: .table,
            text: "",
            style: .bodyDefault,
            position: position,
            tableColumns: ComposerTable.defaultColumns(),
            tableRows: rows,
            tableEntries: [entry],
            selectedTableEntryID: entry.id
        )
    }

    /// A folder widget, Pursuit or Node, with its name placeholder centered on the square.
    private static func newFolderBlock(kind: BlockKind, placeholder: String, at position: BlockPosition) -> ComposerBlock {
        let style = TextBlockStyle.headingDefault
        let module = PursuitWidgetShape.square.moduleSize(scale: CGFloat(style.scale))
        let font = UIFont.systemFont(ofSize: style.fontSize * style.scale, weight: .semibold)
        let textSize = (NSString(string: placeholder)).size(withAttributes: [.font: font])
        let width = max(module.width, 1)
        let height = max(module.height, 1)
        let textX = min(max(Double((width - textSize.width) / 2 / width), 0), 1)
        let textY = min(max(Double((height - textSize.height) / 2 / height), 0), 1)
        return ComposerBlock(
            id: ComposerBlockID(),
            kind: kind,
            text: "",
            style: style,
            position: position,
            pursuitID: ComposerDocumentID(),
            pursuitTextX: textX,
            pursuitTextY: textY
        )
    }
}

enum ComposerDocumentRole: String, Codable, Sendable {
    case pursuit
    case node
    case page
}

struct ComposerPursuit: Identifiable, Codable, Equatable, Sendable {
    let id: ComposerDocumentID
    var title: String
    var blocks: [ComposerBlock]
    var role: ComposerDocumentRole

    /// Vertical scale for block positions on this page. Locked so later edits do not move the others.
    var layoutHeight: Double?
    var background: ComposerBoardBackground?

    init(
        id: ComposerDocumentID,
        title: String,
        blocks: [ComposerBlock],
        role: ComposerDocumentRole = .pursuit,
        layoutHeight: Double? = nil,
        background: ComposerBoardBackground? = nil
    ) {
        self.id = id
        self.title = title
        self.blocks = blocks
        self.role = role
        self.layoutHeight = layoutHeight
        self.background = background
    }

    enum CodingKeys: String, CodingKey {
        case id, title, blocks, role, layoutHeight, background
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ComposerDocumentID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        blocks = try container.decode([ComposerBlock].self, forKey: .blocks)
        role = try container.decodeIfPresent(ComposerDocumentRole.self, forKey: .role) ?? .pursuit
        layoutHeight = try container.decodeIfPresent(Double.self, forKey: .layoutHeight)
        background = try container.decodeIfPresent(ComposerBoardBackground.self, forKey: .background)
    }
}

struct ComposerSnapshot: Codable, Equatable, Sendable {
    var mosaicTitle: String
    var mosaicBlocks: [ComposerBlock]
    var pursuits: [ComposerPursuit]
    /// True after the board title has been placed as canvas text. Deleting that text does not restore a fixed title.
    var mosaicTitlePlaced: Bool
    /// True after existing Pursuit pages were cleared to an empty composer.
    var pursuitPagesBlanked: Bool
    /// Vertical scale for block positions on the Mosaic board.
    var mosaicLayoutHeight: Double?
    var mosaicBackground: ComposerBoardBackground?
    /// "Your stickers": cutouts saved to reuse, newest first. Synced with the account, never shown to visitors.
    var stickerLibrary: [ComposerSavedSticker] = []

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
        pursuitPagesBlanked: Bool = false,
        mosaicLayoutHeight: Double? = nil,
        mosaicBackground: ComposerBoardBackground? = nil,
        stickerLibrary: [ComposerSavedSticker] = []
    ) {
        self.stickerLibrary = stickerLibrary
        self.mosaicTitle = mosaicTitle
        self.mosaicBlocks = mosaicBlocks
        self.pursuits = pursuits
        self.mosaicTitlePlaced = mosaicTitlePlaced
        self.pursuitPagesBlanked = pursuitPagesBlanked
        self.mosaicLayoutHeight = mosaicLayoutHeight
        self.mosaicBackground = mosaicBackground
    }

    enum CodingKeys: String, CodingKey {
        case mosaicTitle, mosaicBlocks, pursuits, mosaicTitlePlaced, pursuitPagesBlanked, mosaicLayoutHeight, mosaicBackground, stickerLibrary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mosaicTitle = try container.decode(String.self, forKey: .mosaicTitle)
        mosaicBlocks = try container.decode([ComposerBlock].self, forKey: .mosaicBlocks)
        pursuits = try container.decode([ComposerPursuit].self, forKey: .pursuits)
        mosaicTitlePlaced = try container.decodeIfPresent(Bool.self, forKey: .mosaicTitlePlaced) ?? false
        pursuitPagesBlanked = try container.decodeIfPresent(Bool.self, forKey: .pursuitPagesBlanked) ?? false
        mosaicLayoutHeight = try container.decodeIfPresent(Double.self, forKey: .mosaicLayoutHeight)
        mosaicBackground = try container.decodeIfPresent(ComposerBoardBackground.self, forKey: .mosaicBackground)
        stickerLibrary = ComposerSavedSticker.lenientList(from: container, forKey: .stickerLibrary)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mosaicTitle, forKey: .mosaicTitle)
        try container.encode(mosaicBlocks, forKey: .mosaicBlocks)
        try container.encode(pursuits, forKey: .pursuits)
        try container.encode(mosaicTitlePlaced, forKey: .mosaicTitlePlaced)
        try container.encode(pursuitPagesBlanked, forKey: .pursuitPagesBlanked)
        try container.encodeIfPresent(mosaicLayoutHeight, forKey: .mosaicLayoutHeight)
        try container.encodeIfPresent(mosaicBackground, forKey: .mosaicBackground)
        if !stickerLibrary.isEmpty {
            try container.encode(stickerLibrary, forKey: .stickerLibrary)
        }
    }
}

/// A cutout saved to "Your stickers".
struct ComposerSavedSticker: Codable, Equatable, Identifiable, Sendable {
    var fileName: String
    /// The sticker's starting size on a board, in points.
    var width: Double
    var height: Double

    var id: String { fileName }

    /// Kept short so the list stays a small part of the Mosaic board's saved data.
    static let limit = 200

    /// Entries that can't be read are skipped one by one, so a single bad entry can't empty the
    /// list (which would then sync as empty).
    static func lenientList<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) -> [ComposerSavedSticker] {
        guard let entries = try? container.decodeIfPresent([LenientEntry].self, forKey: key) else { return [] }
        return entries.compactMap(\.sticker)
    }

    private struct LenientEntry: Decodable {
        let sticker: ComposerSavedSticker?

        init(from decoder: Decoder) throws {
            sticker = try? ComposerSavedSticker(from: decoder)
        }
    }
}

extension ComposerBlock {
    /// The widget's name, or, when the name was cleared, its highest text item, on one line.
    /// The widget keeps its line breaks; this is the title used everywhere else and synced.
    var pursuitDisplayName: String {
        let name = ComposerTitle.singleLine(text)
        if !name.isEmpty { return name }
        return pursuitTexts
            .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            .lazy
            .map { ComposerTitle.singleLine($0.text) }
            .first { !$0.isEmpty } ?? ""
    }
}

/// A drop shadow under a piece, for depth.
enum ComposerPieceShadow: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case soft
    case lifted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .soft: "Soft"
        case .lifted: "Lifted"
        }
    }
}

/// Decoration around a photo or video. The crop shape (rounded, circle) is separate: `mediaShape`.
enum ComposerFrameStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case polaroid
    case tape
    case torn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .polaroid: "Polaroid"
        case .tape: "Tape"
        case .torn: "Torn"
        }
    }

    static let captionLimit = 40
}

/// Black reads as depth on light boards; white reads as a glow on dark ones.
enum ComposerShadowColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case black
    case white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: "Black"
        case .white: "White"
        }
    }
}

enum ComposerPieceLook {
    /// Never fully invisible, so a faded piece can still be found and selected.
    static let minimumOpacity = 0.1

    static func clampedOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, minimumOpacity), 1)
    }
}

/// Any JSON value, kept as decoded so it can be written back unchanged.
nonisolated enum ComposerJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ComposerJSONValue])
    case object([String: ComposerJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ComposerJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: ComposerJSONValue].self))
        }
    }

    var strings: Set<String> {
        switch self {
        case .string(let value): [value]
        case .array(let values): values.reduce(into: []) { $0.formUnion($1.strings) }
        case .object(let fields): fields.values.reduce(into: []) { $0.formUnion($1.strings) }
        case .null, .bool, .number: []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

enum ComposerTitle {
    /// A title on one line with single spaces. Lines of one character each were a word written
    /// downward, so they join without spaces; other lines join with a space.
    nonisolated static func singleLine(_ raw: String) -> String {
        let lines = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
        let separator = lines.count > 1 && lines.allSatisfy({ $0.count == 1 }) ? "" : " "
        return lines.joined(separator: separator)
    }
}

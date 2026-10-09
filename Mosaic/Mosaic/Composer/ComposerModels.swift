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
    case tabs
    case banner
    case table
    case social
    case pursuit
}

enum BlockMenuOption: String, CaseIterable, Identifiable {
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
    case tabs
    case banner
    case table
    case social
    case pursuit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .group: "Group"
        case .text: "Text"
        case .heading: "Heading"
        case .list: "List"
        case .media: "Media"
        case .carousel: "Carousel"
        case .calendar: "Calendar"
        case .graph: "Graph"
        case .link: "Link"
        case .node: "Node"
        case .tabs: "Tabs"
        case .banner: "Banner"
        case .table: "Table"
        case .social: "Socials"
        case .pursuit: "Pursuit"
        }
    }

    var systemImage: String {
        switch self {
        case .group: "square.on.square"
        case .text: "textformat"
        case .heading: "textformat.size.larger"
        case .list: "list.bullet"
        case .media: "photo"
        case .carousel: "rectangle.stack"
        case .calendar: "calendar"
        case .graph: "chart.xyaxis.line"
        case .link: "link"
        case .node: "folder"
        case .tabs: "rectangle.split.3x1"
        case .banner: "rectangle.topthird.inset.filled"
        case .table: "tablecells"
        case .social: "at"
        case .pursuit: "square.grid.2x2"
        }
    }

    var placementLabel: String {
        switch self {
        case .group: "G"
        case .text: "T"
        case .heading: "H"
        case .list: "•"
        case .media: "▣"
        case .carousel: "◎"
        case .calendar: "▦"
        case .graph: "↗"
        case .link: "🔗"
        case .node: "N"
        case .tabs: "☰"
        case .banner: "B"
        case .table: "⊞"
        case .social: "@"
        case .pursuit: "P"
        }
    }

    var blockKind: BlockKind {
        switch self {
        case .group: .group
        case .text: .text
        case .heading: .heading
        case .list: .list
        case .media: .media
        case .carousel: .carousel
        case .calendar: .calendar
        case .graph: .graph
        case .link: .link
        case .node: .node
        case .tabs: .tabs
        case .banner: .banner
        case .table: .table
        case .social: .social
        case .pursuit: .pursuit
        }
    }

    /// Lowercased tokens for add-menu search (extend as options grow).
    var searchTokens: String {
        switch self {
        case .text: "text paragraph write"
        case .heading: "heading title headline"
        case .list: "list bullet number numbered checkbox todo task dash letter"
        case .media: "media photo image picture"
        case .carousel: "carousel carosoul slider"
        case .calendar: "calendar date day month year schedule"
        case .graph: "graph chart line plot axis"
        case .link: "link url web"
        case .group: "group selection multi select cluster"
        case .node: "node folder organize"
        case .tabs: "tabs tab set"
        case .banner: "banner header cover"
        case .table: "table spreadsheet grid columns rows"
        case .social: "social instagram tiktok twitter youtube twitch"
        case .pursuit: "pursuit project goal"
        }
    }

    static func menuOptions(
        matching query: String,
        includingPursuit: Bool = true,
        includingCalendar: Bool = true,
        includingGraph: Bool = true,
        includingNode: Bool = true,
        includingTabs: Bool = true,
        includingBanner: Bool = true,
        includingTable: Bool = true
    ) -> [BlockMenuOption] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var ordered = Array(allCases.reversed())
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
        if !includingTabs {
            ordered.removeAll { $0 == .tabs }
        }
        if !includingBanner {
            ordered.removeAll { $0 == .banner }
        }
        if !includingTable {
            ordered.removeAll { $0 == .table }
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

struct CalendarDayEntry: Codable, Equatable, Identifiable, Sendable {
    var year: Int
    var month: Int
    var day: Int
    var note: String
    var media: [CarouselMediaItem]
    var mediaIndex: Int

    var id: String { String(format: "%04d-%02d-%02d", year, month, day) }

    var hasContent: Bool {
        media.contains { !$0.fileName.isEmpty } || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        let minY = ordered.map(\.y).min() ?? 0
        let maxY = ordered.map(\.y).max() ?? 0
        let xSpan = maxX - minX
        let ySpan = maxY - minY
        return ordered.map { point in
            let nx: CGFloat = xSpan == 0 ? 0.5 : CGFloat((point.x.timeIntervalSinceReferenceDate - minX) / xSpan)
            let ny: CGFloat = ySpan == 0 ? 0.5 : CGFloat(Double(point.y - minY) / Double(ySpan))
            return Placed(id: point.id, nx: nx, ny: ny)
        }
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
        let bounds = UIScreen.main.bounds
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

    enum CodingKeys: String, CodingKey {
        case id, kind, text, style, position, mediaFileName, mediaShape, mediaWarp, mediaZoom, mediaPanX, mediaPanY, linkURL, pursuitID, pursuitShape, pursuitLayout, pursuitTextX, pursuitTextY, pursuitTexts, pursuitImageZoom, pursuitImagePanX, pursuitImagePanY, pursuitFill, pursuitImageFileName, carouselItems, carouselIndex, calendarEntries, listItems, listMarker, graphTitle, graphKind, graphXAxis, graphYAxis, graphXUnitName, graphYUnitName, graphPoints, graphWidthScale, graphHeightScale, tabs, selectedTabID, tabID, mediaFrameAspect, bannerHeight, tableColumns, tableRows, tableEntries, selectedTableEntryID, socialPlatform, groupMembers, groupWidth, groupHeight
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
        groupHeight: Double = 0
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
        if kind == .table {
            ComposerTable.ensure(&self)
        }
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
        case .pursuit:
            newFolderBlock(kind: .pursuit, placeholder: "Pursuit", at: position)
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
}

struct ComposerPursuit: Identifiable, Codable, Equatable, Sendable {
    let id: ComposerDocumentID
    var title: String
    var blocks: [ComposerBlock]
    var role: ComposerDocumentRole

    /// Vertical scale for block positions on this page. Locked so later edits do not move the others.
    var layoutHeight: Double?

    init(
        id: ComposerDocumentID,
        title: String,
        blocks: [ComposerBlock],
        role: ComposerDocumentRole = .pursuit,
        layoutHeight: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.blocks = blocks
        self.role = role
        self.layoutHeight = layoutHeight
    }

    enum CodingKeys: String, CodingKey {
        case id, title, blocks, role, layoutHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ComposerDocumentID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        blocks = try container.decode([ComposerBlock].self, forKey: .blocks)
        role = try container.decodeIfPresent(ComposerDocumentRole.self, forKey: .role) ?? .pursuit
        layoutHeight = try container.decodeIfPresent(Double.self, forKey: .layoutHeight)
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
        mosaicLayoutHeight: Double? = nil
    ) {
        self.mosaicTitle = mosaicTitle
        self.mosaicBlocks = mosaicBlocks
        self.pursuits = pursuits
        self.mosaicTitlePlaced = mosaicTitlePlaced
        self.pursuitPagesBlanked = pursuitPagesBlanked
        self.mosaicLayoutHeight = mosaicLayoutHeight
    }

    enum CodingKeys: String, CodingKey {
        case mosaicTitle, mosaicBlocks, pursuits, mosaicTitlePlaced, pursuitPagesBlanked, mosaicLayoutHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mosaicTitle = try container.decode(String.self, forKey: .mosaicTitle)
        mosaicBlocks = try container.decode([ComposerBlock].self, forKey: .mosaicBlocks)
        pursuits = try container.decode([ComposerPursuit].self, forKey: .pursuits)
        mosaicTitlePlaced = try container.decodeIfPresent(Bool.self, forKey: .mosaicTitlePlaced) ?? false
        pursuitPagesBlanked = try container.decodeIfPresent(Bool.self, forKey: .pursuitPagesBlanked) ?? false
        mosaicLayoutHeight = try container.decodeIfPresent(Double.self, forKey: .mosaicLayoutHeight)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mosaicTitle, forKey: .mosaicTitle)
        try container.encode(mosaicBlocks, forKey: .mosaicBlocks)
        try container.encode(pursuits, forKey: .pursuits)
        try container.encode(mosaicTitlePlaced, forKey: .mosaicTitlePlaced)
        try container.encode(pursuitPagesBlanked, forKey: .pursuitPagesBlanked)
        try container.encodeIfPresent(mosaicLayoutHeight, forKey: .mosaicLayoutHeight)
    }
}

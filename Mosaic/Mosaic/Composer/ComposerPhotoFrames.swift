import SwiftUI

/// Polaroid, tape, and torn-paper frames around a photo or video on the board. Every style uses
/// the same layout (padding, paper, caption, tape) with different sizes, so switching styles
/// doesn't rebuild the media: a playing video keeps playing.
struct ComposerPhotoFrameModifier: ViewModifier {
    var style: ComposerFrameStyle
    var caption: String
    /// Keeps a torn edge the same every time this piece is drawn.
    var seed: UInt64
    /// The media's width, which every part of the frame is proportioned to.
    var width: CGFloat

    static let paper = Color(red: 0.985, green: 0.98, blue: 0.965)
    static let tape = Color(red: 0.95, green: 0.91, blue: 0.78)

    struct Insets: Equatable {
        var top: CGFloat
        var side: CGFloat
        var bottom: CGFloat
    }

    static func insets(for style: ComposerFrameStyle, width: CGFloat) -> Insets {
        switch style {
        case .none, .tape: Insets(top: 0, side: 0, bottom: 0)
        case .polaroid: Insets(top: width * 0.055, side: width * 0.055, bottom: width * 0.24)
        case .torn: Insets(top: width * 0.05, side: width * 0.05, bottom: width * 0.05)
        }
    }

    func body(content: Content) -> some View {
        let insets = Self.insets(for: style, width: width)
        let showsPaper = style == .polaroid || style == .torn
        content
            .padding(EdgeInsets(top: insets.top, leading: insets.side, bottom: insets.bottom, trailing: insets.side))
            .background {
                ComposerTornPaperShape(seed: seed, roughness: style == .torn ? width * 0.014 : 0, step: max(width * 0.035, 6))
                    .fill(Self.paper.opacity(showsPaper ? 1 : 0))
            }
            .overlay(alignment: .bottom) {
                Text(style == .polaroid ? caption : "")
                    .font(.custom("Noteworthy-Bold", size: max(width * 0.075, 9)))
                    .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.22))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: max(width, 1), height: max(insets.bottom, 1))
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                let strip = CGSize(width: width * 0.32, height: width * 0.09)
                let shown = style == .tape
                HStack {
                    tapeStrip(strip).rotationEffect(.degrees(-32))
                    Spacer(minLength: 0)
                    tapeStrip(strip).rotationEffect(.degrees(32))
                }
                .frame(width: width * 1.12)
                .offset(y: -strip.height * 0.15)
                .opacity(shown ? 1 : 0)
                .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.2), value: style)
    }

    private func tapeStrip(_ size: CGSize) -> some View {
        Rectangle()
            .fill(Self.tape.opacity(0.78))
            .overlay(Rectangle().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
            .frame(width: max(size.width, 1), height: max(size.height, 1))
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
    }

    /// Where the photo itself sits inside a framed piece measured at `padded` size. The frame's
    /// padding grows with the photo's width, so that width is solved from the padded one.
    static func mediaFrame(inPadded padded: CGSize, style: ComposerFrameStyle) -> CGRect {
        let perPoint = insets(for: style, width: 1)
        let width = padded.width / (1 + 2 * perPoint.side)
        let inset = insets(for: style, width: width)
        return CGRect(
            x: inset.side,
            y: inset.top,
            width: max(width, 1),
            height: max(padded.height - inset.top - inset.bottom, 1)
        )
    }

    /// Stable across launches, unlike `hashValue`, so a torn edge never changes.
    static func seed(for id: ComposerBlockID) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in id.rawValue.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// A rectangle whose edges are torn: points every `step` along each side, each pulled inward by
/// up to `roughness`. With no roughness it's a plain rectangle.
struct ComposerTornPaperShape: Shape {
    var seed: UInt64
    var roughness: CGFloat
    var step: CGFloat

    var animatableData: CGFloat {
        get { roughness }
        set { roughness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard roughness > 0.1, rect.width > 1, rect.height > 1 else { return Path(rect) }
        var generator = SplitMix64(seed: seed)
        var points: [CGPoint] = []
        func edge(from start: CGPoint, to end: CGPoint, inward: CGVector) {
            let length = hypot(end.x - start.x, end.y - start.y)
            let count = max(Int(length / step), 2)
            for index in 0..<count {
                let t = CGFloat(index) / CGFloat(count)
                let depth = roughness * CGFloat(generator.nextUnit())
                points.append(CGPoint(
                    x: start.x + (end.x - start.x) * t + inward.dx * depth,
                    y: start.y + (end.y - start.y) * t + inward.dy * depth
                ))
            }
        }
        edge(from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.minY), inward: CGVector(dx: 0, dy: 1))
        edge(from: CGPoint(x: rect.maxX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY), inward: CGVector(dx: -1, dy: 0))
        edge(from: CGPoint(x: rect.maxX, y: rect.maxY), to: CGPoint(x: rect.minX, y: rect.maxY), inward: CGVector(dx: 0, dy: -1))
        edge(from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.minX, y: rect.minY), inward: CGVector(dx: 1, dy: 0))
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

/// A small seeded random number generator, so the same seed always gives the same tear.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }

    /// 0…1.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

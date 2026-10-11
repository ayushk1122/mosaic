import SwiftUI

enum ComposerResizeCorner: Equatable, Hashable, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: Self { self }

    var movesLeading: Bool { self == .topLeft || self == .bottomLeft }
    var movesTop: Bool { self == .topLeft || self == .topRight }

    /// The corner that stays put while this one is dragged.
    var anchor: UnitPoint {
        switch self {
        case .topLeft: .bottomTrailing
        case .topRight: .bottomLeading
        case .bottomLeft: .topTrailing
        case .bottomRight: .topLeading
        }
    }

    /// Positive values mean the box should grow.
    func signedGrowth(_ translation: CGSize) -> CGSize {
        switch self {
        case .bottomRight:
            CGSize(width: translation.width, height: translation.height)
        case .topLeft:
            CGSize(width: -translation.width, height: -translation.height)
        case .topRight:
            CGSize(width: translation.width, height: -translation.height)
        case .bottomLeft:
            CGSize(width: -translation.width, height: translation.height)
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: movesLeading ? rect.minX : rect.maxX,
            y: movesTop ? rect.minY : rect.maxY
        )
    }
}

struct ComposerResizeCornerFrames: Equatable {
    var topLeft = CGRect.zero
    var topRight = CGRect.zero
    var bottomLeft = CGRect.zero
    var bottomRight = CGRect.zero

    func contains(_ point: CGPoint) -> Bool {
        [topLeft, topRight, bottomLeft, bottomRight].contains { frame in
            frame.width > 1 && frame.insetBy(dx: -8, dy: -8).contains(point)
        }
    }

    mutating func update(_ corner: ComposerResizeCorner, to frame: CGRect) {
        switch corner {
        case .topLeft where topLeft != frame: topLeft = frame
        case .topRight where topRight != frame: topRight = frame
        case .bottomLeft where bottomLeft != frame: bottomLeft = frame
        case .bottomRight where bottomRight != frame: bottomRight = frame
        default: break
        }
    }
}

struct ComposerResizeCornerFrameKey: PreferenceKey {
    static var defaultValue: [ComposerBlockID: ComposerResizeCornerFrames] = [:]

    static func reduce(
        value: inout [ComposerBlockID: ComposerResizeCornerFrames],
        nextValue: () -> [ComposerBlockID: ComposerResizeCornerFrames]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct ComposerResizePreview: Equatable {
    var blockID: ComposerBlockID
    var corner: ComposerResizeCorner
    var scaleX: CGFloat
    var scaleY: CGFloat
    var frame: CGRect
}

/// A selection box with a dot on each corner. The dots stay under the finger while the box follows the drag.
struct ComposerResizeChrome: View {
    var blockID: ComposerBlockID
    var layout: CGSize
    var scaleX: CGFloat
    var scaleY: CGFloat
    var anchor: UnitPoint
    var onChanged: (ComposerResizeCorner, CGSize) -> Void
    var onEnded: (ComposerResizeCorner, CGSize) -> Void

    @State private var cornerFrames = ComposerResizeCornerFrames()

    var body: some View {
        let bounds = CGRect(origin: .zero, size: layout)
        let rect = Self.liveRect(layout: layout, scaleX: scaleX, scaleY: scaleY, anchor: anchor)
        ZStack {
            Rectangle()
                .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
            ForEach(ComposerResizeCorner.allCases) { corner in
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1))
                    .frame(width: 14, height: 14)
                    .position(corner.point(in: rect))
                    .allowsHitTesting(false)
                ComposerCornerCatcher(
                    onChanged: { onChanged(corner, $0) },
                    onEnded: { onEnded(corner, $0) }
                )
                .frame(width: 44, height: 44)
                .position(corner.point(in: bounds))
                .onGeometryChange(for: CGRect.self) { item in
                    item.frame(in: .named("composerRoot"))
                } action: { frame in
                    guard frame.width.isFinite, frame.height.isFinite, frame.width > 1, frame.height > 1 else { return }
                    let current: CGRect
                    switch corner {
                    case .topLeft: current = cornerFrames.topLeft
                    case .topRight: current = cornerFrames.topRight
                    case .bottomLeft: current = cornerFrames.bottomLeft
                    case .bottomRight: current = cornerFrames.bottomRight
                    }
                    guard abs(current.minX - frame.minX) > 0.5
                        || abs(current.minY - frame.minY) > 0.5
                        || abs(current.width - frame.width) > 0.5 else { return }
                    cornerFrames.update(corner, to: frame)
                }
            }
        }
        .frame(width: max(layout.width, 1), height: max(layout.height, 1))
        .preference(key: ComposerResizeCornerFrameKey.self, value: [blockID: cornerFrames])
        .accessibilityElement(children: .contain)
    }

    static func liveRect(layout: CGSize, scaleX: CGFloat, scaleY: CGFloat, anchor: UnitPoint) -> CGRect {
        let safeX = scaleX.isFinite ? scaleX : 1
        let safeY = scaleY.isFinite ? scaleY : 1
        let width = max(layout.width * safeX, 1)
        let height = max(layout.height * safeY, 1)
        let originX = anchor.x * layout.width - anchor.x * width
        let originY = anchor.y * layout.height - anchor.y * height
        return CGRect(x: originX, y: originY, width: width, height: height)
    }
}

enum ComposerResizeMath {
    /// Uniform scale from the corner that stays put to the finger, so the box grows smoothly.
    static func uniformScale(frame: CGRect, corner: ComposerResizeCorner, translation: CGSize) -> CGFloat {
        let anchor = corner.anchor
        let fixed = CGPoint(
            x: frame.minX + anchor.x * frame.width,
            y: frame.minY + anchor.y * frame.height
        )
        let start = corner.point(in: frame)
        let finger = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
        let base = hypot(start.x - fixed.x, start.y - fixed.y)
        let next = hypot(finger.x - fixed.x, finger.y - fixed.y)
        guard base > 1, next.isFinite else { return 1 }
        return min(max(next / base, 0.2), 5)
    }
}

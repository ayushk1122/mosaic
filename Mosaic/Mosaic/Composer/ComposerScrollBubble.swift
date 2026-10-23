import SwiftUI
import UIKit

/// Where the board is scrolled, and how far it can go.
struct ComposerScrollBubbleMetrics: Equatable, Sendable {
    var offset: CGFloat = 0
    var minOffset: CGFloat = 0
    var maxOffset: CGFloat = 0
    var containerHeight: CGFloat = 0
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    init(offset: CGFloat = 0, minOffset: CGFloat = 0, maxOffset: CGFloat = 0) {
        self.offset = offset
        self.minOffset = minOffset
        self.maxOffset = maxOffset
    }

    init(_ geometry: ScrollGeometry) {
        offset = geometry.contentOffset.y
        minOffset = -geometry.contentInsets.top
        maxOffset = max(
            geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height,
            minOffset
        )
        containerHeight = geometry.containerSize.height
        topInset = geometry.contentInsets.top
        bottomInset = geometry.contentInsets.bottom
    }

    /// The part of the board on screen, in the board's own coordinates. Nil before the first layout.
    func visibleContentRect(width: CGFloat) -> CGRect? {
        guard containerHeight > 1, width > 1 else { return nil }
        let top = offset + topInset
        return CGRect(x: 0, y: top, width: width, height: max(containerHeight - topInset - bottomInset, 1))
    }

    /// A board that fits on screen has nothing to scroll.
    var isScrollable: Bool { maxOffset - minOffset > 1 }

    var progress: CGFloat {
        guard isScrollable else { return 0 }
        return min(max((offset - minOffset) / (maxOffset - minOffset), 0), 1)
    }

    func offset(forProgress progress: CGFloat) -> CGFloat {
        minOffset + min(max(progress, 0), 1) * (maxOffset - minOffset)
    }

    /// Top of the bubble within a track `track` tall.
    static func bubbleTop(progress: CGFloat, track: CGFloat, bubble: CGFloat) -> CGFloat {
        min(max(progress, 0), 1) * max(track - bubble, 0)
    }
}

/// The part of the board that floating controls must stay inside.
struct ComposerVisibleArea: Equatable {
    var width: CGFloat
    var isViewing: Bool
    var isBookPage: Bool

    /// The on-screen board in board coordinates, less the bottom row of buttons while editing.
    func rect(_ metrics: ComposerScrollBubbleMetrics) -> CGRect? {
        guard var rect = metrics.visibleContentRect(width: width) else { return nil }
        if !isViewing {
            rect.size.height = max(rect.height - (ComposerAddMenuMetrics.button + 28), 1)
        }
        // A journal page's top corners turn the page and take touches, so controls stay below them.
        if isBookPage {
            rect.origin.y += ScrapbookMetrics.turnCorner
            rect.size.height = max(rect.height - ScrapbookMetrics.turnCorner, 1)
        }
        return rect
    }
}

/// Offsets a floating control from its piece's top-left so it stays on screen. It reads the scroll
/// position here rather than in the board, so scrolling moves the control without redrawing the board.
struct ComposerFloatingPlacement: ViewModifier {
    var rail: ComposerScrollBubbleRail
    var area: ComposerVisibleArea
    var frame: CGRect?
    var size: CGSize
    var gap: CGFloat
    var anchorY: CGFloat?
    var trailing: Bool

    func body(content: Content) -> some View {
        content.offset(offset)
    }

    private var offset: CGSize {
        guard let frame, frame.width > 1, let visible = area.rect(rail.metrics) else {
            let x = trailing ? (frame?.width ?? size.width) - size.width : 0
            return CGSize(width: x, height: -(size.height + gap))
        }
        // Trailing controls center over a strip at the piece's right edge, so they line up with it.
        let around = trailing
            ? CGRect(x: frame.maxX - size.width, y: frame.minY, width: size.width, height: frame.height)
            : frame
        let placement = ComposerChromePlacement.floating(
            size: size,
            around: around,
            visible: visible,
            gap: gap,
            anchorY: anchorY
        )
        return CGSize(width: placement.origin.x - frame.minX, height: placement.origin.y - frame.minY)
    }
}

/// Moves the rotate handle below its piece when its spot above would be off screen. Watches the
/// scroll position on the board's behalf and reports only when the side changes.
struct ComposerRotateHandleSide: View {
    var rail: ComposerScrollBubbleRail
    var area: ComposerVisibleArea
    var rotation: Double
    var frame: CGRect
    var lift: CGFloat
    @Binding var below: Bool

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: goesBelow, initial: true) { _, value in
                if below != value { below = value }
            }
    }

    private var goesBelow: Bool {
        guard let visible = area.rect(rail.metrics) else { return false }
        let radians = rotation * .pi / 180
        let reach = frame.height / 2 + lift
        let handle = CGPoint(
            x: frame.midX + reach * CGFloat(sin(radians)),
            y: frame.midY - reach * CGFloat(cos(radians))
        )
        return !visible.insetBy(dx: 22, dy: 22).contains(handle)
    }
}

/// Shared by the board's scroll view and the bubble, so only the bubble redraws as the board scrolls.
@MainActor
@Observable
final class ComposerScrollBubbleRail {
    var metrics = ComposerScrollBubbleMetrics()
    @ObservationIgnored weak var scroll: UIScrollView?
    /// The scroll view whose pan `begin()` turned off, so `finish()` turns that same one back on
    /// even if the board's scroll view was replaced mid-drag.
    @ObservationIgnored private weak var heldScroll: UIScrollView?

    /// The board's own pan would also follow the finger and pull the other way.
    func begin() {
        heldScroll = scroll
        scroll?.panGestureRecognizer.isEnabled = false
    }

    /// Moves the board directly, the way the drag-to-scroll follower does, so the board doesn't rebuild each step.
    func scroll(toProgress progress: CGFloat) {
        guard let scroll else { return }
        let y = metrics.offset(forProgress: progress)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: false)
        CATransaction.commit()
    }

    /// Glides the board so a spot on it sits in the middle of the screen, as far as the board allows.
    func glide(toCenter y: CGFloat) {
        guard let scroll else { return }
        let visible = max(metrics.containerHeight - metrics.topInset - metrics.bottomInset, 1)
        let offset = min(max(y - metrics.topInset - visible / 2, metrics.minOffset), metrics.maxOffset)
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: true)
    }

    /// Gives the board its own pan back. The offset isn't handed to SwiftUI's scroll position:
    /// SwiftUI follows the scroll view's offset itself, and its scroll position clamps short of
    /// the bottom, which jumped the board back up when the bubble was let go.
    func finish() {
        heldScroll?.panGestureRecognizer.isEnabled = true
        scroll?.panGestureRecognizer.isEnabled = true
        heldScroll = nil
    }
}

/// The small bubble on the right edge in edit mode. Hold and drag it to move through a long board.
struct ComposerScrollBubble: View {
    var rail: ComposerScrollBubbleRail

    @State private var held = false
    /// Where on the bubble the finger landed, so the bubble doesn't jump to center under it.
    @State private var grab: CGFloat = 0
    /// Resets on its own when the drag is cancelled, which `onEnded` doesn't report.
    @GestureState private var dragging = false

    private let bubbleHeight = ComposerAddMenuMetrics.topControl
    private let trackSpace = "composer.scrollBubbleTrack"

    var body: some View {
        if rail.metrics.isScrollable {
            track
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let track = proxy.size.height
            let top = ComposerScrollBubbleMetrics.bubbleTop(
                progress: rail.metrics.progress,
                track: track,
                bubble: bubbleHeight
            )
            bubble
                .frame(width: 36, height: bubbleHeight + 20)
                .contentShape(Rectangle())
                .offset(x: proxy.size.width - 36, y: top - 10)
                .gesture(
                    // Measured against the still track: the bubble itself moves under the finger.
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(trackSpace))
                        .updating($dragging) { _, active, _ in active = true }
                        .onChanged { value in
                            if !held {
                                held = true
                                grab = value.startLocation.y - top
                                rail.begin()
                            }
                            rail.scroll(toProgress: (value.location.y - grab) / max(track - bubbleHeight, 1))
                        }
                        .onEnded { value in
                            if held {
                                rail.scroll(toProgress: (value.location.y - grab) / max(track - bubbleHeight, 1))
                            }
                            held = false
                            rail.finish()
                        }
                )
                // On the bubble rather than the whole track, so VoiceOver's box is the control itself.
                .accessibilityElement()
                .accessibilityLabel("Scroll board")
                .accessibilityValue("\(Int((rail.metrics.progress * 100).rounded())) percent")
                .accessibilityAdjustableAction { direction in
                    let step: CGFloat = direction == .increment ? 0.1 : -0.1
                    rail.scroll(toProgress: rail.metrics.progress + step)
                    rail.finish()
                }
                .accessibilityIdentifier("composer.scrollBubble")
        }
        .coordinateSpace(name: trackSpace)
        .onChange(of: dragging) { _, active in
            if !active { release() }
        }
        .onDisappear { release() }
    }

    /// The board's own pan stays off while held, so an interrupted hold must hand it back.
    private func release() {
        guard held else { return }
        held = false
        rail.finish()
    }

    /// One grey bubble that brightens and swells on a soft spring while held.
    private var bubble: some View {
        Capsule()
            .fill(Color(white: held ? 0.86 : 0.62).opacity(held ? 0.95 : 0.7))
            .frame(width: 18, height: bubbleHeight)
            .scaleEffect(x: held ? 1.35 : 1, y: held ? 1.12 : 1)
            .shadow(color: .black.opacity(held ? 0.28 : 0.18), radius: held ? 6 : 3, y: 2)
            .animation(.spring(response: 0.32, dampingFraction: 0.5), value: held)
    }
}

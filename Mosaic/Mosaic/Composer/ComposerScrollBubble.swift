import SwiftUI
import UIKit

/// Where the board is scrolled, and how far it can go.
struct ComposerScrollBubbleMetrics: Equatable, Sendable {
    var offset: CGFloat = 0
    var minOffset: CGFloat = 0
    var maxOffset: CGFloat = 0

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

/// Shared by the board's scroll view and the bubble, so only the bubble redraws as the board scrolls.
@MainActor
@Observable
final class ComposerScrollBubbleRail {
    var metrics = ComposerScrollBubbleMetrics()
    @ObservationIgnored weak var scroll: UIScrollView?

    /// The board's own pan would also follow the finger and pull the other way.
    func begin() {
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

    /// Hands the final offset back to SwiftUI's scroll position.
    func finish() {
        guard let scroll else { return }
        scroll.panGestureRecognizer.isEnabled = true
        ComposerCanvasScrollMark.report(scroll, offset: scroll.contentOffset.y)
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
        }
        .coordinateSpace(name: trackSpace)
        .onChange(of: dragging) { _, active in
            if !active { release() }
        }
        .onDisappear { release() }
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

/// Finds the board's scroll view for the bubble. It sits beside the scroll view, so the nearest tagged one is this board's.
struct ComposerScrollBubbleFinder: UIViewRepresentable {
    var rail: ComposerScrollBubbleRail

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: FinderView, context: Context) {
        uiView.rail = rail
        uiView.resolve()
    }

    final class FinderView: UIView {
        weak var rail: ComposerScrollBubbleRail?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            resolve()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            resolve()
        }

        func resolve() {
            guard let rail, rail.scroll?.window == nil else { return }
            var ancestor: UIView? = superview
            var depth = 0
            while let view = ancestor, depth < 16 {
                if let found = view.firstTaggedCanvasScroll() {
                    rail.scroll = found
                    return
                }
                ancestor = view.superview
                depth += 1
            }
        }
    }
}

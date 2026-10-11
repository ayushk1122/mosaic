import SwiftUI
import UIKit

/// Shared with the edge-follow scroller while a component is being dragged.
final class ComposerDragScrollRelay {
    var active = false
    var fingerY: CGFloat = -1
    var viewportMinY: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var boost: CGFloat = 0
    /// Dragged piece edges in canvas content space, without the follow boost.
    var tracksItem = false
    var itemMinY: CGFloat = 0
    var itemMaxY: CGFloat = 0
    var dragDeltaY: CGFloat = 0
    var dragDeltaTime = Date.distantPast
}

/// Scrolls the page when a dragged component reaches the top or bottom of the screen.
struct ComposerDragScrollDriver: UIViewRepresentable {
    var relay: ComposerDragScrollRelay
    @Binding var boost: CGFloat
    var onOffset: (CGFloat) -> Void
    var onNeedRoom: () -> Void

    func makeUIView(context: Context) -> ComposerDragScrollDriverView {
        let view = ComposerDragScrollDriverView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: ComposerDragScrollDriverView, context: Context) {
        uiView.relay = relay
        uiView.onBoost = { boost = $0 }
        uiView.onOffset = onOffset
        uiView.onNeedRoom = onNeedRoom
        uiView.sync()
    }
}

final class ComposerDragScrollDriverView: UIView {
    weak var relay: ComposerDragScrollRelay?
    var onBoost: (CGFloat) -> Void = { _ in }
    var onOffset: (CGFloat) -> Void = { _ in }
    var onNeedRoom: () -> Void = {}
    private var displayLink: CADisplayLink?
    private weak var scroll: UIScrollView?
    private var lastRoomRequest = Date.distantPast
    private var intendedOffset: CGFloat?
    private var applyingOffset = false

    func sync() {
        if relay?.active == true {
            start()
        } else {
            stop()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() }
    }

    private func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
        intendedOffset = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !applyingOffset, let intendedOffset, relay?.active == true, let scroll = resolvedScroll() else { return }
        guard abs(scroll.contentOffset.y - intendedOffset) > 0.5 else { return }
        applyingOffset = true
        scroll.setContentOffset(CGPoint(x: 0, y: intendedOffset), animated: false)
        applyingOffset = false
    }

    @objc private func step() {
        followIfNeeded()
    }

    private func followIfNeeded() {
        guard let relay, relay.active else {
            stop()
            return
        }
        guard let scroll = resolvedScroll() else { return }
        let height = scroll.bounds.height
        guard height > 1 else { return }
        let zone: CGFloat = 72
        let maxSpeed: CGFloat = 16
        let y = relay.fingerY
        var delta: CGFloat = 0
        if y >= 0, y < zone {
            delta = -maxSpeed * (1 - y / zone)
        } else if y > height - zone {
            delta = maxSpeed * min(max(y - (height - zone), 0) / zone, 1)
        } else if relay.tracksItem, Date().timeIntervalSince(relay.dragDeltaTime) < 0.12 {
            let visualTop = relay.itemMinY + relay.boost - scroll.contentOffset.y
            let visualBottom = relay.itemMaxY + relay.boost - scroll.contentOffset.y
            if relay.dragDeltaY < -0.4, visualTop < zone {
                delta = -maxSpeed * min((zone - visualTop) / zone, 1)
            } else if relay.dragDeltaY > 0.4, visualBottom > height - zone {
                delta = maxSpeed * min((visualBottom - (height - zone)) / zone, 1)
            }
        }
        guard abs(delta) > 0.2 else { return }
        let maxOffset = max(scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom, 0)
        if delta > 0, maxOffset - scroll.contentOffset.y < 48, Date().timeIntervalSince(lastRoomRequest) > 0.2 {
            lastRoomRequest = Date()
            onNeedRoom()
        }
        let next = min(max(scroll.contentOffset.y + delta, -scroll.adjustedContentInset.top), maxOffset)
        let applied = next - scroll.contentOffset.y
        guard abs(applied) > 0.05 else { return }
        if !scroll.isScrollEnabled {
            scroll.isScrollEnabled = true
        }
        intendedOffset = next
        applyingOffset = true
        scroll.setContentOffset(CGPoint(x: 0, y: next), animated: false)
        applyingOffset = false
        onOffset(next)
        relay.boost += applied
        onBoost(relay.boost)
    }

    private func resolvedScroll() -> UIScrollView? {
        if let scroll, scroll.window != nil, abs(scroll.bounds.height - preferredHeight) < 120 || preferredHeight < 1 {
            return scroll
        }
        self.scroll = nil
        var ancestor: UIView? = superview
        var depth = 0
        while let view = ancestor, depth < 16 {
            if let found = view.firstTaggedCanvasScroll() {
                scroll = found
                return found
            }
            ancestor = view.superview
            depth += 1
        }
        return nil
    }

    private var preferredHeight: CGFloat {
        if let relay, relay.viewportHeight > 1 { return relay.viewportHeight }
        return bounds.height
    }
}


extension UIView {
    func firstDescendantScrollView() -> UIScrollView? {
        if let scroll = self as? UIScrollView { return scroll }
        for child in subviews {
            if let found = child.firstDescendantScrollView() { return found }
        }
        return nil
    }

    func firstTaggedCanvasScroll() -> UIScrollView? {
        if let scroll = self as? UIScrollView, scroll.accessibilityIdentifier == ComposerCanvasScrollMark.id {
            return scroll
        }
        for child in subviews {
            if let found = child.firstTaggedCanvasScroll() { return found }
        }
        return nil
    }
}

enum ComposerCanvasScrollMark {
    static let id = "composer.canvas.scroll"
    private static var syncKey: UInt8 = 0

    static func installSync(on scroll: UIScrollView, _ onOffset: @escaping (CGFloat) -> Void) {
        objc_setAssociatedObject(scroll, &syncKey, ComposerCanvasScrollSync(onOffset), .OBJC_ASSOCIATION_RETAIN)
    }

    static func report(_ scroll: UIScrollView, offset: CGFloat) {
        (objc_getAssociatedObject(scroll, &syncKey) as? ComposerCanvasScrollSync)?.onOffset(offset)
    }
}

private final class ComposerCanvasScrollSync: NSObject {
    let onOffset: (CGFloat) -> Void

    init(_ onOffset: @escaping (CGFloat) -> Void) {
        self.onOffset = onOffset
    }
}

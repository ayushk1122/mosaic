import SwiftUI
import UIKit

/// Shared with the edge-follow scroller while a component is being dragged.
/// `boost` is observed only by the dragged piece, so the rest of the board does not rebuild each frame.
@Observable
final class ComposerDragScrollRelay {
    var active = false
    var fingerY: CGFloat = -1
    var viewportMinY: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var boost: CGFloat = 0
    var intendedOffset: CGFloat?
    /// Dragged piece edges in canvas content space, without the follow boost.
    var tracksItem = false
    var itemMinY: CGFloat = 0
    var itemMaxY: CGFloat = 0
    var dragDeltaY: CGFloat = 0
    var dragDeltaTime = Date.distantPast
    /// The piece being dragged. Its layer moves with the page in the same frame.
    weak var followView: UIView?
}

/// Marks the dragged piece so the page can slide it with the canvas without a SwiftUI rebuild.
struct DragFollowMarker: UIViewRepresentable {
    var relay: ComposerDragScrollRelay
    var enabled: Bool

    func makeUIView(context: Context) -> DragFollowMarkerView {
        let view = DragFollowMarkerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: DragFollowMarkerView, context: Context) {
        uiView.relay = relay
        uiView.enabled = enabled
        uiView.claimHost()
        uiView.apply()
    }
}

final class DragFollowMarkerView: UIView {
    weak var relay: ComposerDragScrollRelay?
    var enabled = false

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        claimHost()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        apply()
    }

    func claimHost() {
        guard enabled, let host = blockHost() else { return }
        relay?.followView = host
    }

    func apply() {
        guard let host = blockHost() else { return }
        let boost = enabled ? (relay?.boost ?? 0) : 0
        var transform = host.transform
        let upright = abs(transform.a - 1) < 0.001 && abs(transform.b) < 0.001
            && abs(transform.c) < 0.001 && abs(transform.d - 1) < 0.001
        guard upright, abs(transform.tx) < 0.01 else { return }
        guard abs(transform.ty - boost) > 0.01 else { return }
        transform.ty = boost
        host.transform = transform
    }

    /// The background sits inside the block container, which is what should travel with the finger.
    private func blockHost() -> UIView? {
        let markerHeight = bounds.height
        var current = superview
        var fallback: UIView?
        while let view = current, !(view is UIScrollView) {
            guard view.bounds.width > 8, view.bounds.height > 8 else {
                current = view.superview
                continue
            }
            fallback = view
            let aboutTheBlock = markerHeight < 8 || view.bounds.height < markerHeight + 80
            if view.subviews.count > 1, aboutTheBlock {
                return view
            }
            if markerHeight > 8, view.bounds.height > markerHeight + 120 {
                return fallback
            }
            current = view.superview
        }
        return fallback
    }
}

/// Scrolls the page when a dragged component reaches the top or bottom of the screen.
struct ComposerDragScrollDriver: UIViewRepresentable {
    var relay: ComposerDragScrollRelay
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
        uiView.onOffset = onOffset
        uiView.onNeedRoom = onNeedRoom
        uiView.sync()
    }
}

final class ComposerDragScrollDriverView: UIView {
    weak var relay: ComposerDragScrollRelay?
    var onOffset: (CGFloat) -> Void = { _ in }
    var onNeedRoom: () -> Void = {}
    private var displayLink: CADisplayLink?
    private weak var scroll: UIScrollView?
    private var lastRoomRequest = Date.distantPast
    private var intendedOffset: CGFloat?
    private var applyingOffset = false
    private var velocity: CGFloat = 0
    private var lastStep = CACurrentMediaTime()
    private weak var watchedScroll: UIScrollView?
    private var offsetWatch: NSKeyValueObservation?

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
        lastStep = CACurrentMediaTime()
        velocity = 0
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
        intendedOffset = nil
        velocity = 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !applyingOffset, let intendedOffset, relay?.active == true, let scroll = resolvedScroll() else { return }
        guard abs(scroll.contentOffset.y - intendedOffset) > 0.5 else { return }
        assignOffset(intendedOffset, to: scroll)
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = min(max(now - lastStep, 1.0 / 120.0), 1.0 / 30.0)
        lastStep = now
        followIfNeeded(dt: dt)
    }

    private func followIfNeeded(dt: CGFloat) {
        guard let relay, relay.active else {
            stop()
            return
        }
        guard let scroll = resolvedScroll() else { return }
        let height = scroll.bounds.height
        guard height > 1 else { return }
        let zone: CGFloat = 108
        let maxSpeed: CGFloat = 720
        let y = relay.fingerY
        var target: CGFloat = 0
        if y >= 0, y < zone {
            let depth = 1 - y / zone
            target = -maxSpeed * depth * depth
        } else if y > height - zone {
            let depth = min(max(y - (height - zone), 0) / zone, 1)
            target = maxSpeed * depth * depth
        } else if relay.tracksItem {
            let visualTop = relay.itemMinY + relay.boost - scroll.contentOffset.y
            let visualBottom = relay.itemMaxY + relay.boost - scroll.contentOffset.y
            if relay.dragDeltaY < -0.2, visualTop < zone {
                let depth = min(max((zone - visualTop) / zone, 0), 1)
                target = -maxSpeed * depth * depth
            } else if relay.dragDeltaY > 0.2, visualBottom > height - zone {
                let depth = min(max((visualBottom - (height - zone)) / zone, 0), 1)
                target = maxSpeed * depth * depth
            }
        }
        let blend = 1 - exp(-dt * 14)
        velocity += (target - velocity) * blend
        if abs(target) < 1, abs(velocity) < 12 {
            velocity = 0
            return
        }
        let delta = velocity * dt
        guard abs(delta) > 0.05 else { return }
        let maxOffset = max(scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom, 0)
        if delta > 0, maxOffset - scroll.contentOffset.y < 48, Date().timeIntervalSince(lastRoomRequest) > 0.2 {
            lastRoomRequest = Date()
            onNeedRoom()
        }
        let next = min(max(scroll.contentOffset.y + delta, -scroll.adjustedContentInset.top), maxOffset)
        let applied = next - scroll.contentOffset.y
        guard abs(applied) > 0.05 else { return }
        intendedOffset = next
        relay.intendedOffset = next
        relay.boost += applied
        assignOffset(next, to: scroll)
        applyFollowShift()
    }

    /// Moves the scroll view without telling SwiftUI, so the page does not rebuild on each step.
    private func assignOffset(_ y: CGFloat, to scroll: UIScrollView) {
        applyingOffset = true
        let delegate = scroll.delegate
        scroll.delegate = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scroll.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        CATransaction.commit()
        scroll.delegate = delegate
        applyingOffset = false
    }

    private func applyFollowShift() {
        guard let relay, let host = relay.followView else { return }
        var transform = host.transform
        let upright = abs(transform.a - 1) < 0.001 && abs(transform.b) < 0.001
            && abs(transform.c) < 0.001 && abs(transform.d - 1) < 0.001
        guard upright, abs(transform.tx) < 0.01 else { return }
        guard abs(transform.ty - relay.boost) > 0.01 else { return }
        transform.ty = relay.boost
        host.transform = transform
    }

    private func watch(_ scroll: UIScrollView) {
        guard watchedScroll !== scroll else { return }
        watchedScroll = scroll
        offsetWatch = scroll.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
            guard let self, !self.applyingOffset, self.relay?.active == true, let intended = self.intendedOffset else { return }
            guard abs(scroll.contentOffset.y - intended) > 0.5 else { return }
            self.assignOffset(intended, to: scroll)
            self.applyFollowShift()
        }
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
                watch(found)
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

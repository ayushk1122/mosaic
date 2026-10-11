import SwiftUI
import UIKit

enum ComposerSocialPlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case instagram
    case tiktok
    case twitter
    case youtube
    case twitch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .twitter: "Twitter"
        case .youtube: "YouTube"
        case .twitch: "Twitch"
        }
    }

    var assetName: String {
        switch self {
        case .instagram: "SocialInstagram"
        case .tiktok: "SocialTikTok"
        case .twitter: "SocialTwitter"
        case .youtube: "SocialYouTube"
        case .twitch: "SocialTwitch"
        }
    }

    /// A pasted https link is kept. A bare username becomes that platform’s profile URL.
    func profileURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let direct = URL(string: trimmed),
           let scheme = direct.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return direct
        }
        if trimmed.contains("."), !trimmed.contains(" "), !trimmed.hasPrefix("@") {
            let candidate = trimmed.hasPrefix("//") ? "https:\(trimmed)" : "https://\(trimmed)"
            return URL(string: candidate)
        }
        var handle = trimmed
        if handle.hasPrefix("@") {
            handle.removeFirst()
        }
        handle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty, !handle.contains(" "), !handle.contains("/") else { return nil }
        let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle
        switch self {
        case .instagram:
            return URL(string: "https://instagram.com/\(encoded)")
        case .tiktok:
            return URL(string: "https://www.tiktok.com/@\(encoded)")
        case .twitter:
            return URL(string: "https://twitter.com/\(encoded)")
        case .youtube:
            return URL(string: "https://www.youtube.com/@\(encoded)")
        case .twitch:
            return URL(string: "https://www.twitch.tv/\(encoded)")
        }
    }
}

struct ComposerSocialMark: View {
    let platform: ComposerSocialPlatform
    var side: CGFloat

    var body: some View {
        Image(platform.assetName)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: side, height: side)
            .contentShape(Rectangle())
    }
}

struct ComposerSocialCanvasBlock: View {
    @Binding var block: ComposerBlock
    var canvasSize: CGSize
    var livePinchScale: CGFloat
    var isSelected: Bool
    var isLifted: Bool
    var isRelocating: Bool
    var isViewing: Bool
    var cornerResizing: Binding<Bool>
    var onEdit: () -> Void
    var onOpen: (() -> Void)? = nil

    @Environment(\.composerCoordinateSpace) private var composerSpace
    @State private var cornerDrag: SocialCornerDrag?
    @State private var cornerFrames = ComposerSocialCornerFrames()

    private static let minSide: CGFloat = 56 * 0.45
    private static let maxSide: CGFloat = 56 * 3.2

    private var platform: ComposerSocialPlatform {
        ComposerSocialPlatform(rawValue: block.socialPlatform) ?? .instagram
    }

    private var showsHandles: Bool {
        isSelected && !isLifted && !isRelocating && !isViewing
    }

    private var baseSide: CGFloat {
        56 * CGFloat(block.style.scale) * livePinchScale
    }

    var body: some View {
        let extra = cornerDrag?.extra ?? 0
        let liveSide = min(max(baseSide + extra, Self.minSide), Self.maxSide)
        let applied = liveSide - baseSide
        let scale = liveSide / 56
        let link = block.linkURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        VStack(spacing: showsHandles ? 6 - SocialLogoChrome.margin : 6 * scale) {
            logoBoard(liveSide: liveSide, applied: applied)
            if isSelected, !isViewing, link.isEmpty {
                Text("Add link")
                    .font(.system(size: 12 * scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .contentShape(Rectangle())
        .opacity(isLifted ? 0.92 : 1)
        .overlay(alignment: .bottomTrailing) {
            if isSelected, !isViewing {
                socialPencil
                    .offset(x: 8, y: 8)
            }
        }
        .preference(
            key: ComposerSocialCornerFrameKey.self,
            value: showsHandles ? [block.id: cornerFrames] : [:]
        )
        .accessibilityLabel(platform.title)
        .accessibilityIdentifier("composer.social.\(block.id.rawValue)")
    }

    private func logoBoard(liveSide: CGFloat, applied: CGFloat) -> some View {
        let margin = showsHandles ? SocialLogoChrome.margin : 0
        let board = baseSide + margin * 2
        return ZStack(alignment: .topLeading) {
            ComposerSocialMark(platform: platform, side: baseSide)
                .frame(width: baseSide, height: baseSide)
                .modifier(SocialOpenModifier(isEnabled: onOpen != nil, action: { onOpen?() }))
                .overlay {
                    if isSelected, !isLifted, !isRelocating {
                        Rectangle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                    }
                }
                .scaleEffect(
                    baseSide > 0 ? liveSide / baseSide : 1,
                    anchor: (cornerDrag?.corner ?? .bottomRight).scaleAnchor
                )
                .frame(width: baseSide, height: baseSide, alignment: .topLeading)
                .offset(x: margin, y: margin)
            if showsHandles {
                ForEach(SocialLogoCorner.allCases) { corner in
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1))
                        .frame(width: 14, height: 14)
                        .position(dotCenter(corner, applied: applied))
                        .allowsHitTesting(false)
                    cornerCatcher(corner)
                        .position(dotCenter(corner, applied: 0))
                }
            }
        }
        .frame(width: board, height: board, alignment: .topLeading)
    }

    private func cornerCatcher(_ corner: SocialLogoCorner) -> some View {
        ComposerCornerCatcher(
            onChanged: { translation in
                let growth = corner.growth(for: translation)
                let next = min(max(baseSide + growth, Self.minSide), Self.maxSide)
                if cornerResizing.wrappedValue == false {
                    cornerResizing.wrappedValue = true
                }
                cornerDrag = SocialCornerDrag(corner: corner, extra: next - baseSide, translation: translation)
            },
            onEnded: { translation in
                cornerResizing.wrappedValue = false
                let growth = corner.growth(for: translation)
                let nextSide = min(max(baseSide + growth, Self.minSide), Self.maxSide)
                let resized = nextSide - baseSide
                cornerDrag = nil
                guard abs(resized) > 0.5 else { return }
                var updated = block
                updated.style.scale = Double(nextSide / 56)
                if canvasSize.width > 1, canvasSize.height > 1 {
                    let dx = resized / canvasSize.width
                    let dy = resized / canvasSize.height
                    switch corner {
                    case .topLeft:
                        updated.position.x -= dx
                        updated.position.y -= dy
                    case .topRight:
                        updated.position.y -= dy
                    case .bottomLeft:
                        updated.position.x -= dx
                    case .bottomRight:
                        break
                    }
                }
                block = updated
            }
        )
        .frame(width: SocialLogoChrome.hitSide, height: SocialLogoChrome.hitSide)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(composerSpace))
        } action: { frame in
            switch corner {
            case .topLeft where cornerFrames.topLeft != frame: cornerFrames.topLeft = frame
            case .topRight where cornerFrames.topRight != frame: cornerFrames.topRight = frame
            case .bottomLeft where cornerFrames.bottomLeft != frame: cornerFrames.bottomLeft = frame
            case .bottomRight where cornerFrames.bottomRight != frame: cornerFrames.bottomRight = frame
            default: break
            }
        }
        .accessibilityLabel("Resize logo")
        .accessibilityAddTraits(.isButton)
    }

    /// Center of this corner in the board. `applied` is the live growth while a corner is held.
    private func dotCenter(_ corner: SocialLogoCorner, applied: CGFloat) -> CGPoint {
        let margin = showsHandles ? SocialLogoChrome.margin : 0
        var minX = margin
        var minY = margin
        var maxX = margin + baseSide
        var maxY = margin + baseSide
        if let dragged = cornerDrag?.corner, applied != 0 {
            switch dragged {
            case .bottomRight:
                maxX += applied
                maxY += applied
            case .topLeft:
                minX -= applied
                minY -= applied
            case .topRight:
                maxX += applied
                minY -= applied
            case .bottomLeft:
                minX -= applied
                maxY += applied
            }
        }
        return CGPoint(
            x: corner.isTrailing ? maxX : minX,
            y: corner.isBottom ? maxY : minY
        )
    }

    private var socialPencil: some View {
        Image(systemName: "pencil")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 26, height: 26)
            .background(Color(red: 0.20, green: 0.21, blue: 0.23), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Circle())
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ComposerPencilFrameKey.self,
                        value: [block.id: proxy.frame(in: .named(composerSpace))]
                    )
                }
            }
            .highPriorityGesture(TapGesture().onEnded { onEdit() })
            .accessibilityLabel("Edit Social")
            .accessibilityAddTraits(.isButton)
    }
}

private struct SocialOpenModifier: ViewModifier {
    var isEnabled: Bool
    var action: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.highPriorityGesture(TapGesture().onEnded { action() })
        } else {
            content
        }
    }
}

struct ComposerSocialEditor: View {
    @State private var platform: ComposerSocialPlatform
    @State private var link: String
    var onCancel: () -> Void
    var onSave: (ComposerSocialPlatform, String) -> Void

    init(
        platform: ComposerSocialPlatform,
        link: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping (ComposerSocialPlatform, String) -> Void
    ) {
        _platform = State(initialValue: platform)
        _link = State(initialValue: link)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Choose a platform")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                VStack(spacing: 8) {
                    ForEach(ComposerSocialPlatform.allCases) { option in
                        Button {
                            platform = option
                        } label: {
                            HStack(spacing: 12) {
                                ComposerSocialMark(platform: option, side: 28)
                                Text(option.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.white)
                                Spacer()
                                if platform == option {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                platform == option ? Color.white.opacity(0.12) : Color.white.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                TextField("Profile link or username", text: $link)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(MosaicBrand.inkBlack)
            .navigationTitle("Social")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(platform, link)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

enum SocialLogoChrome {
    /// Room around a selected logo so the corner dots sit inside the block’s touch bounds.
    static let margin: CGFloat = 24
    static let hitSide: CGFloat = 44
}

private enum SocialLogoCorner: Equatable, Hashable, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: Self { self }

    var isTrailing: Bool {
        self == .topRight || self == .bottomRight
    }

    var isBottom: Bool {
        self == .bottomLeft || self == .bottomRight
    }

    /// The corner that stays put while this one is dragged.
    var scaleAnchor: UnitPoint {
        switch self {
        case .topLeft: .bottomTrailing
        case .topRight: .bottomLeading
        case .bottomLeft: .topTrailing
        case .bottomRight: .topLeading
        }
    }

    /// How far the square side should grow so the pulled edge follows the finger.
    func growth(for translation: CGSize) -> CGFloat {
        let width = translation.width
        let height = translation.height
        switch self {
        case .bottomRight:
            return abs(width) >= abs(height) ? width : height
        case .topLeft:
            return abs(width) >= abs(height) ? -width : -height
        case .topRight:
            return abs(width) >= abs(height) ? width : -height
        case .bottomLeft:
            return abs(width) >= abs(height) ? -width : height
        }
    }
}

/// A corner touch target. Its pan wins over the page scroll view.
struct ComposerCornerCatcher: UIViewRepresentable {
    var onChanged: (CGSize) -> Void
    var onEnded: (CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ComposerCornerCatcherView {
        let view = ComposerCornerCatcherView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ComposerCornerCatcherView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        uiView.coordinator = context.coordinator
    }

    static func dismantleUIView(_ uiView: ComposerCornerCatcherView, coordinator: Coordinator) {
        uiView.releaseScroll()
        coordinator.onEnded = { _ in }
        coordinator.onChanged = { _ in }
    }

    final class Coordinator: NSObject {
        var onChanged: (CGSize) -> Void = { _ in }
        var onEnded: (CGSize) -> Void = { _ in }
    }
}

final class ComposerCornerCatcherView: UIView, UIGestureRecognizerDelegate {
    weak var coordinator: ComposerCornerCatcher.Coordinator?
    private var lockedScroll: UIScrollView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = true
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        lockScroll()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        releaseScroll()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        releaseScroll()
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: window)
        let size = CGSize(width: translation.x, height: translation.y)
        switch pan.state {
        case .began, .changed:
            lockScroll()
            coordinator?.onChanged(size)
        case .ended, .cancelled, .failed:
            coordinator?.onEnded(size)
            releaseScroll()
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        otherGestureRecognizer.view is UIScrollView && otherGestureRecognizer is UIPanGestureRecognizer
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    private func lockScroll() {
        guard let scroll = enclosingScrollView() else { return }
        lockedScroll = scroll
        scroll.isScrollEnabled = false
    }

    fileprivate func releaseScroll() {
        lockedScroll?.isScrollEnabled = true
        lockedScroll = nil
    }

    private func enclosingScrollView() -> UIScrollView? {
        var current = superview
        while let view = current {
            if let scroll = view as? UIScrollView { return scroll }
            current = view.superview
        }
        return nil
    }
}

private struct SocialCornerDrag: Equatable {
    var corner: SocialLogoCorner
    var extra: CGFloat
    var translation: CGSize
}

struct ComposerSocialCornerFrames: Equatable {
    var topLeft = CGRect.zero
    var topRight = CGRect.zero
    var bottomLeft = CGRect.zero
    var bottomRight = CGRect.zero

    func contains(_ point: CGPoint) -> Bool {
        [topLeft, topRight, bottomLeft, bottomRight].contains { frame in
            frame.width > 1 && frame.insetBy(dx: -8, dy: -8).contains(point)
        }
    }
}

struct ComposerSocialCornerFrameKey: PreferenceKey {
    static var defaultValue: [ComposerBlockID: ComposerSocialCornerFrames] = [:]

    static func reduce(
        value: inout [ComposerBlockID: ComposerSocialCornerFrames],
        nextValue: () -> [ComposerBlockID: ComposerSocialCornerFrames]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}


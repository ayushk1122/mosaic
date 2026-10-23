import SwiftUI
import UIKit

/// Orbit ("your daily orbit"): the boards people follow that changed in the last day, one at a
/// time. Swipe sideways between boards, scroll within one, or let the navigator glide from update
/// to update. The trail at the top has a circle per board, joined by lines that grow as each
/// board's updates are seen and turn green once they all are. Boards not done come first and done
/// ones last. Ends with "You're all caught up".
struct MosaicOrbitView: View {
    /// Bumped when the Orbit tab is tapped while open: back to the start.
    var resetCount = 0
    /// Leaves for Explore from the last page.
    var onExplore: () -> Void = {}

    @Environment(MosaicOrbitModel.self) private var orbit: MosaicOrbitModel?
    @Environment(\.mosaicTabBarHidden) private var tabBarHidden
    @Environment(\.scenePhase) private var scenePhase

    /// The order shown. It's put together again only when Orbit is opened or the app comes back,
    /// never while paging, so boards don't move as they're seen.
    @State private var deck: [MosaicOrbitItem] = []
    @State private var page: String?
    /// Kept for a board across rebuilds: its board view registered with this guide when it appeared.
    @State private var guides: [UUID: ComposerUpdateGuide] = [:]
    @State private var headerHeight: CGFloat = 0
    /// Bumped to start every page over, closing whatever was opened from it.
    @State private var pagesStart = 0
    /// Bumped when the boards in the deck change, so the pager starts fresh rather than scrolling
    /// to a place the new deck doesn't have.
    @State private var deckVersion = 0
    /// Boards with a journal open on them, read from the boards themselves so it can't go stale.
    @State private var journalOpen: Set<UUID> = []

    private static let endPage = "end"
    static let done = Color(red: 0.3, green: 0.85, blue: 0.45)
    private let muted = Color.white.opacity(0.6)

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MosaicBrand.inkBlack.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(tabBarHidden ? .hidden : .visible, for: .tabBar)
            .task { await reload(force: false) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await reload(force: false) } }
            }
            .onChange(of: resetCount) { startOver() }
            .accessibilityIdentifier(MosaicTab.orbit.screenAccessibilityIdentifier)
    }

    @ViewBuilder
    private var content: some View {
        if let orbit {
            if !deck.isEmpty || orbit.phase == .ready {
                pager(orbit)
            } else if orbit.phase == .failed {
                VStack(spacing: 12) {
                    message("Orbit couldn't load. Check your connection and try again.")
                    Button("Try again") { Task { await reload(force: true) } }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            } else {
                ProgressView().tint(.white)
            }
        } else {
            message("Sign in to see your daily orbit: what people you follow added today.")
        }
    }

    /// Something else has the screen on this board: the owner's Mosaic, or a journal. Orbit's
    /// header and navigator step aside, and sideways swipes don't change boards.
    private func stepsAside(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return guides[id]?.isAway == true || journalOpen.contains(id)
    }

    private func pager(_ orbit: MosaicOrbitModel) -> some View {
        let away = stepsAside(page.flatMap(UUID.init(uuidString:)))
        return TabView(selection: $page) {
            ForEach(deck) { item in
                boardPage(item)
                    .tag(Optional(item.id.uuidString))
            }
            caughtUp(orbit)
                .safeAreaPadding(.top, headerHeight)
                .tag(Optional(Self.endPage))
        }
        .id(deckVersion)
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Boards reach the edges of the screen, under the status bar and header at the top and
        // the tab bar at the bottom, as on Circle.
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        // One header for every page, so the trail stays put while the outline moves from board to board.
        .overlay(alignment: .top) {
            if !away {
                header(orbit)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: away)
    }

    private var currentGuide: ComposerUpdateGuide? {
        page.flatMap(UUID.init(uuidString:)).flatMap { guides[$0] }
    }

    /// The board on screen, or `deck.count` for the caught-up page.
    private var currentIndex: Int {
        page.flatMap { id in deck.firstIndex { $0.id.uuidString == id } } ?? deck.count
    }

    @ViewBuilder
    private func boardPage(_ item: MosaicOrbitItem) -> some View {
        if let guide = guides[item.id] {
            NavigationStack {
                MosaicVisitView(target: item.target, embedded: true)
            }
            .id(pagesStart)
            // On the stack, so a node or page opened from the board marks and guides through its updates too.
            .environment(\.composerUpdateAddresses, item.addresses)
            .environment(\.composerAddedAddresses, item.addedAddresses)
            .environment(\.composerNewBoards, item.newBoardIDs)
            .environment(guide)
            // The board scrolls beneath the glass header. Both step aside while the owner's Mosaic
            // is open on top, which has its own way back.
            .environment(\.composerTopInset, stepsAside(item.id) ? 0 : headerHeight)
            // While a Mosaic or journal is open on the page, sideways swipes don't change boards.
            .background(MosaicOrbitPagerLock(isLocked: stepsAside(item.id)))
            .onPreferenceChange(ComposerJournalOpenKey.self) { open in
                if open { journalOpen.insert(item.id) } else { journalOpen.remove(item.id) }
            }
            .overlay(alignment: .bottomLeading) {
                if !stepsAside(item.id) {
                    navigator(guide)
                        .padding(.leading, 20)
                        .padding(.bottom, 20)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: stepsAside(item.id))
        }
    }

    private func header(_ orbit: MosaicOrbitModel) -> some View {
        let allDone = !deck.isEmpty && deck.allSatisfy { orbit.isDone($0) }
        let index = currentIndex
        return VStack(alignment: .leading, spacing: 10) {
            MosaicOrbitTrail(
                stops: deck.map { MosaicOrbitTrail.Stop(item: $0, progress: orbit.progress(of: $0)) },
                current: index
            ) { selected in
                withAnimation(.easeInOut(duration: 0.3)) {
                    page = selected < deck.count ? deck[selected].id.uuidString : Self.endPage
                }
            }
            if index < deck.count {
                let item = deck[index]
                HStack(spacing: 8) {
                    Text(item.heading)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(MosaicOrbitText.age(of: item.latestAt))
                        .font(.caption)
                        .foregroundStyle(muted)
                    Spacer(minLength: 0)
                    if allDone {
                        Label("All caught up", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Self.done)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: allDone)
    }

    /// Glides from update to update: up for the one before, down for the next, and on to the next
    /// board after the last.
    private func navigator(_ guide: ComposerUpdateGuide) -> some View {
        HStack(spacing: 2) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { guide.previous() }
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .disabled((guide.position ?? 0) == 0)
            .accessibilityLabel("Previous update")
            Text(guide.label)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy, value: guide.label)
                .fixedSize()
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { guide.next() }
            } label: {
                Image(systemName: guide.isAtEnd && guide.isAtRoot ? "arrow.right" : "chevron.down")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(guide.isAtEnd && guide.isAtRoot ? "Next board" : "Next update")
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityIdentifier("orbit.navigator")
    }

    private func caughtUp(_ orbit: MosaicOrbitModel) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(deck.allSatisfy { orbit.isDone($0) } && !deck.isEmpty ? Self.done : .white)
            Text("You're all caught up")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(deck.isEmpty
                 ? "Nothing new in your orbit today. What people you follow add shows up here for a day."
                 : "That's your daily orbit. New updates show up here as people add them.")
                .font(.subheadline)
                .foregroundStyle(muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            HStack(spacing: 12) {
                Button("Check again") { Task { await reload(force: true) } }
                    .buttonStyle(.bordered)
                Button("Explore", action: onExplore)
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(MosaicBrand.inkBlack)
            }
            .tint(.white)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("orbit.caughtUp")
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }

    /// Loads the day and, unless someone is partway into a board (inside a node, or on the
    /// owner's Mosaic), puts the deck together again: boards not done first.
    private func reload(force: Bool) async {
        guard let orbit else { return }
        await orbit.refresh()
        let settled = (currentGuide.map(\.isAtRoot) ?? true) && !stepsAside(page.flatMap(UUID.init(uuidString:)))
        if force || deck.isEmpty || page == Self.endPage || settled { takeDeck() }
    }

    /// Back to the start: every page closes what was opened from it, and Orbit opens on the first
    /// board not done.
    private func startOver() {
        pagesStart += 1
        takeDeck(freshGuides: true)
    }

    /// Opens on the first board not done, or on the caught-up page when every board is.
    private func takeDeck(freshGuides: Bool = false) {
        guard let orbit else { return }
        let ordered = orbit.ordered()
        if ordered.map(\.id) != deck.map(\.id) { deckVersion += 1 }
        deck = ordered
        var kept: [UUID: ComposerUpdateGuide] = [:]
        for item in deck {
            let guide = (freshGuides ? nil : guides[item.id]) ?? ComposerUpdateGuide()
            configure(guide, for: item, orbit: orbit)
            kept[item.id] = guide
        }
        guides = kept
        page = deck.first { !orbit.isDone($0) }?.id.uuidString ?? Self.endPage
    }

    private func configure(_ guide: ComposerUpdateGuide, for item: MosaicOrbitItem, orbit: MosaicOrbitModel) {
        guide.resetSeen(orbit.seenKeys(of: item))
        guide.onSeen = { [weak orbit] keys in
            guard let orbit else { return }
            let wasDone = orbit.isDone(item)
            orbit.markViewed(keys, on: item)
            guard !wasDone, orbit.isDone(item) else { return }
            // A board finished is a small win; the whole day, a bigger one.
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            if deck.allSatisfy({ orbit.isDone($0) }) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
        guide.onFinished = {
            withAnimation(.easeInOut(duration: 0.35)) { page = nextPage(after: item.id) }
        }
    }

    private func nextPage(after id: UUID) -> String {
        guard let index = deck.firstIndex(where: { $0.id == id }), index + 1 < deck.count else { return Self.endPage }
        return deck[index + 1].id.uuidString
    }
}

/// A circle per board, joined by lines. Each line grows as its board's updates are seen and turns
/// green once they all are; a finished board's circle fades. The board on screen is outlined. The
/// circles keep their size however many boards there are, and the trail scrolls to reach them.
struct MosaicOrbitTrail: View {
    struct Stop: Equatable {
        var item: MosaicOrbitItem
        var progress: Double

        var isDone: Bool { progress >= 1 }
        var seenCount: Int { Int((progress * Double(item.pieces.count)).rounded()) }
    }

    var stops: [Stop]
    /// The board on screen; `stops.count` for the caught-up page.
    var current: Int
    var onSelect: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0

    /// Scroll targets that never collide: a board keeps its own id as the trail grows or reorders.
    private enum Spot: Hashable {
        case board(UUID)
        case end
    }

    private func spot(for index: Int) -> Spot {
        index < stops.count ? .board(stops[index].item.id) : .end
    }

    static let circle: CGFloat = 44
    static let shortestLine: CGFloat = 24
    static let end: CGFloat = 26
    /// Room around the circles for the outline and glow, which the scroll view would clip.
    private static let margin: CGFloat = 8

    /// Lines share the width when the boards fit, and keep their shortest length when they don't.
    static func lineLength(boards: Int, width: CGFloat) -> CGFloat {
        guard boards > 0 else { return shortestLine }
        let free = width - 2 * margin - CGFloat(boards) * circle - end
        return max(shortestLine, free / CGFloat(boards))
    }

    var body: some View {
        let line = Self.lineLength(boards: stops.count, width: width)
        let allDone = !stops.isEmpty && stops.allSatisfy(\.isDone)
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(stops.enumerated()), id: \.element.item.id) { index, stop in
                        circle(stop, at: index)
                            .id(Spot.board(stop.item.id))
                        connector(stop.progress, length: line)
                    }
                    endNode(allDone: allDone)
                        .id(Spot.end)
                }
                .padding(Self.margin)
            }
            .scrollIndicators(.hidden)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: stops.map(\.progress))
            .onChange(of: spot(for: current), initial: true) { _, spot in
                if reduceMotion {
                    proxy.scrollTo(spot, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(spot, anchor: .center) }
                }
            }
        }
        .frame(height: Self.circle + 2 * Self.margin)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityIdentifier("orbit.trail")
    }

    private func circle(_ stop: Stop, at index: Int) -> some View {
        let isCurrent = index == current
        let item = stop.item
        return Button {
            onSelect(index)
        } label: {
            Group {
                if item.role == .pursuit {
                    MosaicPursuitCoverView(item: item.cover, size: Self.circle)
                } else {
                    MosaicAvatarView(path: item.owner.avatarPath, name: item.ownerName, size: Self.circle)
                }
            }
            .opacity(stop.isDone && !isCurrent ? 0.4 : 1)
            .overlay {
                if isCurrent {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .padding(-4)
                        .shadow(color: .white.opacity(0.7), radius: 6)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isCurrent)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: stop.isDone)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.role == .pursuit ? "\(item.title.isEmpty ? "Pursuit" : item.title) by \(item.ownerName)" : "\(item.ownerName)'s Mosaic")
        .accessibilityValue(
            "\(stop.seenCount) of \(item.pieces.count) updates seen" + (isCurrent ? ", current board" : "")
        )
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("orbit.trail.\(item.id.uuidString.lowercased())")
    }

    private func connector(_ progress: Double, length: CGFloat) -> some View {
        let fill = min(max(progress, 0), 1)
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.2))
            Capsule()
                .fill(fill >= 1 ? MosaicOrbitView.done : Color.white)
                .frame(width: length * fill)
        }
        .frame(width: length, height: 3)
        .accessibilityHidden(true)
    }

    private func endNode(allDone: Bool) -> some View {
        let isCurrent = current == stops.count
        return Button {
            onSelect(stops.count)
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(allDone ? MosaicBrand.inkBlack : .white)
                .frame(width: Self.end, height: Self.end)
                .background(allDone ? MosaicOrbitView.done : Color.white.opacity(0.15), in: Circle())
                .overlay {
                    if isCurrent {
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .padding(-4)
                            .shadow(color: .white.opacity(0.7), radius: 6)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("All caught up")
        .accessibilityValue(allDone ? "Every board seen" : "")
        .accessibilityIdentifier("orbit.trail.end")
    }
}

/// Stops Orbit's pager from paging while something else has a page's screen. SwiftUI's
/// `scrollDisabled` would also stop every scroll view inside the page (the board, a journal, a
/// Mosaic opened over it), and a page can't turn it back on, so this reaches the pager itself.
private struct MosaicOrbitPagerLock: UIViewRepresentable {
    var isLocked: Bool

    func makeUIView(context: Context) -> MosaicOrbitPagerLockView {
        MosaicOrbitPagerLockView()
    }

    func updateUIView(_ view: MosaicOrbitPagerLockView, context: Context) {
        view.setLocked(isLocked)
    }
}

private final class MosaicOrbitPagerLockView: UIView {
    private var locked = false
    private weak var pager: UICollectionView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Only a page that locks touches the pager, so pages loaded beside it leave it alone.
    func setLocked(_ value: Bool) {
        guard value != locked else { return }
        locked = value
        findPager()?.isScrollEnabled = !value
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if locked { findPager()?.isScrollEnabled = false }
    }

    /// A page taken away while locked mustn't leave the pager stuck.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil, locked { pager?.isScrollEnabled = true }
    }

    private func findPager() -> UICollectionView? {
        if let pager { return pager }
        var view = superview
        while let current = view {
            if let found = current as? UICollectionView {
                pager = found
                return found
            }
            view = current.superview
        }
        return nil
    }
}

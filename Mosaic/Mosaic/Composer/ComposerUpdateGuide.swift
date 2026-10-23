import SwiftUI

/// Where a thing with an update appears on the board: its frame in the board's canvas, whether its
/// container is showing it (a carousel's side cards and days in another month aren't), and its place
/// in its container's own order.
struct ComposerUpdateAnchor: Equatable, Sendable {
    var frame: CGRect
    var isPresented: Bool
    var order: Int = 0
}

/// The anchors on a board, by address. One shown wins over one set aside under the same address.
struct ComposerUpdateAnchorKey: PreferenceKey {
    static let defaultValue: [String: ComposerUpdateAnchor] = [:]

    static func reduce(value: inout [String: ComposerUpdateAnchor], nextValue: () -> [String: ComposerUpdateAnchor]) {
        value.merge(nextValue()) { current, next in
            next.isPresented && !current.isPresented ? next : current
        }
    }
}

/// Addresses are paths from a piece down: "c" for a piece, "c/carouselitems/two" for a card in it.
enum ComposerUpdateAddress {
    /// The address itself and everything above it, shortest first.
    static func lineage(of address: String) -> [String] {
        let parts = address.split(separator: "/")
        return parts.indices.map { parts[...$0].joined(separator: "/") }
    }

    static func isWithin(_ address: String, _ ancestor: String) -> Bool {
        address == ancestor || address.hasPrefix(ancestor + "/")
    }

    static func piece(of address: String) -> String {
        String(address.split(separator: "/", maxSplits: 1).first ?? Substring(address))
    }

    /// A calendar day's address part, as the server writes it: "2026-03-05".
    static func day(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The date in a calendar day's address part.
    static func date(of part: String) -> (year: Int, month: Int, day: Int)? {
        let numbers = part.split(separator: "-").compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        return (numbers[0], numbers[1], numbers[2])
    }
}

/// Walks through the updates on a board opened from Orbit. The board says which updates are on it
/// and which pieces open nodes or pages with updates; the views showing them place anchors. Each
/// update goes to the deepest anchored place that holds it (a card, a day), or to the piece when
/// nothing finer is anchored; something new inside something that's new itself goes with it. Next
/// brings each stop into view in reading order, opens a node or page whose updates come next, and
/// steps back out once they're done. A stop counts as seen once it's shown mostly on screen, or
/// when the navigator reaches it.
@MainActor
@Observable
final class ComposerUpdateGuide {
    /// What the board on screen holds.
    struct Plan: Equatable, Sendable {
        struct Update: Equatable, Sendable {
            var address: String
            var piece: ComposerBlockID
            /// The piece's place in reading order.
            var order: Int
        }

        struct Opener: Equatable, Sendable {
            var piece: ComposerBlockID
            var board: UUID
            /// Nodes and Pursuits are opened by the navigator; a scrapbook's pages are seen with it.
            var opens: Bool
            var order: Int
        }

        var updates: [Update] = []
        var openers: [Opener] = []
        /// Addresses of things added, rather than changed; what's inside one goes with it.
        var added: Set<String> = []

        var isEmpty: Bool { updates.isEmpty && openers.isEmpty }
    }

    struct Stop: Equatable, Sendable {
        /// Where the navigator goes: an anchored address, or the piece.
        var address: String
        var piece: ComposerBlockID
        /// A node or page this piece opens, with updates inside.
        var opens: UUID? = nil
        /// The updates reaching this stop checks off.
        var covers: Set<String> = []
        var order: Int = 0

        var seenKeys: Set<String> { covers.isEmpty ? [address] : covers }
    }

    /// Asks the board on screen to bring a stop into view, and its container to show it, or to open
    /// what it leads to.
    struct Request: Equatable {
        var address: String
        var piece: ComposerBlockID
        var opens: Bool
        var nonce: Int
    }

    /// Which stop was last brought into view; nil before the first.
    private(set) var position: Int?
    /// Addresses of updates seen so far, and of nodes and pages opened with nothing else new.
    private(set) var seen: Set<String>
    private(set) var request: Request?
    /// Bumped to ask a node or page opened from the board to close again.
    private(set) var leaveCount = 0
    /// The board on screen: the board the page opened on, or a node or page opened from it.
    private(set) var board: String?
    /// The stop the navigator brought up, while it's on screen; the rest of the board dims around it.
    private(set) var spotlit: String?
    /// Somewhere other than the updates, like the owner's Mosaic opened on top: Orbit steps aside.
    var isAway = false

    private var plans: [String: Plan] = [:]
    private var anchorsByBoard: [String: [String: ComposerUpdateAnchor]] = [:]

    /// Past the last update, to move on to the next board.
    @ObservationIgnored var onFinished: () -> Void = {}
    /// Newly seen addresses, to keep the progress for the day.
    @ObservationIgnored var onSeen: (Set<String>) -> Void = { _ in }

    @ObservationIgnored private var root: String?
    @ObservationIgnored private var saved: [String: Int] = [:]
    @ObservationIgnored private var entered: Set<UUID> = []
    @ObservationIgnored private var nonce = 0

    init(seen: Set<String> = []) {
        self.seen = seen
    }

    static func key(for documentID: ComposerDocumentID?) -> String {
        documentID?.rawValue.lowercased() ?? "mosaic"
    }

    var isAtRoot: Bool { board == nil || board == root }

    /// The anchors of the board on screen.
    var anchors: [String: ComposerUpdateAnchor] { board.flatMap { anchorsByBoard[$0] } ?? [:] }

    /// The stops of the board on screen, in reading order.
    var stops: [Stop] {
        guard let board, let plan = plans[board] else { return [] }
        return Self.stops(plan: plan, anchors: anchorsByBoard[board] ?? [:])
    }

    /// "5 updates" before the first, then "3 of 5", for the board on screen.
    var label: String {
        let stops = stops
        guard !stops.isEmpty else { return "No updates here" }
        guard let position else { return stops.count == 1 ? "1 update" : "\(stops.count) updates" }
        return "\(min(position, stops.count - 1) + 1) of \(stops.count)"
    }

    /// Next leaves this board: for the next board in Orbit, or back out of a node.
    var isAtEnd: Bool {
        let stops = stops
        guard let position, position < stops.count else { return stops.isEmpty }
        let opensNext = stops[position].opens.map { !entered.contains($0) } ?? false
        return position >= stops.count - 1 && !opensNext
    }

    /// A board came on screen (the first one is the page's own); a board shown again after a node
    /// closes picks up where it was.
    func show(board: String, plan: Plan) {
        if root == nil { root = board }
        if self.board != board, let current = self.board {
            saved[current] = position
        }
        if plans[board] != plan { plans[board] = plan }
        if self.board != board {
            self.board = board
            position = saved[board]
            spotlit = nil
        }
        let count = stops.count
        if let position, position >= count {
            self.position = count == 0 ? nil : count - 1
        }
    }

    /// The anchors a board's views placed. Kept per board, so a board shown again has them at once.
    func setAnchors(_ anchors: [String: ComposerUpdateAnchor], board: String) {
        let rounded = anchors.mapValues { anchor in
            var anchor = anchor
            anchor.frame = anchor.frame.integral
            return anchor
        }
        if anchorsByBoard[board] != rounded { anchorsByBoard[board] = rounded }
    }

    /// What's still seen after Orbit is put together again; an update made since then is unseen.
    func resetSeen(_ keys: Set<String>) {
        seen = keys
    }

    func markSeen(_ keys: Set<String>) {
        let fresh = keys.subtracting(seen)
        guard !fresh.isEmpty else { return }
        seen.formUnion(fresh)
        onSeen(fresh)
    }

    func setSpotlit(_ address: String?) {
        if spotlit != address { spotlit = address }
    }

    func next() {
        let stops = stops
        // At a piece that opens a node or page with updates, Next goes inside first.
        if let position, position < stops.count, let opens = stops[position].opens, !entered.contains(opens) {
            entered.insert(opens)
            ask(stops[position], opens: true)
            return
        }
        let target = (position ?? -1) + 1
        if target < stops.count {
            position = target
            ask(stops[target], opens: false)
            // Reaching an update with the navigator is seeing it.
            markSeen(stops[target].seenKeys)
        } else if !isAtRoot {
            leaveCount += 1
        } else {
            onFinished()
        }
    }

    func previous() {
        let stops = stops
        guard let position, position > 0, position - 1 < stops.count else { return }
        self.position = position - 1
        ask(stops[position - 1], opens: false)
        markSeen(stops[position - 1].seenKeys)
    }

    private func ask(_ stop: Stop, opens: Bool) {
        nonce += 1
        request = Request(address: stop.address, piece: stop.piece, opens: opens, nonce: nonce)
    }

    // MARK: Stops from the plan and anchors

    /// Where an update goes. Inside something added itself, it goes with that; otherwise to the
    /// deepest anchor holding it; otherwise to its piece.
    nonisolated static func target(of address: String, piece: String, added: Set<String>,
                                   anchors: [String: ComposerUpdateAnchor]) -> String {
        let lineage = ComposerUpdateAddress.lineage(of: address)
        if let new = lineage.dropLast().first(where: { added.contains($0) }) { return new }
        return lineage.reversed().first { anchors[$0] != nil } ?? piece
    }

    /// The frame to place a stop by: its own anchor when shown, otherwise the nearest shown anchor
    /// that holds it.
    nonisolated static func placement(of address: String, anchors: [String: ComposerUpdateAnchor]) -> ComposerUpdateAnchor? {
        for candidate in ComposerUpdateAddress.lineage(of: address).reversed() {
            if let anchor = anchors[candidate], anchor.isPresented { return anchor }
        }
        return nil
    }

    /// Stops in reading order: by piece, then in the order the container keeps them (cards as
    /// arranged, days by date, rows top to bottom), then by where they are.
    nonisolated static func stops(plan: Plan, anchors: [String: ComposerUpdateAnchor]) -> [Stop] {
        var stops: [String: Stop] = [:]
        for update in plan.updates {
            let pieceKey = update.piece.rawValue.lowercased()
            let target = target(of: update.address, piece: pieceKey, added: plan.added, anchors: anchors)
            var stop = stops[target] ?? Stop(address: target, piece: update.piece, order: update.order)
            stop.covers.insert(update.address)
            stop.order = min(stop.order, update.order)
            stops[target] = stop
        }
        for opener in plan.openers {
            let key = opener.piece.rawValue.lowercased()
            var stop = stops[key] ?? Stop(address: key, piece: opener.piece, order: opener.order)
            stop.covers.insert(opener.board.uuidString.lowercased())
            if opener.opens, stop.opens == nil { stop.opens = opener.board }
            stops[key] = stop
        }
        return stops.values.sorted { a, b in
            if a.order != b.order { return a.order < b.order }
            let firstOrder = anchors[a.address]?.order ?? 0
            let secondOrder = anchors[b.address]?.order ?? 0
            if firstOrder != secondOrder { return firstOrder < secondOrder }
            if let first = placement(of: a.address, anchors: anchors), let second = placement(of: b.address, anchors: anchors) {
                if first.frame.minY != second.frame.minY { return first.frame.minY < second.frame.minY }
                if first.frame.minX != second.frame.minX { return first.frame.minX < second.frame.minX }
            }
            return a.address < b.address
        }
    }
}

/// Watches what's on screen: a stop shown mostly on screen is seen, and the stop the navigator
/// brought up is spotlit while it's there. It reads the scroll position here, so scrolling doesn't
/// redraw the board.
struct ComposerUpdateWatcher: View {
    var rail: ComposerScrollBubbleRail
    var width: CGFloat
    var guide: ComposerUpdateGuide
    var board: String

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onChange(of: onScreen, initial: true) { _, shown in
                guard guide.board == board else { return }
                guide.markSeen(Set(guide.stops.filter { shown.contains($0.address) }.flatMap(\.seenKeys)))
            }
            // Next can bring up a stop that's already on screen, so the spotlight follows the ask too.
            .onChange(of: spotlight, initial: true) { _, address in
                guard guide.board == board else { return }
                guide.setSpotlit(address)
            }
    }

    /// The stop the navigator asked for, while it's on screen.
    private var spotlight: String? {
        guard let asked = guide.request, !asked.opens else { return nil }
        return onScreen.contains(asked.address) ? asked.address : nil
    }

    /// Stops shown mostly on screen: half the thing, or half the screen for something taller.
    private var onScreen: Set<String> {
        guard guide.board == board, let visible = rail.metrics.visibleContentRect(width: width) else { return [] }
        let anchors = guide.anchors
        var shown = Set<String>()
        for stop in guide.stops {
            guard let anchor = anchors[stop.address], anchor.isPresented,
                  anchor.frame.width > 1, anchor.frame.height > 1 else { continue }
            let overlap = anchor.frame.intersection(visible)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area >= anchor.frame.width * anchor.frame.height * 0.5 || area >= visible.width * visible.height * 0.5 {
                shown.insert(stop.address)
            }
        }
        return shown
    }
}

/// Dims the board slightly around the spotlit stop, with a soft opening where it is.
struct ComposerSpotlightDim: View {
    var guide: ComposerUpdateGuide
    var board: String

    /// How much darker the rest of the board gets. An experiment: see update-navigation.md.
    static let dimming = 0.5
    /// Room around the spotlit thing left undimmed, so its glow shows in full.
    static let opening: CGFloat = 26

    var body: some View {
        let frame = guide.board == board ? guide.spotlit.flatMap { guide.anchors[$0]?.frame } : nil
        ZStack {
            if let frame {
                Rectangle()
                    .fill(Color.black.opacity(Self.dimming))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .frame(width: frame.width + 2 * Self.opening, height: frame.height + 2 * Self.opening)
                            .position(x: frame.midX, y: frame.midY)
                            .blur(radius: 18)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: frame)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Environment: every update's address on the board opened from Orbit, and in its nodes and pages,
/// and which of them were added rather than changed.
private struct ComposerUpdateAddressesKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

private struct ComposerAddedAddressesKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

extension EnvironmentValues {
    var composerUpdateAddresses: Set<String> {
        get { self[ComposerUpdateAddressesKey.self] }
        set { self[ComposerUpdateAddressesKey.self] = newValue }
    }

    var composerAddedAddresses: Set<String> {
        get { self[ComposerAddedAddressesKey.self] }
        set { self[ComposerAddedAddressesKey.self] = newValue }
    }
}

extension View {
    /// Marks where something that may have an update appears. On a board opened from Orbit, if it
    /// holds an update, it glows until what's in it is seen, glows brighter while the navigator has
    /// it spotlit, and tells the guide where it is. Elsewhere it does nothing.
    func updateAnchor(_ address: String, isPresented: Bool = true, order: Int = 0, leadsElsewhere: Bool = false) -> some View {
        modifier(ComposerUpdateAnchorModifier(address: address, isPresented: isPresented, order: order,
                                              leadsElsewhere: leadsElsewhere))
    }

    /// Places anchors for things a container holds but isn't showing now, at the container.
    func hiddenUpdateAnchors(_ addresses: [String: Int]) -> some View {
        modifier(ComposerHiddenUpdateAnchors(addresses: addresses))
    }
}

private struct ComposerUpdateAnchorModifier: ViewModifier {
    var address: String
    var isPresented: Bool
    var order: Int
    var leadsElsewhere: Bool

    @Environment(ComposerUpdateGuide.self) private var guide: ComposerUpdateGuide?
    @Environment(\.composerUpdateAddresses) private var addresses
    @Environment(\.composerCoordinateSpace) private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var held: [String] {
        addresses.filter { ComposerUpdateAddress.isWithin($0, address) }
    }

    func body(content: Content) -> some View {
        if let guide, leadsElsewhere || !held.isEmpty {
            let unseen = leadsElsewhere || held.contains { !guide.seen.contains($0) }
            content
                .modifier(ComposerSpotlightGlow(
                    strength: unseen ? 1 : 0,
                    isSpotlit: guide.spotlit == address,
                    reduceMotion: reduceMotion
                ))
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ComposerUpdateAnchorKey.self,
                            value: [address: ComposerUpdateAnchor(
                                frame: proxy.frame(in: .named(space + ".canvas")),
                                isPresented: isPresented,
                                order: order
                            )]
                        )
                    }
                }
                .accessibilityCustomContent("Update", unseen ? "New" : "Seen")
        } else {
            content
        }
    }
}

private struct ComposerHiddenUpdateAnchors: ViewModifier {
    var addresses: [String: Int]

    @Environment(ComposerUpdateGuide.self) private var guide: ComposerUpdateGuide?
    @Environment(\.composerCoordinateSpace) private var space

    func body(content: Content) -> some View {
        if guide != nil, !addresses.isEmpty {
            content.background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named(space + ".canvas"))
                    Color.clear.preference(
                        key: ComposerUpdateAnchorKey.self,
                        value: addresses.mapValues { ComposerUpdateAnchor(frame: frame, isPresented: false, order: $0) }
                    )
                }
            }
        } else {
            content
        }
    }
}

/// The spotlight: a glow just outside the thing, following its shape. While spotlit it's brighter
/// and wider, the thing lifts a little, and it pulses once on arrival; it fades away once what's in
/// it is seen.
private struct ComposerSpotlightGlow: ViewModifier {
    var strength: Double
    var isSpotlit: Bool
    var reduceMotion: Bool

    @State private var pulse = false

    func body(content: Content) -> some View {
        let lit = isSpotlit && strength > 0
        content
            .shadow(color: .white.opacity((lit ? 1 : 0.75) * strength), radius: lit ? (pulse ? 14 : 9) : 6)
            .shadow(color: .white.opacity((lit ? 0.85 : 0.45) * strength), radius: lit ? (pulse ? 34 : 24) : 14)
            .shadow(color: .white.opacity((lit ? 0.5 : 0) * strength), radius: lit ? (pulse ? 60 : 44) : 0)
            .scaleEffect(lit && !reduceMotion ? 1.03 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: strength)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: lit)
            .onChange(of: lit) { _, lit in
                guard lit, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.25)) { pulse = true }
                withAnimation(.easeInOut(duration: 0.45).delay(0.25)) { pulse = false }
            }
    }
}

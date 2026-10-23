import Foundation

/// A followed board that gained pieces in the last day.
struct MosaicOrbitItem: Identifiable, Hashable, Sendable {
    enum Role: String, Sendable {
        case mosaic
        case pursuit
    }

    /// One change: a new piece, something new inside one, writing, an item checked off.
    struct Piece: Hashable, Sendable {
        var id: String
        /// The piece to mark, lowercased as the board stores it.
        var piece: String
        var kind: String
        /// The nodes and pages it sits in, nearest first.
        var inside: [UUID] = []
        /// When it last changed. A later change to the same thing makes it new again.
        var at: Date? = nil

        /// Where the change is: the piece, or something inside it ("c/carouselitems/two"), without
        /// what kind of change it was. Seeing it is recorded under this address.
        nonisolated var address: String {
            (id.split(separator: "#", maxSplits: 1).first.map(String.init) ?? id).lowercased()
        }

        nonisolated var seenKey: String { address }
    }

    var id: UUID
    var role: Role
    var title: String
    var owner: MosaicPersonResult
    var latestAt: Date
    /// Newest first.
    var pieces: [Piece]
    /// Opened since its latest update.
    var seen: Bool
    var coverFile: String? = nil
    var coverAsset: String? = nil
    /// What the follower has seen of it, from any device: each key with the time of the version seen.
    var seenThrough: [String: Date] = [:]

    var ownerName: String { owner.displayName.isEmpty ? owner.username : owner.displayName }

    /// "Ada · Golf", or just "Ada" for their Mosaic.
    var heading: String {
        guard role == .pursuit else { return ownerName }
        return "\(ownerName) · \(title.isEmpty ? "Pursuit" : title)"
    }

    /// Opens the board itself: the Pursuit, or the owner's Mosaic.
    var target: MosaicVisitTarget {
        MosaicVisitTarget(person: owner, pursuitID: role == .pursuit ? id : nil)
    }

    /// Every update's address, on the board and in its nodes and pages.
    var addresses: Set<String> { Set(pieces.map(\.address)) }
    /// The addresses of things added, rather than changed.
    var addedAddresses: Set<String> { Set(pieces.filter { !$0.id.contains("#") }.map(\.address)) }
    var newBoardIDs: Set<UUID> { Set(pieces.flatMap(\.inside)) }

    init(id: UUID, role: Role, title: String, owner: MosaicPersonResult, latestAt: Date, pieces: [Piece], seen: Bool,
         coverFile: String? = nil, coverAsset: String? = nil, seenThrough: [String: Date] = [:]) {
        self.id = id
        self.role = role
        self.title = title
        self.owner = owner
        self.latestAt = latestAt
        self.pieces = pieces
        self.seen = seen
        self.coverFile = coverFile
        self.coverAsset = coverAsset
        self.seenThrough = seenThrough
    }

    /// The Pursuit's cover, in the shape the cover view reads.
    var cover: MosaicFollowedItem {
        MosaicFollowedItem(kind: .pursuit, targetID: id, owner: owner, title: title,
                           coverFile: coverFile, coverAsset: coverAsset)
    }

    init?(row: [String: Any]) {
        guard let id = (row["board_id"] as? String).flatMap(UUID.init(uuidString:)),
              let role = (row["role"] as? String).flatMap(Role.init(rawValue:)),
              let ownerID = (row["owner_id"] as? String).flatMap(UUID.init(uuidString:)),
              let username = row["username"] as? String,
              let latestAt = (row["latest_at"] as? String).flatMap(ComposerServerTime.date(from:)),
              let pieces = row["pieces"] as? [[String: Any]]
        else { return nil }
        self.init(
            id: id,
            role: role,
            title: (row["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            owner: MosaicPersonResult(
                id: ownerID,
                username: username,
                displayName: (row["display_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                avatarPath: row["avatar_path"] as? String
            ),
            latestAt: latestAt,
            pieces: pieces.compactMap { piece in
                guard let id = piece["id"] as? String, let kind = piece["kind"] as? String else { return nil }
                return Piece(
                    id: id,
                    piece: ((piece["piece"] as? String) ?? id).lowercased(),
                    kind: kind,
                    inside: (piece["in"] as? [String] ?? []).compactMap(UUID.init(uuidString:)),
                    at: (piece["at"] as? String).flatMap(ComposerServerTime.date(from:))
                )
            },
            seen: row["seen"] as? Bool ?? false,
            coverFile: row["cover_file"] as? String,
            coverAsset: row["cover_asset"] as? String,
            seenThrough: (row["seen_keys"] as? [String: String] ?? [:]).compactMapValues(ComposerServerTime.date(from:))
        )
    }
}

enum MosaicOrbitText {
    /// "now", "5m", "2h".
    static func age(of date: Date, now: Date = .now) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return "\(Int(seconds / 3600))h"
    }
}

struct MosaicOrbitClient: Sendable {
    var config: SupabaseSyncConfig
    var session: URLSession = .shared

    func feed(accessToken: String) async throws -> [MosaicOrbitItem] {
        var request = URLRequest(url: config.url.appending(path: "rest/v1/rpc/today_feed"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { throw SupabaseDocumentSyncError.requestFailed }
        return rows.compactMap(MosaicOrbitItem.init(row:))
    }

    /// Records what was seen on a board: each key with the time of the version seen.
    func markSeen(board: UUID, seen: [String: Date], accessToken: String) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let body: [String: Any] = [
            "p_board": board.uuidString.lowercased(),
            "p_seen": seen.mapValues { formatter.string(from: $0) }
        ]
        var request = URLRequest(url: config.url.appending(path: "rest/v1/rpc/mark_orbit_seen"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseDocumentSyncError.requestFailed }
        guard (200..<300).contains(http.statusCode) else {
            // Only what may go through later is worth sending again.
            let later = http.statusCode >= 500 || [401, 408, 429].contains(http.statusCode)
            throw later ? SupabaseDocumentSyncError.requestFailed : Rejected()
        }
    }

    /// The server turned it down for good.
    struct Rejected: Error {}
}

/// The day's updates, shared by the Orbit tab and its badge. What's been seen is kept on the phone
/// and on the server, so a board finished on one device is finished on all of them.
@MainActor
@Observable
final class MosaicOrbitModel {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed
    }

    private(set) var items: [MosaicOrbitItem] = []
    private(set) var phase = Phase.idle
    /// Seen on this phone: for each board, each key with the time of the version seen.
    private(set) var viewed: [UUID: [String: Date]] = [:]
    @ObservationIgnored private let account: MosaicAccount
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var viewedAt: [UUID: Date] = [:]
    /// Seen here and not yet sent; everything kept on the phone is sent again once per launch,
    /// which costs little and covers sends cut off by the app closing.
    @ObservationIgnored private var unsent: [UUID: [String: Date]] = [:]
    @ObservationIgnored private var sendTask: Task<Void, Never>?

    init(account: MosaicAccount) {
        self.account = account
        loadViewed()
        unsent = viewed
    }

    /// The tab's badge: boards not done.
    var unseenCount: Int { items.filter { !isDone($0) }.count }

    /// What's been seen of a board, here or on another device.
    func seen(on item: MosaicOrbitItem) -> [String: Date] {
        item.seenThrough.merging(viewed[item.id] ?? [:]) { max($0, $1) }
    }

    /// How much of a board's updates have been seen, from 0 to 1.
    func progress(of item: MosaicOrbitItem) -> Double {
        Self.progress(of: item, seen: seen(on: item))
    }

    func isDone(_ item: MosaicOrbitItem) -> Bool { progress(of: item) >= 1 }

    /// The keys of updates already seen, for a board's guide.
    func seenKeys(of item: MosaicOrbitItem) -> Set<String> {
        let seen = seen(on: item)
        return Set(item.pieces.filter { Self.isSeen($0, through: seen) }.map(\.seenKey))
    }

    /// Boards not done first and done ones last, each newest first, as Instagram orders stories.
    func ordered() -> [MosaicOrbitItem] {
        Self.ordered(items) { isDone($0) }
    }

    nonisolated static func isSeen(_ piece: MosaicOrbitItem.Piece, through seen: [String: Date]) -> Bool {
        guard let through = seen[piece.seenKey] else { return false }
        // A change with no time comes from an older server; having seen it at all is enough.
        guard let at = piece.at else { return true }
        return through >= at
    }

    nonisolated static func progress(of item: MosaicOrbitItem, seen: [String: Date]) -> Double {
        guard !item.pieces.isEmpty else { return 1 }
        let done = item.pieces.filter { isSeen($0, through: seen) }.count
        return Double(done) / Double(item.pieces.count)
    }

    nonisolated static func ordered(_ items: [MosaicOrbitItem], isDone: (MosaicOrbitItem) -> Bool) -> [MosaicOrbitItem] {
        items.enumerated()
            .map { (index: $0.offset, item: $0.element, done: isDone($0.element)) }
            .sorted { a, b in
                if a.done != b.done { return !a.done }
                if a.item.latestAt != b.item.latestAt { return a.item.latestAt > b.item.latestAt }
                return a.index < b.index
            }
            .map(\.item)
    }

    /// Records keys seen on a board, as the versions the board showed. Keys that aren't updates are
    /// left out.
    func markViewed(_ keys: Set<String>, on item: MosaicOrbitItem) {
        var board = viewed[item.id] ?? [:]
        var fresh: [String: Date] = [:]
        for key in keys {
            let versions = item.pieces.filter { $0.seenKey == key }
            guard !versions.isEmpty else { continue }
            let through = versions.compactMap(\.at).max() ?? .now
            if let before = board[key], before >= through { continue }
            board[key] = through
            fresh[key] = through
        }
        guard !fresh.isEmpty else { return }
        viewed[item.id] = board
        viewedAt[item.id] = .now
        unsent[item.id, default: [:]].merge(fresh) { max($0, $1) }
        saveViewed()
        scheduleSend()
    }

    // MARK: Sent to the server

    /// Sends a few seconds after the last thing seen, so a run of updates goes in one request.
    private func scheduleSend() {
        sendTask?.cancel()
        sendTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.sendSeen()
        }
    }

    /// Sends what's waiting. What fails waits for the next send.
    func sendSeen() async {
        let batch = unsent
        guard !batch.isEmpty else { return }
        unsent = [:]
        guard let config = SupabaseSyncConfig.current(), let token = await account.accessToken() else {
            requeue(batch)
            return
        }
        let client = MosaicOrbitClient(config: config)
        for (board, seen) in batch {
            do {
                try await client.markSeen(board: board, seen: seen, accessToken: token)
            } catch is MosaicOrbitClient.Rejected {
                // Kept on the phone still; sending it again wouldn't help.
            } catch {
                requeue([board: seen])
            }
        }
    }

    private func requeue(_ batch: [UUID: [String: Date]]) {
        for (board, seen) in batch {
            unsent[board, default: [:]].merge(seen) { max($0, $1) }
        }
    }

    // MARK: Kept on the phone

    private struct Stored: Codable {
        var seen: [String: Date]
        var at: Date
    }

    /// Updates stay in Orbit for a day, so what was seen is kept a little longer and then dropped.
    nonisolated static let viewedKeptFor: TimeInterval = 36 * 60 * 60

    private var viewedDefaultsKey: String? {
        account.session.map { "orbit.seen.\($0.userID.uuidString.lowercased())" }
    }

    /// Kept before what was seen had times: each board's keys, and when the board was last looked at.
    private struct StoredBefore: Codable {
        var keys: [String]
        var at: Date
    }

    private func loadViewed() {
        if let session = account.session {
            let before = "today.viewed.\(session.userID.uuidString.lowercased())"
            if let data = UserDefaults.standard.data(forKey: before),
               let stored = try? JSONDecoder().decode([String: StoredBefore].self, from: data) {
                // Seen when the board was last looked at, which covers every version shown then.
                for (id, entry) in stored {
                    guard let board = UUID(uuidString: id), Date.now.timeIntervalSince(entry.at) < Self.viewedKeptFor else { continue }
                    viewed[board] = Dictionary(entry.keys.map { ($0, entry.at) }) { max($0, $1) }
                    viewedAt[board] = entry.at
                }
                UserDefaults.standard.removeObject(forKey: before)
                saveViewed()
            }
        }
        guard let key = viewedDefaultsKey,
              let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode([String: Stored].self, from: data)
        else { return }
        for (id, entry) in stored {
            guard let board = UUID(uuidString: id), Date.now.timeIntervalSince(entry.at) < Self.viewedKeptFor else { continue }
            viewed[board] = entry.seen
            viewedAt[board] = entry.at
        }
    }

    private func saveViewed() {
        guard let key = viewedDefaultsKey else { return }
        var stored: [String: Stored] = [:]
        for (board, seen) in viewed {
            let at = viewedAt[board] ?? .now
            guard Date.now.timeIntervalSince(at) < Self.viewedKeptFor else { continue }
            stored[board.uuidString] = Stored(seen: seen, at: at)
        }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Loads the day's updates. Calls made while one is loading wait for it rather than starting another.
    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await load() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func load() async {
        if items.isEmpty { phase = .loading }
        // What was seen goes first, so the feed comes back with it.
        sendTask?.cancel()
        await sendSeen()
        guard let config = SupabaseSyncConfig.current(), let token = await account.accessToken() else {
            phase = .failed
            return
        }
        do {
            items = try await MosaicOrbitClient(config: config).feed(accessToken: token)
            phase = .ready
        } catch {
            if items.isEmpty { phase = .failed }
        }
    }

}

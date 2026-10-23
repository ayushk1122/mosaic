import Foundation

/// One tile in Explore: a shared Mosaic or Pursuit, its owner, and its preview image.
struct MosaicExploreItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case mosaic
        case pursuit
    }

    var id: UUID
    var kind: Kind
    var title: String
    var ownerID: UUID
    var username: String
    var displayName: String
    var avatarPath: String?
    var previewPath: String
    var followerCount = 0

    var ownerName: String { displayName.isEmpty ? username : displayName }

    /// "Name" for a Mosaic, "Name: Pursuit" for a Pursuit.
    var caption: String {
        guard kind == .pursuit else { return ownerName }
        let pursuit = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(ownerName): \(pursuit.isEmpty ? "Pursuit" : pursuit)"
    }

    /// Opens the owner's Mosaic, on the Pursuit when the tile is one.
    var target: MosaicVisitTarget {
        MosaicVisitTarget(person: owner, pursuitID: kind == .pursuit ? id : nil)
    }

    /// Opens the owner's Mosaic itself, whichever board the tile is.
    var ownerTarget: MosaicVisitTarget {
        MosaicVisitTarget(person: owner, pursuitID: nil)
    }

    private var owner: MosaicPersonResult {
        MosaicPersonResult(id: ownerID, username: username, displayName: displayName, avatarPath: avatarPath)
    }

    init(id: UUID, kind: Kind, title: String, ownerID: UUID, username: String,
         displayName: String, avatarPath: String?, previewPath: String, followerCount: Int = 0) {
        self.id = id
        self.kind = kind
        self.title = title
        self.ownerID = ownerID
        self.username = username
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.previewPath = previewPath
        self.followerCount = followerCount
    }

    init?(row: [String: Any]) {
        guard let id = (row["document_id"] as? String).flatMap(UUID.init(uuidString:)),
              let kind = (row["role"] as? String).flatMap(Kind.init(rawValue:)),
              let ownerID = (row["owner_id"] as? String).flatMap(UUID.init(uuidString:)),
              let username = row["username"] as? String,
              let previewPath = row["preview_path"] as? String
        else { return nil }
        self.init(
            id: id,
            kind: kind,
            title: row["title"] as? String ?? "",
            ownerID: ownerID,
            username: username,
            displayName: (row["display_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            avatarPath: row["avatar_path"] as? String,
            previewPath: previewPath,
            followerCount: (row["follower_count"] as? NSNumber)?.intValue ?? 0
        )
    }
}

/// Talks to the Explore functions: sharing a board, its preview image, and the feed.
struct MosaicExploreClient: Sendable {
    enum Filter: String, CaseIterable, Identifiable, Sendable {
        case all
        case mosaics
        case pursuits

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All"
            case .mosaics: "Mosaics"
            case .pursuits: "Pursuits"
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable, Sendable {
        case shuffle
        case trending
        case popular
        case leastPopular = "least_popular"
        case newest
        case updated

        var id: String { rawValue }

        var title: String {
            switch self {
            case .shuffle: "Shuffled"
            case .trending: "Trending"
            case .popular: "Most followers"
            case .leastPopular: "Fewest followers"
            case .newest: "Newest to Explore"
            case .updated: "Recently updated"
            }
        }

        /// Shown under the title in the menu.
        var detail: String? {
            switch self {
            case .trending: "Most new followers this week"
            default: nil
            }
        }

        var systemImage: String {
            switch self {
            case .shuffle: "shuffle"
            case .trending: "flame"
            case .popular: "arrow.down"
            case .leastPopular: "arrow.up"
            case .newest: "sparkle"
            case .updated: "clock.arrow.circlepath"
            }
        }
    }

    static let pageSize = 30

    /// One page of shared boards, never the caller's own. Boards the sort ranks the same, or all of
    /// them when shuffled, come in the order `seed` shuffles them to. `query` matches board titles
    /// and owners' display names and usernames; `hideFollowed` leaves out boards the caller follows.
    func feed(filter: Filter, sort: Sort = .shuffle, hideFollowed: Bool = false, query: String = "",
              seed: String, offset: Int, accessToken: String) async throws -> [MosaicExploreItem] {
        let data = try await rpc("explore_feed", body: [
            "p_kind": filter.rawValue,
            "p_seed": seed,
            "p_offset": offset,
            "p_limit": Self.pageSize,
            "p_query": query.trimmingCharacters(in: .whitespacesAndNewlines),
            "p_sort": sort.rawValue,
            "p_hide_followed": hideFollowed
        ], accessToken: accessToken)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        return rows.compactMap(MosaicExploreItem.init(row:))
    }

    var config: SupabaseSyncConfig
    var session: URLSession = .shared

    /// Only a public Mosaic, or a public Pursuit on a public Mosaic, can be shared; the server checks.
    func setSharing(id: UUID, shared: Bool, accessToken: String) async throws {
        _ = try await rpc("set_explore_sharing", body: [
            "p_id": id.uuidString.lowercased(),
            "p_shared": shared
        ], accessToken: accessToken)
    }

    /// Stores the image in the owner's media folder as `{asset}/display`, then points the board at it.
    func publishPreview(_ jpeg: Data, for id: UUID, ownerID: UUID, accessToken: String) async throws {
        let asset = UUID()
        let path = "\(ownerID.uuidString.lowercased())/\(asset.uuidString.lowercased())/display"
        let root = config.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/storage/v1/object/media/\(path)") else {
            throw SupabaseDocumentSyncError.requestFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jpeg
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SupabaseDocumentSyncError.requestFailed
        }
        _ = try await rpc("set_explore_preview", body: [
            "p_id": id.uuidString.lowercased(),
            "p_asset": asset.uuidString.lowercased()
        ], accessToken: accessToken)
    }

    /// The owner's boards that are shared, and when each preview was last made.
    func sharedBoards(ownerID: UUID, accessToken: String) async throws -> [UUID: Date?] {
        var components = URLComponents(url: config.url.appending(path: "rest/v1/documents"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "owner_id", value: "eq.\(ownerID.uuidString.lowercased())"),
            URLQueryItem(name: "explore_shared", value: "eq.true"),
            URLQueryItem(name: "select", value: "id,explore_preview_at")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { throw SupabaseDocumentSyncError.requestFailed }
        var shared: [UUID: Date?] = [:]
        for row in rows {
            guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)) else { continue }
            shared[id] = (row["explore_preview_at"] as? String).flatMap(Self.date(from:))
        }
        return shared
    }

    private static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private func rpc(_ name: String, body: [String: Any], accessToken: String) async throws -> Data {
        var request = URLRequest(url: config.url.appending(path: "rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SupabaseDocumentSyncError.requestFailed
        }
        return data
    }
}

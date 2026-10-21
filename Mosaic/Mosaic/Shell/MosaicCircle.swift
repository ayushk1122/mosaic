import ImageIO
import SwiftUI
import UIKit

struct MosaicCircleBubble: Identifiable, Hashable, Sendable {
    var id: UUID
    var role: String
    var title: String
    var level: MosaicVisibilityLevel
    var followerCount: Int
    var pendingCount: Int
    var badgeCount: Int

    var isMosaic: Bool { role == "mosaic" }
}

struct MosaicCirclePerson: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case request
        case follower
    }

    var kind: Kind
    var requestID: UUID?
    var personID: UUID
    var username: String
    var displayName: String
    var avatarPath: String?
    /// They follow the signed-in person's Mosaic.
    var followsMe = false
    /// The signed-in person follows their Mosaic.
    var iFollow = false
    /// The signed-in person is waiting on a request to see their private Mosaic.
    var iRequested = false
    var hasMosaic = false
    /// Their Mosaic can be followed now, without a request.
    var canFollow = false
    /// When they followed (or asked). Nil only for rows from an older server.
    var followedAt: Date?

    /// The single follow button beside a person, Instagram style.
    enum FollowButton: Equatable, Sendable {
        case following, requested, followBack, follow

        var title: String {
            switch self {
            case .following: "Following"
            case .requested: "Requested"
            case .followBack: "Follow back"
            case .follow: "Follow"
            }
        }
    }

    var id: String { "\(kind.rawValue)-\(requestID?.uuidString ?? personID.uuidString)" }
    var name: String { displayName.isEmpty ? username : displayName }

    /// Matches the display name or username, ignoring case, accents, and a leading "@".
    func matches(_ query: String) -> Bool {
        var needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        while needle.hasPrefix("@") { needle.removeFirst() }
        guard !needle.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return displayName.range(of: needle, options: options) != nil
            || username.range(of: needle, options: options) != nil
    }
    var asResult: MosaicPersonResult {
        MosaicPersonResult(id: personID, username: username, displayName: displayName, avatarPath: avatarPath)
    }

    /// No button for someone without a Mosaic, since there is nothing to follow.
    var followButton: FollowButton? {
        if iFollow { return .following }
        if iRequested { return .requested }
        guard hasMosaic else { return nil }
        return followsMe ? .followBack : .follow
    }

    /// Applies `change` to every row for `personID`, since one person can be both a request and a follower.
    static func updating(
        _ personID: UUID,
        in people: [MosaicCirclePerson],
        _ change: (inout MosaicCirclePerson) -> Void
    ) -> [MosaicCirclePerson] {
        people.map { person in
            guard person.personID == personID else { return person }
            var person = person
            change(&person)
            return person
        }
    }

    /// An accepted request leaves Requests and appears first under Followers, without reloading the list.
    static func accepting(_ request: MosaicCirclePerson, in people: [MosaicCirclePerson]) -> [MosaicCirclePerson] {
        var next = people.filter { $0.id != request.id }
        guard !next.contains(where: { $0.kind == .follower && $0.personID == request.personID }) else { return next }
        var follower = request
        follower.kind = .follower
        follower.requestID = nil
        follower.followedAt = .now
        next.insert(follower, at: next.firstIndex(where: { $0.kind == .follower }) ?? next.endIndex)
        return next
    }
}

/// How a circle's follower list is ordered or narrowed. One applies at a time, per circle.
enum MosaicFollowerFilter: String, CaseIterable, Identifiable, Sendable {
    case latest
    case earliest
    case following
    case notFollowing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latest: "Latest"
        case .earliest: "Earliest"
        case .following: "Following"
        case .notFollowing: "Not following"
        }
    }

    /// The chosen one stands in for the filter button itself.
    var systemImage: String {
        switch self {
        case .latest: "arrow.down"
        case .earliest: "arrow.up"
        case .following: "person.crop.circle.badge.checkmark"
        case .notFollowing: "person.crop.circle.badge.xmark"
        }
    }

    /// Bare arrows read heavier than circled symbols at the same size, so the button draws them smaller.
    var isBareSymbol: Bool { self == .latest || self == .earliest }

    /// Latest and Earliest reorder everyone by follow date. Following and Not following keep
    /// newest first and show only people the owner does, or doesn't, follow back.
    func apply(to followers: [MosaicCirclePerson]) -> [MosaicCirclePerson] {
        let newestFirst = followers.enumerated().sorted { lhs, rhs in
            switch (lhs.element.followedAt, rhs.element.followedAt) {
            case let (l?, r?) where l != r: return l > r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
        switch self {
        case .latest: return newestFirst
        case .earliest: return newestFirst.reversed()
        case .following: return newestFirst.filter(\.iFollow)
        case .notFollowing: return newestFirst.filter { !$0.iFollow }
        }
    }

    /// Shown when the filter leaves nobody (before any search narrows it further).
    var emptyMessage: String {
        switch self {
        case .latest, .earliest: "No one follows this yet."
        case .following: "You don’t follow any of these followers yet."
        case .notFollowing: "You follow every one of these followers."
        }
    }
}

/// Places Pursuit bubbles on rings around the Mosaic, like petals.
/// The first ring holds 10, each ring out holds 6 more, and each ring out uses smaller bubbles.
/// The layout grows to fill the screen. When the rings would not fit, the space between them tightens first, then the whole layout scales down.
enum MosaicCircleLayout {
    struct Bubble: Equatable {
        var center: CGPoint
        var size: CGFloat
        var labelWidth: CGFloat
    }

    struct Plan: Equatable {
        var mosaicSize: CGFloat
        var ringRadii: [CGFloat]
        var bubbles: [Bubble]
        var size: CGSize
    }

    static let mosaicSize: CGFloat = 104
    static let firstSize: CGFloat = 60
    static let firstRadius: CGFloat = 132
    static let shrink: CGFloat = 0.82
    static let smallestSize: CGFloat = 34
    static let labelHeight: CGFloat = 22
    static let ringGap: CGFloat = 8
    static let edgeMargin: CGFloat = 12
    static let largestScale: CGFloat = 1.6

    static func ringCapacity(_ ring: Int) -> Int { 10 + 6 * (ring - 1) }

    static func ringCount(for count: Int) -> Int {
        var rings = 0
        var placed = 0
        while placed < count {
            rings += 1
            placed += ringCapacity(rings)
        }
        return rings
    }

    static func bubbleSize(onRing ring: Int) -> CGFloat {
        max(smallestSize, firstSize * pow(shrink, CGFloat(ring - 1)))
    }

    /// Ring radii with `room` from 0 (rings packed, staggered bubbles nest between each other) to 1 (a full label's space between rings).
    static func radii(rings: Int, room: CGFloat) -> [CGFloat] {
        let tightFirst = mosaicSize / 2 + firstSize / 2 + labelHeight + 4
        var radii: [CGFloat] = []
        for ring in stride(from: 1, through: rings, by: 1) {
            if let previous = radii.last {
                let packed = bubbleSize(onRing: ring - 1) / 2 + bubbleSize(onRing: ring) / 2 + 6
                radii.append(previous + packed + room * (labelHeight + ringGap - 6))
            } else {
                radii.append(tightFirst + room * (firstRadius - tightFirst))
            }
        }
        return radii
    }

    static func plan(count: Int, width: CGFloat, height: CGFloat = .infinity) -> Plan {
        let rings = ringCount(for: count)
        // Names hang below the bubbles, so only the height has to leave room for one under the outer ring.
        let available = max(0, min(width / 2 - edgeMargin, height / 2 - edgeMargin - labelHeight))

        func extent(_ radii: [CGFloat]) -> CGFloat {
            radii.last.map { $0 + bubbleSize(onRing: rings) / 2 } ?? mosaicSize / 2
        }
        let roomy = extent(radii(rings: rings, room: 1))
        let packed = extent(radii(rings: rings, room: 0))
        let room = roomy - packed > 0 ? min(1, max(0, (available - packed) / (roomy - packed))) : 1
        let ringRadii = radii(rings: rings, room: room)
        let half = extent(ringRadii)
        let scale = rings == 0 ? min(1, available / half) : min(largestScale, available / half)

        var bubbles: [Bubble] = []
        var placed = 0
        for ring in stride(from: 1, through: rings, by: 1) {
            let capacity = ringCapacity(ring)
            let onRing = min(capacity, count - placed)
            let radius = ringRadii[ring - 1] * scale
            let size = bubbleSize(onRing: ring) * scale
            let chord = 2 * radius * sin(.pi / CGFloat(capacity))
            let start = -CGFloat.pi / 2 + (ring.isMultiple(of: 2) ? .pi / CGFloat(onRing) : 0)
            for index in 0..<onRing {
                let angle = start + 2 * .pi * CGFloat(index) / CGFloat(onRing)
                bubbles.append(Bubble(
                    center: CGPoint(x: radius * cos(angle), y: radius * sin(angle)),
                    size: size,
                    labelWidth: max(size, chord - 4)
                ))
            }
            placed += onRing
        }

        return Plan(
            mosaicSize: mosaicSize * scale,
            ringRadii: ringRadii.map { $0 * scale },
            bubbles: bubbles,
            size: CGSize(
                width: 2 * (half * scale + edgeMargin),
                height: 2 * (half * scale + edgeMargin + (rings == 0 ? 0 : labelHeight))
            )
        )
    }
}

/// Small decoded copies of board photos, read through ImageIO so a full-size photo is never held in memory.
enum MosaicThumbnail {
    /// A 72-point bubble on a 3x screen.
    static let bubblePixelSize = 220

    private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "hevc", "3gp"]

    @MainActor private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 64
        return cache
    }()

    static func isVideo(_ fileName: String) -> Bool {
        videoExtensions.contains((fileName as NSString).pathExtension.lowercased())
    }

    nonisolated static func image(at url: URL, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        return image(from: source, maxPixelSize: maxPixelSize)
    }

    nonisolated static func image(data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        return image(from: source, maxPixelSize: maxPixelSize)
    }

    private nonisolated static func image(from source: CGImageSource, maxPixelSize: Int) -> UIImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: thumbnail)
    }

    @MainActor static func cached(_ fileName: String) -> UIImage? {
        cache.object(forKey: fileName as NSString)
    }

    @MainActor static func store(_ image: UIImage, for fileName: String) {
        cache.setObject(image, forKey: fileName as NSString)
    }
}

struct MosaicCircleClient: Sendable {
    var config: SupabaseSyncConfig
    var session: URLSession = .shared

    func overview(accessToken: String) async throws -> [MosaicCircleBubble] {
        let data = try await rpc("circle_overview", body: [:], accessToken: accessToken)
        return try Self.bubbles(from: data)
    }

    func people(documentID: UUID, accessToken: String) async throws -> [MosaicCirclePerson] {
        let data = try await rpc(
            "circle_people",
            body: ["p_document_id": documentID.uuidString.lowercased()],
            accessToken: accessToken
        )
        return try Self.people(from: data)
    }

    /// Distinct visitors since midnight in `timeZone`, by board. Boards without visits today are absent.
    func dailyVisits(timeZone: TimeZone = .current, accessToken: String) async throws -> [UUID: Int] {
        let data = try await rpc("circle_visits", body: ["p_time_zone": timeZone.identifier], accessToken: accessToken)
        return try Self.visitCounts(from: data)
    }

    func markSeen(documentID: UUID, accessToken: String) async throws {
        _ = try await rpc(
            "mark_circle_seen",
            body: ["p_document_id": documentID.uuidString.lowercased()],
            accessToken: accessToken
        )
    }

    func respond(requestID: UUID, accept: Bool, accessToken: String) async throws {
        _ = try await rpc(
            "respond_to_request",
            body: ["p_request_id": requestID.uuidString.lowercased(), "p_accept": accept],
            accessToken: accessToken
        )
    }

    func removeFollower(documentID: UUID, followerID: UUID, accessToken: String) async throws {
        _ = try await rpc(
            "remove_follower",
            body: [
                "p_document_id": documentID.uuidString.lowercased(),
                "p_follower_id": followerID.uuidString.lowercased()
            ],
            accessToken: accessToken
        )
    }

    static func bubbles(from data: Data) throws -> [MosaicCircleBubble] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        return rows.compactMap { row in
            guard let id = (row["document_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let role = row["role"] as? String
            else { return nil }
            return MosaicCircleBubble(
                id: id,
                role: role,
                title: ComposerTitle.singleLine(row["title"] as? String ?? ""),
                level: MosaicVisibilityLevel.parse(row["visibility"] as? String, role: role),
                followerCount: (row["follower_count"] as? NSNumber)?.intValue ?? 0,
                pendingCount: (row["pending_count"] as? NSNumber)?.intValue ?? 0,
                badgeCount: (row["badge_count"] as? NSNumber)?.intValue ?? 0
            )
        }
    }

    static func visitCounts(from data: Data) throws -> [UUID: Int] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        var counts: [UUID: Int] = [:]
        for row in rows {
            guard let id = (row["document_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let count = (row["visit_count"] as? NSNumber)?.intValue
            else { continue }
            counts[id] = count
        }
        return counts
    }

    static func people(from data: Data) throws -> [MosaicCirclePerson] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        return rows.compactMap { row in
            guard let kind = (row["kind"] as? String).flatMap(MosaicCirclePerson.Kind.init(rawValue:)),
                  let personID = (row["person_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let username = row["username"] as? String
            else { return nil }
            return MosaicCirclePerson(
                kind: kind,
                requestID: (row["request_id"] as? String).flatMap(UUID.init(uuidString:)),
                personID: personID,
                username: username,
                displayName: (row["display_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                avatarPath: row["avatar_path"] as? String,
                followsMe: row["follows_me"] as? Bool ?? false,
                iFollow: row["i_follow"] as? Bool ?? false,
                iRequested: row["i_requested"] as? Bool ?? false,
                hasMosaic: row["has_mosaic"] as? Bool ?? false,
                canFollow: row["can_follow"] as? Bool ?? false,
                followedAt: (row["created_at"] as? String).flatMap(Self.timestamp(from:))
            )
        }
    }

    /// PostgREST timestamps, with or without fractional seconds.
    static func timestamp(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        // Postgres sends microseconds; drop the fraction if the formatter refuses six digits.
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return formatter.date(from: trimmed)
    }

    private func rpc(_ name: String, body: [String: Any], accessToken: String) async throws -> Data {
        let endpoint = config.url
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("rpc")
            .appendingPathComponent(name)
        var request = URLRequest(url: endpoint)
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

struct MosaicCircleView: View {
    @Environment(\.mosaicAccount) private var account
    @Environment(\.mosaicTabBarHidden) private var tabBarHidden
    @Environment(ComposerStore.self) private var store

    @State private var bubbles: [MosaicCircleBubble] = []
    @State private var avatarPath: String?
    @State private var ownName = ""
    @State private var loaded = false
    @State private var failed = false
    @State private var opened: MosaicCircleBubble?
    @State private var viewport = CGSize(width: 402, height: 700)
    @State private var covers: [UUID: UIImage] = [:]

    private let muted = Color.white.opacity(0.55)

    private var mosaic: MosaicCircleBubble? { bubbles.first(where: \.isMosaic) }
    private var pursuits: [MosaicCircleBubble] { bubbles.filter { !$0.isMosaic } }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, minHeight: viewport.height)
        }
        .refreshable { await load() }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(tabBarHidden ? .hidden : .visible, for: .tabBar)
        .navigationDestination(item: $opened) { bubble in
            MosaicCircleBubbleView(bubble: bubble)
        }
        .onAppear { Task { await load() } }
        // Includes the media versions, so covers appear once a restore downloads their files.
        .task(id: ComposerCircleCoverKey(files: coverFiles, versions: store.mediaVersions)) { await loadCovers(coverFiles) }
        .accessibilityIdentifier(MosaicTab.circle.screenAccessibilityIdentifier)
        .mosaicPageBackground(.circle)
    }

    @ViewBuilder
    private var content: some View {
        if account == nil {
            note("Sign in to see your Circle.")
        } else if failed && bubbles.isEmpty {
            note("Your Circle could not be loaded.")
        } else if !loaded {
            ProgressView()
                .tint(muted)
        } else if let mosaic {
            ring(mosaic: mosaic)
        } else {
            note("Your Mosaic shows up here after it syncs.")
        }
    }

    private func ring(mosaic: MosaicCircleBubble) -> some View {
        let plan = MosaicCircleLayout.plan(count: pursuits.count, width: viewport.width, height: viewport.height)
        return ZStack {
            ForEach(Array(plan.ringRadii.enumerated()), id: \.offset) { _, radius in
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .frame(width: 2 * radius, height: 2 * radius)
            }
            ForEach(Array(pursuits.enumerated()), id: \.element.id) { index, pursuit in
                let spot = plan.bubbles[index]
                bubbleButton(pursuit, size: spot.size, labelWidth: spot.labelWidth)
                    .offset(x: spot.center.x, y: spot.center.y)
            }
            bubbleButton(mosaic, size: plan.mosaicSize, labelWidth: nil)
        }
        .frame(width: plan.size.width, height: plan.size.height)
    }

    private func bubbleButton(_ bubble: MosaicCircleBubble, size: CGFloat, labelWidth: CGFloat?) -> some View {
        Button {
            opened = bubble
        } label: {
            bubbleFace(bubble, size: size)
                .overlay(alignment: .topTrailing) {
                    if bubble.badgeCount > 0 {
                        Text(bubble.badgeCount > 99 ? "99+" : "\(bubble.badgeCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(Color(red: 0.78, green: 0.22, blue: 0.22), in: Capsule())
                            .overlay(Capsule().stroke(MosaicBrand.inkBlack, lineWidth: 1.5))
                            .offset(x: 2, y: -2)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let labelWidth {
                        Text(title(for: bubble))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(width: labelWidth)
                            .offset(y: 20)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bubble.isMosaic ? "Mosaic" : title(for: bubble))
        .accessibilityValue(
            "\(bubble.followerCount) followers" + (bubble.badgeCount > 0 ? ", \(bubble.badgeCount) to see" : "")
        )
        .accessibilityIdentifier("circle.bubble.\(bubble.isMosaic ? "mosaic" : bubble.id.uuidString.lowercased())")
    }

    @ViewBuilder
    private func bubbleFace(_ bubble: MosaicCircleBubble, size: CGFloat) -> some View {
        if bubble.isMosaic {
            MosaicAvatarView(path: avatarPath, name: ownName.isEmpty ? "M" : ownName, size: size)
                .overlay(Circle().stroke(.white, lineWidth: 2))
        } else {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                if let cover = covers[bubble.id] {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(String(title(for: bubble).prefix(1)).uppercased())
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                if bubble.level == .private {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MosaicBrand.inkBlack)
                        .frame(width: 20, height: 20)
                        .background(.white, in: Circle())
                        .accessibilityLabel("Private")
                }
            }
        }
    }

    private func title(for bubble: MosaicCircleBubble) -> String {
        let local = ComposerTitle.singleLine(
            store.snapshot.pursuits.first(where: { ComposerBoardSync.uuid($0.id) == bubble.id })?.title ?? ""
        )
        if !local.isEmpty { return local }
        return bubble.title.isEmpty ? "Pursuit" : bubble.title
    }

    /// Photo cover file for each Pursuit widget on the board. Video covers show the initial letter.
    private struct ComposerCircleCoverKey: Equatable {
        var files: [UUID: String]
        var versions: [String: Int]
    }

    private var coverFiles: [UUID: String] {
        var files: [UUID: String] = [:]
        func collect(_ blocks: [ComposerBlock]) {
            for block in blocks {
                if block.kind == .pursuit,
                   let id = block.pursuitID.flatMap(ComposerBoardSync.uuid),
                   let file = block.pursuitImageFileName,
                   !MosaicThumbnail.isVideo(file) {
                    files[id] = file
                }
                collect(block.groupMembers)
            }
        }
        collect(store.snapshot.mosaicBlocks)
        return files
    }

    private func loadCovers(_ files: [UUID: String]) async {
        var loaded: [UUID: UIImage] = [:]
        for (id, file) in files {
            if let cached = MosaicThumbnail.cached(file) {
                loaded[id] = cached
                continue
            }
            let url = store.mediaURL(for: file)
            let image = await Task.detached(priority: .userInitiated) {
                MosaicThumbnail.image(at: url, maxPixelSize: MosaicThumbnail.bubblePixelSize)
            }.value
            guard !Task.isCancelled else { return }
            if let image {
                MosaicThumbnail.store(image, for: file)
                loaded[id] = image
            }
        }
        covers = loaded
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.top, 24)
    }

    private func load() async {
        guard let account,
              let config = SupabaseSyncConfig.current(),
              let userID = account.session?.userID,
              let token = await account.accessToken()
        else { return }
        do {
            bubbles = try await MosaicCircleClient(config: config).overview(accessToken: token)
            failed = false
        } catch {
            failed = true
        }
        loaded = true
        if let profile = try? await MosaicSettingsClient(config: config).loadProfile(userID: userID, accessToken: token) {
            avatarPath = profile.avatarPath
            ownName = profile.displayName.isEmpty ? profile.username : profile.displayName
        }
    }
}

struct MosaicCircleBubbleView: View {
    var bubble: MosaicCircleBubble

    @Environment(\.mosaicAccount) private var account
    @Environment(ComposerStore.self) private var store

    @State private var people: [MosaicCirclePerson] = []
    @State private var loaded = false
    @State private var status = ""
    @State private var busy: String?
    @State private var visiting: MosaicVisitTarget?
    @State private var dailyVisits: Int?
    @State private var followerQuery = ""
    /// Nil until the person picks one; the list is newest first and the button shows the plain filter icon.
    @State private var chosenFilter: MosaicFollowerFilter?
    @State private var showsFilters = false
    @FocusState private var searchFocused: Bool

    private var followerFilter: MosaicFollowerFilter { chosenFilter ?? .latest }
    /// The sliders and the arrows have no circle, so they are drawn a size smaller.
    private var filterIconIsBare: Bool { chosenFilter?.isBareSymbol ?? true }

    private let muted = Color.white.opacity(0.55)
    private let field = Color.white.opacity(0.08)

    private var requests: [MosaicCirclePerson] { people.filter { $0.kind == .request } }
    private var followers: [MosaicCirclePerson] { people.filter { $0.kind == .follower } }
    private var filteredFollowers: [MosaicCirclePerson] { followerFilter.apply(to: followers) }
    private var shownFollowers: [MosaicCirclePerson] { filteredFollowers.filter { $0.matches(followerQuery) } }

    private var heading: String {
        if bubble.isMosaic { return "Mosaic" }
        let local = ComposerTitle.singleLine(
            store.snapshot.pursuits.first(where: { ComposerBoardSync.uuid($0.id) == bubble.id })?.title ?? ""
        )
        if !local.isEmpty { return local }
        return bubble.title.isEmpty ? "Pursuit" : bubble.title
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                engagement
                if !loaded {
                    ProgressView()
                        .tint(muted)
                        .frame(maxWidth: .infinity)
                } else {
                    if !requests.isEmpty {
                        section("Requests", count: requests.count) {
                            ForEach(requests) { person in
                                requestRow(person)
                            }
                        }
                    }
                    section("Followers", count: followers.count, trailing: {
                        if !followers.isEmpty {
                            HStack(spacing: 8) {
                                followerFilterMenu
                                followerSearch
                            }
                        }
                    }) {
                        if followers.isEmpty {
                            Text("No one follows this yet.")
                                .font(.footnote)
                                .foregroundStyle(muted)
                        } else if filteredFollowers.isEmpty {
                            Text(followerFilter.emptyMessage)
                                .font(.footnote)
                                .foregroundStyle(muted)
                                .padding(.vertical, 8)
                        } else if shownFollowers.isEmpty {
                            Text("No followers match “\(followerQuery.trimmingCharacters(in: .whitespacesAndNewlines))”.")
                                .font(.footnote)
                                .foregroundStyle(muted)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(shownFollowers) { person in
                                followerRow(person)
                            }
                        }
                    }
                }

                if !status.isEmpty {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await load() }
        .background(MosaicBrand.inkBlack.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .navigationTitle(heading)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(MosaicBrand.inkBlack, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load(markSeen: true) }
        .navigationDestination(item: $visiting) { target in
            MosaicVisitView(target: target)
        }
        .accessibilityIdentifier("circle.bubbleScreen")
    }

    /// Followers takes 60% of the row and Daily Visits 40%.
    private var engagement: some View {
        let spacing: CGFloat = 12
        let followerTotal = loaded ? followers.count : bubble.followerCount
        return HStack(alignment: .top, spacing: spacing) {
            statCard("\(heading) Followers", value: followerTotal)
                .containerRelativeFrame(.horizontal) { width, _ in (width - 40 - spacing) * 0.6 }
                .accessibilityIdentifier("circle.stat.followers")
            statCard("Daily Visits", value: dailyVisits)
                .containerRelativeFrame(.horizontal) { width, _ in (width - 40 - spacing) * 0.4 }
                .accessibilityIdentifier("circle.stat.dailyVisits")
        }
    }

    /// A missing value shows a dash, such as visits before they load or when they can't be read.
    private func statCard(_ title: String, value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.custom("BradleyHandITCTT-Bold", size: 20, relativeTo: .headline))
                .underline()
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(value.map(String.init) ?? "—")
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(value == nil ? muted : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func section<Content: View>(
        _ title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        section(title, count: count, trailing: { EmptyView() }, content: content)
    }

    private func section<Trailing: View, Content: View>(
        _ title: String,
        count: Int,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(muted)
                Spacer(minLength: 12)
                trailing()
            }
            VStack(spacing: 0) {
                content()
            }
        }
    }

    /// Sort or narrow this circle's followers. Once one is picked, its icon replaces the filter icon.
    private var followerFilterMenu: some View {
        Button {
            showsFilters = true
        } label: {
            Image(systemName: chosenFilter?.systemImage ?? "slider.horizontal.3")
                .font(filterIconIsBare ? .body.weight(.semibold) : .title3)
                .foregroundStyle(chosenFilter == nil ? muted : .white)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsFilters, arrowEdge: .top) {
            followerFilterOptions
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("Filter followers")
        .accessibilityValue(followerFilter.title)
        .accessibilityIdentifier("circle.followerFilter")
    }

    /// Only as wide as the longest option.
    private var followerFilterOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(MosaicFollowerFilter.allCases) { filter in
                Button {
                    // Tapping the chosen filter again clears it, back to the unfiltered list.
                    chosenFilter = chosenFilter == filter ? nil : filter
                    showsFilters = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: filter.systemImage)
                            .font(.footnote)
                            .frame(width: 18)
                        Text(filter.title)
                            .font(.footnote)
                        Spacer(minLength: 10)
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .opacity(filter == chosenFilter ? 1 : 0)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(filter == chosenFilter ? .isSelected : [])
                .accessibilityHint(filter == chosenFilter ? "Clears the filter" : "")
            }
        }
        .padding(.vertical, 4)
        .fixedSize()
        // No background of its own: the popover's system glass shows through, like the menu did.
        .environment(\.colorScheme, .dark)
    }

    /// A small field at the far right of the Followers title; it filters the list as you type.
    private var followerSearch: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(muted)
            TextField("", text: $followerQuery, prompt: Text("Search").foregroundStyle(muted))
                .font(.footnote)
                .foregroundStyle(.white)
                .tint(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("circle.followerSearch")
            if !followerQuery.isEmpty {
                Button {
                    followerQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 150, height: 30)
        .background(field, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search followers")
    }

    /// Opens the person's Mosaic. A private one shows its lock and a request button there.
    private func personLabel(_ person: MosaicCirclePerson) -> some View {
        Button {
            visiting = MosaicVisitTarget(person: person.asResult)
        } label: {
            HStack(spacing: 10) {
                MosaicAvatarView(path: person.avatarPath, name: person.name, size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(person.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("@\(person.username)")
                        .font(.caption)
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens @\(person.username)’s Mosaic")
        .accessibilityIdentifier("circle.person.\(person.username)")
    }

    private func roundButton(_ systemName: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(filled ? MosaicBrand.inkBlack : .white)
                .frame(width: 28, height: 28)
                .background(filled ? Color.white : field, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func requestRow(_ person: MosaicCirclePerson) -> some View {
        HStack(spacing: 8) {
            personLabel(person)
            roundButton("checkmark", filled: true) {
                Task { await respond(person, accept: true) }
            }
            .accessibilityLabel("Accept \(person.username)")
            .accessibilityIdentifier("circle.accept.\(person.username)")
            roundButton("xmark", filled: false) {
                Task { await respond(person, accept: false) }
            }
            .accessibilityLabel("Decline \(person.username)")
            .accessibilityIdentifier("circle.decline.\(person.username)")
        }
        .disabled(busy == person.id)
        .opacity(busy == person.id ? 0.5 : 1)
        .padding(.vertical, 5)
    }

    /// Following opens a menu to unfollow. Requested waits on them. Follow and Follow back follow their Mosaic, or ask to when it's private.
    @ViewBuilder
    private func followButton(_ button: MosaicCirclePerson.FollowButton, for person: MosaicCirclePerson) -> some View {
        let filled = button == .follow || button == .followBack
        let face = Text(button.title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(filled ? MosaicBrand.inkBlack : .white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(filled ? Color.white : field, in: Capsule())
        switch button {
        case .following:
            Menu {
                Button("Unfollow @\(person.username)", systemImage: "person.badge.minus", role: .destructive) {
                    Task { await unfollow(person) }
                }
            } label: {
                face
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityIdentifier("circle.following.\(person.username)")
        case .requested:
            face
                .accessibilityIdentifier("circle.requested.\(person.username)")
        case .follow, .followBack:
            Button {
                Task { await follow(person) }
            } label: {
                face
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("circle.follow.\(person.username)")
        }
    }

    private func followerRow(_ person: MosaicCirclePerson) -> some View {
        HStack(spacing: 8) {
            personLabel(person)
            if let button = person.followButton {
                followButton(button, for: person)
            }
            Menu {
                Button(role: .destructive) {
                    Task { await remove(person) }
                } label: {
                    Text("Remove follower")
                    if bubble.isMosaic {
                        Text("Also removes them from your Pursuits")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Options for \(person.username)")
        }
        .disabled(busy == person.id)
        .opacity(busy == person.id ? 0.5 : 1)
        .padding(.vertical, 5)
    }

    private func connection() async -> (client: MosaicCircleClient, token: String)? {
        guard let account,
              let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken()
        else { return nil }
        return (MosaicCircleClient(config: config), token)
    }

    private func load(markSeen: Bool = false) async {
        guard let link = await connection() else { return }
        let client = link.client, token = link.token
        async let visitsCall = try? client.dailyVisits(accessToken: token)
        do {
            people = try await client.people(documentID: bubble.id, accessToken: token)
            status = ""
        } catch {
            status = "This list could not be loaded."
        }
        loaded = true
        if let visits = await visitsCall {
            dailyVisits = visits[bubble.id] ?? 0
        }
        if markSeen {
            try? await client.markSeen(documentID: bubble.id, accessToken: token)
        }
    }

    private func respond(_ person: MosaicCirclePerson, accept: Bool) async {
        guard let requestID = person.requestID, let link = await connection() else { return }
        let client = link.client, token = link.token
        busy = person.id
        defer { busy = nil }
        do {
            try await client.respond(requestID: requestID, accept: accept, accessToken: token)
            withAnimation {
                if accept {
                    people = MosaicCirclePerson.accepting(person, in: people)
                    if bubble.isMosaic {
                        people = MosaicCirclePerson.updating(person.personID, in: people) { $0.followsMe = true }
                    }
                } else {
                    people.removeAll { $0.id == person.id }
                }
            }
            status = ""
            try? await client.markSeen(documentID: bubble.id, accessToken: token)
        } catch {
            status = "That request could not be answered."
        }
    }

    private func unfollow(_ person: MosaicCirclePerson) async {
        guard let config = SupabaseSyncConfig.current(), let token = await account?.accessToken() else { return }
        busy = person.id
        defer { busy = nil }
        do {
            try await MosaicVisitClient(config: config).unfollowMosaic(ownerID: person.personID, accessToken: token)
            withAnimation {
                people = MosaicCirclePerson.updating(person.personID, in: people) { $0.iFollow = false }
            }
            status = ""
        } catch {
            status = "@\(person.username) could not be unfollowed."
        }
    }

    /// Follows their Mosaic when it's open to the signed-in person, and otherwise asks to see it.
    private func follow(_ person: MosaicCirclePerson) async {
        guard let config = SupabaseSyncConfig.current(), let token = await account?.accessToken() else { return }
        let client = MosaicVisitClient(config: config)
        busy = person.id
        defer { busy = nil }
        do {
            var canFollow = person.canFollow
            if !canFollow {
                let reply = try await client.requestMosaic(ownerID: person.personID, accessToken: token)
                canFollow = MosaicVisit.status(afterRequestReply: reply) == "accepted"
            }
            if canFollow {
                try await client.followMosaic(ownerID: person.personID, accessToken: token)
            }
            withAnimation {
                people = MosaicCirclePerson.updating(person.personID, in: people) {
                    $0.canFollow = canFollow
                    $0.iFollow = canFollow
                    $0.iRequested = !canFollow
                }
            }
            status = ""
        } catch {
            status = "@\(person.username) could not be followed."
        }
    }

    private func remove(_ person: MosaicCirclePerson) async {
        guard let link = await connection() else { return }
        let client = link.client, token = link.token
        busy = person.id
        defer { busy = nil }
        do {
            try await client.removeFollower(documentID: bubble.id, followerID: person.personID, accessToken: token)
            people.removeAll { $0.id == person.id }
            status = ""
        } catch {
            status = "That follower could not be removed."
        }
    }
}

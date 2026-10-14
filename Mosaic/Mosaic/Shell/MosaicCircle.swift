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

    var id: String { "\(kind.rawValue)-\(requestID?.uuidString ?? personID.uuidString)" }
    var name: String { displayName.isEmpty ? username : displayName }
    var asResult: MosaicPersonResult {
        MosaicPersonResult(id: personID, username: username, displayName: displayName, avatarPath: avatarPath)
    }

    /// An accepted request leaves Requests and appears first under Followers, without reloading the list.
    static func accepting(_ request: MosaicCirclePerson, in people: [MosaicCirclePerson]) -> [MosaicCirclePerson] {
        var next = people.filter { $0.id != request.id }
        guard !next.contains(where: { $0.kind == .follower && $0.personID == request.personID }) else { return next }
        var follower = request
        follower.kind = .follower
        follower.requestID = nil
        next.insert(follower, at: next.firstIndex(where: { $0.kind == .follower }) ?? next.endIndex)
        return next
    }
}

/// How the signed-in person stands with someone listed in their Circle.
struct MosaicCircleRelation: Equatable, Sendable {
    var follows: Bool
    var requested: Bool
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
                title: (row["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                level: MosaicVisibilityLevel.parse(row["visibility"] as? String, role: role),
                followerCount: (row["follower_count"] as? NSNumber)?.intValue ?? 0,
                pendingCount: (row["pending_count"] as? NSNumber)?.intValue ?? 0,
                badgeCount: (row["badge_count"] as? NSNumber)?.intValue ?? 0
            )
        }
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
                avatarPath: row["avatar_path"] as? String
            )
        }
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
        .background(MosaicBrand.inkBlack.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(tabBarHidden ? .hidden : .visible, for: .tabBar)
        .navigationDestination(item: $opened) { bubble in
            MosaicCircleBubbleView(bubble: bubble)
        }
        .onAppear { Task { await load() } }
        .task(id: coverFiles) { await loadCovers(coverFiles) }
        .accessibilityIdentifier(MosaicTab.circle.screenAccessibilityIdentifier)
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
                .overlay(alignment: .topLeading) {
                    Text(bubble.followerCount > 99 ? "99+" : "\(bubble.followerCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MosaicBrand.inkBlack)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(MosaicBrand.inkBlack, lineWidth: 2))
                        .offset(x: -4, y: -4)
                }
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
        let local = store.snapshot.pursuits
            .first(where: { ComposerBoardSync.uuid($0.id) == bubble.id })?
            .title
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !local.isEmpty { return local }
        return bubble.title.isEmpty ? "Pursuit" : bubble.title
    }

    /// Photo cover file for each Pursuit widget on the board. Video covers show the initial letter.
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
    @State private var relations: [UUID: MosaicCircleRelation] = [:]
    @State private var visiting: MosaicVisitTarget?

    private let muted = Color.white.opacity(0.55)
    private let field = Color.white.opacity(0.08)

    private var requests: [MosaicCirclePerson] { people.filter { $0.kind == .request } }
    private var followers: [MosaicCirclePerson] { people.filter { $0.kind == .follower } }

    private var heading: String {
        if bubble.isMosaic { return "Mosaic" }
        let local = store.snapshot.pursuits
            .first(where: { ComposerBoardSync.uuid($0.id) == bubble.id })?
            .title
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !local.isEmpty { return local }
        return bubble.title.isEmpty ? "Pursuit" : bubble.title
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
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
                    section("Followers", count: followers.count) {
                        if followers.isEmpty {
                            Text("No one follows this yet.")
                                .font(.footnote)
                                .foregroundStyle(muted)
                        } else {
                            ForEach(followers) { person in
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

    private func section<Content: View>(
        _ title: String,
        count: Int,
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
            }
            VStack(spacing: 0) {
                content()
            }
        }
    }

    /// Opens the person's Mosaic. A private one shows its lock and a request button there.
    private func personLabel(_ person: MosaicCirclePerson) -> some View {
        let relation = relations[person.personID]
        return Button {
            visiting = MosaicVisitTarget(person: person.asResult)
        } label: {
            HStack(spacing: 10) {
                MosaicAvatarView(path: person.avatarPath, name: person.name, size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        Text(person.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if relation?.follows != true, relation?.requested == true {
                            Image(systemName: "person.badge.clock.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(MosaicVisitLockBadge.pendingColor)
                                .accessibilityLabel("Requested")
                        }
                    }
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

    private func followerRow(_ person: MosaicCirclePerson) -> some View {
        HStack(spacing: 8) {
            personLabel(person)
            if relations[person.personID]?.follows == true {
                Menu {
                    Button("Unfollow @\(person.username)", systemImage: "person.badge.minus", role: .destructive) {
                        Task { await unfollow(person) }
                    }
                } label: {
                    Image(systemName: "person.fill.checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MosaicBrand.inkBlack)
                        .frame(width: 28, height: 28)
                        .background(.white, in: Circle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("Following @\(person.username)")
                .accessibilityIdentifier("circle.following.\(person.username)")
            }
            Menu {
                Button("Remove follower", role: .destructive) {
                    Task { await remove(person) }
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
        do {
            people = try await client.people(documentID: bubble.id, accessToken: token)
            status = ""
        } catch {
            status = "This list could not be loaded."
        }
        loaded = true
        if markSeen {
            try? await client.markSeen(documentID: bubble.id, accessToken: token)
        }
        await loadRelations(token: token)
    }

    /// Whether the signed-in person follows, or has asked to see, each Mosaic in the list.
    private func loadRelations(token: String) async {
        guard let config = SupabaseSyncConfig.current() else { return }
        let client = MosaicVisitClient(config: config)
        let ids = Array(Set(people.map(\.personID)))
        var found: [UUID: MosaicCircleRelation] = [:]
        await withTaskGroup(of: (UUID, MosaicCircleRelation?).self) { group in
            var queue = ids.makeIterator()
            func next() {
                guard let id = queue.next() else { return }
                group.addTask {
                    let profile = try? await client.profile(userID: id, accessToken: token)
                    return (id, profile.map { MosaicCircleRelation(follows: $0.followsMosaic, requested: $0.isRequested) })
                }
            }
            for _ in 0..<4 { next() }
            while let (id, relation) = await group.next() {
                if let relation { found[id] = relation }
                next()
            }
        }
        guard !Task.isCancelled else { return }
        relations = found
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
                relations[person.personID]?.follows = false
            }
            status = ""
        } catch {
            status = "@\(person.username) could not be unfollowed."
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

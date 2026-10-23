import SwiftUI

struct MosaicVisitProfile: Equatable, Sendable {
    var userID: UUID
    var username: String
    var displayName: String
    var avatarPath: String?
    var mosaicID: UUID?
    var isPublic: Bool
    var canView: Bool
    var requestStatus: String?
    var followsMosaic: Bool
    /// Only for someone who may see the Mosaic.
    var followerCount: Int?

    var name: String { displayName.isEmpty ? username : displayName }
    var isRequested: Bool { requestStatus == "pending" }
}

struct MosaicVisitPursuit: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var level: MosaicVisibilityLevel
    var canOpen: Bool
    var requestStatus: String?
    var following: Bool
    /// Only for a Pursuit the visitor may open.
    var followerCount: Int? = nil

    var isRequested: Bool { requestStatus == "pending" }
    var displayTitle: String { title.isEmpty ? "Pursuit" : title }
    /// A private Pursuit also needs the visitor to still follow it: following the Mosaic doesn't grant it,
    /// and unfollowing gives it up until the owner approves another request.
    var isOpen: Bool { canOpen && (level == .public || following) }
}

/// What a visitor may do with one Pursuit on someone else's Mosaic.
enum MosaicVisitAccess: Equatable, Sendable {
    case open
    case locked
    /// Requested and waiting on the owner.
    case pending
}

/// The lock on a Pursuit the visitor can't open. It turns amber while a request waits for the owner.
struct MosaicVisitLockBadge: View {
    var access: MosaicVisitAccess

    static let pendingColor = Color(red: 0.96, green: 0.66, blue: 0.16)

    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(MosaicBrand.inkBlack)
            .frame(width: 24, height: 24)
            .background(access == .pending ? Self.pendingColor : .white, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .accessibilityLabel(access == .pending ? "Private, request pending" : "Private, request to view")
    }
}

struct MosaicVisitClient: Sendable {
    var config: SupabaseSyncConfig
    var session: URLSession = .shared

    func profile(userID: UUID, accessToken: String) async throws -> MosaicVisitProfile? {
        let data = try await rpc("profile_view", body: ["p_user_id": userID.uuidString.lowercased()], accessToken: accessToken)
        return try Self.profile(from: data)
    }

    func boards(ownerID: UUID, accessToken: String) async throws -> [ComposerSyncDocument] {
        let data = try await rpc("viewer_boards", body: ["p_owner": ownerID.uuidString.lowercased()], accessToken: accessToken)
        return try Self.boards(from: data)
    }

    func pursuits(ownerID: UUID, accessToken: String) async throws -> [MosaicVisitPursuit] {
        let data = try await rpc("viewer_pursuits", body: ["p_owner": ownerID.uuidString.lowercased()], accessToken: accessToken)
        return try Self.pursuits(from: data)
    }

    func requestMosaic(ownerID: UUID, accessToken: String) async throws -> String? {
        let data = try await rpc("request_mosaic_access", body: ["p_owner": ownerID.uuidString.lowercased()], accessToken: accessToken)
        return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
    }

    func requestPursuit(id: UUID, accessToken: String) async throws -> String? {
        let data = try await rpc("request_pursuit_access", body: ["p_pursuit_id": id.uuidString.lowercased()], accessToken: accessToken)
        return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
    }

    func followMosaic(ownerID: UUID, accessToken: String) async throws {
        _ = try await rpc("follow_mosaic", body: ["p_owner": ownerID.uuidString.lowercased()], accessToken: accessToken)
    }

    func unfollowMosaic(ownerID: UUID, accessToken: String) async throws {
        _ = try await rpc("unfollow_mosaic", body: ["p_owner": ownerID.uuidString.lowercased()], accessToken: accessToken)
    }

    func followPursuit(id: UUID, accessToken: String) async throws {
        _ = try await rpc("follow_pursuit", body: ["p_pursuit_id": id.uuidString.lowercased()], accessToken: accessToken)
    }

    func unfollowPursuit(id: UUID, accessToken: String) async throws {
        _ = try await rpc(
            "unfollow",
            body: ["p_target_type": "pursuit", "p_target_id": id.uuidString.lowercased()],
            accessToken: accessToken
        )
    }

    /// Counts toward the owner's Daily Visits. The server ignores the owner and boards the caller can't see.
    func recordVisit(documentID: UUID, accessToken: String) async throws {
        _ = try await rpc("record_visit", body: ["p_document_id": documentID.uuidString.lowercased()], accessToken: accessToken)
    }

    /// One Storage object, or nil when it is missing or not readable. `inLowDataMode: false` skips
    /// the download while Low Data Mode is on, for fetches nobody has asked to see yet.
    func download(path: String, accessToken: String, inLowDataMode: Bool = true) async -> Data? {
        guard let url = URL(string: "\(config.url.absoluteString)/storage/v1/object/authenticated/media/\(path)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.allowsConstrainedNetworkAccess = inLowDataMode
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }
        return data
    }

    static func profile(from data: Data) throws -> MosaicVisitProfile? {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        guard let row = rows.first,
              let userID = (row["user_id"] as? String).flatMap(UUID.init(uuidString:))
        else { return nil }
        return MosaicVisitProfile(
            userID: userID,
            username: row["username"] as? String ?? "",
            displayName: (row["display_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            avatarPath: row["avatar_path"] as? String,
            mosaicID: (row["mosaic_id"] as? String).flatMap(UUID.init(uuidString:)),
            isPublic: row["mosaic_visibility"] as? String == "public",
            canView: row["can_view"] as? Bool ?? false,
            requestStatus: row["request_status"] as? String,
            followsMosaic: row["follows_mosaic"] as? Bool ?? false,
            followerCount: (row["follower_count"] as? NSNumber)?.intValue
        )
    }

    static func pursuits(from data: Data) throws -> [MosaicVisitPursuit] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        return rows.compactMap { row in
            guard let id = (row["pursuit_id"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            return MosaicVisitPursuit(
                id: id,
                title: ComposerTitle.singleLine(row["title"] as? String ?? ""),
                level: MosaicVisibilityLevel.parse(row["visibility"] as? String, role: "pursuit"),
                canOpen: row["can_open"] as? Bool ?? false,
                requestStatus: row["request_status"] as? String,
                following: row["following"] as? Bool ?? false,
                followerCount: (row["follower_count"] as? NSNumber)?.intValue
            )
        }
    }

    static func boards(from data: Data) throws -> [ComposerSyncDocument] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        let decoder = JSONDecoder()
        return rows.compactMap { row in
            guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let role = (row["role"] as? String).flatMap(ComposerSyncRole.init(rawValue:)),
                  let rawBody = row["body"],
                  let bodyData = try? JSONSerialization.data(withJSONObject: rawBody),
                  let body = try? decoder.decode(ComposerBoardBody.self, from: bodyData)
            else { return nil }
            return ComposerSyncDocument(
                id: id,
                parentID: (row["parent_id"] as? String).flatMap(UUID.init(uuidString:)),
                role: role,
                title: ComposerTitle.singleLine(row["title"] as? String ?? ""),
                visibility: "",
                body: body
            )
        }
    }

    /// Storage paths to try for one file, best first. Photos have a display copy; a GIF's display
    /// copy is a still, and a sticker's is a JPEG without transparency (it would show on a solid
    /// box), so their originals are used. Other PNGs use the smaller display copy.
    nonisolated static func objectPaths(ownerID: UUID, assetID: String, fileName: String, isSticker: Bool = false) -> [String] {
        let owner = ownerID.uuidString.lowercased()
        let asset = assetID.lowercased()
        let usesOriginal = isSticker || ["mov", "mp4", "m4v", "gif"].contains((fileName as NSString).pathExtension.lowercased())
        return (usesOriginal ? ["original"] : ["display", "original"]).map { "\(owner)/\(asset)/\($0)" }
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

/// Where the visitor stands with each Pursuit on the Mosaic they are looking at.
@MainActor
@Observable
final class MosaicVisit {
    let ownerID: UUID
    var pursuits: [UUID: MosaicVisitPursuit]
    var requestTarget: MosaicVisitPursuit?
    var pendingTarget: MosaicVisitPursuit?
    var busy: Set<UUID> = []
    var problem: String?
    var media: MosaicVisitMedia?
    var mosaicID: UUID?
    /// Called when a refresh opens or closes a Pursuit, so its board can be fetched or dropped.
    var onAccessChanged: (() -> Void)?
    /// The Mosaic's owner, for the Pursuit cards' "by @owner".
    var owner: MosaicPersonResult?
    /// Set while the visit is on the Pursuit it opened on: moves up to the whole Mosaic.
    var onVisitMosaic: (() -> Void)?
    /// After the owner's card follows, unfollows, or requests, so the visit screen can catch up.
    var onProfileChange: ((MosaicVisitProfile) -> Void)?
    /// Bumped as every follow, unfollow, and request starts and again when it ends, so a refresh
    /// fetched before or during one can't undo it.
    @ObservationIgnored private var changes = 0
    /// What happened while the visit screen was covered by a Pursuit opened inside it, and so had
    /// no callbacks attached; it catches up when it shows again.
    @ObservationIgnored private var missedAccessChange = false
    @ObservationIgnored private var missedProfile: MosaicVisitProfile?
    @ObservationIgnored private var reportedVisits: Set<UUID> = []

    private let account: MosaicAccount
    private let client: MosaicVisitClient

    init(ownerID: UUID, pursuits: [MosaicVisitPursuit], account: MosaicAccount, client: MosaicVisitClient) {
        self.ownerID = ownerID
        self.pursuits = Dictionary(uniqueKeysWithValues: pursuits.map { ($0.id, $0) })
        self.account = account
        self.client = client
    }

    /// A Pursuit the server didn't list for this visitor stays locked.
    func access(_ id: UUID) -> MosaicVisitAccess {
        Self.access(pursuits[id])
    }

    nonisolated static func access(_ pursuit: MosaicVisitPursuit?) -> MosaicVisitAccess {
        guard let pursuit else { return .locked }
        if pursuit.isOpen { return .open }
        return pursuit.isRequested ? .pending : .locked
    }

    /// Only boards the visitor may open. Locked Pursuits and everything inside them are dropped,
    /// so nothing from them is shown or has its media downloaded.
    nonisolated static func authorizedDocuments(
        _ documents: [ComposerSyncDocument],
        pursuits: [MosaicVisitPursuit]
    ) -> [ComposerSyncDocument] {
        let open = Set(pursuits.filter(\.isOpen).map(\.id))
        var dropped = Set(documents.filter { $0.role == .pursuit && !open.contains($0.id) }.map(\.id))
        var changed = true
        while changed {
            changed = false
            for document in documents where !dropped.contains(document.id) {
                if let parent = document.parentID, dropped.contains(parent) {
                    dropped.insert(document.id)
                    changed = true
                }
            }
        }
        return documents.filter { !dropped.contains($0.id) }
    }

    /// Reports a board the visitor is looking at, once per visit; `nil` is the Mosaic itself.
    /// Failures are ignored so they never get in the way of the visit.
    func recordVisit(to documentID: UUID?) {
        guard let id = Self.visitTarget(documentID, mosaicID: mosaicID, pursuits: pursuits, reported: reportedVisits) else { return }
        reportedVisits.insert(id)
        Task { [account, client] in
            guard let token = await account.accessToken() else { return }
            try? await client.recordVisit(documentID: id, accessToken: token)
        }
    }

    /// The board to report, if any: the Mosaic, or a Pursuit the visitor can open.
    /// Pages and nodes inside a Pursuit aren't Pursuits, so they aren't reported.
    nonisolated static func visitTarget(
        _ documentID: UUID?,
        mosaicID: UUID?,
        pursuits: [UUID: MosaicVisitPursuit],
        reported: Set<UUID>
    ) -> UUID? {
        let target: UUID?
        if let documentID {
            target = pursuits[documentID]?.isOpen == true ? documentID : nil
        } else {
            target = mosaicID
        }
        guard let target, !reported.contains(target) else { return nil }
        return target
    }

    func askToRequest(_ id: UUID) {
        guard let pursuit = pursuits[id] else {
            problem = "This Pursuit is private."
            return
        }
        switch Self.access(pursuit) {
        case .open: return
        case .locked: requestTarget = pursuit
        case .pending: pendingTarget = pursuit
        }
    }

    func follow(_ id: UUID) async {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        defer { busy.remove(id) }
        changes += 1
        defer { changes += 1 }
        guard let token = await account.accessToken() else { return }
        do {
            try await client.followPursuit(id: id, accessToken: token)
            setFollowing(true, for: id)
        } catch {
            problem = "That Pursuit could not be followed."
        }
    }

    func unfollow(_ id: UUID) async {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        defer { busy.remove(id) }
        changes += 1
        defer { changes += 1 }
        guard let token = await account.accessToken() else { return }
        do {
            try await client.unfollowPursuit(id: id, accessToken: token)
            let wasOpen = openIDs
            setFollowing(false, for: id)
            if openIDs != wasOpen {
                accessChanged()
            }
        } catch {
            problem = "That Pursuit could not be unfollowed."
        }
    }

    /// Changed on a copy and stored once: reading `pursuits` while an optional-chained write to it is
    /// under way is an overlapping access, which traps.
    private func setFollowing(_ following: Bool, for id: UUID) {
        guard var pursuit = pursuits[id], pursuit.following != following else { return }
        pursuit.following = following
        pursuit.followerCount = pursuit.followerCount.map { max($0 + (following ? 1 : -1), 0) }
        pursuits[id] = pursuit
    }

    func request(_ id: UUID) async {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        defer { busy.remove(id) }
        changes += 1
        defer { changes += 1 }
        guard let token = await account.accessToken() else {
            problem = "That request could not be sent."
            return
        }
        let reply: String?
        do {
            reply = try await client.requestPursuit(id: id, accessToken: token)
        } catch {
            problem = "That request could not be sent."
            return
        }
        if let fresh = try? await client.pursuits(ownerID: ownerID, accessToken: token) {
            apply(fresh)
        } else {
            pursuits[id]?.requestStatus = Self.status(afterRequestReply: reply)
        }
        if let problem = Self.requestProblem(pursuits[id]) {
            self.problem = problem
        }
    }

    /// The request call's own reply isn't a reliable status; only an answered request is taken from it.
    nonisolated static func status(afterRequestReply reply: String?) -> String {
        if let reply, reply == "declined" || reply == "accepted" { return reply }
        return "pending"
    }

    /// Still locked after a successful request call: the server has no request waiting on the owner.
    nonisolated static func requestProblem(_ pursuit: MosaicVisitPursuit?) -> String? {
        guard let pursuit, access(pursuit) == .locked else { return nil }
        return "Your request to view \(pursuit.displayTitle) wasn’t saved. Please try again."
    }

    func refresh() async {
        let started = changes
        guard let token = await account.accessToken() else { return }
        // Revalidate the Mosaic gate itself; Pursuit-only diffs miss revocation with zero open Pursuits.
        if let profile = try? await client.profile(userID: ownerID, accessToken: token),
           changes == started,
           !profile.canView {
            accessChanged()
            return
        }
        guard let fresh = try? await client.pursuits(ownerID: ownerID, accessToken: token),
              changes == started
        else { return }
        apply(fresh)
    }

    private func apply(_ fresh: [MosaicVisitPursuit]) {
        let wasOpen = openIDs
        pursuits = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0) })
        if openIDs != wasOpen {
            accessChanged()
        }
    }

    private func accessChanged() {
        if let onAccessChanged {
            onAccessChanged()
        } else {
            missedAccessChange = true
        }
    }

    /// The owner's card changed a follow or request.
    func profileChanged(_ profile: MosaicVisitProfile) {
        if let onProfileChange {
            onProfileChange(profile)
        } else {
            missedProfile = profile
            // Unfollowing the Mosaic also unfollows its Pursuits; the bubbles catch up now.
            Task { await refresh() }
        }
    }

    /// What the visit screen missed while it was covered, cleared as it is read.
    func takeMissed() -> (accessChanged: Bool, profile: MosaicVisitProfile?) {
        defer {
            missedAccessChange = false
            missedProfile = nil
        }
        return (missedAccessChange, missedProfile)
    }

    private var openIDs: Set<UUID> {
        Set(pursuits.values.filter(\.isOpen).map(\.id))
    }
}

/// Bottom right of a visited Pursuit page: its bubble, with a badge for whether the visitor follows
/// it. Tapping it opens the Pursuit's card, where that changes.
struct MosaicVisitPursuitControls: View {
    let pursuitID: UUID

    @Environment(ComposerStore.self) private var store
    @Environment(MosaicVisit.self) private var visit
    @Environment(\.mosaicAccount) private var account
    @State private var cover: UIImage?
    @State private var showsCard = false
    /// The card switched to the owner's, from "by @owner".
    @State private var showsOwner = false

    private var coverFile: String? {
        func find(_ blocks: [ComposerBlock]) -> String? {
            for block in blocks {
                if block.kind == .pursuit, block.pursuitID.flatMap({ ComposerBoardSync.uuid($0) }) == pursuitID {
                    return block.pursuitImageFileName
                }
                if let found = find(block.groupMembers) { return found }
            }
            return nil
        }
        return find(store.snapshot.mosaicBlocks).flatMap { MosaicThumbnail.isVideo($0) ? nil : $0 }
    }

    var body: some View {
        if let pursuit = visit.pursuits[pursuitID] {
            Button {
                showsOwner = false
                MosaicCardPresentation.withoutSlide { showsCard = true }
            } label: {
                bubble(pursuit)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pursuit.displayTitle)
            .accessibilityValue(MosaicFollowStatus(pursuit).spoken)
            .accessibilityHint("Shows the Pursuit, with a way to follow it")
            .accessibilityIdentifier("visit.pursuitBubble")
            .task(id: ComposerMediaLoadKey(coverFile.map { store.mediaURL(for: $0) }, versions: store.mediaVersions)) { await loadCover() }
            .mosaicCardCover(isPresented: $showsCard) { close in
                card(close: close)
                    .environment(visit)
                    .environment(\.mosaicAccount, account)
            }
        }
    }

    @ViewBuilder
    private func card(close: @escaping () -> Void) -> some View {
        if showsOwner, let owner = visit.owner {
            MosaicProfileCard(
                person: owner,
                onVisit: visit.onVisitMosaic.map { visitMosaic in
                    {
                        close()
                        // After the card has gone, so the board it sits on isn't swapped out under it.
                        Task {
                            try? await Task.sleep(for: .milliseconds(250))
                            visitMosaic()
                        }
                    }
                },
                onProfileChange: { visit.profileChanged($0) },
                onClose: close
            )
            .transition(.opacity)
        } else {
            MosaicPursuitCard(
                pursuitID: pursuitID,
                cover: cover,
                coverURL: coverFile.map { store.mediaURL(for: $0) },
                owner: visit.owner,
                onShowOwner: { withAnimation(.easeInOut(duration: 0.2)) { showsOwner = true } },
                onClose: close
            )
            .transition(.opacity)
        }
    }

    private func bubble(_ pursuit: MosaicVisitPursuit) -> some View {
        ZStack {
            Circle()
                .fill(MosaicBrand.inkBlack)
            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(pursuit.displayTitle.prefix(1)).uppercased())
                    .font(.system(size: ComposerAddMenuMetrics.button * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: ComposerAddMenuMetrics.button, height: ComposerAddMenuMetrics.button)
        .clipShape(Circle())
        .overlay(Circle().stroke(MosaicBrand.inkBlack, lineWidth: 2))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        .overlay(alignment: .bottomTrailing) {
            MosaicFollowBadge(status: MosaicFollowStatus(pursuit))
                .offset(x: 4, y: 4)
        }
    }

    private func loadCover() async {
        guard let file = coverFile else {
            cover = nil
            return
        }
        let url = store.mediaURL(for: file)
        let pixelSize = MosaicThumbnail.bubblePixelSize
        let image = await Task.detached(priority: .userInitiated) {
            MosaicThumbnail.image(at: url, maxPixelSize: pixelSize)
        }.value
        guard !Task.isCancelled, let image else { return }
        cover = image
    }
}

/// Whose Mosaic to open, and optionally which of its Pursuits to open on.
struct MosaicVisitTarget: Hashable, Sendable {
    var person: MosaicPersonResult
    var pursuitID: UUID?
}

/// Another person's Mosaic, opened from Discover. It is always in view mode.
struct MosaicVisitView: View {
    let person: MosaicPersonResult
    var pursuitID: UUID?

    init(target: MosaicVisitTarget) {
        person = target.person
        pursuitID = target.pursuitID
    }

    @Environment(\.mosaicAccount) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private enum Phase {
        case loading
        case failed
        case noMosaic
        case locked
        case ready(ComposerStore, MosaicChrome, MosaicVisit, start: ComposerDocumentID?)
    }

    @State private var loadAttempt = 0
    @State private var phase = Phase.loading
    @State private var profile: MosaicVisitProfile?
    @State private var requesting = false
    /// The first appearance follows a fresh load, so only later returns refresh access.
    @State private var visitAppeared = false
    @State private var showsAvatar = false

    private let muted = Color.white.opacity(0.55)

    var body: some View {
        content
            .overlay {
                if showsAvatar {
                    MosaicProfileCard(
                        person: person,
                        profile: profile,
                        onVisit: visitMosaicFromPursuit,
                        onProfileChange: profileChanged,
                        onClose: closeCard
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.86)))
                }
            }
            .background(MosaicBrand.inkBlack.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: loadAttempt) { await load() }
            .onAppear {
                // Back from a Pursuit opened inside the visit: follows and unfollows reload again.
                if case .ready(let store, let chrome, let visit, let start) = phase, visit.onAccessChanged == nil {
                    attach(visit, store: store, chrome: chrome, start: start)
                }
            }
            .onDisappear {
                if case .ready(_, _, let visit, _) = phase {
                    detach(visit)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .tint(muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) { backChevron }
        case .failed:
            VStack(spacing: 12) {
                Text("This Mosaic could not be opened.")
                Button("Retry") { loadAttempt += 1 }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) { backChevron }
        case .noMosaic:
            note("@\(person.username) has not shared a Mosaic yet.")
        case .locked:
            lockedMosaic
        case .ready(let store, let chrome, let visit, let start):
            visitedMosaic(store: store, chrome: chrome, visit: visit, start: start)
        }
    }

    private var avatarPath: String? { profile?.avatarPath ?? person.avatarPath }

    private var mosaicFollowStatus: MosaicFollowStatus {
        profile?.followsMosaic == true ? .following : .follow
    }

    /// The owner's picture. Tapping it opens their profile card, where they're followed.
    private func ownerAvatar(size: CGFloat, badged: Bool = false) -> some View {
        Button(action: openCard) {
            MosaicAvatarView(path: avatarPath, name: profile?.name ?? person.username, size: size)
                .overlay(alignment: .bottomTrailing) {
                    if badged {
                        MosaicFollowBadge(status: mosaicFollowStatus)
                            .offset(x: 4, y: 4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("@\(person.username)")
        .accessibilityValue(badged ? mosaicFollowStatus.spoken : "")
        .accessibilityHint("Shows their profile")
        .accessibilityIdentifier("visit.ownerAvatar")
    }

    private func openCard() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { showsAvatar = true }
    }

    private func closeCard() {
        withAnimation(.easeOut(duration: 0.2)) { showsAvatar = false }
    }

    /// Only a visit that opened on a Pursuit has somewhere further to go: the whole Mosaic.
    private var visitMosaicFromPursuit: (() -> Void)? {
        guard case .ready(let store, let chrome, let visit, let start) = phase, start != nil else { return nil }
        return {
            closeCard()
            moveUpToMosaic(store: store, chrome: chrome, visit: visit)
        }
    }

    private func moveUpToMosaic(store: ComposerStore, chrome: MosaicChrome, visit: MosaicVisit) {
        visit.onVisitMosaic = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            phase = .ready(store, chrome, visit, start: nil)
        }
    }

    /// What the visit's cards need from this screen: who the owner is, how to catch up after the
    /// owner's card changes something, and, on a visit that opened on a Pursuit, the way up.
    private func attach(_ visit: MosaicVisit, store: ComposerStore, chrome: MosaicChrome, start: ComposerDocumentID?) {
        visit.onAccessChanged = { loadAttempt += 1 }
        visit.onProfileChange = { profileChanged($0) }
        visit.onVisitMosaic = start == nil ? nil : { moveUpToMosaic(store: store, chrome: chrome, visit: visit) }
        let missed = visit.takeMissed()
        if let profile = missed.profile {
            profileChanged(profile)
        }
        if missed.accessChanged {
            loadAttempt += 1
        }
    }

    /// The visit's callbacks hold this screen, which holds the visit: let both go.
    private func detach(_ visit: MosaicVisit) {
        visit.onAccessChanged = nil
        visit.onProfileChange = nil
        visit.onVisitMosaic = nil
    }

    private func profileChanged(_ changed: MosaicVisitProfile) {
        let wasClosed = profile?.canView == false
        profile = changed
        if wasClosed, changed.canView {
            closeCard()
            loadAttempt += 1
        } else if case .ready(_, _, let visit, _) = phase {
            Task { await visit.refresh() }
        }
    }

    private var backChevron: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .padding(.leading, 8)
        .accessibilityLabel("Back")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) { backChevron }
    }

    // MARK: Private Mosaic

    private var lockedMosaic: some View {
        let requested = profile?.isRequested == true
        return ZStack {
            blurredBoard
            VStack(spacing: 14) {
                ownerAvatar(size: 88)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                VStack(spacing: 2) {
                    Text(profile?.name ?? person.username)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("@\(person.username)")
                        .font(.subheadline)
                        .foregroundStyle(muted)
                }
                Button {
                    Task { await requestMosaic() }
                } label: {
                    Label {
                        Text(requested ? "Requested" : "Request to view")
                    } icon: {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(requested ? MosaicVisitLockBadge.pendingColor : MosaicBrand.inkBlack)
                    }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(requested ? .white : MosaicBrand.inkBlack)
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(requested ? Color.white.opacity(0.16) : .white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(requested || requesting)
                .padding(.top, 6)
                .accessibilityIdentifier("visit.requestMosaic")
            }
        }
        .overlay(alignment: .topLeading) { backChevron }
        .refreshable { loadAttempt += 1 }
    }

    /// Stand-in tiles behind the blur. Nothing from the private Mosaic is downloaded.
    private var blurredBoard: some View {
        GeometryReader { proxy in
            let columns = 3
            let gap: CGFloat = 10
            let width = (proxy.size.width - gap * CGFloat(columns + 1)) / CGFloat(columns)
            let heights: [CGFloat] = [150, 210, 120, 180, 240, 140, 200, 130, 170, 220, 160, 190]
            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<columns, id: \.self) { column in
                    VStack(spacing: gap) {
                        ForEach(0..<4, id: \.self) { row in
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.06 + Double((row + column) % 3) * 0.05))
                                .frame(width: width, height: heights[(column * 4 + row) % heights.count])
                        }
                    }
                }
            }
            .padding(gap)
            .blur(radius: 18)
        }
        .ignoresSafeArea()
    }

    // MARK: Visible Mosaic

    private func visitedMosaic(store: ComposerStore, chrome: MosaicChrome, visit: MosaicVisit, start: ComposerDocumentID?) -> some View {
        MosaicComposerView(documentID: start)
            // Moving from a Pursuit up to the Mosaic is a fresh board, not the Pursuit's scroll and sizes.
            .id(start)
            .environment(store)
            .environment(chrome)
            .environment(visit)
            .overlay(alignment: .bottomTrailing) {
                if start == nil {
                    ownerAvatar(size: ComposerAddMenuMetrics.button, badged: true)
                        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                } else {
                    // Left of the Pursuit's bubble, which the board shows in this corner.
                    ownerMosaicButton
                        .padding(.trailing, 20 + pursuitControlsWidth(start: start, visit: visit))
                        .padding(.bottom, 20)
                }
            }
            .alert(
                "Request to view \(visit.requestTarget?.displayTitle ?? "this Pursuit")?",
                isPresented: Binding(
                    get: { visit.requestTarget != nil },
                    set: { if !$0 { visit.requestTarget = nil } }
                ),
                presenting: visit.requestTarget
            ) { pursuit in
                Button("Request") {
                    Task { await visit.request(pursuit.id) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "Request pending",
                isPresented: Binding(
                    get: { visit.pendingTarget != nil },
                    set: { if !$0 { visit.pendingTarget = nil } }
                ),
                presenting: visit.pendingTarget
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { pursuit in
                Text("@\(person.username) hasn’t answered your request to view \(pursuit.displayTitle) yet.")
            }
            .alert(
                visit.problem ?? "",
                isPresented: Binding(
                    get: { visit.problem != nil },
                    set: { if !$0 { visit.problem = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            }
            .onAppear {
                guard start == nil, visitAppeared else {
                    visitAppeared = true
                    return
                }
                Task { await visit.refresh() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await visit.refresh() } }
            }
    }

    /// `MosaicVisitPursuitControls`: the Pursuit's bubble.
    private func pursuitControlsWidth(start: ComposerDocumentID?, visit: MosaicVisit) -> CGFloat {
        guard start.flatMap({ ComposerBoardSync.uuid($0) }).flatMap({ visit.pursuits[$0] }) != nil else { return 0 }
        return ComposerAddMenuMetrics.button + 12
    }

    /// On a visit that opened on a Pursuit, the owner's picture opens their card, which leads up to
    /// their whole Mosaic.
    private var ownerMosaicButton: some View {
        Button(action: openCard) {
            MosaicAvatarView(path: avatarPath, name: profile?.name ?? person.username, size: ComposerAddMenuMetrics.button)
                .overlay(Circle().stroke(MosaicBrand.inkBlack, lineWidth: 2))
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                .overlay(alignment: .bottomTrailing) {
                    MosaicFollowBadge(status: mosaicFollowStatus)
                        .offset(x: 4, y: 4)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("@\(person.username)")
        .accessibilityValue(mosaicFollowStatus.spoken)
        .accessibilityHint("Shows their profile, with a way to their Mosaic")
        .accessibilityIdentifier("visit.ownerMosaic")
    }

    // MARK: Loading and actions

    private func connection() async -> (client: MosaicVisitClient, token: String)? {
        guard let account,
              let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken()
        else { return nil }
        return (MosaicVisitClient(config: config), token)
    }

    private func load() async {
        if case .ready(_, _, let previous, _) = phase {
            detach(previous)
        }
        phase = .loading
        guard let account, let viewerID = account.session?.userID,
              let link = await connection() else {
            phase = .failed
            return
        }
        let client = link.client, token = link.token
        do {
            guard let found = try await client.profile(userID: person.id, accessToken: token) else {
                phase = .failed
                return
            }
            try Task.checkCancellation()
            guard account.session?.userID == viewerID else { throw CancellationError() }
            profile = found
            guard let mosaicID = found.mosaicID else {
                phase = .noMosaic
                return
            }
            guard found.canView else {
                phase = .locked
                return
            }

            async let boardsCall = client.boards(ownerID: found.userID, accessToken: token)
            async let pursuitsCall = client.pursuits(ownerID: found.userID, accessToken: token)
            let pursuits = try await pursuitsCall
            let documents = MosaicVisit.authorizedDocuments(try await boardsCall, pursuits: pursuits)
            guard var snapshot = ComposerBoardSync.assemble(mosaicID: mosaicID, documents: documents) else {
                phase = .failed
                return
            }
            // The server leaves saved stickers out of visitors' copy; never keep them if one slips in.
            snapshot.stickerLibrary = []

            try Task.checkCancellation()
            guard account.session?.userID == viewerID else { throw CancellationError() }
            let location = MosaicVisitMedia.location(viewerID: viewerID, ownerID: found.userID)
            let media = try MosaicVisitMedia(documents: documents, mosaicID: mosaicID,
                                            ownerID: found.userID, location: location, client: client)

            let store = ComposerStore(seedSnapshot: snapshot, persistToDisk: false, location: location)
            let visit = MosaicVisit(ownerID: found.userID, pursuits: pursuits, account: account, client: client)
            visit.media = media
            visit.mosaicID = mosaicID
            visit.owner = MosaicPersonResult(
                id: found.userID, username: found.username, displayName: found.displayName, avatarPath: found.avatarPath
            )
            let start = pursuitID.flatMap { wanted in
                snapshot.pursuits.first { ComposerBoardSync.uuid($0.id) == wanted }?.id
            }
            if let pursuitID, start == nil, visit.access(pursuitID) != .open {
                visit.askToRequest(pursuitID)
            }
            let chrome = MosaicChrome(isVisiting: true)
            attach(visit, store: store, chrome: chrome, start: start)
            phase = .ready(store, chrome, visit, start: start)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }

    private func requestMosaic() async {
        guard !requesting else { return }
        requesting = true
        defer { requesting = false }
        guard let link = await connection(), let ownerID = profile?.userID else { return }
        if let status = try? await link.client.requestMosaic(ownerID: ownerID, accessToken: link.token) {
            profile?.requestStatus = status
            if status == "accepted" {
                // Through the screen's own load task, so it stops if the person has left.
                loadAttempt += 1
            }
        }
    }
}

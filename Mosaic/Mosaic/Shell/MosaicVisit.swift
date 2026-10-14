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

    /// One Storage object, or nil when it is missing or not readable.
    func download(path: String, accessToken: String) async -> Data? {
        guard let url = URL(string: "\(config.url.absoluteString)/storage/v1/object/authenticated/media/\(path)") else {
            return nil
        }
        var request = URLRequest(url: url)
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
            followsMosaic: row["follows_mosaic"] as? Bool ?? false
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
                title: (row["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                level: MosaicVisibilityLevel.parse(row["visibility"] as? String, role: "pursuit"),
                canOpen: row["can_open"] as? Bool ?? false,
                requestStatus: row["request_status"] as? String,
                following: row["following"] as? Bool ?? false
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
                title: row["title"] as? String ?? "",
                visibility: "",
                body: body
            )
        }
    }

    /// Storage paths to try for one file, best first. Photos have a display copy;
    /// a GIF's display copy is a still, so its original is used.
    nonisolated static func objectPaths(ownerID: UUID, assetID: String, fileName: String) -> [String] {
        let owner = ownerID.uuidString.lowercased()
        let asset = assetID.lowercased()
        let usesOriginal = ["mov", "mp4", "m4v", "gif"].contains((fileName as NSString).pathExtension.lowercased())
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
    /// Called when a refresh opens or closes a Pursuit, so its board can be fetched or dropped.
    var onAccessChanged: (() -> Void)?
    /// Bumped by every follow, unfollow, and request, so a refresh fetched before one can't undo it.
    @ObservationIgnored private var changes = 0

    private let account: MosaicAccount
    private let client: MosaicVisitClient

    init(ownerID: UUID, pursuits: [MosaicVisitPursuit], account: MosaicAccount, client: MosaicVisitClient) {
        self.ownerID = ownerID
        self.pursuits = Dictionary(uniqueKeysWithValues: pursuits.map { ($0.id, $0) })
        self.account = account
        self.client = client
    }

    var publicPursuits: [MosaicVisitPursuit] {
        pursuits.values
            .filter { $0.level == .public && $0.isOpen }
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
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
        guard !busy.contains(id), let token = await account.accessToken() else { return }
        busy.insert(id)
        defer { busy.remove(id) }
        changes += 1
        do {
            try await client.followPursuit(id: id, accessToken: token)
            pursuits[id]?.following = true
        } catch {
            problem = "That Pursuit could not be followed."
        }
    }

    func unfollow(_ id: UUID) async {
        guard !busy.contains(id), let token = await account.accessToken() else { return }
        busy.insert(id)
        defer { busy.remove(id) }
        changes += 1
        do {
            try await client.unfollowPursuit(id: id, accessToken: token)
            let wasOpen = openIDs
            pursuits[id]?.following = false
            if openIDs != wasOpen {
                onAccessChanged?()
            }
        } catch {
            problem = "That Pursuit could not be unfollowed."
        }
    }

    func request(_ id: UUID) async {
        guard !busy.contains(id) else { return }
        guard let token = await account.accessToken() else {
            problem = "That request could not be sent."
            return
        }
        busy.insert(id)
        defer { busy.remove(id) }
        changes += 1
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
        guard let token = await account.accessToken(),
              let fresh = try? await client.pursuits(ownerID: ownerID, accessToken: token),
              changes == started
        else { return }
        apply(fresh)
    }

    private func apply(_ fresh: [MosaicVisitPursuit]) {
        let wasOpen = openIDs
        pursuits = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0) })
        if openIDs != wasOpen {
            onAccessChanged?()
        }
    }

    private var openIDs: Set<UUID> {
        Set(pursuits.values.filter(\.isOpen).map(\.id))
    }
}

/// Bottom right of a visited Pursuit page: its cover, and follow or unfollow.
struct MosaicVisitPursuitControls: View {
    let pursuitID: UUID

    @Environment(ComposerStore.self) private var store
    @Environment(MosaicVisit.self) private var visit
    @State private var cover: UIImage?

    private var coverFile: String? {
        func find(_ blocks: [ComposerBlock]) -> String? {
            for block in blocks {
                if block.kind == .pursuit, block.pursuitID.flatMap(ComposerBoardSync.uuid) == pursuitID {
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
            HStack(spacing: 12) {
                logo(pursuit)
                if pursuit.isOpen {
                    toggle(pursuit)
                }
            }
            .task(id: ComposerMediaLoadKey(coverFile.map { store.mediaURL(for: $0) }, versions: store.mediaVersions)) { await loadCover() }
        }
    }

    private func logo(_ pursuit: MosaicVisitPursuit) -> some View {
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
        .accessibilityLabel(pursuit.displayTitle)
    }

    @ViewBuilder
    private func toggle(_ pursuit: MosaicVisitPursuit) -> some View {
        Group {
            if pursuit.following {
                Menu {
                    if pursuit.level != .public {
                        Text("This Pursuit is private. You’ll need to request access again.")
                    }
                    Button("Unfollow", systemImage: "minus.circle", role: .destructive) {
                        Task { await visit.unfollow(pursuitID) }
                    }
                } label: {
                    glyph("minus")
                }
                .menuStyle(.button)
            } else {
                Button {
                    Task { await visit.follow(pursuitID) }
                } label: {
                    glyph("plus")
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(visit.busy.contains(pursuitID))
        .accessibilityLabel(pursuit.following ? "Unfollow \(pursuit.displayTitle)" : "Follow \(pursuit.displayTitle)")
        .accessibilityIdentifier("visit.pursuitFollow")
    }

    private func glyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: ComposerAddMenuMetrics.button, height: ComposerAddMenuMetrics.button)
            .background(MosaicBrand.inkBlack, in: Circle())
            .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
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
    @State private var showsFollowSheet = false
    @State private var following = false
    /// The first appearance follows a fresh load, so only later returns refresh access.
    @State private var visitAppeared = false

    private let muted = Color.white.opacity(0.55)

    var body: some View {
        content
            .background(MosaicBrand.inkBlack.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: loadAttempt) { await load() }
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
                MosaicAvatarView(path: profile?.avatarPath ?? person.avatarPath, name: profile?.name ?? person.username, size: 88)
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
        .refreshable { await load() }
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
            .environment(store)
            .environment(chrome)
            .environment(visit)
            .overlay(alignment: .bottomTrailing) {
                if start == nil {
                    HStack(spacing: 12) {
                        MosaicAvatarView(path: profile?.avatarPath ?? person.avatarPath, name: profile?.name ?? person.username, size: ComposerAddMenuMetrics.button)
                            .overlay(Circle().stroke(MosaicBrand.inkBlack, lineWidth: 2))
                            .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                            .accessibilityLabel("@\(person.username)")
                        followButton(visit: visit)
                    }
                    .padding(.trailing, 20)
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
            .sheet(isPresented: $showsFollowSheet) {
                followSheet(visit: visit)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(MosaicBrand.inkBlack)
            }
    }

    @ViewBuilder
    private func followButton(visit: MosaicVisit) -> some View {
        let isFollowing = profile?.followsMosaic == true
        Group {
            if isFollowing {
                Menu {
                    Button("Unfollow", systemImage: "person.badge.minus", role: .destructive) {
                        Task { await unfollow(visit: visit) }
                    }
                } label: {
                    followGlyph("person.fill.checkmark")
                }
                .menuStyle(.button)
            } else {
                Button {
                    showsFollowSheet = true
                } label: {
                    followGlyph("person.fill.badge.plus")
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(following)
        .accessibilityLabel(isFollowing ? "Following" : "Follow")
        .accessibilityIdentifier("visit.followMosaic")
    }

    private func followGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: ComposerAddMenuMetrics.button, height: ComposerAddMenuMetrics.button)
            .background(MosaicBrand.inkBlack, in: Circle())
            .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
    }

    private func followSheet(visit: MosaicVisit) -> some View {
        let pursuits = visit.publicPursuits
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                MosaicAvatarView(path: profile?.avatarPath ?? person.avatarPath, name: profile?.name ?? person.username, size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Follow @\(person.username)")
                        .font(.headline)
                        .foregroundStyle(.white)
                    if !pursuits.isEmpty {
                        Text("You’ll also follow")
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                }
            }
            if !pursuits.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(pursuits) { pursuit in
                            HStack(spacing: 10) {
                                Image(systemName: pursuit.following ? "checkmark.circle.fill" : "circle.grid.2x2")
                                    .font(.subheadline)
                                    .foregroundStyle(muted)
                                    .frame(width: 22)
                                Text(pursuit.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                Task { await followMosaic(visit: visit) }
            } label: {
                Text("Follow")
                    .font(.headline)
                    .foregroundStyle(MosaicBrand.inkBlack)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(following)
            .accessibilityIdentifier("visit.confirmFollow")
        }
        .padding(20)
        .environment(\.colorScheme, .dark)
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
            guard let snapshot = ComposerBoardSync.assemble(mosaicID: mosaicID, documents: documents) else {
                phase = .failed
                return
            }

            try Task.checkCancellation()
            guard account.session?.userID == viewerID else { throw CancellationError() }
            let location = MosaicVisitMedia.location(viewerID: viewerID, ownerID: found.userID)
            let media = try MosaicVisitMedia(documents: documents, mosaicID: mosaicID,
                                            ownerID: found.userID, location: location, client: client)

            let store = ComposerStore(seedSnapshot: snapshot, persistToDisk: false, location: location)
            let visit = MosaicVisit(ownerID: found.userID, pursuits: pursuits, account: account, client: client)
            visit.media = media
            visit.onAccessChanged = { loadAttempt += 1 }
            let start = pursuitID.flatMap { wanted in
                snapshot.pursuits.first { ComposerBoardSync.uuid($0.id) == wanted }?.id
            }
            if let pursuitID, start == nil, visit.access(pursuitID) != .open {
                visit.askToRequest(pursuitID)
            }
            phase = .ready(store, MosaicChrome(isVisiting: true), visit, start: start)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }

    private func requestMosaic() async {
        guard let link = await connection(), let ownerID = profile?.userID else { return }
        requesting = true
        defer { requesting = false }
        if let status = try? await link.client.requestMosaic(ownerID: ownerID, accessToken: link.token) {
            profile?.requestStatus = status
            if status == "accepted" {
                await load()
            }
        }
    }

    private func followMosaic(visit: MosaicVisit) async {
        guard let link = await connection(), let ownerID = profile?.userID else { return }
        following = true
        defer { following = false }
        do {
            try await link.client.followMosaic(ownerID: ownerID, accessToken: link.token)
            profile?.followsMosaic = true
            showsFollowSheet = false
            await visit.refresh()
        } catch {
            visit.problem = "This Mosaic could not be followed."
        }
    }

    private func unfollow(visit: MosaicVisit) async {
        guard let link = await connection(), let ownerID = profile?.userID else { return }
        following = true
        defer { following = false }
        do {
            try await link.client.unfollowMosaic(ownerID: ownerID, accessToken: link.token)
            profile?.followsMosaic = false
            await visit.refresh()
        } catch {
            visit.problem = "This Mosaic could not be unfollowed."
        }
    }
}

import SwiftUI
import UIKit

/// One Mosaic or Pursuit the signed-in person follows.
struct MosaicFollowedItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case mosaic
        case pursuit
    }

    var kind: Kind
    var targetID: UUID
    var owner: MosaicPersonResult
    var title: String
    var coverFile: String?
    var coverAsset: String?
    /// Changed since the follower last opened it; for a Mosaic, also one of its Pursuits they can open.
    var hasUpdate = false

    var id: String { "\(kind.rawValue).\(targetID.uuidString)" }
    var ownerName: String { owner.displayName.isEmpty ? owner.username : owner.displayName }
    var displayTitle: String { title.isEmpty ? "Pursuit" : title }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [owner.username, owner.displayName, kind == .pursuit ? title : ""]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

struct MosaicFollowingClient: Sendable {
    var config: SupabaseSyncConfig
    var session: URLSession = .shared

    func following(accessToken: String) async throws -> [MosaicFollowedItem] {
        try Self.items(from: await rpc("my_follows", body: [:], accessToken: accessToken))
    }

    /// Unfollowing a Mosaic also unfollows every Pursuit of that owner.
    func unfollow(_ item: MosaicFollowedItem, accessToken: String) async throws {
        switch item.kind {
        case .mosaic:
            _ = try await rpc(
                "unfollow_mosaic",
                body: ["p_owner": item.owner.id.uuidString.lowercased()],
                accessToken: accessToken
            )
        case .pursuit:
            _ = try await rpc(
                "unfollow",
                body: ["p_target_type": item.kind.rawValue, "p_target_id": item.targetID.uuidString.lowercased()],
                accessToken: accessToken
            )
        }
    }

    /// Opening a board reads it: its mark goes at once, before the list reloads from the server.
    static func read(_ items: [MosaicFollowedItem], opening target: MosaicVisitTarget) -> [MosaicFollowedItem] {
        items.map { item in
            var item = item
            let opened = target.pursuitID.map { item.kind == .pursuit && item.targetID == $0 }
                ?? (item.kind == .mosaic && item.owner.id == target.person.id)
            if opened { item.hasUpdate = false }
            return item
        }
    }

    /// What is left of the list after unfollowing one item.
    static func remaining(_ items: [MosaicFollowedItem], after item: MosaicFollowedItem) -> [MosaicFollowedItem] {
        items.filter { other in
            item.kind == .mosaic ? other.owner.id != item.owner.id : other.id != item.id
        }
    }

    static func items(from data: Data) throws -> [MosaicFollowedItem] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        return rows.compactMap { row in
            guard let kind = (row["target_type"] as? String).flatMap(MosaicFollowedItem.Kind.init(rawValue:)),
                  let targetID = (row["target_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let ownerID = (row["owner_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let username = row["username"] as? String
            else { return nil }
            return MosaicFollowedItem(
                kind: kind,
                targetID: targetID,
                owner: MosaicPersonResult(
                    id: ownerID,
                    username: username,
                    displayName: (row["display_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    avatarPath: row["avatar_path"] as? String
                ),
                title: (row["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                coverFile: row["cover_file"] as? String,
                coverAsset: row["cover_asset"] as? String,
                hasUpdate: row["has_update"] as? Bool ?? false
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

/// A followed Pursuit's cover photo in a circle, or its first letter.
struct MosaicPursuitCoverView: View {
    var item: MosaicFollowedItem
    var size: CGFloat

    @Environment(\.mosaicAccount) private var account
    @State private var image: UIImage?

    private var paths: [String] {
        guard let asset = item.coverAsset, let file = item.coverFile else { return [] }
        let isVideo = ["mov", "mp4", "m4v"].contains((file as NSString).pathExtension.lowercased())
        guard !isVideo else { return [] }
        let base = "\(item.owner.id.uuidString.lowercased())/\(asset.lowercased())"
        return ["\(base)/thumb", "\(base)/display"]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.1))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(item.displayTitle.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: paths) { await load() }
    }

    private func load() async {
        guard let first = paths.first else {
            image = nil
            return
        }
        // Decoded at the circle's size, so each size is cached on its own.
        let pixels = Int(size * 3)
        let key = "media/\(first)@\(pixels)"
        if let cached = MosaicAvatarCache.image(for: key) {
            image = cached
            return
        }
        guard let account,
              let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken()
        else { return }
        let client = MosaicVisitClient(config: config)
        // Decoded off the main thread, rather than at full size on it when first drawn.
        for path in paths {
            if let data = await client.download(path: path, accessToken: token),
               let loaded = await Task.detached(priority: .userInitiated, operation: {
                   MosaicThumbnail.image(data: data, maxPixelSize: pixels)
               }).value {
                guard !Task.isCancelled else { return }
                MosaicAvatarCache.store(loaded, for: key)
                image = loaded
                return
            }
        }
    }
}

/// Circle's Following side: the Pursuits and Mosaics the owner follows, each list with its own
/// search. A blue mark shows what changed since it was last opened.
struct MosaicFollowingView: View {
    /// Whether this side of Circle is showing; the lists reload each time it comes into view.
    var isShown = true

    @Environment(\.mosaicAccount) private var account

    @State private var opened: MosaicVisitTarget?
    @State private var following: [MosaicFollowedItem] = []
    /// Rows opened just now. The server learns of the visit in the background, so a reload on
    /// coming back can arrive before it and would bring the mark back.
    @State private var readAt: [String: Date] = [:]
    @State private var loaded = false
    @State private var pursuitQuery = ""
    @State private var mosaicQuery = ""
    @FocusState private var listFocus: MosaicFollowedItem.Kind?

    private let field = Color.white.opacity(0.08)
    private let muted = Color.white.opacity(0.55)
    /// The mark on a followed board that changed since it was last opened.
    private static let updateColor = Color(red: 0.32, green: 0.64, blue: 1)

    var body: some View {
        Group {
            if account == nil {
                Text("Sign in to see who you follow.")
                    .font(.footnote)
                    .foregroundStyle(muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    column(.pursuit)
                    column(.mosaic)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea(.keyboard)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { listFocus = nil }
        }
        .onAppear { Task { await load() } }
        .onChange(of: isShown) { _, shown in
            if shown {
                Task { await load() }
            } else {
                listFocus = nil
            }
        }
        .navigationDestination(item: $opened) { target in
            MosaicVisitView(target: target)
                // Another person, or another Pursuit, while one is open is a new visit, not this one updated.
                .id(target)
        }
        .accessibilityIdentifier("circle.following")
    }

    private func column(_ kind: MosaicFollowedItem.Kind) -> some View {
        let query = kind == .pursuit ? pursuitQuery : mosaicQuery
        let total = following.count { $0.kind == kind }
        let items = following.filter { $0.kind == kind && $0.matches(query) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(kind == .pursuit ? "Pursuits" : "Mosaics")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(muted)
                if loaded {
                    Text("\(total)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.35))
                        .accessibilityIdentifier("following.\(kind.rawValue).total")
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.footnote)
                    .foregroundStyle(muted)
                TextField("", text: kind == .pursuit ? $pursuitQuery : $mosaicQuery, prompt: Text("Search").foregroundStyle(muted))
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($listFocus, equals: kind)
                    .accessibilityIdentifier("following.\(kind.rawValue).field")
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onTapGesture { listFocus = kind }

            if items.isEmpty {
                if loaded {
                    Text(query.isEmpty ? "None yet" : "No matches")
                        .font(.caption)
                        .foregroundStyle(muted)
                        .padding(.top, 2)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            row(item)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A tap opens the board; following, unfollowing, and the owner's Mosaic are all there. Holding
    /// it still offers a quick unfollow.
    private func row(_ item: MosaicFollowedItem) -> some View {
        Button {
            listFocus = nil
            open(MosaicVisitTarget(person: item.owner, pursuitID: item.kind == .pursuit ? item.targetID : nil))
        } label: {
            rowLabel(item)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Unfollow", systemImage: "person.badge.minus", role: .destructive) {
                Task { await unfollow(item) }
            }
        }
        .accessibilityValue(item.hasUpdate ? "Updated" : "")
        .accessibilityAction(named: "Unfollow") {
            Task { await unfollow(item) }
        }
        .accessibilityIdentifier("following.\(item.kind.rawValue).\(item.owner.username)")
    }

    private func open(_ target: MosaicVisitTarget) {
        let read = MosaicFollowingClient.read(following, opening: target)
        for (before, after) in zip(following, read) where before.hasUpdate && !after.hasUpdate {
            readAt[after.id] = .now
        }
        following = read
        opened = target
    }

    private func rowLabel(_ item: MosaicFollowedItem) -> some View {
        HStack(spacing: 8) {
            if item.kind == .pursuit {
                HStack(spacing: -8) {
                    MosaicAvatarView(path: item.owner.avatarPath, name: item.ownerName, size: 30)
                        .overlay(Circle().stroke(MosaicBrand.inkBlack, lineWidth: 2))
                        .zIndex(1)
                    MosaicPursuitCoverView(item: item, size: 30)
                }
            } else {
                MosaicAvatarView(path: item.owner.avatarPath, name: item.ownerName, size: 30)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(item.kind == .pursuit ? item.displayTitle : item.ownerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("@\(item.owner.username)")
                    .font(.caption)
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.hasUpdate {
                Circle()
                    .fill(Self.updateColor)
                    .frame(width: 8, height: 8)
                    .padding(.trailing, 4)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .animation(.easeOut(duration: 0.2), value: item.hasUpdate)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func load() async {
        guard let account,
              let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken(),
              let items = try? await MosaicFollowingClient(config: config).following(accessToken: token)
        else {
            loaded = true
            return
        }
        following = items.map { item in
            var item = item
            if let at = readAt[item.id], Date.now.timeIntervalSince(at) < 30 {
                item.hasUpdate = false
            }
            return item
        }
        loaded = true
    }

    private func unfollow(_ item: MosaicFollowedItem) async {
        guard let account,
              let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken()
        else { return }
        do {
            try await MosaicFollowingClient(config: config).unfollow(item, accessToken: token)
            withAnimation { following = MosaicFollowingClient.remaining(following, after: item) }
        } catch {
            await load()
        }
    }
}

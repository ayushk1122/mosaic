import SwiftUI
import UIKit

struct MosaicPersonResult: Identifiable, Hashable, Sendable {
    var id: UUID
    var username: String
    var displayName: String
    var avatarPath: String? = nil
}

/// Profile pictures already downloaded this session, keyed by Storage path.
@MainActor
enum MosaicAvatarCache {
    private static let images = NSCache<NSString, UIImage>()

    static func image(for path: String) -> UIImage? {
        images.object(forKey: path as NSString)
    }

    static func store(_ image: UIImage, for path: String) {
        images.setObject(image, forKey: path as NSString)
    }
}

/// A round profile picture, or the first letter of the name until one loads.
struct MosaicAvatarView: View {
    var path: String?
    var name: String
    var size: CGFloat

    @Environment(\.mosaicAccount) private var account
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.14))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: path) { await load() }
    }

    private func load() async {
        guard let path else {
            image = nil
            return
        }
        if let cached = MosaicAvatarCache.image(for: path) {
            image = cached
            return
        }
        image = nil
        guard let account,
              let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken(),
              let data = try? await MosaicSettingsClient(config: config).loadAvatar(path: path, accessToken: token),
              let loaded = UIImage(data: data),
              !Task.isCancelled
        else { return }
        MosaicAvatarCache.store(loaded, for: path)
        image = loaded
    }
}

struct MosaicSearchClient: Sendable {
    var config: SupabaseSyncConfig
    var session: URLSession = .shared

    /// People whose username or display name matches the query, at most 20, through `search_profiles`.
    func people(matching query: String, accessToken: String) async throws -> [MosaicPersonResult] {
        let endpoint = config.url
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("rpc")
            .appendingPathComponent("search_profiles")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["p_query": query])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SupabaseDocumentSyncError.requestFailed
        }
        return try Self.results(from: data)
    }

    static func results(from data: Data) throws -> [MosaicPersonResult] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        return rows.compactMap { row in
            guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let username = row["username"] as? String
            else { return nil }
            let displayName = (row["display_name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return MosaicPersonResult(
                id: id,
                username: username,
                displayName: displayName,
                avatarPath: row["avatar_path"] as? String
            )
        }
    }
}

/// Discover: username search on the top half, and what the owner follows on the bottom half.
struct MosaicDiscoverView: View {
    var linked: Binding<MosaicLink.Target?> = .constant(nil)
    var onOpenOwnMosaic: () -> Void = {}

    @Environment(\.mosaicAccount) private var account
    @Environment(\.mosaicTabBarHidden) private var tabBarHidden

    private enum Phase: Equatable {
        case idle
        case searching
        case done
        case failed
    }

    @State private var query = ""
    @State private var results: [MosaicPersonResult] = []
    @State private var phase = Phase.idle
    @State private var opened: MosaicVisitTarget?
    @State private var following: [MosaicFollowedItem] = []
    @State private var followingLoaded = false
    @State private var pursuitQuery = ""
    @State private var mosaicQuery = ""
    @FocusState private var focused: Bool
    @FocusState private var listFocus: MosaicFollowedItem.Kind?

    private let field = Color.white.opacity(0.08)
    private let muted = Color.white.opacity(0.55)
    /// The mark on a followed board that changed since it was last opened.
    private static let updateColor = Color(red: 0.32, green: 0.64, blue: 1)

    private var cleaned: String {
        MosaicSettingsList.typedUsername(query).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    searchField
                    content
                }
                .frame(height: proxy.size.height * 0.5 - 12, alignment: .top)
                Text("Following")
                    .font(.headline)
                    .foregroundStyle(muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("discover.following.title")
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                HStack(alignment: .top, spacing: 14) {
                    followingColumn(.pursuit)
                    followingColumn(.mosaic)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea(.keyboard)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    focused = false
                    listFocus = nil
                }
        }
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(tabBarHidden ? .hidden : .visible, for: .tabBar)
        .task(id: cleaned) { await search(cleaned) }
        .task(id: linked.wrappedValue) { await openLink() }
        .onAppear {
            Task { await loadFollowing() }
        }
        .navigationDestination(item: $opened) { target in
            MosaicVisitView(target: target)
        }
        .accessibilityIdentifier(MosaicTab.search.screenAccessibilityIdentifier)
        .mosaicPageBackground(.discover)
    }

    // MARK: Following

    private func followingColumn(_ kind: MosaicFollowedItem.Kind) -> some View {
        let query = kind == .pursuit ? pursuitQuery : mosaicQuery
        let total = following.count { $0.kind == kind }
        let items = following.filter { $0.kind == kind && $0.matches(query) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(kind == .pursuit ? "Pursuits" : "Mosaics")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(muted)
                if followingLoaded {
                    Text("\(total)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.35))
                        .accessibilityIdentifier("discover.\(kind.rawValue).total")
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
                    .accessibilityIdentifier("discover.\(kind.rawValue).field")
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onTapGesture { listFocus = kind }

            if items.isEmpty {
                if followingLoaded {
                    Text(query.isEmpty ? "None yet" : "No matches")
                        .font(.caption)
                        .foregroundStyle(muted)
                        .padding(.top, 2)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            followedRow(item)
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
    private func followedRow(_ item: MosaicFollowedItem) -> some View {
        Button {
            focused = false
            listFocus = nil
            open(MosaicVisitTarget(person: item.owner, pursuitID: item.kind == .pursuit ? item.targetID : nil))
        } label: {
            followedRowLabel(item)
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
        .accessibilityIdentifier("discover.\(item.kind.rawValue).\(item.owner.username)")
    }

    private func open(_ target: MosaicVisitTarget) {
        following = MosaicFollowingClient.read(following, opening: target)
        opened = target
    }

    private func followedRowLabel(_ item: MosaicFollowedItem) -> some View {
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

    private func loadFollowing() async {
        guard let account,
              let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken(),
              let items = try? await MosaicFollowingClient(config: config).following(accessToken: token)
        else {
            followingLoaded = true
            return
        }
        following = items
        followingLoaded = true
    }

    /// Opens the Mosaic a link names, on its Pursuit when it names one. An unknown name is left in
    /// the search field.
    private func openLink() async {
        guard let target = linked.wrappedValue,
              let account,
              let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken()
        else { return }
        let name = target.username
        let match = try? await MosaicSearchClient(config: config)
            .people(matching: name, accessToken: token)
            .first { $0.username == name }
        guard !Task.isCancelled else { return }
        if let match {
            if match.id == account.session?.userID {
                onOpenOwnMosaic()
            } else {
                focused = false
                opened = MosaicVisitTarget(person: match, pursuitID: target.pursuitID)
            }
        } else {
            query = name
        }
        linked.wrappedValue = nil
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
            await loadFollowing()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(muted)
            TextField("", text: $query, prompt: Text("Search names and usernames").foregroundStyle(muted))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(.white)
                .tint(.white)
                .focused($focused)
                .accessibilityIdentifier("search.field")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { focused = true }
    }

    @ViewBuilder
    private var content: some View {
        if account == nil {
            note("Sign in to find people.")
        } else if cleaned.isEmpty {
            EmptyView()
        } else if phase == .failed {
            note("Search is not available right now.")
        } else if results.isEmpty {
            if phase == .done {
                note("No one matches “\(cleaned)” yet.")
            } else {
                ProgressView()
                    .tint(muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { person in
                        row(person)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func row(_ person: MosaicPersonResult) -> some View {
        let isSelf = person.id == account?.session?.userID
        let name = person.displayName.isEmpty ? person.username : person.displayName
        return HStack(spacing: 12) {
            MosaicAvatarView(path: person.avatarPath, name: name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("@\(person.username)")
                    .font(.subheadline)
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isSelf {
                Text("You")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(muted)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isSelf else { return }
            focused = false
            opened = MosaicVisitTarget(person: person)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelf ? [] : .isButton)
        .accessibilityIdentifier("search.result.\(person.username)")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(muted)
            .padding(.top, 4)
    }

    private func search(_ text: String) async {
        guard !text.isEmpty else {
            results = []
            phase = .idle
            return
        }
        phase = .searching
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled,
              let account,
              let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken()
        else { return }
        do {
            let found = try await MosaicSearchClient(config: config).people(matching: text, accessToken: token)
            guard !Task.isCancelled else { return }
            results = found
            phase = .done
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            phase = .failed
        }
    }
}

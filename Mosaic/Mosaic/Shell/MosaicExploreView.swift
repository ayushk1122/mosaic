import SwiftUI
import UIKit

/// Public Mosaics and Pursuits their owners chose to share, in a shuffled grid. Tapping one opens
/// that person's Mosaic, on the Pursuit when the tile is one. The search bar finds people by name
/// or username, then shared boards; while it's in use the grid steps aside for the results.
struct MosaicExploreView: View {
    /// Set by a `mosaic://@username` link; Explore opens that person's Mosaic and clears it.
    var linked: Binding<MosaicLink.Target?> = .constant(nil)
    /// Bumped when the Explore tab is tapped while open: back to the top of the feed.
    var resetCount = 0
    var onOpenOwnMosaic: () -> Void = {}

    @Environment(\.mosaicAccount) private var account
    @Environment(\.mosaicTabBarHidden) private var tabBarHidden

    private enum Phase: Equatable {
        case loading
        case ready
        case failed
        case signedOut
    }

    private enum SearchPhase: Equatable {
        case idle
        case searching
        case done
        case failed
    }

    @State private var filter = MosaicExploreClient.Filter.all
    @State private var sort = MosaicExploreClient.Sort.shuffle
    /// Explore is for finding new people; what they follow is already in Circle. Remembered.
    @AppStorage("explore.hideFollowed") private var hideFollowed = true
    @State private var items: [MosaicExploreItem] = []
    /// The same seed pages without repeats; pulling to refresh picks a new one.
    @State private var seed = UUID().uuidString
    @State private var phase = Phase.loading
    @State private var loadingMore = false
    @State private var reachedEnd = false
    /// Where the next page starts on the server; tiles already shown can make the list shorter.
    @State private var nextOffset = 0
    /// Bumped by every reload, so a page asked for before it isn't added to the new list.
    @State private var generation = 0
    /// What the grid holds now; coming back from a visit shouldn't start it over.
    @State private var loadedRequest: Request?
    @State private var opened: MosaicVisitTarget?
    /// The tile whose owner's profile card is open.
    @State private var card: MosaicExploreItem?

    /// On from a tap in the search bar until Cancel; the grid waits underneath, where it was.
    @State private var isSearching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var people: [MosaicPersonResult] = []
    @State private var boards: [MosaicExploreItem] = []
    @State private var searchPhase = SearchPhase.idle
    @State private var feedPosition = ScrollPosition(edge: .top)

    private let muted = Color.white.opacity(0.55)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)
    private static let handwriting = "BradleyHandITCTT-Bold"

    /// What to fetch: a new filter or sort starts over from the first page.
    private struct Request: Equatable {
        var filter: MosaicExploreClient.Filter
        var sort: MosaicExploreClient.Sort
        var hideFollowed: Bool
    }

    private var request: Request {
        Request(filter: filter, sort: sort, hideFollowed: hideFollowed)
    }

    /// The search text without a leading @, which people often type before a username.
    private var cleaned: String {
        MosaicSettingsList.typedUsername(query).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ZStack(alignment: .top) {
                feed
                    .opacity(isSearching ? 0 : 1)
                    .allowsHitTesting(!isSearching)
                    .accessibilityHidden(isSearching)
                if isSearching {
                    searchResults
                        .transition(.opacity)
                }
            }
        }
        .padding(.top, 8)
        .animation(.easeOut(duration: 0.2), value: isSearching)
        .task(id: request) {
            guard loadedRequest != request || items.isEmpty else { return }
            await reload(reshuffle: false)
        }
        .task(id: cleaned) { await search(cleaned) }
        .task(id: linked.wrappedValue) { await openLink() }
        .onChange(of: searchFocused) { _, focused in
            if focused { isSearching = true }
        }
        .onChange(of: resetCount) {
            card = nil
            opened = nil
            endSearch()
            withAnimation { feedPosition.scrollTo(edge: .top) }
        }
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(tabBarHidden || card != nil ? .hidden : .visible, for: .tabBar)
        .navigationDestination(item: $opened) { target in
            MosaicVisitView(target: target)
                // Another person, or another Pursuit, while one is open is a new visit, not this one updated.
                .id(target)
        }
        // A container, so the pinned header's own identifiers aren't replaced by the screen's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(MosaicTab.explore.screenAccessibilityIdentifier)
        .mosaicPageBackground(.explore)
        .overlay {
            if let card {
                MosaicProfileCard(
                    person: card.ownerTarget.person,
                    onVisit: {
                        closeCard()
                        opened = card.ownerTarget
                    },
                    onProfileChange: { changed in
                        // Following their Mosaic here takes its tile out when followed boards are hidden.
                        guard hideFollowed, changed.followsMosaic else { return }
                        items.removeAll { $0.ownerID == card.ownerID && $0.kind == .mosaic }
                    },
                    onClose: closeCard
                )
                .transition(.opacity.combined(with: .scale(scale: 0.86)))
            }
        }
    }

    private func closeCard() {
        withAnimation(.easeOut(duration: 0.2)) { card = nil }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if !isSearching {
                Text("Explore")
                    .font(.custom(Self.handwriting, size: 40, relativeTo: .largeTitle))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            searchField
            if isSearching {
                Button("Cancel", action: endSearch)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .accessibilityIdentifier("explore.search.cancel")
            }
        }
        .frame(minHeight: 48)
        .padding(.horizontal, 16)
    }

    private func endSearch() {
        searchFocused = false
        query = ""
        isSearching = false
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(muted)
            TextField("", text: $query, prompt: Text("Search").foregroundStyle(muted))
                .font(.subheadline)
                .foregroundStyle(.white)
                .tint(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .accessibilityIdentifier("explore.search")
            if !query.isEmpty {
                Button {
                    query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.1), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { searchFocused = true }
    }

    // MARK: Feed

    private var feed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    sortMenu
                    filterChips
                }
                .padding(.horizontal, 16)
                content
            }
            // Room to scroll the last row above the Customize page button.
            .padding(.bottom, ComposerAddMenuMetrics.button + 32)
        }
        .scrollPosition($feedPosition)
        .refreshable { await reload(reshuffle: true) }
    }

    private var sortMenu: some View {
        let sorted = sort != .shuffle || hideFollowed
        return Menu {
            Picker("Sort by", selection: $sort) {
                ForEach(MosaicExploreClient.Sort.allCases) { option in
                    Label {
                        Text(option.title)
                        if let detail = option.detail { Text(detail) }
                    } icon: {
                        Image(systemName: option.systemImage)
                    }
                    .tag(option)
                }
            }
            Section {
                Toggle(isOn: $hideFollowed) {
                    Label("Hide boards I follow", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(sorted ? MosaicBrand.inkBlack : .white)
                .frame(width: 34, height: 34)
                .background(sorted ? Color.white : Color.white.opacity(0.1), in: Circle())
        }
        .accessibilityLabel("Sort and filter")
        .accessibilityValue(hideFollowed ? "\(sort.title), hiding boards you follow" : sort.title)
        .accessibilityIdentifier("explore.sort")
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(MosaicExploreClient.Filter.allCases) { option in
                let chosen = filter == option
                Button {
                    guard filter != option else { return }
                    filter = option
                } label: {
                    Text(option.title)
                        .font(.custom(Self.handwriting, size: 17, relativeTo: .subheadline))
                        .foregroundStyle(chosen ? MosaicBrand.inkBlack : .white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(chosen ? Color.white : Color.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier("explore.filter.\(option.rawValue)")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .signedOut:
            message("Sign in to explore other people's Mosaics.")
        case .loading where items.isEmpty:
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        case .failed where items.isEmpty:
            VStack(spacing: 12) {
                message("Explore couldn't load. Check your connection and try again.")
                Button("Try again") { Task { await reload(reshuffle: false) } }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
            .frame(maxWidth: .infinity)
        default:
            if items.isEmpty {
                message(emptyText)
            } else {
                grid(items, loadsMore: true)
                if loadingMore {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
        }
    }

    private func grid(_ tiles: [MosaicExploreItem], loadsMore: Bool) -> some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(tiles) { item in
                MosaicExploreTile(
                    item: item,
                    onOpen: {
                        searchFocused = false
                        opened = item.target
                    },
                    onOpenOwner: {
                        searchFocused = false
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { card = item }
                    }
                )
                .onAppear {
                    if loadsMore, item.id == items.last?.id { Task { await loadMore() } }
                }
            }
        }
    }

    private var emptyText: String {
        if hideFollowed {
            return "You follow everything here. Turn off Hide boards I follow to see it all again."
        }
        return switch filter {
        case .all: "Nothing here yet. Share a public Mosaic or Pursuit from Settings to be one of the first."
        case .mosaics: "No Mosaics shared yet."
        case .pursuits: "No Pursuits shared yet."
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 60)
    }

    // MARK: Search

    private var searchResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if account == nil {
                    message("Sign in to find people.")
                } else if cleaned.isEmpty {
                    message("Search for people by name or username.")
                } else if searchPhase == .failed {
                    message("Search is not available right now.")
                } else if searchPhase != .done {
                    ProgressView()
                        .tint(muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else if people.isEmpty && boards.isEmpty {
                    message("No one matches “\(cleaned)” yet.")
                } else {
                    if !people.isEmpty {
                        sectionTitle("People")
                        LazyVStack(spacing: 0) {
                            ForEach(people) { person in
                                MosaicPersonRow(person: person, isSelf: person.id == account?.session?.userID) {
                                    searchFocused = false
                                    opened = MosaicVisitTarget(person: person)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    if !boards.isEmpty {
                        sectionTitle("Boards")
                            .padding(.top, people.isEmpty ? 0 : 10)
                        grid(boards, loadsMore: false)
                    }
                }
            }
            .padding(.bottom, ComposerAddMenuMetrics.button + 32)
        }
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("explore.results")
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(muted)
            .padding(.horizontal, 16)
            .accessibilityAddTraits(.isHeader)
    }

    /// People first, then shared boards whose titles or owners match, most followed first.
    private func search(_ text: String) async {
        guard !text.isEmpty else {
            people = []
            boards = []
            searchPhase = .idle
            return
        }
        searchPhase = .searching
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled,
              let account,
              let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken()
        else { return }
        async let foundPeople = MosaicSearchClient(config: config).people(matching: text, accessToken: token)
        async let foundBoards = MosaicExploreClient(config: config)
            .feed(filter: .all, sort: .popular, query: text, seed: seed, offset: 0, accessToken: token)
        do {
            let (matchedPeople, matchedBoards) = try await (foundPeople, foundBoards)
            guard !Task.isCancelled else { return }
            people = matchedPeople
            boards = matchedBoards
            searchPhase = .done
        } catch {
            guard !Task.isCancelled else { return }
            people = []
            boards = []
            searchPhase = .failed
        }
    }

    /// Opens the Mosaic a link names, on its Pursuit when it names one. An unknown name is left in
    /// the search bar.
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
                searchFocused = false
                opened = MosaicVisitTarget(person: match, pursuitID: target.pursuitID)
            }
        } else {
            isSearching = true
            query = name
        }
        linked.wrappedValue = nil
    }

    // MARK: Loading

    private func reload(reshuffle: Bool) async {
        if reshuffle { seed = UUID().uuidString }
        generation += 1
        let current = generation
        reachedEnd = false
        if !reshuffle { phase = .loading }
        guard let page = await fetch(offset: 0), current == generation else { return }
        items = page
        nextOffset = page.count
        reachedEnd = page.count < MosaicExploreClient.pageSize
        loadedRequest = request
        phase = .ready
    }

    private func loadMore() async {
        guard phase == .ready, !loadingMore, !reachedEnd else { return }
        loadingMore = true
        defer { loadingMore = false }
        let current = generation
        // A page of only tiles already shown adds nothing to scroll to, so keep going.
        while !reachedEnd {
            guard let page = await fetch(offset: nextOffset), current == generation else { return }
            nextOffset += page.count
            reachedEnd = page.count < MosaicExploreClient.pageSize
            let known = Set(items.map(\.id))
            let fresh = page.filter { !known.contains($0.id) }
            items.append(contentsOf: fresh)
            if !fresh.isEmpty { return }
        }
    }

    /// Nil when it couldn't load; the phase says why.
    private func fetch(offset: Int) async -> [MosaicExploreItem]? {
        guard let account, let config = SupabaseSyncConfig.current() else {
            phase = .signedOut
            return nil
        }
        guard let token = await account.accessToken() else {
            phase = account.session == nil ? .signedOut : .failed
            return nil
        }
        let requested = request
        do {
            let page = try await MosaicExploreClient(config: config)
                .feed(filter: requested.filter, sort: requested.sort, hideFollowed: requested.hideFollowed,
                      seed: seed, offset: offset, accessToken: token)
            // A filter or sort changed while this page loaded belongs to the newer request.
            guard requested == request, !Task.isCancelled else { return nil }
            return page
        } catch {
            guard !Task.isCancelled else { return nil }
            if items.isEmpty || offset == 0 { phase = .failed }
            return nil
        }
    }
}

/// A shared board's preview, with its owner's picture and name ("Name: Pursuit" for a Pursuit).
/// The picture opens the owner's profile card.
struct MosaicExploreTile: View {
    let item: MosaicExploreItem
    var onOpen: () -> Void = {}
    var onOpenOwner: () -> Void = {}

    private var ownerCardLabel: String { "Show \(item.ownerName)'s profile" }

    var body: some View {
        Color.white.opacity(0.06)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                MosaicExplorePreviewImage(path: item.previewPath)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 56)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 5) {
                    avatar
                    // Two lines, so a long name doesn't hide the Pursuit's.
                    Text(item.caption)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .allowsHitTesting(false)
                }
                .padding(6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.kind == .pursuit ? "\(item.caption), Pursuit" : "\(item.caption), Mosaic")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, onOpen)
            .accessibilityActions {
                Button(ownerCardLabel, action: onOpenOwner)
            }
            .accessibilityIdentifier("explore.tile.\(item.id.uuidString.lowercased())")
    }

    private var avatar: some View {
        Button(action: onOpenOwner) {
            MosaicAvatarView(path: item.avatarPath, name: item.ownerName, size: 18)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
                // A little bigger to touch than to see.
                .contentShape(Circle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("explore.tile.owner.\(item.id.uuidString.lowercased())")
    }
}

/// Downloads a preview once per session and decodes it at tile size, off the main thread.
private struct MosaicExplorePreviewImage: View {
    let path: String

    @Environment(\.mosaicAccount) private var account
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .task(id: path) { await load() }
    }

    private func load() async {
        if let cached = MosaicExplorePreviewCache.image(for: path) {
            image = cached
            return
        }
        guard let account, let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken(),
              let data = await MosaicVisitClient(config: config).download(path: path, accessToken: token),
              !Task.isCancelled
        else { return }
        let decoded = await Task.detached(priority: .userInitiated) {
            MosaicThumbnail.image(data: data, maxPixelSize: 480)
        }.value
        guard let decoded, !Task.isCancelled else { return }
        MosaicExplorePreviewCache.store(decoded, for: path)
        image = decoded
    }
}

@MainActor
private enum MosaicExplorePreviewCache {
    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    static func image(for path: String) -> UIImage? {
        images.object(forKey: path as NSString)
    }

    static func store(_ image: UIImage, for path: String) {
        images.setObject(image, forKey: path as NSString)
    }
}

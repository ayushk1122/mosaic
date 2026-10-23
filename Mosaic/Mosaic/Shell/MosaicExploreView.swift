import SwiftUI
import UIKit

/// Public Mosaics and Pursuits their owners chose to share, in a shuffled grid. Tapping one opens
/// that person's Mosaic, on the Pursuit when the tile is one.
struct MosaicExploreView: View {
    @Environment(\.mosaicAccount) private var account
    @Environment(\.mosaicTabBarHidden) private var tabBarHidden

    private enum Phase: Equatable {
        case loading
        case ready
        case failed
        case signedOut
    }

    @State private var filter = MosaicExploreClient.Filter.all
    @State private var sort = MosaicExploreClient.Sort.shuffle
    /// Explore is for finding new people; what they follow is already in Circle. Remembered.
    @AppStorage("explore.hideFollowed") private var hideFollowed = true
    @State private var query = ""
    @FocusState private var searching: Bool
    @State private var items: [MosaicExploreItem] = []
    /// The same seed pages without repeats; pulling to refresh picks a new one.
    @State private var seed = UUID().uuidString
    @State private var phase = Phase.loading
    @State private var loadingMore = false
    @State private var reachedEnd = false
    @State private var opened: MosaicVisitTarget?
    /// The tile whose owner's profile card is open.
    @State private var card: MosaicExploreItem?

    private let muted = Color.white.opacity(0.55)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)
    private static let handwriting = "BradleyHandITCTT-Bold"

    /// What to fetch: a new filter, sort, or search starts over from the first page.
    private struct Request: Equatable {
        var filter: MosaicExploreClient.Filter
        var sort: MosaicExploreClient.Sort
        var hideFollowed: Bool
        var query: String
    }

    private var request: Request {
        Request(filter: filter, sort: sort, hideFollowed: hideFollowed,
                query: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Text("Explore")
                        .font(.custom(Self.handwriting, size: 40, relativeTo: .largeTitle))
                        .foregroundStyle(.white)
                        .fixedSize()
                        .accessibilityAddTraits(.isHeader)
                    searchField
                }
                .padding(.horizontal, 16)
                HStack(spacing: 8) {
                    sortMenu
                    filterChips
                }
                .padding(.horizontal, 16)
                content
            }
            .padding(.top, 8)
            // Room to scroll the last row above the Customize page button.
            .padding(.bottom, ComposerAddMenuMetrics.button + 32)
        }
        .refreshable { await reload(reshuffle: true) }
        .task(id: request) {
            // Typing waits for a pause; a filter or sort tap loads at once.
            if !request.query.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            await reload(reshuffle: false)
        }
        .scrollDismissesKeyboard(.immediately)
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(tabBarHidden || card != nil ? .hidden : .visible, for: .tabBar)
        .navigationDestination(item: $opened) { target in
            MosaicVisitView(target: target)
        }
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

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(muted)
            TextField("Search", text: $query)
                .font(.subheadline)
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searching)
                .accessibilityIdentifier("explore.search")
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
        .padding(.horizontal, 12)
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.1), in: Capsule())
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
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(items) { item in
                        MosaicExploreTile(
                            item: item,
                            onOpen: { opened = item.target },
                            onOpenOwner: {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { card = item }
                            }
                        )
                        .onAppear {
                            if item.id == items.last?.id { Task { await loadMore() } }
                        }
                    }
                }
                if loadingMore {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
        }
    }

    private var emptyText: String {
        if !request.query.isEmpty {
            return "Nothing matches “\(request.query)”."
        }
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

    private func reload(reshuffle: Bool) async {
        if reshuffle { seed = UUID().uuidString }
        reachedEnd = false
        if !reshuffle { phase = .loading }
        guard let page = await fetch(offset: 0) else { return }
        items = page
        reachedEnd = page.count < MosaicExploreClient.pageSize
        phase = .ready
    }

    private func loadMore() async {
        guard phase == .ready, !loadingMore, !reachedEnd else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let page = await fetch(offset: items.count) else { return }
        let known = Set(items.map(\.id))
        items.append(contentsOf: page.filter { !known.contains($0.id) })
        reachedEnd = page.count < MosaicExploreClient.pageSize
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
                      query: requested.query, seed: seed, offset: offset, accessToken: token)
            // A filter, sort, or search changed while this page loaded belongs to the newer request.
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

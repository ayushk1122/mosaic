import SwiftUI
import UIKit

enum MosaicTab: String, CaseIterable, Identifiable {
    case feed
    case mosaic
    case circle
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: "Feed"
        case .mosaic: "Mosaic"
        case .circle: "Circle"
        case .search: "Discover"
        }
    }

    var systemImage: String {
        switch self {
        case .feed: "rectangle.stack"
        case .mosaic: "square.grid.2x2"
        case .circle: "person.2"
        case .search: "magnifyingglass"
        }
    }

    var screenAccessibilityIdentifier: String {
        "\(rawValue).screen"
    }
}

private struct MosaicTabBarHiddenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var mosaicTabBarHidden: Bool {
        get { self[MosaicTabBarHiddenKey.self] }
        set { self[MosaicTabBarHiddenKey.self] = newValue }
    }
}

private struct MosaicAccountEnvironmentKey: EnvironmentKey {
    static let defaultValue: MosaicAccount? = nil
}

extension EnvironmentValues {
    var mosaicAccount: MosaicAccount? {
        get { self[MosaicAccountEnvironmentKey.self] }
        set { self[MosaicAccountEnvironmentKey.self] = newValue }
    }
}

@MainActor
@Observable
final class MosaicChrome {
    /// Someone else's Mosaic. It stays in view mode.
    let isVisiting: Bool
    var isViewing = false {
        didSet {
            if isVisiting, !isViewing { isViewing = true }
        }
    }

    init(isVisiting: Bool = false) {
        self.isVisiting = isVisiting
        self.isViewing = isVisiting
    }
}

struct MosaicTabShell: View {
    @State private var selection: MosaicTab = .mosaic
    @State private var chrome = MosaicChrome()
    @State private var store: ComposerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var downloads = ComposerBackgroundRestore()
    @State private var downloadAttempt = 0
    @State private var remoteSync: ComposerRemoteSync
    var account: MosaicAccount?

    init(
        account: MosaicAccount? = nil,
        persistToDisk: Bool = !ProcessInfo.processInfo.arguments.contains("UITestSkipLaunchAnimation")
    ) {
        self.account = account
        let location: ComposerStorageLocation = account?.session.map { .account($0.userID) } ?? .shared()
        let store = ComposerStore(persistToDisk: persistToDisk, location: location)
        store.placeMosaicTitleIfNeeded()
        _store = State(initialValue: store)
        _remoteSync = State(initialValue: ComposerRemoteSync(location: location))
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(MosaicTab.allCases) { tab in
                tabRoot(for: tab)
                    .tabItem {
                        tabLabel(for: tab)
                    }
                    .tag(tab)
            }
        }
        .tint(.white)
        .toolbarBackground(MosaicBrand.inkBlack, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .animation(.easeOut(duration: 0.28), value: chrome.isViewing)
        .onAppear {
            MosaicTabBarStyling.apply()
        }
        .task {
            guard let account else { return }
            store.onPersisted = { [weak store] in
                guard let store else { return }
                remoteSync.schedule(snapshot: store.snapshot, account: account, mediaFile: store.mediaURL(for:))
            }
            remoteSync.schedule(snapshot: store.snapshot, account: account, mediaFile: store.mediaURL(for:))
        }
        .task(id: downloadAttempt) {
            guard let account, let owner = account.session?.userID,
                  ComposerBackgroundRestore.needsWork(store: store) else { return }
            do {
                guard let config = SupabaseSyncConfig.current(), let token = await account.accessToken(),
                      account.session?.userID == owner else { throw SupabaseDocumentSyncError.requestFailed }
                try Task.checkCancellation()
                try await downloads.run(store: store, client: SupabaseDocumentSync(config: config),
                                        ownerID: owner, accessToken: token)
            } catch {
                guard !Task.isCancelled else { return }
                downloads.failure = "Some content couldn’t load. Your edits are saved on this device."
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !downloads.isLoading { downloadAttempt += 1 }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if downloads.isLoading || downloads.failure != nil || store.isRestoringDocuments {
                HStack(spacing: 10) {
                    if downloads.isLoading || downloads.failure == nil { ProgressView().tint(.white) }
                    Text(downloads.failure ?? (store.isRestoringDocuments ? "Loading Pursuits…" : "Downloading media · \(downloads.remainingMedia) left"))
                        .font(.caption)
                    Spacer(minLength: 0)
                    if downloads.failure != nil {
                        Button("Retry") { downloadAttempt += 1 }
                            .font(.caption.bold())
                            .disabled(downloads.isLoading)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(MosaicBrand.inkBlack)
                .accessibilityIdentifier("mosaic.downloadStatus")
            }
        }
        .environment(\.composerMediaVersions, store.mediaVersions)
        .environment(store)
        .environment(chrome)
        .environment(\.mosaicAccount, account)
        .environment(\.mosaicTabBarHidden, chrome.isViewing)
    }

    @ViewBuilder
    private func tabRoot(for tab: MosaicTab) -> some View {
        NavigationStack {
            Group {
                if tab == .mosaic {
                    MosaicComposerView(documentID: nil)
                } else if tab == .search {
                    MosaicDiscoverView()
                } else if tab == .circle {
                    MosaicCircleView()
                } else {
                    MosaicTabPlaceholder(tab: tab)
                }
            }
            .toolbar(chrome.isViewing ? .hidden : .visible, for: .tabBar)
        }
    }

    @ViewBuilder
    private func tabLabel(for tab: MosaicTab) -> some View {
        if tab == .mosaic {
            Label {
                Text(tab.title)
            } icon: {
                Image("MosaicMonogramTab")
                    .renderingMode(.template)
            }
        } else {
            Label(tab.title, systemImage: tab.systemImage)
        }
    }
}

@MainActor
private enum MosaicTabBarStyling {
    static func apply() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(
            red: 0.04,
            green: 0.04,
            blue: 0.04,
            alpha: 1
        )
        appearance.shadowColor = UIColor.black.withAlphaComponent(0.25)

        let selected = UIColor.white
        let normal = UIColor.white.withAlphaComponent(0.78)

        for layout in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ] {
            layout.normal.iconColor = normal
            layout.normal.titleTextAttributes = [.foregroundColor: normal]
            layout.selected.iconColor = selected
            layout.selected.titleTextAttributes = [.foregroundColor: selected]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().tintColor = selected
        UITabBar.appearance().unselectedItemTintColor = normal
    }
}

private struct MosaicTabPlaceholder: View {
    let tab: MosaicTab

    @Environment(\.mosaicTabBarHidden) private var tabBarHidden

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle(tab.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(tabBarHidden ? .hidden : .visible, for: .tabBar)
        .accessibilityIdentifier(tab.screenAccessibilityIdentifier)
        .accessibilityLabel(tab.title)
    }
}

enum MosaicBrand {
    static let cream = Color(red: 0.965, green: 0.949, blue: 0.902)
    static let inkBlack = Color(red: 0.04, green: 0.04, blue: 0.04)
}

#Preview("Mosaic") {
    MosaicTabShell(persistToDisk: false)
}

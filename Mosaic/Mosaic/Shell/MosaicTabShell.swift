import SwiftUI
import UIKit

enum MosaicTab: String, CaseIterable, Identifiable {
    case mosaic
    case circle
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mosaic: "Mosaic"
        case .circle: "Circle"
        case .search: "Discover"
        }
    }

    var systemImage: String {
        switch self {
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
            if isViewing, !oldValue { viewAs = .user }
        }
    }
    /// Each time the owner enters view mode it starts as a visitor would see the board.
    var viewAs: MosaicViewAs = .user

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
    @State private var downloads: ComposerBackgroundRestore
    @State private var downloadAttempt = 0
    @State private var remoteSync: ComposerRemoteSync
    @State private var pageBackgrounds: MosaicPageBackgrounds
    @State private var pursuitPrivacy = MosaicPursuitPrivacy()
    var account: MosaicAccount?
    /// Set by a `mosaic://@username` link; Discover opens that person's Mosaic and clears it.
    var linkedUsername: Binding<String?>

    init(
        account: MosaicAccount? = nil,
        linkedUsername: Binding<String?> = .constant(nil),
        persistToDisk: Bool = !ProcessInfo.processInfo.arguments.contains("UITestSkipLaunchAnimation")
    ) {
        self.account = account
        self.linkedUsername = linkedUsername
        let location: ComposerStorageLocation = account?.session.map { .account($0.userID) } ?? .shared()
        let store = ComposerStore(persistToDisk: persistToDisk, location: location)
        store.placeMosaicTitleIfNeeded()
        _store = State(initialValue: store)
        let downloads = ComposerBackgroundRestore()
        if account?.session != nil { downloads.noteExpectedFiles(store: store) }
        _downloads = State(initialValue: downloads)
        _remoteSync = State(initialValue: ComposerRemoteSync(location: location))
        _pageBackgrounds = State(initialValue: MosaicPageBackgrounds(location: location, persistToDisk: persistToDisk))
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
                remoteSync.schedule(
                    snapshot: store.snapshot,
                    account: account,
                    mediaFile: store.mediaURL(for:),
                    protectingDocumentIDs: store.syncProtectedDocumentUUIDs
                )
            }
            remoteSync.schedule(
                snapshot: store.snapshot,
                account: account,
                mediaFile: store.mediaURL(for:),
                protectingDocumentIDs: store.syncProtectedDocumentUUIDs
            )
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
                if !downloads.recoveredFiles.isEmpty {
                    remoteSync.schedule(
                        snapshot: store.snapshot,
                        account: account,
                        mediaFile: store.mediaURL(for:),
                        protectingDocumentIDs: store.syncProtectedDocumentUUIDs
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                downloads.failure = "Some content couldn’t load. Your edits are saved on this device."
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if !downloads.isLoading { downloadAttempt += 1 }
                // Keep retrying cloud upload for photos that exist on this phone but not for visitors.
                if let account, remoteSync.hasUnmappedLocalMedia(snapshot: store.snapshot, mediaFile: store.mediaURL(for:)) {
                    remoteSync.schedule(
                        snapshot: store.snapshot,
                        account: account,
                        mediaFile: store.mediaURL(for:),
                        protectingDocumentIDs: store.syncProtectedDocumentUUIDs
                    )
                } else if let account {
                    // A push that failed while offline goes out once the app is back.
                    remoteSync.resumeIfNeeded(account: account)
                }
            } else if phase == .background, let account {
                // An edit still in its short pause would otherwise wait until the next launch.
                remoteSync.flushNow(account: account)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if store.saveFailed {
                Text("Your latest changes couldn’t be saved on this phone. Free up storage — Mosaic keeps trying.")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.36, green: 0.18, blue: 0.18))
                    .accessibilityIdentifier("mosaic.saveStatus")
            } else if let failure = downloads.failure, !downloads.isLoading {
                HStack(spacing: 10) {
                    Text(failure)
                        .font(.caption)
                    Spacer(minLength: 0)
                    Button("Retry") { downloadAttempt += 1 }
                        .font(.caption.bold())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(MosaicBrand.inkBlack)
                .accessibilityIdentifier("mosaic.downloadStatus")
            }
        }
        .environment(\.composerMediaVersions, store.mediaVersions)
        .environment(\.composerMediaWaiting, mediaWaiting)
        .onChange(of: linkedUsername.wrappedValue, initial: true) { _, name in
            if name != nil { selection = .search }
        }
        .environment(store)
        .environment(chrome)
        .environment(remoteSync)
        .environment(pageBackgrounds)
        .environment(pursuitPrivacy)
        .environment(\.mosaicAccount, account)
        .environment(\.mosaicTabBarHidden, chrome.isViewing)
    }

    /// After downloads fail, nothing is coming until Retry, so missing media shows as unavailable.
    private var mediaWaiting: ComposerMediaWaiting {
        if downloads.failure != nil, !downloads.isLoading { return ComposerMediaWaiting() }
        return ComposerMediaWaiting(all: store.isRestoringDocuments, files: downloads.expectedFiles)
    }

    @ViewBuilder
    private func tabRoot(for tab: MosaicTab) -> some View {
        NavigationStack {
            Group {
                switch tab {
                case .mosaic:
                    MosaicComposerView(documentID: nil)
                case .search:
                    MosaicDiscoverView(linkedUsername: linkedUsername) { selection = .mosaic }
                case .circle:
                    MosaicCircleView()
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

enum MosaicBrand {
    static let cream = Color(red: 0.965, green: 0.949, blue: 0.902)
    static let inkBlack = Color(red: 0.04, green: 0.04, blue: 0.04)
}

#Preview("Mosaic") {
    MosaicTabShell(persistToDisk: false)
}

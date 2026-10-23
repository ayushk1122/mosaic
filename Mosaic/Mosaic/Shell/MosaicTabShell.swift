import SwiftUI
import UIKit

enum MosaicTab: String, CaseIterable, Identifiable {
    case mosaic
    case orbit
    case circle
    case explore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mosaic: "Mosaic"
        case .orbit: "Orbit"
        case .circle: "Circle"
        case .explore: "Explore"
        }
    }

    /// The app's own drawings, as template images that take the tab bar's colors.
    var assetImage: String? {
        switch self {
        case .mosaic: "MosaicMonogramTab"
        case .orbit: "OrbitTab"
        case .circle: "CircleTab"
        case .explore: nil
        }
    }

    var systemImage: String {
        switch self {
        case .explore: "sparkles"
        default: "circle"
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
    /// Bumped when a tab is tapped while it's already open: it goes back to where it starts.
    @State private var resets: [MosaicTab: Int] = [:]
    @State private var chrome = MosaicChrome()
    @State private var store: ComposerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var downloads: ComposerBackgroundRestore
    @State private var downloadAttempt = 0
    @State private var remoteSync: ComposerRemoteSync
    @State private var pageBackgrounds: MosaicPageBackgrounds
    @State private var pursuitPrivacy = MosaicPursuitPrivacy()
    /// Images of the owner's boards shared to Explore; only when signed in.
    @State private var explorePreviews: MosaicExplorePreviews?
    /// What people the owner follows added today, for Orbit; only when signed in.
    @State private var orbit: MosaicOrbitModel?
    var account: MosaicAccount?
    /// Set by a `mosaic://@username` link; Explore opens that person's Mosaic and clears it.
    var linked: Binding<MosaicLink.Target?>

    init(
        account: MosaicAccount? = nil,
        linked: Binding<MosaicLink.Target?> = .constant(nil),
        persistToDisk: Bool = !ProcessInfo.processInfo.arguments.contains("UITestSkipLaunchAnimation")
    ) {
        self.account = account
        self.linked = linked
        let location: ComposerStorageLocation = account?.session.map { .account($0.userID) } ?? .shared()
        let store = ComposerStore(persistToDisk: persistToDisk, location: location)
        store.placeMosaicTitleIfNeeded()
        _store = State(initialValue: store)
        let downloads = ComposerBackgroundRestore()
        if account?.session != nil { downloads.noteExpectedFiles(store: store) }
        _downloads = State(initialValue: downloads)
        _remoteSync = State(initialValue: ComposerRemoteSync(location: location))
        _pageBackgrounds = State(initialValue: MosaicPageBackgrounds(location: location, persistToDisk: persistToDisk))
        _explorePreviews = State(initialValue: account.map { MosaicExplorePreviews(store: store, account: $0) })
        _orbit = State(initialValue: account.map { MosaicOrbitModel(account: $0) })
    }

    var body: some View {
        TabView(selection: Binding(
            get: { selection },
            set: { tab in
                if tab == selection { resets[tab, default: 0] += 1 }
                selection = tab
            }
        )) {
            ForEach(MosaicTab.allCases) { tab in
                tabRoot(for: tab)
                    .tabItem {
                        tabLabel(for: tab)
                    }
                    .badge(tab == .orbit ? orbit?.unseenCount ?? 0 : 0)
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
            remoteSync.store = store
            // Captures only what it uses: holding the view (and through it the store) would keep
            // the old store alive after signing out.
            store.onPersisted = { [weak store, remoteSync, account] in
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
                  await ComposerBackgroundRestore.needsWork(store: store) else {
                // Nothing left to download (the missing piece may have been deleted): clear an old failure.
                downloads.failure = nil
                return
            }
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
        .task(id: scenePhase) {
            // Boards changed on another device: on open, on returning to the app, and every minute while open.
            guard let account, scenePhase == .active else { return }
            remoteSync.store = store
            // Shared boards edited since their Explore image was made get a new one.
            explorePreviews?.refreshStale()
            // The Orbit badge counts what's new since the app was last open.
            Task { await orbit?.refresh() }
            while !Task.isCancelled {
                remoteSync.pullNow(account: account)
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: remoteSync.pullCount) {
            // Pulled boards may show photos this phone doesn't have yet.
            if account?.session != nil { downloads.noteExpectedFiles(store: store) }
            if !downloads.isLoading { downloadAttempt += 1 }
        }
        .onChange(of: scenePhase) { _, phase in
            // What was just seen in Orbit reaches the server before the app is put away.
            if phase == .background { Task { await orbit?.sendSeen() } }
            if phase == .active {
                if !downloads.isLoading { downloadAttempt += 1 }
                if let account {
                    Task { @MainActor in
                        // Keep retrying cloud upload for photos that exist on this phone but not for visitors.
                        if await remoteSync.hasUnmappedLocalMedia(snapshot: store.snapshot, mediaFile: store.mediaURL(for:)) {
                            remoteSync.schedule(
                                snapshot: store.snapshot,
                                account: account,
                                mediaFile: store.mediaURL(for:),
                                protectingDocumentIDs: store.syncProtectedDocumentUUIDs
                            )
                        } else {
                            // A push that failed while offline goes out once the app is back.
                            remoteSync.resumeIfNeeded(account: account)
                        }
                    }
                }
            } else if phase == .inactive {
                // Swiping the app away from the switcher may never reach the background phase.
                store.flushPendingSave()
            } else if phase == .background {
                store.flushPendingSave()
                // An edit still in its short pause would otherwise wait until the next launch.
                if let account {
                    remoteSync.flushNow(account: account)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let board = remoteSync.oversizedBoards.first {
                Text("“\(board)” is too large to sync. Remove a drawing or photo from it to sync it again.")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.36, green: 0.28, blue: 0.12))
                    .accessibilityIdentifier("sync.tooLarge")
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
        .onChange(of: linked.wrappedValue, initial: true) { _, target in
            // A `mosaic://@username` link opens from Explore, where people are searched.
            if target != nil { selection = .explore }
        }
        .environment(store)
        .environment(chrome)
        .environment(remoteSync)
        .environment(pageBackgrounds)
        .environment(pursuitPrivacy)
        .environment(explorePreviews)
        .environment(orbit)
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
        if tab == .orbit {
            // Each of Orbit's pages has a navigation stack of its own: a board opened from one
            // stays on that page, under Orbit's header, and goes back to it.
            MosaicOrbitView(resetCount: resets[.orbit, default: 0]) { selection = .explore }
                .toolbar(chrome.isViewing ? .hidden : .visible, for: .tabBar)
        } else {
            stackedTabRoot(for: tab)
        }
    }

    private func stackedTabRoot(for tab: MosaicTab) -> some View {
        NavigationStack {
            Group {
                switch tab {
                case .mosaic:
                    MosaicComposerView(documentID: nil)
                case .orbit:
                    EmptyView()
                case .explore:
                    MosaicExploreView(linked: linked, resetCount: resets[.explore, default: 0]) { selection = .mosaic }
                case .circle:
                    MosaicCircleScreen()
                }
            }
            .toolbar(chrome.isViewing ? .hidden : .visible, for: .tabBar)
        }
        // Mosaic and Circle start over, closing whatever was opened; Explore keeps its feed and
        // closes what's open itself.
        .id(tab == .explore ? 0 : resets[tab, default: 0])
    }

    @ViewBuilder
    private func tabLabel(for tab: MosaicTab) -> some View {
        if let asset = tab.assetImage {
            Label {
                Text(tab.title)
            } icon: {
                Image(asset)
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

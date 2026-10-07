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
        case .search: "Search"
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

@MainActor
@Observable
final class MosaicChrome {
    var isViewing = false
}

struct MosaicTabShell: View {
    @State private var selection: MosaicTab = .mosaic
    @State private var chrome = MosaicChrome()
    @State private var store: ComposerStore

    init(persistToDisk: Bool = !ProcessInfo.processInfo.arguments.contains("UITestSkipLaunchAnimation")) {
        _store = State(initialValue: ComposerStore(persistToDisk: persistToDisk))
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
        .environment(store)
        .environment(chrome)
        .environment(\.mosaicTabBarHidden, chrome.isViewing)
    }

    @ViewBuilder
    private func tabRoot(for tab: MosaicTab) -> some View {
        NavigationStack {
            Group {
                if tab == .mosaic {
                    MosaicComposerView(documentID: nil)
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

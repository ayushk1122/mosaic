//
//  MosaicApp.swift
//  Mosaic
//
//  Created by Ayush Krishnappa on 9/28/26.
//

import SwiftUI

@main
struct MosaicApp: App {
    var body: some Scene {
        WindowGroup {
            MosaicRootView()
        }
    }
}

private struct MosaicRootView: View {
    private enum LaunchPhase {
        case animating
        case finished
    }

    @State private var launchPhase: LaunchPhase = ProcessInfo.processInfo.arguments.contains("UITestSkipLaunchAnimation")
        ? .finished
        : .animating
    @State private var account = MosaicAccount()
    @State private var restoredSession = false

    private var skipsAccount: Bool {
        ProcessInfo.processInfo.arguments.contains("UITestSkipLaunchAnimation")
            || SupabaseSyncConfig.current() == nil
    }

    var body: some View {
        Group {
            switch launchPhase {
            case .animating:
                MosaicLaunchAnimationView {
                    withAnimation(.easeOut(duration: 0.35)) {
                        launchPhase = .finished
                    }
                }
            case .finished:
                signedInShell
            }
        }
        .task {
            guard !skipsAccount else { return }
            await account.restore()
            restoredSession = true
        }
    }

    @ViewBuilder
    private var signedInShell: some View {
        if skipsAccount {
            ContentView()
        } else if !restoredSession {
            MosaicBrand.cream.ignoresSafeArea()
        } else if account.session == nil {
            MosaicSignInView(account: account)
        } else {
            ContentView(account: account)
        }
    }
}

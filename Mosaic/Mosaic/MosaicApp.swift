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
    @State private var preparedUserID: UUID?

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
        .onChange(of: account.session?.userID) { _, userID in
            if userID == nil {
                preparedUserID = nil
            }
        }
    }

    @ViewBuilder
    private var signedInShell: some View {
        if skipsAccount {
            ContentView()
        } else if !restoredSession {
            MosaicBrand.cream.ignoresSafeArea()
        } else if let userID = account.session?.userID {
            if preparedUserID == userID {
                ContentView(account: account)
                    .id(userID)
            } else {
                MosaicBrand.cream.ignoresSafeArea()
                    .task(id: userID) {
                        await ComposerLegacyStorage.prepare(for: account)
                        preparedUserID = userID
                    }
            }
        } else {
            MosaicSignInView(account: account)
        }
    }
}

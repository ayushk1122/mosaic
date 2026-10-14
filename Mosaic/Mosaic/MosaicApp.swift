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
                MosaicAccountPreparationView(account: account, userID: userID) {
                    preparedUserID = userID
                }
                .id(userID)
            }
        } else {
            MosaicSignInView(account: account)
        }
    }
}

/// Open the editor once the landing board is cached; children and media load in the shell.
private struct MosaicAccountPreparationView: View {
    var account: MosaicAccount
    var userID: UUID
    var onReady: () -> Void
    @State private var attempt = 0
    @State private var failure: String?

    var body: some View {
        ZStack {
            MosaicBrand.cream.ignoresSafeArea()
            VStack(spacing: 18) {
                if let failure {
                    Text("Couldn’t load your Mosaic")
                        .font(.title2.bold())
                    Text(failure)
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        self.failure = nil
                        attempt += 1
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Sign out") {
                        Task { await account.signOut() }
                    }
                } else {
                    ProgressView()
                    Text("Loading your Mosaic…")
                }
            }
            .padding(32)
            .foregroundStyle(MosaicBrand.inkBlack)
        }
        .task(id: attempt) {
            do {
                await ComposerLegacyStorage.prepare(for: account)
                try Task.checkCancellation()
                let location = ComposerStorageLocation.account(userID)
                if !ComposerAccountRestore.hasLocalAccount(at: location) {
                    guard let config = SupabaseSyncConfig.current(),
                          let token = await account.accessToken(), account.session?.userID == userID
                    else { throw SupabaseDocumentSyncError.requestFailed }
                    try await ComposerAccountRestore(client: SupabaseDocumentSync(config: config))
                        .prepare(ownerID: userID, accessToken: token, location: location)
                }
                try Task.checkCancellation()
                guard account.session?.userID == userID else { return }
                onReady()
            } catch {
                guard !Task.isCancelled, account.session?.userID == userID else { return }
                failure = (error as? ComposerRestoreError)?.errorDescription
                    ?? "Check your connection and try again. Your saved Mosaic hasn’t been changed."
            }
        }
    }
}

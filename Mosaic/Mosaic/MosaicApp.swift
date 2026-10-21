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
    /// Profile setup finished; account preparation can run next.
    @State private var onboardingPassedUserID: UUID?
    /// Kept through sign-in, so a link tapped before the shell exists still opens.
    @State private var linkedUsername: String?

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
        .onOpenURL { url in
            if let name = MosaicLink.username(from: url) {
                linkedUsername = name
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
                onboardingPassedUserID = nil
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
                ContentView(account: account, linkedUsername: $linkedUsername)
                    .id(userID)
            } else if onboardingPassedUserID == userID {
                MosaicAccountPreparationView(account: account, userID: userID) {
                    preparedUserID = userID
                }
                .id(userID)
            } else {
                MosaicOnboardingGateView(account: account, userID: userID) {
                    onboardingPassedUserID = userID
                }
                .id(userID)
            }
        } else {
            MosaicSignInView(account: account)
        }
    }
}

/// Resolves onboarding before the first Mosaic download on this device.
private struct MosaicOnboardingGateView: View {
    var account: MosaicAccount
    var userID: UUID
    var onReady: () -> Void

    @State private var route = MosaicOnboardingRoute.loading
    @State private var status: MosaicOnboardingStatus?
    @State private var attempt = 0

    var body: some View {
        Group {
            switch route {
            case .loading:
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(MosaicBrand.inkBlack)
                    Text("Loading your account…")
                        .foregroundStyle(MosaicBrand.inkBlack)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MosaicBrand.cream.ignoresSafeArea())
                .environment(\.colorScheme, .light)
            case .retry:
                VStack(spacing: 16) {
                    Text("Couldn’t reach Mosaic")
                        .font(.title3.bold())
                        .foregroundStyle(MosaicBrand.inkBlack)
                    Text("Check your connection to finish setting up this account.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(MosaicBrand.inkBlack.opacity(0.72))
                    Button("Try again") { attempt += 1 }
                        .buttonStyle(.borderedProminent)
                        .tint(MosaicBrand.inkBlack)
                    Button("Sign out") {
                        Task { await account.signOut() }
                    }
                    .foregroundStyle(MosaicBrand.inkBlack.opacity(0.55))
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MosaicBrand.cream.ignoresSafeArea())
                .environment(\.colorScheme, .light)
            case .needsSetup:
                MosaicOnboardingView(account: account, userID: userID, existing: status) {
                    MosaicOnboardingCache.markComplete(userID)
                    route = .readyForPreparation
                }
            case .readyForPreparation:
                Color.clear
                    .onAppear { onReady() }
            }
        }
        .task(id: attempt) {
            await resolveRoute()
        }
    }

    private func resolveRoute() async {
        route = .loading
        let location = ComposerStorageLocation.account(userID)
        let hasLocalAccount = ComposerAccountRestore.hasLocalAccount(at: location)
        let cachedComplete = MosaicOnboardingCache.isComplete(userID)
        if cachedComplete {
            route = .readyForPreparation
            return
        }
        guard let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken(),
              account.session?.userID == userID
        else {
            route = MosaicOnboardingRouter.route(
                cachedComplete: false,
                hasLocalAccount: hasLocalAccount,
                status: nil
            )
            return
        }
        let status = await Self.onboardingStatus(config: config, token: token)
        guard account.session?.userID == userID else { return }
        self.status = status
        if status?.isOnboarded == true {
            MosaicOnboardingCache.markComplete(userID)
        }
        let next = MosaicOnboardingRouter.route(
            cachedComplete: cachedComplete,
            hasLocalAccount: hasLocalAccount,
            status: status
        )
        route = next
    }

    /// Asks up to three times before showing "Couldn't reach Mosaic": right after signing in, a
    /// brief connection drop otherwise sent people to Try again for no visible reason.
    private static func onboardingStatus(config: SupabaseSyncConfig, token: String) async -> MosaicOnboardingStatus? {
        let client = MosaicOnboardingClient(config: config)
        for delay in [0, 600, 1500] {
            if delay > 0 {
                try? await Task.sleep(for: .milliseconds(delay))
            }
            guard !Task.isCancelled else { return nil }
            do {
                return try await client.status(accessToken: token)
            } catch {
                continue
            }
        }
        return nil
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

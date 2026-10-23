import SwiftUI
import UIKit

/// The signed-in person's profile picture. Tapping it copies their `mosaic://@username` link.
struct MosaicOwnProfileButton: View {
    var size: CGFloat
    /// Changing this reloads the profile, so a new picture or username shows after Settings.
    var refresh = 0

    @Environment(\.mosaicAccount) private var account
    @State private var username = ""
    @State private var displayName = ""
    @State private var avatarPath: String?
    @State private var copied = false
    @State private var copies = 0

    private var link: URL? { MosaicLink.url(username: username) }

    var body: some View {
        Button(action: copy) {
            MosaicAvatarView(path: avatarPath, name: displayName.isEmpty ? username : displayName, size: size)
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if copied {
                Text("Mosaic link copied!")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(MosaicBrand.inkBlack, in: Capsule())
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                    .fixedSize()
                    .offset(y: -40)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .allowsHitTesting(false)
            }
        }
        .disabled(link == nil)
        .accessibilityLabel(copied ? "Mosaic link copied" : "Copy Mosaic link")
        .accessibilityIdentifier("composer.copyMosaicLink")
        .task(id: refresh) { await load() }
    }

    private func copy() {
        guard let link else { return }
        UIPasteboard.general.string = link.absoluteString
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        copies += 1
        let copy = copies
        withAnimation(.easeOut(duration: 0.18)) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard copy == copies else { return }
            withAnimation(.easeOut(duration: 0.18)) { copied = false }
        }
    }

    private func load() async {
        guard let account,
              let userID = account.session?.userID,
              let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken(),
              let profile = try? await MosaicSettingsClient(config: config).loadProfile(userID: userID, accessToken: token),
              !Task.isCancelled
        else { return }
        username = profile.username
        displayName = MosaicSettingsList.displayName(from: profile.displayName)
        avatarPath = profile.avatarPath
    }
}

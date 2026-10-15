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

/// Someone else's profile picture shown large, still round, with a button on its lower right
/// that copies their `mosaic://@username` link. Tapping outside closes it.
struct MosaicAvatarPreview: View {
    var path: String?
    var name: String
    var username: String
    var onClose: () -> Void

    @State private var copied = false
    @State private var copies = 0

    private static let copySide: CGFloat = 52

    private var link: URL? { MosaicLink.url(username: username) }

    var body: some View {
        GeometryReader { proxy in
            let side = max(min(proxy.size.width - 64, 320), 120)
            ZStack {
                Color.black.opacity(0.78)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)
                VStack(spacing: 16) {
                    MosaicAvatarView(path: path, name: name, size: side)
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                        .overlay(alignment: .bottomTrailing) {
                            copyButton
                                .offset(x: copyInset(side), y: copyInset(side))
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("@\(username)’s profile picture")
                    VStack(spacing: 2) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Text("Mosaic link copied!")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .opacity(copied ? 1 : 0)
                        .accessibilityHidden(!copied)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }

    /// Centers the button on the circle's edge at its lower right, 45° down from the side.
    private func copyInset(_ side: CGFloat) -> CGFloat {
        let edge = side / 2 * (1 + 1 / 2.squareRoot())
        return edge - (side - Self.copySide / 2)
    }

    private var copyButton: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "square.on.square")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(MosaicBrand.inkBlack)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.copySide, height: Self.copySide)
                .background(.white, in: Circle())
                .overlay(Circle().stroke(MosaicBrand.inkBlack, lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(link == nil)
        .accessibilityLabel(copied ? "Mosaic link copied" : "Copy @\(username)’s Mosaic link")
        .accessibilityIdentifier("visit.copyMosaicLink")
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
}

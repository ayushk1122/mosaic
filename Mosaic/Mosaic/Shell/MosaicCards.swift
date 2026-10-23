import SwiftUI
import UIKit

/// What a Mosaic or Pursuit circle's corner badge says.
enum MosaicFollowStatus: Equatable {
    case follow
    case following
    case locked
    /// Locked, with a request waiting on the owner.
    case pending

    init(_ pursuit: MosaicVisitPursuit) {
        if pursuit.isOpen {
            self = pursuit.following ? .following : .follow
        } else {
            self = pursuit.isRequested ? .pending : .locked
        }
    }

    var spoken: String {
        switch self {
        case .follow: "Not following"
        case .following: "Following"
        case .locked: "Private"
        case .pending: "Private, request pending"
        }
    }
}

/// The corner of a Mosaic or Pursuit circle: whether the visitor follows it, or that it's locked.
/// Tapping the circle opens its card, where that changes.
struct MosaicFollowBadge: View {
    var status: MosaicFollowStatus
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .black))
            .foregroundStyle(status == .following ? .white : MosaicBrand.inkBlack)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .background(background, in: Circle())
            .overlay(Circle().stroke(status == .following ? Color.white : MosaicBrand.inkBlack, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch status {
        case .follow: "plus"
        case .following: "checkmark"
        case .locked, .pending: "lock.fill"
        }
    }

    private var background: Color {
        switch status {
        case .follow, .locked: .white
        case .following: MosaicBrand.inkBlack
        case .pending: MosaicVisitLockBadge.pendingColor
        }
    }
}

enum MosaicCardText {
    static func followers(_ count: Int?) -> String? {
        guard let count else { return nil }
        return count == 1 ? "1 follower" : "\(count) followers"
    }
}

/// A wide button on a card.
struct MosaicCardPill: View {
    var title: String
    var systemImage: String?
    var filled = false
    var loading = false

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(.white)
            } else if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(filled ? MosaicBrand.inkBlack : .white)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(filled ? Color.white : Color.white.opacity(0.14), in: Capsule())
        .contentShape(Capsule())
        .accessibilityLabel(title)
    }
}

private let mosaicCardCopySide: CGFloat = 52

/// What every card looks like: a large round picture with a button on its lower right that copies
/// a link, a title and a line under it, a follower count, and a row of buttons. Tapping outside
/// closes it.
struct MosaicCardLayout<Picture: View, Subtitle: View, Actions: View>: View {
    var title: String
    var link: URL?
    /// "Mosaic" or "Pursuit", for the copy button.
    var linkKind: String
    var followerText: String?
    var problem: String?
    var onClose: () -> Void
    @ViewBuilder var picture: (CGFloat) -> Picture
    @ViewBuilder var subtitle: () -> Subtitle
    @ViewBuilder var actions: () -> Actions

    @State private var copied = false
    @State private var copies = 0

    var body: some View {
        GeometryReader { proxy in
            let side = max(min(proxy.size.width - 96, 260), 120)
            ZStack {
                Color.black.opacity(0.78)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)
                VStack(spacing: 16) {
                    picture(side)
                        .frame(width: side, height: side)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                        .overlay(alignment: .bottomTrailing) {
                            copyButton
                                .offset(x: copyInset(side), y: copyInset(side))
                        }
                        .accessibilityElement(children: .contain)
                    VStack(spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        subtitle()
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                        // Kept in place while loading, so the buttons don't jump.
                        Text(followerText ?? " ")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.top, 4)
                            .accessibilityHidden(followerText == nil)
                    }
                    .padding(.horizontal, 32)
                    HStack(spacing: 10) {
                        actions()
                    }
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 32)
                    Text(problem ?? "\(linkKind) link copied!")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .padding(.horizontal, 32)
                        .opacity(copied || problem != nil ? 1 : 0)
                        .accessibilityHidden(!copied && problem == nil)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }

    /// Centers the button on the circle's edge at its lower right, 45° down from the side.
    private func copyInset(_ side: CGFloat) -> CGFloat {
        let edge = side / 2 * (1 + 1 / 2.squareRoot())
        return edge - (side - mosaicCardCopySide / 2)
    }

    private var copyButton: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "square.on.square")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(MosaicBrand.inkBlack)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: mosaicCardCopySide, height: mosaicCardCopySide)
                .background(.white, in: Circle())
                .overlay(Circle().stroke(MosaicBrand.inkBlack, lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(link == nil)
        .accessibilityLabel(copied ? "\(linkKind) link copied" : "Copy \(title)’s \(linkKind) link")
        .accessibilityIdentifier("card.copyLink")
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

// MARK: Mosaic

/// Someone else's profile card: their picture, name, and follower count, with buttons to follow
/// their Mosaic (or ask to see a private one) and, where given, to visit it.
struct MosaicProfileCard: View {
    var person: MosaicPersonResult
    /// What's already known, shown while the card loads the latest.
    var profile: MosaicVisitProfile?
    /// Nil where the visitor is already on this Mosaic.
    var onVisit: (() -> Void)?
    /// After a follow, unfollow, or request here, so the screen behind can catch up.
    var onProfileChange: (MosaicVisitProfile) -> Void = { _ in }
    var onClose: () -> Void

    @Environment(\.mosaicAccount) private var account
    @State private var loaded: MosaicVisitProfile?
    @State private var loading = true
    @State private var busy = false
    @State private var problem: String?

    private var current: MosaicVisitProfile? { loaded ?? profile }
    private var username: String { current?.username ?? person.username }
    private var name: String {
        if let current { return current.name }
        return person.displayName.isEmpty ? person.username : person.displayName
    }

    var body: some View {
        MosaicCardLayout(
            title: name,
            link: MosaicLink.url(username: username),
            linkKind: "Mosaic",
            followerText: MosaicCardText.followers(current?.followerCount),
            problem: problem,
            onClose: onClose
        ) { side in
            MosaicAvatarView(path: current?.avatarPath ?? person.avatarPath, name: name, size: side)
                .accessibilityLabel("@\(username)’s profile picture")
        } subtitle: {
            Text("@\(username)")
        } actions: {
            if let current, current.mosaicID != nil {
                if current.canView {
                    followButton(current)
                } else {
                    requestButton(current)
                }
            } else if loading {
                MosaicCardPill(title: "Loading", loading: true)
            }
            if let onVisit, current?.mosaicID != nil || loading {
                Button(action: onVisit) {
                    MosaicCardPill(title: "Visit Mosaic", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profileCard.visit")
            }
        }
        .disabled(busy)
        .accessibilityIdentifier("profileCard")
        .task { await load() }
    }

    @ViewBuilder
    private func followButton(_ current: MosaicVisitProfile) -> some View {
        if current.followsMosaic {
            Menu {
                Button(role: .destructive) {
                    Task { await setFollowing(false) }
                } label: {
                    Label("Unfollow", systemImage: "person.badge.minus")
                    Text("Also unfollows their Pursuits")
                }
            } label: {
                MosaicCardPill(title: "Following", systemImage: "checkmark")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityIdentifier("profileCard.follow")
        } else {
            Button {
                Task { await setFollowing(true) }
            } label: {
                MosaicCardPill(title: "Follow", systemImage: "person.fill.badge.plus", filled: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profileCard.follow")
        }
    }

    private func requestButton(_ current: MosaicVisitProfile) -> some View {
        Button {
            Task { await request() }
        } label: {
            MosaicCardPill(
                title: current.isRequested ? "Requested" : "Request to view",
                systemImage: "lock.fill",
                filled: !current.isRequested
            )
        }
        .buttonStyle(.plain)
        .disabled(current.isRequested)
        .accessibilityIdentifier("profileCard.request")
    }

    private func connection() async -> (client: MosaicVisitClient, token: String)? {
        guard let account, let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken()
        else { return nil }
        return (MosaicVisitClient(config: config), token)
    }

    private func load() async {
        defer { loading = false }
        guard let link = await connection(),
              let found = try? await link.client.profile(userID: person.id, accessToken: link.token),
              !Task.isCancelled
        else { return }
        loaded = found
    }

    private func setFollowing(_ follow: Bool) async {
        guard var updated = current, let link = await connection() else { return }
        busy = true
        defer { busy = false }
        do {
            if follow {
                try await link.client.followMosaic(ownerID: person.id, accessToken: link.token)
            } else {
                try await link.client.unfollowMosaic(ownerID: person.id, accessToken: link.token)
            }
            updated.followsMosaic = follow
            updated.followerCount = updated.followerCount.map { max($0 + (follow ? 1 : -1), 0) }
            loaded = updated
            problem = nil
            onProfileChange(updated)
        } catch {
            problem = follow ? "This Mosaic could not be followed." : "This Mosaic could not be unfollowed."
        }
    }

    private func request() async {
        guard var updated = current, let link = await connection() else { return }
        busy = true
        defer { busy = false }
        guard let status = try? await link.client.requestMosaic(ownerID: person.id, accessToken: link.token) else {
            problem = "The request could not be sent."
            return
        }
        updated.requestStatus = status
        loaded = updated
        problem = nil
        if status == "accepted" { await load() }
        onProfileChange(loaded ?? updated)
    }
}

// MARK: Pursuit

/// A Pursuit's card on someone else's Mosaic: its cover, name, owner, and follower count, with
/// buttons to follow or unfollow it, or ask to see it when it's private.
struct MosaicPursuitCard: View {
    let pursuitID: UUID
    /// The bubble's small copy, shown until the sharp one has loaded.
    var cover: UIImage?
    var coverURL: URL?
    var owner: MosaicPersonResult?
    /// Tapping "by @owner" switches to the owner's card.
    var onShowOwner: () -> Void
    var onClose: () -> Void

    @Environment(MosaicVisit.self) private var visit
    @Environment(\.displayScale) private var displayScale
    @State private var sharpCover: UIImage?

    /// Big enough for the card's largest circle on this screen.
    private var sharpPixelSize: Int { Int((260 * displayScale).rounded(.up)) }

    var body: some View {
        let pursuit = visit.pursuits[pursuitID]
        let title = pursuit?.displayTitle ?? "Pursuit"
        MosaicCardLayout(
            title: title,
            link: owner.flatMap { MosaicLink.url(username: $0.username, pursuitID: pursuitID) },
            linkKind: "Pursuit",
            followerText: MosaicCardText.followers(pursuit?.followerCount),
            problem: visit.problem,
            onClose: close
        ) { side in
            ZStack {
                MosaicBrand.inkBlack
                if let cover {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                }
                if let sharpCover {
                    Image(uiImage: sharpCover)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
                if cover == nil, sharpCover == nil {
                    Text(String(title.prefix(1)).uppercased())
                        .font(.system(size: side * 0.4, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityLabel("\(title)’s cover")
        } subtitle: {
            if let owner {
                Button(action: onShowOwner) {
                    HStack(spacing: 3) {
                        Text("by @\(owner.username)")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("by @\(owner.username)")
                .accessibilityHint("Shows their profile")
                .accessibilityIdentifier("pursuitCard.owner")
            }
        } actions: {
            if let pursuit {
                if pursuit.isOpen {
                    followButton(pursuit)
                } else {
                    Button {
                        Task { await visit.request(pursuitID) }
                    } label: {
                        MosaicCardPill(
                            title: pursuit.isRequested ? "Requested" : "Request to view",
                            systemImage: "lock.fill",
                            filled: !pursuit.isRequested
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(pursuit.isRequested)
                    .accessibilityIdentifier("pursuitCard.request")
                }
            }
        }
        .disabled(visit.busy.contains(pursuitID))
        .accessibilityIdentifier("pursuitCard")
        .task(id: coverURL) { await loadSharpCover() }
    }

    private func loadSharpCover() async {
        guard let coverURL else { return }
        let pixelSize = sharpPixelSize
        let image = await Task.detached(priority: .userInitiated) {
            MosaicThumbnail.image(at: coverURL, maxPixelSize: pixelSize)
        }.value
        guard !Task.isCancelled, let image else { return }
        withAnimation(.easeOut(duration: 0.25)) { sharpCover = image }
    }

    @ViewBuilder
    private func followButton(_ pursuit: MosaicVisitPursuit) -> some View {
        if pursuit.following {
            Menu {
                if pursuit.level != .public {
                    Text("This Pursuit is private. You’ll need to request access again.")
                }
                Button("Unfollow", systemImage: "minus.circle", role: .destructive) {
                    Task { await visit.unfollow(pursuitID) }
                }
            } label: {
                MosaicCardPill(title: "Following", systemImage: "checkmark")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityIdentifier("pursuitCard.follow")
        } else {
            Button {
                Task { await visit.follow(pursuitID) }
            } label: {
                MosaicCardPill(title: "Follow", systemImage: "plus", filled: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pursuitCard.follow")
        }
    }

    /// The card shows the visit's problems itself; closing it clears them so no alert follows.
    private func close() {
        visit.problem = nil
        onClose()
    }
}

// MARK: Presenting

/// Presents and dismisses card covers without the full-screen cover's slide.
enum MosaicCardPresentation {
    static func withoutSlide(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}

/// Shows a card over everything, the tab bar included, fading in rather than sliding up. Set the
/// binding inside `MosaicCardPresentation.withoutSlide` so the cover itself doesn't slide.
struct MosaicCardCover<Card: View>: ViewModifier {
    @Binding var isPresented: Bool
    let card: (_ close: @escaping () -> Void) -> Card

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            MosaicCardFade(isPresented: $isPresented, card: card)
                .presentationBackground(.clear)
        }
    }
}

private struct MosaicCardFade<Card: View>: View {
    @Binding var isPresented: Bool
    let card: (_ close: @escaping () -> Void) -> Card

    @State private var shown = false

    var body: some View {
        card(close)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.2)) { shown = true }
            }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            MosaicCardPresentation.withoutSlide { isPresented = false }
        }
    }
}

extension View {
    func mosaicCardCover<Card: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder card: @escaping (_ close: @escaping () -> Void) -> Card
    ) -> some View {
        modifier(MosaicCardCover(isPresented: isPresented, card: card))
    }
}

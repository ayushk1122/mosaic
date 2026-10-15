import SwiftUI

/// Whose eyes view mode shows the owner's own Mosaic through.
enum MosaicViewAs: Sendable {
    /// Everything the owner built.
    case me
    /// What someone visiting the Mosaic sees.
    case user
}

/// The server's privacy level for each of the signed-in person's Pursuits.
@MainActor
@Observable
final class MosaicPursuitPrivacy {
    private(set) var levels: [UUID: MosaicVisibilityLevel] = [:]
    private(set) var isLoaded = false

    func refresh(account: MosaicAccount) async {
        guard let config = SupabaseSyncConfig.current(),
              let userID = account.session?.userID,
              let token = await account.accessToken(),
              let boards = try? await MosaicSettingsClient(config: config).loadBoards(userID: userID, accessToken: token),
              account.session?.userID == userID
        else { return }
        levels = Self.levels(from: boards)
        isLoaded = true
    }

    func set(_ level: MosaicVisibilityLevel, for id: UUID) {
        levels[id] = level
    }

    nonisolated static func levels(from boards: [MosaicRemoteBoard]) -> [UUID: MosaicVisibilityLevel] {
        var levels: [UUID: MosaicVisibilityLevel] = [:]
        for board in boards where board.role == "pursuit" {
            levels[board.id] = board.level
        }
        return levels
    }
}

/// How Pursuit widgets on the owner's board show their privacy.
struct MosaicPrivacyDisplay: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case off
        /// Edit mode: a badge on every Pursuit visitors can't freely open.
        case badges
        /// View as User: the board as a visitor with no approvals sees it.
        case visitor
    }

    enum Look: Equatable, Sendable {
        case shown
        case locked
        case removed
    }

    var mode: Mode = .off
    var levels: [UUID: MosaicVisibilityLevel] = [:]

    /// A Pursuit the server has no row for yet is withheld from visitors, the same as a hidden one.
    func level(of block: ComposerBlock) -> MosaicVisibilityLevel? {
        guard block.kind == .pursuit, let id = block.pursuitID.flatMap(ComposerBoardSync.uuid) else { return nil }
        return levels[id] ?? .hidden
    }

    /// Matches `viewer_pursuit_block` for a visitor with no approved requests.
    func look(of block: ComposerBlock) -> Look {
        guard mode == .visitor, let level = level(of: block) else { return .shown }
        switch level {
        case .public: return .shown
        case .private: return .locked
        case .hidden: return .removed
        }
    }

    func badge(for block: ComposerBlock) -> MosaicVisibilityLevel? {
        guard mode == .badges, let level = level(of: block), level != .public else { return nil }
        return level
    }
}

private struct MosaicPrivacyDisplayKey: EnvironmentKey {
    static let defaultValue = MosaicPrivacyDisplay()
}

extension EnvironmentValues {
    var mosaicPrivacyDisplay: MosaicPrivacyDisplay {
        get { self[MosaicPrivacyDisplayKey.self] }
        set { self[MosaicPrivacyDisplayKey.self] = newValue }
    }
}

/// Edit-mode marker on a hidden or private Pursuit widget.
struct MosaicPrivacyBadge: View {
    var level: MosaicVisibilityLevel

    var body: some View {
        Image(systemName: level == .hidden ? "eye.slash.fill" : "lock.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(MosaicBrand.inkBlack)
            .frame(width: 24, height: 24)
            .background(.white, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .accessibilityLabel(level == .hidden ? "Hidden from visitors" : "Private")
    }
}

/// Sits between the profile button and the edit button in view mode.
struct MosaicViewAsToggle: View {
    @Binding var viewAs: MosaicViewAs
    var isChecking: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(isChecking && viewAs == .user ? "Checking…" : "View as")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            HStack(spacing: 2) {
                segment("Me", value: .me)
                segment("User", value: .user)
            }
            .padding(4)
            .frame(height: ComposerAddMenuMetrics.button)
            .background(MosaicBrand.inkBlack, in: Capsule())
            .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View as")
        .accessibilityIdentifier("mosaic.viewAs")
    }

    private func segment(_ title: String, value: MosaicViewAs) -> some View {
        let selected = viewAs == value
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { viewAs = value }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? MosaicBrand.inkBlack : .white)
                .padding(.horizontal, 14)
                .frame(height: ComposerAddMenuMetrics.button - 8)
                .background(selected ? Color.white : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("mosaic.viewAs.\(title.lowercased())")
    }
}

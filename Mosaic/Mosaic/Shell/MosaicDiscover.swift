import SwiftUI
import UIKit

/// One Mosaic or Pursuit the signed-in person follows.
struct MosaicFollowedItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case mosaic
        case pursuit
    }

    var kind: Kind
    var targetID: UUID
    var owner: MosaicPersonResult
    var title: String
    var coverFile: String?
    var coverAsset: String?

    var id: String { "\(kind.rawValue).\(targetID.uuidString)" }
    var ownerName: String { owner.displayName.isEmpty ? owner.username : owner.displayName }
    var displayTitle: String { title.isEmpty ? "Pursuit" : title }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [owner.username, owner.displayName, kind == .pursuit ? title : ""]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

struct MosaicFollowingClient: Sendable {
    var config: SupabaseSyncConfig
    var session: URLSession = .shared

    func following(accessToken: String) async throws -> [MosaicFollowedItem] {
        try Self.items(from: await rpc("my_follows", body: [:], accessToken: accessToken))
    }

    /// Unfollowing a Mosaic also unfollows every Pursuit of that owner.
    func unfollow(_ item: MosaicFollowedItem, accessToken: String) async throws {
        switch item.kind {
        case .mosaic:
            _ = try await rpc(
                "unfollow_mosaic",
                body: ["p_owner": item.owner.id.uuidString.lowercased()],
                accessToken: accessToken
            )
        case .pursuit:
            _ = try await rpc(
                "unfollow",
                body: ["p_target_type": item.kind.rawValue, "p_target_id": item.targetID.uuidString.lowercased()],
                accessToken: accessToken
            )
        }
    }

    /// What is left of the list after unfollowing one item.
    static func remaining(_ items: [MosaicFollowedItem], after item: MosaicFollowedItem) -> [MosaicFollowedItem] {
        items.filter { other in
            item.kind == .mosaic ? other.owner.id != item.owner.id : other.id != item.id
        }
    }

    static func items(from data: Data) throws -> [MosaicFollowedItem] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        return rows.compactMap { row in
            guard let kind = (row["target_type"] as? String).flatMap(MosaicFollowedItem.Kind.init(rawValue:)),
                  let targetID = (row["target_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let ownerID = (row["owner_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let username = row["username"] as? String
            else { return nil }
            return MosaicFollowedItem(
                kind: kind,
                targetID: targetID,
                owner: MosaicPersonResult(
                    id: ownerID,
                    username: username,
                    displayName: (row["display_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    avatarPath: row["avatar_path"] as? String
                ),
                title: (row["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                coverFile: row["cover_file"] as? String,
                coverAsset: row["cover_asset"] as? String
            )
        }
    }

    private func rpc(_ name: String, body: [String: Any], accessToken: String) async throws -> Data {
        let endpoint = config.url
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("rpc")
            .appendingPathComponent(name)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SupabaseDocumentSyncError.requestFailed
        }
        return data
    }
}

/// A followed Pursuit's cover photo in a circle, or its first letter.
struct MosaicPursuitCoverView: View {
    var item: MosaicFollowedItem
    var size: CGFloat

    @Environment(\.mosaicAccount) private var account
    @State private var image: UIImage?

    private var paths: [String] {
        guard let asset = item.coverAsset, let file = item.coverFile else { return [] }
        let isVideo = ["mov", "mp4", "m4v"].contains((file as NSString).pathExtension.lowercased())
        guard !isVideo else { return [] }
        let base = "\(item.owner.id.uuidString.lowercased())/\(asset.lowercased())"
        return ["\(base)/thumb", "\(base)/display"]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.1))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(item.displayTitle.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: paths) { await load() }
    }

    private func load() async {
        guard let first = paths.first else {
            image = nil
            return
        }
        // Decoded at the circle's size, so each size is cached on its own.
        let pixels = Int(size * 3)
        let key = "media/\(first)@\(pixels)"
        if let cached = MosaicAvatarCache.image(for: key) {
            image = cached
            return
        }
        guard let account,
              let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken()
        else { return }
        let client = MosaicVisitClient(config: config)
        // Decoded off the main thread, rather than at full size on it when first drawn.
        for path in paths {
            if let data = await client.download(path: path, accessToken: token),
               let loaded = await Task.detached(priority: .userInitiated, operation: {
                   MosaicThumbnail.image(data: data, maxPixelSize: pixels)
               }).value {
                guard !Task.isCancelled else { return }
                MosaicAvatarCache.store(loaded, for: key)
                image = loaded
                return
            }
        }
    }
}

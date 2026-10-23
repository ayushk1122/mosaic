import SwiftUI
import UIKit

struct MosaicPersonResult: Identifiable, Hashable, Sendable {
    var id: UUID
    var username: String
    var displayName: String
    var avatarPath: String? = nil
}

/// Profile pictures already downloaded this session, keyed by Storage path.
@MainActor
enum MosaicAvatarCache {
    private static let images = NSCache<NSString, UIImage>()

    static func image(for path: String) -> UIImage? {
        images.object(forKey: path as NSString)
    }

    static func store(_ image: UIImage, for path: String) {
        images.setObject(image, forKey: path as NSString)
    }
}

/// A round profile picture, or the first letter of the name until one loads.
struct MosaicAvatarView: View {
    var path: String?
    var name: String
    var size: CGFloat

    @Environment(\.mosaicAccount) private var account
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.14))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: path) { await load() }
    }

    private func load() async {
        guard let path else {
            image = nil
            return
        }
        if let cached = MosaicAvatarCache.image(for: path) {
            image = cached
            return
        }
        image = nil
        guard let account,
              let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken(),
              let data = try? await MosaicSettingsClient(config: config).loadAvatar(path: path, accessToken: token),
              let loaded = UIImage(data: data),
              !Task.isCancelled
        else { return }
        MosaicAvatarCache.store(loaded, for: path)
        image = loaded
    }
}

struct MosaicSearchClient: Sendable {
    var config: SupabaseSyncConfig
    var session: URLSession = .shared

    /// People whose username or display name matches the query, at most 20, through `search_profiles`.
    func people(matching query: String, accessToken: String) async throws -> [MosaicPersonResult] {
        let endpoint = config.url
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("rpc")
            .appendingPathComponent("search_profiles")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["p_query": query])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SupabaseDocumentSyncError.requestFailed
        }
        return try Self.results(from: data)
    }

    static func results(from data: Data) throws -> [MosaicPersonResult] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        return rows.compactMap { row in
            guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let username = row["username"] as? String
            else { return nil }
            let displayName = (row["display_name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return MosaicPersonResult(
                id: id,
                username: username,
                displayName: displayName,
                avatarPath: row["avatar_path"] as? String
            )
        }
    }
}

/// One person in search results: their picture, name, and username. Tapping opens their Mosaic,
/// except for the signed-in person, who is marked "You".
struct MosaicPersonRow: View {
    var person: MosaicPersonResult
    var isSelf: Bool
    var onOpen: () -> Void

    private let muted = Color.white.opacity(0.55)

    var body: some View {
        let name = person.displayName.isEmpty ? person.username : person.displayName
        HStack(spacing: 12) {
            MosaicAvatarView(path: person.avatarPath, name: name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("@\(person.username)")
                    .font(.subheadline)
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isSelf {
                Text("You")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(muted)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isSelf else { return }
            onOpen()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelf ? [] : .isButton)
        .accessibilityIdentifier("search.result.\(person.username)")
    }
}

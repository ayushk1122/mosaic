import Foundation

/// `mosaic://@username`, which opens that person's Mosaic in the app.
enum MosaicLink {
    private static let prefix = "mosaic://@"

    static func url(username: String) -> URL? {
        let name = MosaicSettingsList.username(from: username)
        guard MosaicSettingsList.usernameProblems(name).isEmpty else { return nil }
        return URL(string: prefix + name)
    }

    /// The username in a Mosaic link. Sign-in callbacks and anything else on the scheme return nil.
    static func username(from url: URL) -> String? {
        let raw = url.absoluteString
        guard raw.lowercased().hasPrefix(prefix) else { return nil }
        var rest = Substring(raw.dropFirst(prefix.count))
        if let end = rest.firstIndex(where: { "/?#".contains($0) }) {
            rest = rest[..<end]
        }
        let name = MosaicSettingsList.username(from: String(rest))
        return MosaicSettingsList.usernameProblems(name).isEmpty ? name : nil
    }
}

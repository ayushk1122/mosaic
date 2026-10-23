import Foundation

/// `mosaic://@username`, which opens that person's Mosaic in the app, and
/// `mosaic://@username/pursuit/<id>`, which opens it on one of their Pursuits.
enum MosaicLink {
    private static let prefix = "mosaic://@"
    private static let pursuitPath = "/pursuit/"

    /// Whose Mosaic a link opens, and on which Pursuit.
    struct Target: Equatable, Sendable {
        var username: String
        var pursuitID: UUID?
    }

    static func url(username: String, pursuitID: UUID? = nil) -> URL? {
        let name = MosaicSettingsList.username(from: username)
        guard MosaicSettingsList.usernameProblems(name).isEmpty else { return nil }
        let pursuit = pursuitID.map { pursuitPath + $0.uuidString.lowercased() } ?? ""
        return URL(string: prefix + name + pursuit)
    }

    /// The username in a Mosaic link. Sign-in callbacks and anything else on the scheme return nil.
    static func username(from url: URL) -> String? {
        target(from: url)?.username
    }

    /// A Pursuit part that doesn't name a Pursuit is ignored, so the link still opens the Mosaic.
    static func target(from url: URL) -> Target? {
        let raw = url.absoluteString
        guard raw.lowercased().hasPrefix(prefix) else { return nil }
        let rest = Substring(raw.dropFirst(prefix.count))
        let end = rest.firstIndex(where: { "/?#".contains($0) }) ?? rest.endIndex
        let name = MosaicSettingsList.username(from: String(rest[..<end]))
        guard MosaicSettingsList.usernameProblems(name).isEmpty else { return nil }
        var pursuitID: UUID?
        let path = rest[end...]
        if path.lowercased().hasPrefix(pursuitPath) {
            let id = path.dropFirst(pursuitPath.count).prefix { !"/?#".contains($0) }
            pursuitID = UUID(uuidString: String(id))
        }
        return Target(username: name, pursuitID: pursuitID)
    }
}

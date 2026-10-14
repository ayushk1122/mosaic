import SwiftUI

private struct ComposerMediaVersionsKey: EnvironmentKey {
    static let defaultValue: [String: Int] = [:]
}

extension EnvironmentValues {
    var composerMediaVersions: [String: Int] {
        get { self[ComposerMediaVersionsKey.self] }
        set { self[ComposerMediaVersionsKey.self] = newValue }
    }
}

/// Retrigger only the image/video whose previously missing file just arrived.
struct ComposerMediaLoadKey: Hashable {
    var url: URL?
    var version: Int

    init(_ url: URL?, versions: [String: Int]) {
        self.url = url
        version = url.map { versions[$0.lastPathComponent, default: 0] } ?? 0
    }
}

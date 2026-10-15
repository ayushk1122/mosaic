import SwiftUI

private struct ComposerMediaVersionsKey: EnvironmentKey {
    static let defaultValue: [String: Int] = [:]
}

private struct ComposerMediaWaitingKey: EnvironmentKey {
    static let defaultValue = ComposerMediaWaiting()
}

extension EnvironmentValues {
    var composerMediaVersions: [String: Int] {
        get { self[ComposerMediaVersionsKey.self] }
        set { self[ComposerMediaVersionsKey.self] = newValue }
    }

    var composerMediaWaiting: ComposerMediaWaiting {
        get { self[ComposerMediaWaitingKey.self] }
        set { self[ComposerMediaWaitingKey.self] = newValue }
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

/// Files that are still on their way to this phone. A missing file outside this set has nothing
/// coming, so it shows as unavailable instead of loading forever.
struct ComposerMediaWaiting: Equatable {
    /// Everything counts as coming, e.g. while the boards themselves are still downloading.
    var all = false
    var files: Set<String> = []

    func includes(_ fileName: String) -> Bool {
        all || files.contains(fileName)
    }

    func includes(_ url: URL?) -> Bool {
        url.map { includes($0.lastPathComponent) } ?? false
    }
}

/// Stands in for a photo or video whose file is not on this phone and has no copy to download.
struct ComposerMediaUnavailable: View {
    @Environment(\.composerCoordinateSpace) private var composerSpace

    var isVideo = false
    var compact = false
    var onReplace: (() -> Void)? = nil
    /// The board's drag gesture sees taps first, so it needs to know where Replace sits.
    var onReplaceFrame: ((CGRect) -> Void)? = nil

    private var title: String { isVideo ? "Video unavailable" : "Photo unavailable" }

    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            VStack(spacing: compact ? 4 : 8) {
                Image(systemName: isVideo ? "video.slash" : "photo.badge.exclamationmark")
                    .font(compact ? .body : .title2)
                    .accessibilityLabel(title)
                    .accessibilityHidden(!compact)
                if !compact {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                if let onReplace {
                    Text("Replace")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MosaicBrand.inkBlack)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white, in: Capsule())
                        .contentShape(Capsule())
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named(composerSpace))
                        } action: { frame in
                            onReplaceFrame?(frame)
                        }
                        .highPriorityGesture(TapGesture().onEnded { onReplace() })
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onReplace() }
                        .accessibilityIdentifier("composer.media.replaceUnavailable")
                }
            }
            .foregroundStyle(.white.opacity(0.75))
            .padding(8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("composer.media.unavailable")
    }
}

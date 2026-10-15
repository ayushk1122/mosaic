import SwiftUI

enum MosaicPage: String, CaseIterable, Sendable {
    case circle
    case discover
}

/// Circle and Discover backgrounds. They stay on this phone, in the signed-in account's folder,
/// and never sync; their photos sit in that folder's media but no board points to them, so they
/// aren't uploaded either.
@MainActor
@Observable
final class MosaicPageBackgrounds {
    private(set) var backgrounds: [MosaicPage: ComposerBoardBackground] = [:]
    @ObservationIgnored private let fileURL: URL?

    static func fileURL(in location: ComposerStorageLocation) -> URL {
        location.root.appendingPathComponent("page-backgrounds.json")
    }

    init(location: ComposerStorageLocation, persistToDisk: Bool = true) {
        fileURL = persistToDisk ? Self.fileURL(in: location) : nil
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        backgrounds = Self.decode(data)
    }

    func background(for page: MosaicPage) -> ComposerBoardBackground? {
        backgrounds[page]
    }

    func set(_ background: ComposerBoardBackground?, for page: MosaicPage) {
        backgrounds[page] = background
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Self.encode(backgrounds).write(to: fileURL, options: .atomic)
    }

    nonisolated static func encode(_ backgrounds: [MosaicPage: ComposerBoardBackground]) -> Data {
        let keyed = Dictionary(uniqueKeysWithValues: backgrounds.map { ($0.key.rawValue, $0.value) })
        return (try? JSONEncoder().encode(keyed)) ?? Data()
    }

    /// Unknown pages and unreadable entries are skipped, so a file from a newer version still opens.
    nonisolated static func decode(_ data: Data) -> [MosaicPage: ComposerBoardBackground] {
        guard let keyed = try? JSONDecoder().decode([String: LossyBackground].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: keyed.compactMap { key, entry in
            guard let page = MosaicPage(rawValue: key), let background = entry.value else { return nil }
            return (page, background)
        })
    }

    private struct LossyBackground: Decodable {
        let value: ComposerBoardBackground?

        init(from decoder: Decoder) throws {
            value = try? ComposerBoardBackground(from: decoder)
        }
    }
}

/// Puts a page's chosen background behind it, with a composer add menu that offers only Background.
private struct MosaicPageBackdrop: ViewModifier {
    let page: MosaicPage

    @Environment(ComposerStore.self) private var store
    @Environment(MosaicPageBackgrounds.self) private var backgrounds
    @State private var menuExpanded = false
    @State private var editing = false

    private static let fallback = ComposerRGBColor(red: 0.04, green: 0.04, blue: 0.04)

    func body(content: Content) -> some View {
        let background = backgrounds.background(for: page)
        content
            .background {
                ComposerBoardBackdrop(
                    background: background,
                    mediaURL: background?.mediaFileName.map { store.mediaURL(for: $0) },
                    fallback: MosaicBrand.inkBlack
                )
                .ignoresSafeArea()
            }
            .overlay(alignment: .bottomTrailing) {
                ComposerFloatingMenu(
                    isExpanded: $menuExpanded,
                    showsTrashDropZone: false,
                    isTrashHighlighted: false,
                    onlyOptions: [.background],
                    addLabel: "Customize page"
                ) { _ in
                    menuExpanded = false
                    editing = true
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
            .sheet(isPresented: $editing) {
                ComposerBackgroundEditor(
                    documentID: nil,
                    starting: background,
                    fallback: Self.fallback,
                    mediaURL: { store.mediaURL(for: $0) },
                    saveImage: { try store.saveMediaData($0) },
                    onChange: { backgrounds.set($0, for: page) },
                    onClose: { editing = false }
                )
            }
    }
}

extension View {
    func mosaicPageBackground(_ page: MosaicPage) -> some View {
        modifier(MosaicPageBackdrop(page: page))
    }
}

import Foundation
import Testing
@testable import Mosaic

@MainActor
struct ComposerContentTests {
    @Test func acceptsSupportedPostAndShareLinks() {
        let examples: [(String, ComposerContentPlatform)] = [
            ("https://youtu.be/abc123?t=5", .youtube),
            ("https://www.youtube.com/watch?v=abc123", .youtube),
            ("https://youtube.com/shorts/abc123", .youtube),
            ("https://www.instagram.com/reel/abc123/", .instagram),
            ("https://instagram.com/p/abc123/", .instagram),
            ("https://www.tiktok.com/@creator/video/12345", .tiktok),
            ("https://vm.tiktok.com/abc123/", .tiktok),
            ("https://www.twitch.tv/creator/clip/Example", .twitch),
            ("https://clips.twitch.tv/Example", .twitch),
            ("https://twitch.tv/videos/12345", .twitch)
        ]
        for (url, platform) in examples {
            #expect(ComposerContentPlatform.parse(url)?.platform == platform)
        }
    }

    @Test func rejectsUnsafeAndNonContentLinks() {
        for value in ["javascript:alert(1)", "http://youtube.com/watch?v=123", "https://youtube.com.evil.test/watch?v=123",
                      "https://youtube.com@evil.test/watch?v=123", "https://user@youtube.com/watch?v=123",
                      "https://youtube.com:8080/watch?v=123", "https://instagram.com/person/", "https://youtube.com/watch",
                      "https://tiktok.com/", "https://twitch.tv/directory", "file:///tmp/movie.mp4"] {
            #expect(ComposerContentPlatform.parse(value) == nil)
        }
    }

    @Test func contentRoundTripsAsCompatibleLinkAndIncludesCoverInSync() throws {
        var content = ComposerBlock.make(kind: .link, position: BlockPosition(x: 0.1, y: 0.2))
        content.socialPlatform = "content:youtube"
        content.linkURL = "https://youtu.be/abc123"
        content.text = "A useful video"
        content.mediaFileName = "cover.jpg"
        let encoded = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(ComposerBlock.self, from: encoded)
        #expect(decoded == content)
        #expect(decoded.kind == .link)
        #expect(decoded.isContent)
        #expect(decoded.contentPlatform == .youtube)
        var snapshot = ComposerSnapshot.empty
        snapshot.mosaicBlocks = [decoded]
        let id = UUID()
        #expect(ComposerMediaCatalog.references(snapshot: snapshot, mosaicID: id).map(\.fileName) == ["cover.jpg"])
        let docs = ComposerBoardSync.split(snapshot: snapshot, mosaicID: id)
        let restored = try #require(ComposerBoardSync.assemble(mosaicID: id, documents: docs))
        #expect(restored.mosaicBlocks.first?.contentPlatform == .youtube)
        #expect(!ComposerBlock.make(kind: .link, position: BlockPosition(x: 0, y: 0)).isContent)
    }

    @Test func contentIsAvailableOnMosaicsAndPursuits() {
        #expect(BlockMenuOption.menuOptions(matching: "content").contains(.content))
        #expect(BlockMenuOption.menuOptions(matching: "content", includingPursuit: false).contains(.content))
    }
}

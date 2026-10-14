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

    @Test func verticalPlatformsShowTheWholeCover() {
        func size(_ platform: ComposerContentPlatform, _ cover: CGSize?) -> [Int] {
            let card = platform.cardSize(cover: cover)
            return [Int((card.width * 4).rounded()), Int((card.height * 4).rounded())]
        }
        let wide = CGSize(width: 1280, height: 720)
        let tall = CGSize(width: 720, height: 1280)
        #expect(size(.youtube, tall) == [1040, 585])
        #expect(size(.twitch, nil) == [1040, 585])
        #expect(size(.tiktok, tall) == [720, 1280])
        #expect(size(.tiktok, nil) == [720, 1280])
        #expect(size(.instagram, CGSize(width: 1080, height: 1080)) == [1040, 1040])
        #expect(size(.instagram, CGSize(width: 1080, height: 1350)) == [1024, 1280])
        #expect(size(.instagram, wide) == [1040, 585])
        #expect(size(.tiktok, CGSize(width: 100, height: 1000)) == [720, 1280])
    }

    @Test func movingTheCoverStopsAtItsEdges() {
        let card = CGSize(width: 260, height: 146.25)
        let tall = CGSize(width: 720, height: 1280)
        let moved = ComposerContentFraming(panX: 5, panY: 5).clamped(cover: tall, in: card)
        #expect(moved.panX == 0)
        #expect(moved.panY > 0.9 && moved.panY < 1.1)
        let zoomed = ComposerContentFraming(zoom: 10, panX: -5).clamped(cover: tall, in: card)
        #expect(zoomed.zoom == 4)
        #expect(zoomed.panX == -1.5)
        let fits = ComposerContentFraming(panX: 1, panY: 1).clamped(cover: tall, in: CGSize(width: 180, height: 320))
        #expect(fits.panX == 0 && abs(fits.panY) < 0.0001)
    }

    @Test func savedCropSetsTheCardShape() {
        let tall = CGSize(width: 720, height: 1280)
        #expect(ComposerContentPlatform.youtube.cardSize(cover: nil, cropAspect: 1) == CGSize(width: 260, height: 260))
        #expect(ComposerContentPlatform.tiktok.cardSize(cover: tall, cropAspect: 2) == CGSize(width: 260, height: 130))
        #expect(ComposerContentPlatform.instagram.cardSize(cover: tall, cropAspect: 0.5) == CGSize(width: 160, height: 320))
        #expect(ComposerContentPlatform.youtube.cardSize(cover: nil, cropAspect: 10).height > 80)
    }

    @Test func instagramCoverComesFromTheUncroppedEmbedImage() throws {
        let reel = try #require(URL(string: "https://www.instagram.com/reel/DTtg6QJgRdP/"))
        #expect(ComposerInstagramCover.embedURL(for: reel)?.absoluteString == "https://www.instagram.com/p/DTtg6QJgRdP/embed/")
        #expect(ComposerInstagramCover.embedURL(for: try #require(URL(string: "https://instagram.com/person/"))) == nil)
        #expect(ComposerInstagramCover.embedURL(for: try #require(URL(string: "https://instagram.com/p/a%2F..%2Fb/"))) == nil)

        let html = """
        <div><img src="https://static.cdninstagram.com/logo.png"><img class="EmbeddedMediaImage" alt="Post" \
        src="https://scontent-mia5-2.cdninstagram.com/v/full.jpg?stp=dst-jpg_e15_tt6&amp;oh=abc" srcset="x 640w" /></div>
        """
        #expect(ComposerInstagramCover.imageURL(inEmbedHTML: html)?.absoluteString
                == "https://scontent-mia5-2.cdninstagram.com/v/full.jpg?stp=dst-jpg_e15_tt6&oh=abc")
        let foreign = #"<img class="EmbeddedMediaImage" src="https://evil.test/x.jpg">"#
        #expect(ComposerInstagramCover.imageURL(inEmbedHTML: foreign) == nil)
        #expect(ComposerInstagramCover.imageURL(inEmbedHTML: "<html>Log in</html>") == nil)
    }

    @Test func contentIsAvailableOnMosaicsAndPursuits() {
        #expect(BlockMenuOption.menuOptions(matching: "content").contains(.content))
        #expect(BlockMenuOption.menuOptions(matching: "content", includingPursuit: false).contains(.content))
    }
}

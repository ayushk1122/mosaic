import Foundation
import Testing
@testable import Mosaic

@MainActor
struct ComposerPhaseTwoTests {
    @Test
    func musicCanResumeOnlyAfterTheLastPlayingVideoStops() {
        final class Video {}
        let first = Video(), second = Video()
        ComposerVideoAudio.claim(ObjectIdentifier(first))
        ComposerVideoAudio.claim(ObjectIdentifier(second))
        ComposerVideoAudio.release(ObjectIdentifier(first))
        #expect(ComposerVideoAudio.playing == [ObjectIdentifier(second)])
        // Releasing twice, or a video that never played, changes nothing.
        ComposerVideoAudio.release(ObjectIdentifier(first))
        #expect(ComposerVideoAudio.playing.count == 1)
        ComposerVideoAudio.release(ObjectIdentifier(second))
        #expect(ComposerVideoAudio.playing.isEmpty)
    }

    @Test
    func piecesWithTheirOwnIconsFadeOnlyTheirContent() {
        for kind in [BlockKind.text, .heading, .list, .media, .carousel, .social, .pursuit, .node] {
            #expect(ComposerBlock.make(kind: kind, position: BlockPosition(x: 0.2, y: 0.2)).drawsOwnIcons, "\(kind)")
        }
        for kind in [BlockKind.drawing, .sticker, .group, .calendar, .graph, .scrapbook] {
            #expect(!ComposerBlock.make(kind: kind, position: BlockPosition(x: 0.2, y: 0.2)).drawsOwnIcons, "\(kind)")
        }
        var link = ComposerBlock.make(kind: .link, position: BlockPosition(x: 0.2, y: 0.2))
        #expect(!link.drawsOwnIcons)
        link.socialPlatform = "content:youtube"
        #expect(link.drawsOwnIcons == link.isContent)
    }
}

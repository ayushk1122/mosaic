import Foundation
import Testing
import UIKit
@testable import Mosaic

struct GolfFixturesTests {
    private let story = GolfFixtures.iteration0A

    @Test
    func storyIsCompleteAndSpansSeveralMonths() {
        #expect(story.coveredInterval.duration >= 90 * 24 * 60 * 60)
        #expect(!story.currentFocus.title.isEmpty)
        #expect(!story.recentPractice.isEmpty)
        #expect(!story.progress.points.isEmpty)
        #expect(!story.rounds.isEmpty)
        #expect(!story.milestones.isEmpty)
        #expect(!story.media.isEmpty)
    }

    @Test
    func consistencyIsOrderedAndMatchesSummary() {
        #expect(story.consistency.count == 12)
        #expect(story.consistency.map(\.weekStart) == story.consistency.map(\.weekStart).sorted())
        #expect(story.consistency.reduce(0) { $0 + $1.sessionCount } == 18)
        #expect(story.consistency.map(\.id) == (1...12).map { "week-\($0)" })
    }

    @Test
    func progressAndRoundsTellTheSameReadOnlyStory() {
        #expect(story.progress.points.map(\.date) == story.progress.points.map(\.date).sorted())
        #expect(story.progress.points.map(\.value) == [101, 94, 88])
        #expect(story.progress.points.map(\.id) == story.rounds.map(\.id))
        #expect(story.progress.unitLabel == "strokes")
        #expect(story.progress.narrative.localizedCaseInsensitiveContains("not an official handicap"))
    }

    @Test
    func seasonMosaicMatchesTheApprovedStory() {
        #expect(story.seasonMemories.map(\.dateLabel) == ["June", "August", "September", "September 20"])
        #expect(story.seasonMemories.map(\.caption) == [
            "Finding a calmer setup.",
            "Practice became more regular.",
            "Stayed long enough to find the rhythm.",
            "First round under 90."
        ])
    }

    @Test
    func everyFixtureImageResolvesFromTheAssetCatalog() {
        #expect(FixtureImageAsset.allCases.count == 12)
        for asset in FixtureImageAsset.allCases {
            #expect(UIImage(named: asset.rawValue) != nil, "Missing fixture image: \(asset.rawValue)")
        }
    }
}

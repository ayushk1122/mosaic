import Foundation

enum GolfFixtures {
    static let iteration0A: GolfOverviewStory = {
        let rounds = [
            GolfRoundEvidence(
                id: "round-june-14",
                date: date(2026, 6, 14),
                courseName: "Cedar Hills",
                score: 101,
                reflection: "Kept the ball in play and found a calmer pre-shot rhythm."
            ),
            GolfRoundEvidence(
                id: "round-august-9",
                date: date(2026, 8, 9),
                courseName: "Willow Creek",
                score: 94,
                reflection: "Solid contact showed up more often, especially with mid-irons."
            ),
            GolfRoundEvidence(
                id: "round-september-20",
                date: date(2026, 9, 20),
                courseName: "Cedar Hills",
                score: 88,
                reflection: "Trusted the swing and recovered patiently after difficult holes."
            )
        ]

        return GolfOverviewStory(
            title: "My Golf",
            coveredInterval: DateInterval(start: date(2026, 6, 14), end: date(2026, 9, 20)),
            currentFocus: GolfCurrentFocus(
                title: "Consistent contact",
                detail: "Keeping a balanced finish and letting a smooth tempo shape every iron swing.",
                since: date(2026, 8, 24)
            ),
            recentPractice: [
                GolfPracticeEvidence(
                    id: "practice-september-17",
                    date: date(2026, 9, 17),
                    summary: "Rainy evening range",
                    note: "Slowed the transition and finished in balance. Contact stayed centered through the final basket."
                ),
                GolfPracticeEvidence(
                    id: "practice-september-10",
                    date: date(2026, 9, 10),
                    summary: "Nine-hole walk",
                    note: "Committed to one target on every tee and noticed fewer rushed swings."
                ),
                GolfPracticeEvidence(
                    id: "practice-august-31",
                    date: date(2026, 8, 31),
                    summary: "Short-game practice",
                    note: "Used one landing spot for every chip and let feel, not mechanics, lead."
                )
            ],
            consistency: zip(
                [
                    date(2026, 6, 29), date(2026, 7, 6), date(2026, 7, 13),
                    date(2026, 7, 20), date(2026, 7, 27), date(2026, 8, 3),
                    date(2026, 8, 10), date(2026, 8, 17), date(2026, 8, 24),
                    date(2026, 8, 31), date(2026, 9, 7), date(2026, 9, 14)
                ],
                [1, 1, 2, 1, 1, 2, 1, 2, 2, 2, 1, 2]
            ).enumerated().map { index, pair in
                GolfConsistencyWeek(
                    id: "week-\(index + 1)",
                    weekStart: pair.0,
                    sessionCount: pair.1
                )
            },
            progress: GolfProgressSummary(
                title: "A steadier score story",
                dateRangeLabel: "June – September 2026",
                narrative: "Across three sample rounds, scores moved from 101 to 88 strokes while practice became more consistent. This is a personal story, not an official handicap or a claim of causation.",
                unitLabel: "strokes",
                points: rounds.map {
                    GolfProgressPoint(id: $0.id, date: $0.date, value: $0.score)
                }
            ),
            rounds: rounds,
            milestones: [
                GolfMilestone(
                    id: "milestone-under-90",
                    date: date(2026, 9, 20),
                    title: "First round under 90",
                    meaning: "A marker of calmer decisions and a swing that felt familiar from the first tee to the last.",
                    systemImage: "flag.checkered"
                )
            ],
            media: [
                GolfMediaMemory(
                    id: "memory-evening-range",
                    date: date(2026, 9, 17),
                    caption: "Stayed through the rain and found a rhythm worth remembering.",
                    accessibilityDescription: "Abstract rain-themed illustration"
                )
            ]
        )
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date!
    }
}

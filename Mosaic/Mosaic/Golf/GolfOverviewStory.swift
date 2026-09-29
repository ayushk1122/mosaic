import Foundation

struct GolfOverviewStory: Equatable, Sendable {
    let title: String
    let coveredInterval: DateInterval
    let currentFocus: GolfCurrentFocus
    let recentPractice: [GolfPracticeEvidence]
    let consistency: [GolfConsistencyWeek]
    let progress: GolfProgressSummary
    let rounds: [GolfRoundEvidence]
    let milestones: [GolfMilestone]
    let media: [GolfMediaMemory]
}

struct GolfCurrentFocus: Equatable, Sendable {
    let title: String
    let detail: String
    let since: Date
}

struct GolfPracticeEvidence: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let summary: String
    let note: String
}

struct GolfConsistencyWeek: Identifiable, Equatable, Sendable {
    let id: String
    let weekStart: Date
    let sessionCount: Int
}

struct GolfProgressSummary: Equatable, Sendable {
    let title: String
    let dateRangeLabel: String
    let narrative: String
    let unitLabel: String
    let points: [GolfProgressPoint]
}

struct GolfProgressPoint: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let value: Int
}

struct GolfRoundEvidence: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let courseName: String
    let score: Int
    let reflection: String
}

struct GolfMilestone: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let title: String
    let meaning: String
    let systemImage: String
}

struct GolfMediaMemory: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let caption: String
    let accessibilityDescription: String
}

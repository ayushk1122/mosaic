import SwiftUI

struct GolfDestinationView: View {
    private let story: GolfOverviewStory

    init(story: GolfOverviewStory = GolfFixtures.iteration0A) {
        self.story = story
    }

    var body: some View {
        GolfOverviewView(story: story)
    }
}

struct GolfOverviewView: View {
    let story: GolfOverviewStory

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(story.title)
                        .font(.largeTitle.bold())
                    Text("A season of deliberate work, remembered in the moments that mattered.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                GolfCurrentFocusView(focus: story.currentFocus)
                    .accessibilityIdentifier("golf.current-focus")

                GolfRecentPracticeView(practices: story.recentPractice)
                    .accessibilityIdentifier("golf.recent-practice")

                GolfConsistencyGrid(weeks: story.consistency)
                    .accessibilityIdentifier("golf.consistency")

                GolfProgressView(progress: story.progress)
                    .accessibilityIdentifier("golf.progress")

                GolfRoundsView(rounds: story.rounds)
                    .accessibilityIdentifier("golf.rounds")

                GolfMemoriesView(milestones: story.milestones, media: story.media)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .accessibilityIdentifier("golf.overview")
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Golf Overview")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GolfCurrentFocusView: View {
    let focus: GolfCurrentFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Current focus", systemImage: "scope")
                .font(.headline)
                .foregroundStyle(.green)
            Text(focus.title)
                .font(.title2.bold())
            Text(focus.detail)
                .foregroundStyle(.secondary)
            Text("Since \(focus.since.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct GolfRecentPracticeView: View {
    let practices: [GolfPracticeEvidence]

    var body: some View {
        StorySection(title: "Recent practice", subtitle: "Small observations from the latest chapter") {
            VStack(spacing: 0) {
                ForEach(Array(practices.enumerated()), id: \.element.id) { index, practice in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(practice.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(practice.summary)
                            .font(.headline)
                        Text(practice.note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)

                    if index < practices.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct GolfConsistencyGrid: View {
    let weeks: [GolfConsistencyWeek]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        StorySection(title: "12-week rhythm", subtitle: "\(weeks.reduce(0) { $0 + $1.sessionCount }) sessions over 12 weeks") {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weeks) { week in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.green.opacity(week.sessionCount == 2 ? 0.8 : 0.35))
                            .frame(height: 34)
                            .overlay {
                                Text("\(week.sessionCount)")
                                    .font(.caption.bold())
                                    .foregroundStyle(week.sessionCount == 2 ? .white : .primary)
                            }
                        Text(week.weekStart.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(0.8)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "Week of \(week.weekStart.formatted(date: .long, time: .omitted)), \(week.sessionCount) practice \(week.sessionCount == 1 ? "session" : "sessions")"
                    )
                }
            }
            Text("Each cell shows that week’s practice count.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct GolfProgressView: View {
    let progress: GolfProgressSummary

    var body: some View {
        StorySection(title: "Visible progress", subtitle: progress.dateRangeLabel) {
            Text(progress.title)
                .font(.headline)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(progress.points) { point in
                    VStack(spacing: 8) {
                        Text("\(point.value)")
                            .font(.title2.bold().monospacedDigit())
                        Capsule()
                            .fill(Color.green.opacity(0.75))
                            .frame(height: CGFloat(132 - point.value))
                            .frame(minHeight: 28)
                        Text(point.date.formatted(.dateTime.month(.abbreviated)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(point.date.formatted(date: .long, time: .omitted)), sample round, \(point.value) \(progress.unitLabel)")
                }
            }
            .padding(.vertical, 4)
            Text(progress.narrative)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GolfRoundsView: View {
    let rounds: [GolfRoundEvidence]

    var body: some View {
        StorySection(title: "Sample rounds", subtitle: "Read-only evidence from this season") {
            ForEach(rounds) { round in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("\(round.score)")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(.green)
                        .accessibilityLabel("\(round.score) strokes")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sample round · \(round.courseName)")
                            .font(.headline)
                        Text(round.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(round.reflection)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct GolfMemoriesView: View {
    let milestones: [GolfMilestone]
    let media: [GolfMediaMemory]

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            StorySection(title: "Milestone", subtitle: "A moment worth marking") {
                ForEach(milestones) { milestone in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: milestone.systemImage)
                            .font(.title2)
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(milestone.title)
                                .font(.title3.bold())
                            Text(milestone.date.formatted(date: .long, time: .omitted))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(milestone.meaning)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                    .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("golf.milestones")

            StorySection(title: "A memory from the work", subtitle: "The story is more than a score") {
                ForEach(media) { memory in
                    VStack(alignment: .leading, spacing: 12) {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(
                                colors: [.indigo.opacity(0.8), .green.opacity(0.55), .black.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "cloud.rain.fill")
                                .font(.system(size: 76))
                                .foregroundStyle(.white.opacity(0.28))
                                .padding(24)
                            Label("Evening range", systemImage: "figure.golf")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(16)
                        }
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(memory.accessibilityDescription)

                        Text(memory.date.formatted(date: .long, time: .omitted))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(memory.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityIdentifier("golf.media")
        }
    }
}

private struct StorySection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        GolfDestinationView()
    }
}

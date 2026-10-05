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
            LazyVStack(alignment: .leading, spacing: 52) {
                GolfHeroView(story: story)
                    .accessibilityIdentifier("golf.current-focus")

                GolfPracticeChapter(practices: story.recentPractice)
                    .accessibilityIdentifier("golf.recent-practice")

                GolfConsistencyChapter(weeks: story.consistency)
                    .accessibilityIdentifier("golf.consistency")

                GolfProgressChapter(progress: story.progress)
                    .accessibilityIdentifier("golf.progress")

                GolfRoundsChapter(rounds: story.rounds)
                    .accessibilityIdentifier("golf.rounds")

                GolfMemoryChapter(milestones: story.milestones, media: story.media)
            }
            .padding(.bottom, 64)
        }
        .accessibilityIdentifier("golf.overview")
        .background(Color(red: 0.02, green: 0.022, blue: 0.024))
        .navigationTitle("Golf Overview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct GolfHeroView: View {
    let story: GolfOverviewStory

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.31, blue: 0.21), Color(red: 0.19, green: 0.15, blue: 0.08), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "figure.golf")
                .font(.system(size: 190, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.12))
                .offset(x: 120, y: -70)
                .accessibilityHidden(true)
            LinearGradient(colors: [.clear, .black.opacity(0.86)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 18) {
                Text(story.title)
                    .font(.system(.largeTitle, design: .serif, weight: .medium))
                VStack(alignment: .leading, spacing: 6) {
                    Text("CURRENT FOCUS")
                        .font(.caption.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.56))
                    Text(story.currentFocus.title)
                        .font(.title2.weight(.medium))
                    Text(story.currentFocus.detail)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Since \(story.currentFocus.since.formatted(.dateTime.month(.wide).day()))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .foregroundStyle(.white)
            .padding(24)
        }
        .frame(minHeight: 420)
        .accessibilityElement(children: .combine)
    }
}

private struct GolfPracticeChapter: View {
    let practices: [GolfPracticeEvidence]

    var body: some View {
        GolfSection(title: "Practice") {
            VStack(spacing: 0) {
                ForEach(Array(practices.enumerated()), id: \.element.id) { index, practice in
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Text(practice.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.46))
                            .frame(width: 54, alignment: .leading)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(practice.summary)
                                .font(.title3.weight(.regular))
                                .foregroundStyle(.white.opacity(0.9))
                            Text(practice.note)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.58))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 15)
                    .accessibilityElement(children: .combine)
                    if index < practices.count - 1 {
                        Divider().overlay(.white.opacity(0.12))
                    }
                }
            }
        }
    }
}

private struct GolfConsistencyChapter: View {
    let weeks: [GolfConsistencyWeek]

    var body: some View {
        GolfSection(title: "Rhythm") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(weeks) { week in
                        Capsule()
                            .fill(week.sessionCount == 2 ? Color.green.opacity(0.9) : Color.green.opacity(0.35))
                            .frame(maxWidth: .infinity)
                            .frame(height: week.sessionCount == 2 ? 54 : 28)
                            .accessibilityLabel(
                                "Week of \(week.weekStart.formatted(date: .long, time: .omitted)), \(week.sessionCount) practice \(week.sessionCount == 1 ? "session" : "sessions")"
                            )
                    }
                }
                HStack {
                    Text(weeks.first?.weekStart.formatted(.dateTime.month(.abbreviated).day()) ?? "")
                    Spacer()
                    Text(weeks.last?.weekStart.formatted(.dateTime.month(.abbreviated).day()) ?? "")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.46))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(weeks.reduce(0) { $0 + $1.sessionCount }) sessions · \(weeks.count) weeks")
                        .font(.subheadline.monospacedDigit())
                    Text("Short bar: 1 session · Tall bar: 2 sessions")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.58))
            }
        }
    }
}

private struct GolfProgressChapter: View {
    let progress: GolfProgressSummary

    var body: some View {
        GolfSection(title: "Progress") {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(progress.title)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(progress.narrative)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        scoreValues
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        scoreValues
                    }
                }
                Text("Sample rounds · strokes · \(progress.dateRangeLabel)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private var scoreValues: some View {
        ForEach(Array(progress.points.enumerated()), id: \.element.id) { index, point in
            Text("\(point.value)")
                .font(.system(.largeTitle, design: .serif, weight: .medium).monospacedDigit())
                .foregroundStyle(index == progress.points.count - 1 ? Color.green : .white)
                .accessibilityLabel("\(point.date.formatted(date: .long, time: .omitted)), sample round, \(point.value) \(progress.unitLabel)")
            if index < progress.points.count - 1 {
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct GolfRoundsChapter: View {
    let rounds: [GolfRoundEvidence]

    var body: some View {
        GolfSection(title: "Sample rounds") {
            VStack(spacing: 20) {
                ForEach(rounds) { round in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("\(round.score)")
                            .font(.title2.weight(.medium).monospacedDigit())
                            .foregroundStyle(.white)
                            .accessibilityLabel("\(round.score) strokes")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(round.courseName)
                                .foregroundStyle(.white.opacity(0.82))
                            Text(round.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.46))
                            Text(round.reflection)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.58))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct GolfMemoryChapter: View {
    let milestones: [GolfMilestone]
    let media: [GolfMediaMemory]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(zip(milestones, media)), id: \.0.id) { milestone, memory in
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.72), Color.green.opacity(0.48), Color.orange.opacity(0.26), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "cloud.rain.fill")
                        .font(.system(size: 110))
                        .foregroundStyle(.white.opacity(0.12))
                        .offset(x: 190, y: -95)
                        .accessibilityHidden(true)
                    LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MILESTONE")
                            .font(.caption.weight(.semibold))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.56))
                        Text(milestone.title)
                            .font(.system(.title, design: .serif, weight: .medium))
                        Text(memory.caption)
                            .foregroundStyle(.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(milestone.meaning)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(milestone.date.formatted(date: .long, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    .foregroundStyle(.white)
                    .padding(24)
                }
                .frame(minHeight: 330)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(milestone.title), \(milestone.date.formatted(date: .long, time: .omitted)). \(milestone.meaning). \(memory.caption). \(memory.accessibilityDescription)")
                .accessibilityIdentifier("golf.milestones")
            }
        }
        .accessibilityIdentifier("golf.media")
    }
}

private struct GolfSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(.title2, design: .serif, weight: .medium))
                .foregroundStyle(.white)
            content
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    NavigationStack {
        GolfDestinationView()
    }
}

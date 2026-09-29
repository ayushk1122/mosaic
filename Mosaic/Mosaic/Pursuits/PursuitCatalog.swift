import Foundation

struct PursuitID: Hashable, Sendable {
    let rawValue: String
}

enum PursuitKind: String, Sendable {
    case golf
    case fitness
    case modeling
    case cooking
}

struct PursuitSummary: Identifiable, Equatable, Sendable {
    let id: PursuitID
    let kind: PursuitKind
    let title: String
    let subtitle: String
    let systemImage: String
}

struct MosaicProfileFixture: Equatable, Sendable {
    let displayName: String
    let initials: String
    let headline: String
}

struct MosaicHomeFixture: Equatable, Sendable {
    let profile: MosaicProfileFixture
    let pursuits: [PursuitSummary]
}

enum MosaicHomeFixtures {
    static let iteration0A = MosaicHomeFixture(
        profile: MosaicProfileFixture(
            displayName: "Alex Morgan",
            initials: "AM",
            headline: "A life in progress, one pursuit at a time."
        ),
        pursuits: [
            PursuitSummary(
                id: PursuitID(rawValue: "golf"),
                kind: .golf,
                title: "Golf",
                subtitle: "Building a more confident, consistent game",
                systemImage: "figure.golf"
            ),
            PursuitSummary(
                id: PursuitID(rawValue: "fitness"),
                kind: .fitness,
                title: "Fitness",
                subtitle: "Strength and movement for everyday life",
                systemImage: "figure.strengthtraining.traditional"
            ),
            PursuitSummary(
                id: PursuitID(rawValue: "modeling"),
                kind: .modeling,
                title: "Modeling",
                subtitle: "Learning to shape ideas in three dimensions",
                systemImage: "cube.transparent"
            ),
            PursuitSummary(
                id: PursuitID(rawValue: "cooking"),
                kind: .cooking,
                title: "Cooking",
                subtitle: "Becoming more intuitive in the kitchen",
                systemImage: "frying.pan"
            )
        ]
    )
}

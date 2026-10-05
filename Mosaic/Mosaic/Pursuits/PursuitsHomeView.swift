import SwiftUI

struct PursuitsHomeView: View {
    let fixture: MosaicHomeFixture
    let openGolf: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 38) {
                PortfolioIdentityView(profile: fixture.profile)
                    .accessibilityIdentifier("home.profile")

                VStack(alignment: .leading, spacing: 18) {
                    Text("Pursuits")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))

                    ForEach(fixture.pursuits) { pursuit in
                        if pursuit.kind == .golf {
                            Button(action: openGolf) {
                                PursuitPortfolioTile(pursuit: pursuit, isAvailable: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("pursuit.golf.open")
                            .accessibilityHint("Opens Golf Overview")
                        } else {
                            PursuitPortfolioTile(pursuit: pursuit, isAvailable: false)
                                .accessibilityIdentifier("pursuit.\(pursuit.kind.rawValue).planned")
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 32)
            .padding(.bottom, 54)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("home.screen")
        .background(Color(red: 0.025, green: 0.027, blue: 0.03))
        .navigationTitle("Mosaic Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct PortfolioIdentityView: View {
    let profile: MosaicProfileFixture

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MOSAIC")
                .font(.caption.weight(.semibold))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.5))
            Text(profile.displayName)
                .font(.largeTitle.weight(.medium))
                .fontDesign(.serif)
                .foregroundStyle(.white)
            Text("A personal collection in progress.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.58))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PursuitPortfolioTile: View {
    let pursuit: PursuitSummary
    let isAvailable: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleComposition
            } else {
                fixedComposition
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var fixedComposition: some View {
        switch pursuit.kind {
        case .golf:
            GolfHomeComposition(pursuit: pursuit)
        case .fitness:
            FitnessHomeComposition(pursuit: pursuit)
        case .modeling:
            ModelingHomeComposition(pursuit: pursuit)
        case .cooking:
            CookingHomeComposition(pursuit: pursuit)
        }
    }

    private var accessibleComposition: some View {
        VStack(alignment: .leading, spacing: 14) {
            FixtureImageFrame(asset: anchorImage, cornerRadius: 3)
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            VStack(alignment: .leading, spacing: 7) {
                Text(pursuit.title)
                    .font(.title2.weight(.medium))
                    .fontDesign(.serif)
                Text(pursuit.subtitle)
                    .font(.body)
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1)
            }
            .foregroundStyle(.white)
        }
        .padding(16)
        .background(Color(red: 0.075, green: 0.08, blue: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var anchorImage: FixtureImageAsset {
        switch pursuit.kind {
        case .golf: .golfRangeGoldenHour
        case .fitness: .fitnessStrengthMovement
        case .modeling: .modelingEditorialPose
        case .cooking: .cookingWindowLightPasta
        }
    }

    private var statusText: String {
        isAvailable ? "June–September · Open journey" : "Visual study · Planned"
    }

    private var accessibilityLabel: String {
        "\(pursuit.title). \(pursuit.subtitle). \(isAvailable ? "June through September. Open journey." : "Visual study, planned.")"
    }
}

private struct GolfHomeComposition: View {
    let pursuit: PursuitSummary

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            FixtureImageFrame(asset: .golfRangeGoldenHour, cornerRadius: 4)
            LinearGradient(
                colors: [.black.opacity(0.08), .black.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack {
                HStack(alignment: .top) {
                    Text("JUN — SEP")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.7)
                        .foregroundStyle(.white.opacity(0.86))
                        .padding(.vertical, 7)
                        .padding(.horizontal, 9)
                        .background(Color(red: 0.08, green: 0.25, blue: 0.17).opacity(0.9))
                    Spacer()
                    HStack(spacing: 9) {
                        FixtureImageFrame(asset: .golfGloveClubDetail, cornerRadius: 2)
                            .frame(width: 78, height: 70)
                            .rotationEffect(.degrees(-2))
                        FixtureImageFrame(asset: .golfDewyGreenBall, cornerRadius: 2)
                            .frame(width: 78, height: 70)
                            .rotationEffect(.degrees(2))
                    }
                }
                Spacer()
            }
            .padding(14)
            HomeCompositionCopy(
                title: pursuit.title,
                subtitle: pursuit.subtitle,
                status: "June–September · Open journey",
                lightBackground: false
            )
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct FitnessHomeComposition: View {
    let pursuit: PursuitSummary

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.08, green: 0.085, blue: 0.09)
            HStack(spacing: 10) {
                FixtureImageFrame(asset: .fitnessStrengthMovement, cornerRadius: 2)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 10) {
                    FixtureImageFrame(asset: .fitnessChalkedHand, cornerRadius: 2)
                    FixtureImageFrame(asset: .fitnessRecoveryStillLife, cornerRadius: 2)
                }
                .frame(width: 112)
            }
            .padding(12)
            LinearGradient(colors: [.clear, .black.opacity(0.94)], startPoint: .center, endPoint: .bottom)
            HomeCompositionCopy(
                title: pursuit.title,
                subtitle: pursuit.subtitle,
                status: "Visual study · Planned",
                lightBackground: false
            )
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 286)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct ModelingHomeComposition: View {
    let pursuit: PursuitSummary

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.89, green: 0.86, blue: 0.8)
            HStack(alignment: .top, spacing: 8) {
                FixtureImageFrame(asset: .modelingEditorialPose, cornerRadius: 1)
                    .frame(width: 142, height: 232)
                    .rotationEffect(.degrees(-1.5))
                VStack(spacing: 9) {
                    FixtureImageFrame(asset: .modelingContactStudy, cornerRadius: 1)
                        .frame(height: 93)
                        .rotationEffect(.degrees(1.5))
                    FixtureImageFrame(asset: .modelingFabricDetail, cornerRadius: 1)
                        .frame(height: 104)
                }
            }
            .padding(.top, 13)
            .padding(.horizontal, 13)
            .frame(maxHeight: .infinity, alignment: .top)
            Path { path in
                path.move(to: CGPoint(x: 210, y: 34))
                path.addCurve(
                    to: CGPoint(x: 308, y: 47),
                    control1: CGPoint(x: 242, y: 16),
                    control2: CGPoint(x: 275, y: 64)
                )
            }
            .stroke(Color(red: 0.34, green: 0.2, blue: 0.14).opacity(0.48), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .accessibilityHidden(true)
            HomeCompositionCopy(
                title: pursuit.title,
                subtitle: pursuit.subtitle,
                status: "Visual study · Planned",
                lightBackground: true
            )
            .padding(18)
            .background(
                LinearGradient(
                    colors: [.clear, Color(red: 0.94, green: 0.91, blue: 0.85).opacity(0.98)],
                    startPoint: .top,
                    endPoint: .center
                )
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 292)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct CookingHomeComposition: View {
    let pursuit: PursuitSummary

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            FixtureImageFrame(asset: .cookingWindowLightPasta, cornerRadius: 4)
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        FixtureImageFrame(asset: .cookingIngredientPreparation, cornerRadius: 2)
                            .frame(width: 98, height: 78)
                            .rotationEffect(.degrees(2))
                        FixtureImageFrame(asset: .cookingWindowLightPasta, cornerRadius: 2)
                            .frame(width: 78, height: 62)
                            .rotationEffect(.degrees(-2))
                    }
                }
                Spacer()
            }
            .padding(13)
            LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text("repeat-worthy.")
                    .font(.caption.italic())
                    .foregroundStyle(.white.opacity(0.86))
                HomeCompositionCopy(
                    title: pursuit.title,
                    subtitle: pursuit.subtitle,
                    status: "Visual study · Planned",
                    lightBackground: false
                )
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 286)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct HomeCompositionCopy: View {
    let title: String
    let subtitle: String
    let status: String
    let lightBackground: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title2.weight(.medium))
                .fontDesign(.serif)
            Text(subtitle)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text(status)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .padding(.top, 2)
        }
        .foregroundStyle(lightBackground ? Color(red: 0.12, green: 0.1, blue: 0.08) : .white)
    }
}

private struct FixtureImageFrame: View {
    let asset: FixtureImageAsset
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Image(asset.rawValue)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
        }
        .clipped()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

#Preview {
    NavigationStack {
        PursuitsHomeView(fixture: MosaicHomeFixtures.iteration0A, openGolf: {})
    }
}

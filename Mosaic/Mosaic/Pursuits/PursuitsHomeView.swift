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

    @ViewBuilder
    private var accessibleComposition: some View {
        switch pursuit.kind {
        case .golf:
            AccessibleGolfHomeComposition(pursuit: pursuit)
        case .fitness:
            AccessibleFitnessHomeComposition(pursuit: pursuit)
        case .modeling:
            AccessibleModelingHomeComposition(pursuit: pursuit)
        case .cooking:
            AccessibleCookingHomeComposition(pursuit: pursuit)
        }
    }

    private var accessibilityLabel: String {
        "\(pursuit.title). \(pursuit.subtitle). \(isAvailable ? "June through September. Open journey." : "Visual study, planned.")"
    }
}

private struct GolfHomeComposition: View {
    let pursuit: PursuitSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                FixtureImageFrame(asset: .golfRangeGoldenHour, cornerRadius: 4)
                HStack(alignment: .top) {
                    Text("JUN — SEP")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.7)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.vertical, 7)
                        .padding(.horizontal, 9)
                        .background(Color(red: 0.08, green: 0.25, blue: 0.17).opacity(0.94))
                    Spacer()
                    HStack(spacing: 9) {
                        FixtureImageFrame(asset: .golfGloveClubDetail, cornerRadius: 2)
                            .frame(width: 78, height: 64)
                            .rotationEffect(.degrees(-2))
                        FixtureImageFrame(asset: .golfDewyGreenBall, cornerRadius: 2)
                            .frame(width: 78, height: 64)
                            .rotationEffect(.degrees(2))
                    }
                }
                .padding(14)
            }
            .frame(height: 190)
            HomeCompositionCopy(
                title: pursuit.title,
                subtitle: pursuit.subtitle,
                status: "June–September · Open journey",
                lightBackground: false
            )
            .padding(18)
        }
        .background(Color(red: 0.055, green: 0.075, blue: 0.065))
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
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                FixtureImageFrame(asset: .cookingWindowLightPasta, cornerRadius: 4)
                VStack {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            FixtureImageFrame(asset: .cookingIngredientPreparation, cornerRadius: 2)
                                .frame(width: 98, height: 72)
                                .rotationEffect(.degrees(2))
                            FixtureImageFrame(asset: .cookingWindowLightPasta, cornerRadius: 2)
                                .frame(width: 78, height: 56)
                                .rotationEffect(.degrees(-2))
                        }
                    }
                    Spacer()
                }
                .padding(13)
            }
            .frame(height: 190)
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
            .padding(18)
        }
        .background(Color(red: 0.14, green: 0.085, blue: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct AccessibleGolfHomeComposition: View {
    let pursuit: PursuitSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topLeading) {
                FixtureImageFrame(asset: .golfRangeGoldenHour, cornerRadius: 3)
                Text("JUN — SEP")
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .padding(8)
                    .foregroundStyle(.white)
                    .background(Color(red: 0.08, green: 0.25, blue: 0.17).opacity(0.94))
                    .padding(12)
            }
            .frame(height: 170)
            HStack(spacing: 12) {
                FixtureImageFrame(asset: .golfGloveClubDetail, cornerRadius: 2)
                    .frame(height: 92)
                    .rotationEffect(.degrees(-1.5))
                FixtureImageFrame(asset: .golfDewyGreenBall, cornerRadius: 2)
                    .frame(height: 92)
                    .rotationEffect(.degrees(1.5))
            }
            HomeCompositionCopy(
                title: pursuit.title,
                subtitle: pursuit.subtitle,
                status: "June–September · Open journey",
                lightBackground: false
            )
        }
        .padding(16)
        .background(Color(red: 0.055, green: 0.075, blue: 0.065))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct AccessibleFitnessHomeComposition: View {
    let pursuit: PursuitSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                FixtureImageFrame(asset: .fitnessStrengthMovement, cornerRadius: 2)
                    .frame(width: 128, height: 210)
                VStack(spacing: 12) {
                    FixtureImageFrame(asset: .fitnessChalkedHand, cornerRadius: 2)
                        .frame(height: 99)
                    FixtureImageFrame(asset: .fitnessRecoveryStillLife, cornerRadius: 2)
                        .frame(height: 99)
                }
            }
            HomeCompositionCopy(
                title: pursuit.title,
                subtitle: pursuit.subtitle,
                status: "Visual study · Planned",
                lightBackground: false
            )
        }
        .padding(16)
        .background(Color(red: 0.075, green: 0.08, blue: 0.085))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct AccessibleModelingHomeComposition: View {
    let pursuit: PursuitSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                FixtureImageFrame(asset: .modelingEditorialPose, cornerRadius: 1)
                    .frame(width: 124, height: 190)
                    .rotationEffect(.degrees(-1))
                VStack(spacing: 12) {
                    FixtureImageFrame(asset: .modelingContactStudy, cornerRadius: 1)
                        .frame(height: 86)
                        .rotationEffect(.degrees(1))
                    FixtureImageFrame(asset: .modelingFabricDetail, cornerRadius: 1)
                        .frame(height: 86)
                }
            }
            HomeCompositionCopy(
                title: pursuit.title,
                subtitle: pursuit.subtitle,
                status: "Visual study · Planned",
                lightBackground: true
            )
        }
        .padding(16)
        .background(Color(red: 0.92, green: 0.89, blue: 0.83))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct AccessibleCookingHomeComposition: View {
    let pursuit: PursuitSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FixtureImageFrame(asset: .cookingWindowLightPasta, cornerRadius: 3)
                .frame(height: 174)
            HStack(spacing: 12) {
                FixtureImageFrame(asset: .cookingIngredientPreparation, cornerRadius: 2)
                    .frame(height: 96)
                FixtureImageFrame(asset: .cookingWindowLightPasta, cornerRadius: 2)
                    .frame(height: 96)
            }
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
        .padding(16)
        .background(Color(red: 0.14, green: 0.085, blue: 0.06))
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

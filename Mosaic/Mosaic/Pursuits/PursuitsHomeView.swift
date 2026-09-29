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
        }
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

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: pursuit.systemImage)
                .font(.system(size: isAvailable ? 118 : 70, weight: .ultraLight))
                .foregroundStyle(.white.opacity(isAvailable ? 0.16 : 0.09))
                .offset(x: 80, y: -26)
                .accessibilityHidden(true)

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(pursuit.title)
                        .font(isAvailable ? .largeTitle.weight(.medium) : .title2.weight(.medium))
                        .fontDesign(.serif)
                        .foregroundStyle(.white)
                    Text(isAvailable ? "View journey" : "Planned")
                        .font(.caption.weight(.medium))
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer(minLength: 10)
                if isAvailable {
                    Image(systemName: "arrow.up.right")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                        .accessibilityHidden(true)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: isAvailable ? 220 : 132)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .combine)
    }

    private var palette: [Color] {
        switch pursuit.kind {
        case .golf:
            [Color(red: 0.08, green: 0.31, blue: 0.21), Color(red: 0.18, green: 0.16, blue: 0.09)]
        case .fitness:
            [Color(red: 0.20, green: 0.18, blue: 0.25), Color(red: 0.08, green: 0.08, blue: 0.10)]
        case .modeling:
            [Color(red: 0.12, green: 0.20, blue: 0.25), Color(red: 0.07, green: 0.09, blue: 0.11)]
        case .cooking:
            [Color(red: 0.28, green: 0.15, blue: 0.10), Color(red: 0.10, green: 0.07, blue: 0.06)]
        }
    }
}

#Preview {
    NavigationStack {
        PursuitsHomeView(fixture: MosaicHomeFixtures.iteration0A, openGolf: {})
    }
}

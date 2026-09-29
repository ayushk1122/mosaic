import SwiftUI

struct PursuitsHomeView: View {
    let fixture: MosaicHomeFixture
    let openGolf: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ProfileHeaderView(profile: fixture.profile)
                    .accessibilityIdentifier("home.profile")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Your Pursuits")
                        .font(.title2.bold())
                    Text("The parts of life you’re choosing to grow.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVStack(spacing: 14) {
                    ForEach(fixture.pursuits) { pursuit in
                        if pursuit.kind == .golf {
                            Button(action: openGolf) {
                                PursuitTileView(pursuit: pursuit, isAvailable: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("pursuit.golf.open")
                            .accessibilityHint("Opens Golf Overview")
                        } else {
                            PursuitTileView(pursuit: pursuit, isAvailable: false)
                                .accessibilityIdentifier("pursuit.\(pursuit.kind.rawValue).planned")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Mosaic Home")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProfileHeaderView: View {
    let profile: MosaicProfileFixture

    var body: some View {
        HStack(spacing: 16) {
            Text(profile.initials)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.green.gradient, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.title3.bold())
                Text(profile.headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PursuitTileView: View {
    let pursuit: PursuitSummary
    let isAvailable: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: pursuit.systemImage)
                .font(.title2)
                .foregroundStyle(isAvailable ? .white : .secondary)
                .frame(width: 48, height: 48)
                .background(isAvailable ? Color.green.gradient : Color.secondary.opacity(0.12).gradient,
                            in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(pursuit.title)
                    .font(.headline)
                Text(pursuit.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isAvailable {
                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else {
                Text("Planned")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        PursuitsHomeView(fixture: MosaicHomeFixtures.iteration0A, openGolf: {})
    }
}

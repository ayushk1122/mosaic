import SwiftUI

enum MosaicAuthMethod: String, CaseIterable, Identifiable {
    case google
    case apple
    case email
    case phone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: "Google"
        case .apple: "Apple"
        case .email: "Email"
        case .phone: "Phone"
        }
    }

    var systemImage: String {
        switch self {
        case .google: "g.circle.fill"
        case .apple: "apple.logo"
        case .email: "envelope.fill"
        case .phone: "phone.fill"
        }
    }

    /// Google has no SF Symbol; render a styled monogram instead.
    var usesMonogram: Bool { self == .google }
}

struct MosaicAuthField: View {
    var title: String
    var prompt: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var isSecure = false
    var identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MosaicBrand.inkBlack.opacity(0.72))
            Group {
                if isSecure {
                    SecureField(prompt, text: $text)
                } else {
                    TextField(prompt, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .foregroundStyle(MosaicBrand.inkBlack)
            .tint(MosaicBrand.inkBlack)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MosaicBrand.inkBlack.opacity(0.12), lineWidth: 1)
            )
            .accessibilityIdentifier(identifier)
        }
    }
}

struct MosaicAuthSocialRow: View {
    var methods: [MosaicAuthMethod]
    var action: (MosaicAuthMethod) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Or continue with")
                .font(.footnote)
                .foregroundStyle(MosaicBrand.inkBlack.opacity(0.55))
            HStack(spacing: 20) {
                ForEach(methods) { method in
                    Button {
                        action(method)
                    } label: {
                        MosaicAuthSocialIcon(method: method)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(method.title)
                    .accessibilityIdentifier("account.social.\(method.rawValue)")
                }
            }
        }
    }
}

private struct MosaicAuthSocialIcon: View {
    var method: MosaicAuthMethod

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.72))
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(MosaicBrand.inkBlack.opacity(0.08), lineWidth: 1))
            if method.usesMonogram {
                Text("G")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MosaicBrand.inkBlack)
            } else {
                Image(systemName: method.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MosaicBrand.inkBlack)
            }
        }
    }
}

struct MosaicAuthPrimaryButton: View {
    var title: String
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(MosaicBrand.inkBlack.opacity(disabled ? 0.35 : 1), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct MosaicAuthScreenChrome<Content: View>: View {
    var title: String
    var back: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    if let back {
                        Button(action: back) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(MosaicBrand.inkBlack)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)

                Image("MosaicWordmark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(MosaicBrand.inkBlack)
                    .frame(maxWidth: 160)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title.bold())
                    .foregroundStyle(MosaicBrand.inkBlack)

                content()
                    .padding(.horizontal, 28)
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MosaicBrand.cream.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .tint(MosaicBrand.inkBlack)
    }
}

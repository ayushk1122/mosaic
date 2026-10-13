import SwiftUI

struct MosaicSignInView: View {
    var account: MosaicAccount

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image("MosaicWordmark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(MosaicBrand.inkBlack)
                .frame(maxWidth: 240)
                .accessibilityHidden(true)
            Text("Sign in to keep your Mosaic.")
                .font(.body)
                .foregroundStyle(MosaicBrand.inkBlack.opacity(0.72))
            Button {
                account.signInWithGoogle()
            } label: {
                Text("Continue with Google")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 280)
                    .frame(height: 48)
                    .background(MosaicBrand.inkBlack, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("account.signIn")
            if let lastError = account.lastError {
                Text(lastError)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MosaicBrand.inkBlack.opacity(0.72))
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MosaicBrand.cream.ignoresSafeArea())
        .accessibilityIdentifier("account.screen")
    }
}

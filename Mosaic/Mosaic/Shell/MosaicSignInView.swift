import SwiftUI

struct MosaicSignInView: View {
    var account: MosaicAccount

    private enum Route: Equatable {
        case signIn
        case signUp
        case emailOTP(Bool)
        case emailCode(Bool, String)
        case phoneOTP(Bool)
        case phoneCode(Bool, String)
    }

    @State private var route = Route.signIn
    @State private var loginIdentifier = ""
    @State private var password = ""
    @State private var signUpEmail = ""
    @State private var otpEmail = ""
    @State private var otpPhone = ""
    @State private var code = ""
    @State private var busy = false
    @State private var resendAvailableAt: Date?
    @FocusState private var codeFocused: Bool

    private let signInSocial: [MosaicAuthMethod] = [.google, .apple, .email, .phone]
    private let signUpSocial: [MosaicAuthMethod] = [.google, .apple, .phone]

    var body: some View {
        Group {
            switch route {
            case .signIn:
                signInScreen
            case .signUp:
                signUpScreen
            case .emailOTP(let signUp):
                otpEntryScreen(
                    title: signUp ? "Sign up with email" : "Sign in with email",
                    prompt: "you@example.com",
                    text: $otpEmail,
                    keyboard: .emailAddress,
                    identifier: signUp ? "account.signUp.emailEntry" : "account.signIn.emailEntry",
                    back: { route = signUp ? .signUp : .signIn }
                ) {
                    Task { await sendEmailOTP(signUp: signUp) }
                }
            case .emailCode(let signUp, let address):
                otpCodeScreen(
                    title: "Check your email",
                    detail: "Enter the 6-digit code sent to \(address).",
                    back: { route = signUp ? .signUp : .emailOTP(false) }
                ) {
                    Task { await verifyEmailOTP(address, signUp: signUp) }
                } resend: {
                    Task { await sendEmailOTP(to: address, signUp: signUp) }
                }
            case .phoneOTP(let signUp):
                otpEntryScreen(
                    title: signUp ? "Sign up with phone" : "Sign in with phone",
                    prompt: "555 123 4567",
                    text: $otpPhone,
                    keyboard: .phonePad,
                    identifier: signUp ? "account.signUp.phoneEntry" : "account.signIn.phoneEntry",
                    back: { route = signUp ? .signUp : .signIn }
                ) {
                    Task { await sendPhoneOTP(signUp: signUp) }
                }
            case .phoneCode(let signUp, let number):
                otpCodeScreen(
                    title: "Check your messages",
                    detail: "Enter the 6-digit code sent to \(number).",
                    back: { route = .phoneOTP(signUp) }
                ) {
                    Task { await verifyPhoneOTP(number, signUp: signUp) }
                } resend: {
                    Task { await sendPhoneOTP(to: number, signUp: signUp) }
                }
            }
        }
        .accessibilityIdentifier("account.screen")
    }

    private var signInScreen: some View {
        MosaicAuthScreenChrome(title: "Sign in", back: nil) {
            VStack(spacing: 18) {
                MosaicAuthField(
                    title: "Email or username",
                    prompt: "you@example.com",
                    text: $loginIdentifier,
                    keyboard: .emailAddress,
                    identifier: "account.signIn.identifier"
                )
                MosaicAuthField(
                    title: "Password",
                    prompt: "Password",
                    text: $password,
                    isSecure: true,
                    identifier: "account.signIn.password"
                )
                MosaicAuthPrimaryButton(title: "Sign in", disabled: busy || loginIdentifier.isEmpty || password.isEmpty) {
                    Task { await signInWithPassword() }
                }
                .accessibilityIdentifier("account.signIn.submit")

                MosaicAuthSocialRow(methods: signInSocial) { method in
                    handleSocial(method, signUp: false)
                }

                switchAuthFooter(
                    prompt: "New to Mosaic?",
                    action: "Sign up"
                ) {
                    account.clearLastError()
                    route = .signUp
                }

                if let lastError = account.lastError {
                    Text(lastError)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(MosaicBrand.inkBlack.opacity(0.72))
                }
            }
        }
    }

    private var signUpScreen: some View {
        MosaicAuthScreenChrome(title: "Sign up", back: { route = .signIn }) {
            VStack(spacing: 18) {
                MosaicAuthField(
                    title: "Email",
                    prompt: "you@example.com",
                    text: $signUpEmail,
                    keyboard: .emailAddress,
                    identifier: "account.signUp.email"
                )
                Text("We’ll send a code to confirm it’s you. You’ll choose a username and password next.")
                    .font(.footnote)
                    .foregroundStyle(MosaicBrand.inkBlack.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)

                MosaicAuthPrimaryButton(title: "Continue", disabled: busy || !signUpEmailValid) {
                    Task { await sendEmailOTP(to: normalizedSignUpEmail, signUp: true) }
                }
                .accessibilityIdentifier("account.signUp.submit")

                MosaicAuthSocialRow(methods: signUpSocial) { method in
                    handleSocial(method, signUp: true)
                }

                switchAuthFooter(
                    prompt: "Already have an account?",
                    action: "Sign in"
                ) {
                    account.clearLastError()
                    route = .signIn
                }

                if let lastError = account.lastError {
                    Text(lastError)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(MosaicBrand.inkBlack.opacity(0.72))
                }
            }
        }
    }

    private var normalizedSignUpEmail: String {
        signUpEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var signUpEmailValid: Bool {
        let email = normalizedSignUpEmail
        guard let at = email.firstIndex(of: "@") else { return false }
        return at != email.startIndex && email[at...].contains(".")
    }

    private func switchAuthFooter(prompt: String, action: String, handler: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(prompt)
            Button(action, action: handler)
                .fontWeight(.semibold)
        }
        .font(.footnote)
        .foregroundStyle(MosaicBrand.inkBlack.opacity(0.72))
        .padding(.top, 4)
    }

    private func handleSocial(_ method: MosaicAuthMethod, signUp: Bool) {
        account.clearLastError()
        switch method {
        case .google:
            account.signInWithGoogle()
        case .apple:
            account.signInWithApple()
        case .email:
            otpEmail = signUp ? signUpEmail : loginIdentifier
            route = .emailOTP(signUp)
        case .phone:
            route = .phoneOTP(signUp)
        }
    }

    private func signInWithPassword() async {
        busy = true
        defer { busy = false }
        _ = await account.signInWithPassword(identifier: loginIdentifier, password: password)
    }

    private func otpEntryScreen(
        title: String,
        prompt: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        identifier: String,
        back: @escaping () -> Void,
        send: @escaping () -> Void
    ) -> some View {
        MosaicAuthScreenChrome(title: title, back: back) {
            VStack(spacing: 18) {
                MosaicAuthField(
                    title: prompt.contains("@") ? "Email" : "Phone",
                    prompt: prompt,
                    text: text,
                    keyboard: keyboard,
                    identifier: identifier
                )
                MosaicAuthPrimaryButton(title: "Send code", disabled: busy || text.wrappedValue.isEmpty, action: send)
                if let lastError = account.lastError {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(MosaicBrand.inkBlack.opacity(0.72))
                }
            }
        }
    }

    private func otpCodeScreen(
        title: String,
        detail: String,
        back: @escaping () -> Void,
        verify: @escaping () -> Void,
        resend: @escaping () -> Void
    ) -> some View {
        MosaicAuthScreenChrome(title: title, back: back) {
            VStack(spacing: 18) {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(MosaicBrand.inkBlack.opacity(0.72))
                    .multilineTextAlignment(.center)
                TextField("123456", text: $code)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .focused($codeFocused)
                    .foregroundStyle(MosaicBrand.inkBlack)
                    .tint(MosaicBrand.inkBlack)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MosaicBrand.inkBlack.opacity(0.12), lineWidth: 1)
                    )
                    .accessibilityIdentifier("account.codeEntry")
                MosaicAuthPrimaryButton(title: "Verify", disabled: busy || code.count < 6, action: verify)
                if canResend {
                    Button("Resend code", action: resend)
                } else {
                    Text("Resend available in \(resendSeconds)s")
                        .font(.footnote)
                        .foregroundStyle(MosaicBrand.inkBlack.opacity(0.45))
                }
                if let lastError = account.lastError {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(MosaicBrand.inkBlack.opacity(0.72))
                }
            }
        }
        .onAppear { codeFocused = true }
    }

    private var canResend: Bool {
        guard let resendAvailableAt else { return true }
        return Date() >= resendAvailableAt
    }

    private var resendSeconds: Int {
        guard let resendAvailableAt else { return 0 }
        return max(0, Int(resendAvailableAt.timeIntervalSinceNow.rounded(.up)))
    }

    private func sendEmailOTP(signUp: Bool) async {
        let address = otpEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        await sendEmailOTP(to: address, signUp: signUp)
    }

    private func sendEmailOTP(to address: String, signUp: Bool) async {
        busy = true
        defer { busy = false }
        await account.sendEmailCode(address, createUser: signUp)
        guard account.lastError == nil else { return }
        code = ""
        resendAvailableAt = Date().addingTimeInterval(30)
        route = .emailCode(signUp, address)
    }

    private func verifyEmailOTP(_ address: String, signUp: Bool) async {
        busy = true
        defer { busy = false }
        _ = await account.verifyEmailCode(email: address, code: code)
        _ = signUp
    }

    private func sendPhoneOTP(signUp: Bool) async {
        guard let normalized = MosaicPhoneNumber.normalized(otpPhone) else {
            account.present("Enter a valid phone number.")
            return
        }
        await sendPhoneOTP(to: normalized, signUp: signUp)
    }

    private func sendPhoneOTP(to number: String, signUp: Bool) async {
        busy = true
        defer { busy = false }
        await account.sendPhoneCode(number, createUser: signUp)
        guard account.lastError == nil else { return }
        code = ""
        resendAvailableAt = Date().addingTimeInterval(30)
        route = .phoneCode(signUp, number)
    }

    private func verifyPhoneOTP(_ number: String, signUp: Bool) async {
        busy = true
        defer { busy = false }
        _ = await account.verifyPhoneCode(rawPhone: number, code: code)
        _ = signUp
    }
}

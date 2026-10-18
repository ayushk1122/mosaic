import SwiftUI

struct MosaicOnboardingView: View {
    var account: MosaicAccount
    var userID: UUID
    var onComplete: () -> Void

    /// Starts from what the server already holds, so a person can keep their default username.
    init(
        account: MosaicAccount,
        userID: UUID,
        existing: MosaicOnboardingStatus? = nil,
        onComplete: @escaping () -> Void
    ) {
        self.account = account
        self.userID = userID
        self.onComplete = onComplete
        _username = State(initialValue: existing?.username ?? "")
        _displayName = State(initialValue: existing?.displayName ?? "")
        if let birthday = existing?.birthday {
            _birthday = State(initialValue: birthday)
        }
    }

    private enum Step: Int, CaseIterable {
        case username
        case password
        case displayName
        case birthday
    }

    @State private var step = Step.username
    @State private var username = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    @State private var availability = MosaicOnboardingView.Availability.unknown
    @State private var busy = false
    @State private var problem = ""

    private enum Availability {
        case unknown
        case checking
        case available
        case taken
    }

    private enum Mark {
        case none
        case valid
        case invalid
        case busy
    }

    private let warning = Color(red: 1, green: 0.42, blue: 0.4)
    private let success = Color(red: 0.3, green: 0.85, blue: 0.45)

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            Image("MosaicWordmark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(MosaicBrand.inkBlack)
                .frame(maxWidth: 200)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(MosaicBrand.inkBlack)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(MosaicBrand.inkBlack.opacity(0.72))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 28)

            stepContent
                .padding(.horizontal, 28)

            if !problem.isEmpty {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(MosaicBrand.inkBlack.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            HStack(spacing: 12) {
                if step != .username {
                    Button("Back") { previousStep() }
                        .buttonStyle(.bordered)
                        .tint(MosaicBrand.inkBlack)
                        .foregroundStyle(MosaicBrand.inkBlack)
                }
                Button(primaryActionTitle) {
                    Task { await advance() }
                }
                .buttonStyle(.borderedProminent)
                .tint(MosaicBrand.inkBlack)
                .foregroundStyle(.white)
                .disabled(!canAdvance || busy)
            }
            .padding(.horizontal, 28)

            Button("Sign out") {
                Task { await account.signOut() }
            }
            .font(.footnote)
            .foregroundStyle(MosaicBrand.inkBlack.opacity(0.55))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MosaicBrand.cream.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .tint(MosaicBrand.inkBlack)
        .accessibilityIdentifier("onboarding.screen")
        .task(id: username) {
            guard step == .username else { return }
            await checkUsername()
        }
        .onChange(of: username) { _, typed in
            let cleaned = MosaicSettingsList.typedUsername(typed)
            if cleaned != typed {
                username = cleaned
            }
        }
        .onChange(of: displayName) { _, typed in
            if typed.count > MosaicSettingsList.displayNameLimit {
                displayName = String(typed.prefix(MosaicSettingsList.displayNameLimit))
            }
        }
    }

    private var title: String {
        switch step {
        case .username: "Choose a username"
        case .password: "Set a password"
        case .displayName: "Add a display name"
        case .birthday: "When’s your birthday?"
        }
    }

    private var subtitle: String {
        switch step {
        case .username: "This is how people find you on Mosaic."
        case .password: "You’ll be able to sign in with @\(cleanedUsername.isEmpty ? "username" : cleanedUsername) and this password anytime."
        case .displayName: "Shown on your profile and visits."
        case .birthday: ""
        }
    }

    private var primaryActionTitle: String {
        step == .birthday ? "Finish" : "Continue"
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .username:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    HStack(spacing: 1) {
                        Text("@")
                            .foregroundStyle(MosaicBrand.inkBlack.opacity(0.55))
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(MosaicBrand.inkBlack)
                            .tint(MosaicBrand.inkBlack)
                    }
                    .font(.body)

                    markView(usernameMark)
                        .frame(width: 24, height: 24)
                        .accessibilityIdentifier("onboarding.usernameMark")
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MosaicBrand.inkBlack.opacity(0.12), lineWidth: 1)
                )
                .animation(.easeOut(duration: 0.15), value: usernameMark)
                .accessibilityIdentifier("onboarding.username")

                if !usernameAdvice.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(usernameAdvice, id: \.self) { advice in
                            Label {
                                Text(advice)
                            } icon: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.bold))
                            }
                            .font(.footnote)
                            .foregroundStyle(warning)
                        }
                    }
                    .accessibilityIdentifier("onboarding.usernameAdvice")
                }
            }
            .animation(.easeOut(duration: 0.15), value: usernameAdvice)
        case .password:
            SecureField("At least 6 characters", text: $password)
                .foregroundStyle(MosaicBrand.inkBlack)
                .tint(MosaicBrand.inkBlack)
                .textContentType(.newPassword)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MosaicBrand.inkBlack.opacity(0.12), lineWidth: 1)
                )
                .accessibilityIdentifier("onboarding.password")
        case .displayName:
            TextField("Display name", text: $displayName)
                .foregroundStyle(MosaicBrand.inkBlack)
                .tint(MosaicBrand.inkBlack)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MosaicBrand.inkBlack.opacity(0.12), lineWidth: 1)
                )
                .accessibilityIdentifier("onboarding.displayName")
        case .birthday:
            MosaicBirthdayPicker(
                date: $birthday,
                accessibilityIdentifier: "onboarding.birthday"
            )
            .tint(MosaicBrand.inkBlack)
            .colorScheme(.light)
        }
    }

    private var cleanedUsername: String {
        MosaicSettingsList.username(from: username)
    }

    /// Same rule messages as Settings (success is the in-field checkmark, not copy).
    private var usernameProblems: [String] {
        MosaicSettingsList.usernameProblems(username)
    }

    private var usernameAdvice: [String] {
        if !usernameProblems.isEmpty { return usernameProblems }
        if availability == .taken { return ["@\(username) is taken."] }
        return []
    }

    private var usernameMark: Mark {
        if username.isEmpty { return .none }
        if availability == .checking { return .busy }
        if !usernameProblems.isEmpty || availability == .taken { return .invalid }
        return availability == .available ? .valid : .none
    }

    @ViewBuilder
    private func markView(_ mark: Mark) -> some View {
        switch mark {
        case .none:
            Color.clear
        case .busy:
            ProgressView()
                .controlSize(.small)
                .tint(MosaicBrand.inkBlack.opacity(0.55))
        case .valid:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(success)
                .accessibilityLabel("Valid")
        case .invalid:
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(warning)
                .accessibilityLabel("Not valid yet")
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .username:
            usernameProblems.isEmpty && availability == .available
        case .password:
            password.count >= 6
        case .displayName:
            !MosaicSettingsList.displayName(from: displayName).isEmpty
        case .birthday:
            birthday < Calendar.current.startOfDay(for: .now)
        }
    }

    private func previousStep() {
        problem = ""
        if let prior = Step(rawValue: step.rawValue - 1) {
            step = prior
        }
    }

    private func advance() async {
        problem = ""
        switch step {
        case .username:
            await checkUsername()
            if canAdvance, let next = Step(rawValue: step.rawValue + 1) {
                step = next
            }
        case .password, .displayName:
            if let next = Step(rawValue: step.rawValue + 1) {
                step = next
            }
        case .birthday:
            await finish()
        }
    }

    /// Mirrors Settings: debounce, then availability against the live typed username.
    private func checkUsername() async {
        let name = username
        guard MosaicSettingsList.usernameProblems(name).isEmpty else {
            availability = .unknown
            return
        }
        availability = .checking
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled,
              let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken()
        else {
            if !Task.isCancelled {
                problem = "Check your connection and try again."
                availability = .unknown
            }
            return
        }
        let available = try? await MosaicSettingsClient(config: config)
            .isUsernameAvailable(name, userID: userID, accessToken: token)
        guard !Task.isCancelled, name == username else { return }
        switch available {
        case true?: availability = .available
        case false?: availability = .taken
        case nil:
            availability = .unknown
            problem = "Couldn’t check that username."
        }
    }

    private func finish() async {
        guard let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken(),
              account.session?.userID == userID
        else {
            problem = "Check your connection and try again."
            return
        }
        busy = true
        defer { busy = false }
        guard await account.setPassword(password) else {
            step = .password
            problem = account.lastError ?? "Couldn’t save your password. Try again."
            return
        }
        let client = MosaicOnboardingClient(config: config)
        do {
            try await client.complete(
                username: cleanedUsername,
                displayName: MosaicSettingsList.displayName(from: displayName),
                birthday: birthday,
                accessToken: token
            )
            MosaicOnboardingCache.markComplete(userID)
            onComplete()
        } catch MosaicOnboardingError.usernameTaken {
            step = .username
            availability = .taken
            problem = "@\(cleanedUsername) was just taken. Pick another."
        } catch {
            problem = "Couldn’t save your profile. Try again."
        }
    }
}

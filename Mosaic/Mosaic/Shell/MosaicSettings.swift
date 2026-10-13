import SwiftUI

struct MosaicRemoteBoard: Equatable, Sendable {
    var id: UUID
    var role: String
    var title: String
    var isPublic: Bool
}

struct MosaicVisibilityRow: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var isPublic: Bool
    /// False until the board has a row on the server.
    var canChange: Bool
}

enum MosaicSettingsList {
    static let displayNameLimit = 40

    static func displayName(from raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(displayNameLimit))
    }

    /// Drops a leading @ and lowercases. The server only stores lowercase usernames.
    static func username(from raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix("@") {
            name.removeFirst()
        }
        return name.lowercased()
    }

    /// Cleans the field while typing, so capitals and a leading @ never count against the rule.
    static func typedUsername(_ raw: String) -> String {
        var name = raw.lowercased()
        while name.hasPrefix("@") {
            name.removeFirst()
        }
        return name
    }

    /// Every part of the server rule (3 to 20 lowercase letters, numbers, or underscores) the name still misses.
    static func usernameProblems(_ name: String) -> [String] {
        var problems: [String] = []
        if name.count < 3 {
            problems.append("Use at least 3 characters.")
        }
        if name.count > 20 {
            problems.append("Use 20 characters or fewer.")
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
        if !name.allSatisfy({ allowed.contains($0) }) {
            problems.append("Use only letters, numbers, and underscores.")
        }
        return problems
    }

    static func rows(
        snapshot: ComposerSnapshot,
        remote: [MosaicRemoteBoard]
    ) -> (mosaic: MosaicVisibilityRow?, pursuits: [MosaicVisibilityRow]) {
        let remoteMosaic = remote.first { $0.role == "mosaic" }
        let mosaicTitle = snapshot.mosaicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let mosaic = MosaicVisibilityRow(
            id: remoteMosaic?.id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID(),
            title: mosaicTitle.isEmpty ? "Mosaic" : mosaicTitle,
            isPublic: remoteMosaic?.isPublic ?? false,
            canChange: remoteMosaic != nil
        )

        var used: Set<UUID> = []
        var pursuits: [MosaicVisibilityRow] = []
        for pursuit in snapshot.pursuits where pursuit.role == .pursuit {
            guard let id = ComposerBoardSync.uuid(pursuit.id) else { continue }
            used.insert(id)
            let remoteMatch = remote.first { $0.id == id && $0.role == "pursuit" }
            let title = pursuit.title.trimmingCharacters(in: .whitespacesAndNewlines)
            pursuits.append(
                MosaicVisibilityRow(
                    id: id,
                    title: title.isEmpty ? "Pursuit" : title,
                    isPublic: remoteMatch?.isPublic ?? false,
                    canChange: remoteMatch != nil
                )
            )
        }
        for board in remote where board.role == "pursuit" && !used.contains(board.id) {
            let title = board.title.trimmingCharacters(in: .whitespacesAndNewlines)
            pursuits.append(
                MosaicVisibilityRow(
                    id: board.id,
                    title: title.isEmpty ? "Pursuit" : title,
                    isPublic: board.isPublic,
                    canChange: true
                )
            )
        }
        return (mosaic, pursuits)
    }
}

enum MosaicUsernameError: Error, Equatable {
    case taken
    case failed
}

struct MosaicSettingsClient: Sendable {
    var config: SupabaseSyncConfig
    var session: URLSession = .shared

    func saveUsername(_ name: String, userID: UUID, accessToken: String) async throws {
        let url = Self.profileURL(base: config.url, userID: userID)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["username": name])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MosaicUsernameError.failed }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.usernameError(status: http.statusCode, body: data)
        }
    }

    func isUsernameAvailable(_ name: String, userID: UUID, accessToken: String) async throws -> Bool {
        let rows = try await get(
            url: Self.usernameURL(base: config.url, username: name),
            accessToken: accessToken
        )
        let mine = userID.uuidString.lowercased()
        return rows.allSatisfy { ($0["id"] as? String)?.lowercased() == mine }
    }

    static func usernameURL(base: URL, username: String) -> URL {
        var components = URLComponents(url: base.appending(path: "rest/v1/profiles"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "username", value: "eq.\(username)"),
            URLQueryItem(name: "select", value: "id")
        ]
        return components?.url ?? base
    }

    static func usernameError(status: Int, body: Data) -> MosaicUsernameError {
        let message = String(data: body, encoding: .utf8) ?? ""
        if status == 409 || message.contains("23505") {
            return .taken
        }
        return .failed
    }

    func loadProfile(userID: UUID, accessToken: String) async throws -> (username: String, displayName: String) {
        let rows = try await get(
            url: Self.profileURL(base: config.url, userID: userID),
            accessToken: accessToken
        )
        guard let row = rows.first else { throw SupabaseDocumentSyncError.unexpectedResponse }
        let username = row["username"] as? String ?? ""
        let displayName = row["display_name"] as? String ?? ""
        return (username, displayName)
    }

    func saveDisplayName(_ name: String, userID: UUID, accessToken: String) async throws {
        let url = Self.profileURL(base: config.url, userID: userID)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let stored: Any = name.isEmpty ? NSNull() : name
        request.httpBody = try JSONSerialization.data(withJSONObject: ["display_name": stored])
        try await send(request)
    }

    func loadBoards(userID: UUID, accessToken: String) async throws -> [MosaicRemoteBoard] {
        let rows = try await get(
            url: Self.boardsURL(base: config.url, userID: userID),
            accessToken: accessToken
        )
        return rows.compactMap { row in
            guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let role = row["role"] as? String
            else { return nil }
            return MosaicRemoteBoard(
                id: id,
                role: role,
                title: row["title"] as? String ?? "",
                isPublic: (row["visibility"] as? String) == "public"
            )
        }
    }

    func setVisibility(id: UUID, isPublic: Bool, accessToken: String) async throws {
        let endpoint = config.url
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("rpc")
            .appendingPathComponent("set_document_visibility")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "p_id": id.uuidString.lowercased(),
            "p_visibility": isPublic ? "public" : "private"
        ])
        try await send(request)
    }

    static func profileURL(base: URL, userID: UUID) -> URL {
        var components = URLComponents(url: base.appending(path: "rest/v1/profiles"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "select", value: "username,display_name")
        ]
        return components?.url ?? base
    }

    static func boardsURL(base: URL, userID: UUID) -> URL {
        var components = URLComponents(url: base.appending(path: "rest/v1/documents"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "owner_id", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "role", value: "in.(mosaic,pursuit)"),
            URLQueryItem(name: "select", value: "id,role,title,visibility")
        ]
        return components?.url ?? base
    }

    private func get(url: URL, accessToken: String) async throws -> [[String: Any]] {
        var request = URLRequest(url: url)
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let data = try await send(request)
        let json = try JSONSerialization.jsonObject(with: data)
        return json as? [[String: Any]] ?? []
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SupabaseDocumentSyncError.requestFailed
        }
        return data
    }
}

struct MosaicSettingsView: View {
    var account: MosaicAccount
    var store: ComposerStore

    @Environment(\.dismiss) private var dismiss
    private enum EditField: Hashable {
        case username
        case displayName
    }

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

    @State private var username = ""
    @State private var savedUsername = ""
    @State private var usernameMessage = ""
    @State private var availability = Availability.unknown
    @State private var displayName = ""
    @State private var savedDisplayName = ""
    @State private var mosaic: MosaicVisibilityRow?
    @State private var pursuits: [MosaicVisibilityRow] = []
    @State private var status = ""
    @State private var saving: EditField?
    @State private var confirmsLogOut = false
    @State private var didLoad = false
    @State private var profileLoaded = false
    @FocusState private var focused: EditField?

    private let field = Color.white.opacity(0.08)
    private let muted = Color.white.opacity(0.55)
    private let warning = Color(red: 1, green: 0.42, blue: 0.4)
    private let success = Color(red: 0.3, green: 0.85, blue: 0.45)

    private var usernameProblems: [String] {
        guard profileLoaded else { return [] }
        return MosaicSettingsList.usernameProblems(username)
    }

    private var usernameAdvice: [String] {
        if !usernameProblems.isEmpty { return usernameProblems }
        if availability == .taken { return ["@\(username) is taken."] }
        if !usernameMessage.isEmpty { return [usernameMessage] }
        return []
    }

    private var usernameMark: Mark {
        guard profileLoaded else { return .none }
        if saving == .username || availability == .checking { return .busy }
        if !usernameProblems.isEmpty || availability == .taken { return .invalid }
        return availability == .available ? .valid : .none
    }

    private var displayNameMark: Mark {
        guard profileLoaded else { return .none }
        if saving == .displayName { return .busy }
        return MosaicSettingsList.displayName(from: displayName).isEmpty ? .none : .valid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    let open = focused
                    focused = nil
                    if let open {
                        Task { await commit(open) }
                    }
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text("Settings")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Username")
                        textRow(
                            .username,
                            text: $username,
                            prompt: "username",
                            prefix: "@",
                            mark: usernameMark
                        )
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
                            .accessibilityIdentifier("settings.usernameAdvice")
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: usernameAdvice)

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Display name")
                        textRow(
                            .displayName,
                            text: $displayName,
                            prompt: "Add a display name",
                            prefix: nil,
                            mark: displayNameMark
                        )
                    }

                    if let mosaic {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("Mosaic")
                            visibilityRow(mosaic, kind: "Mosaic") { isPublic in
                                Task { await setMosaicPublic(isPublic) }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Pursuits")
                        if pursuits.isEmpty {
                            Text("Pursuits you add will show up here.")
                                .font(.footnote)
                                .foregroundStyle(muted)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(pursuits) { pursuit in
                                    visibilityRow(pursuit, kind: "Pursuit") { isPublic in
                                        Task { await setPursuit(pursuit.id, isPublic: isPublic) }
                                    }
                                }
                            }
                        }
                    }

                    if !status.isEmpty {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(muted)
                    }

                    Button {
                        confirmsLogOut = true
                    } label: {
                        Text("Log out")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.4))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .accessibilityIdentifier("settings.logOut")
                    .confirmationDialog("Log out of Mosaic?", isPresented: $confirmsLogOut, titleVisibility: .visible) {
                        Button("Log out", role: .destructive) {
                            Task {
                                dismiss()
                                await account.signOut()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { focused = nil }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MosaicBrand.inkBlack.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("settings.screen")
        .task { await load() }
        .task(id: username) { await checkUsername() }
        .onChange(of: username) { _, typed in
            let cleaned = MosaicSettingsList.typedUsername(typed)
            if cleaned != typed {
                username = cleaned
            }
            usernameMessage = ""
        }
        .onChange(of: displayName) { _, typed in
            if typed.count > MosaicSettingsList.displayNameLimit {
                displayName = String(typed.prefix(MosaicSettingsList.displayNameLimit))
            }
        }
        .onChange(of: focused) { previous, _ in
            if let previous {
                Task { await commit(previous) }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.white)
    }

    private func textRow(
        _ which: EditField,
        text: Binding<String>,
        prompt: String,
        prefix: String?,
        mark: Mark
    ) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 1) {
                if let prefix {
                    Text(prefix)
                        .foregroundStyle(muted)
                }
                TextField("", text: text, prompt: Text(prompt).foregroundStyle(muted))
                    .textInputAutocapitalization(which == .username ? .never : .words)
                    .autocorrectionDisabled(which == .username)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($focused, equals: which)
                    .submitLabel(.done)
                    .onSubmit { focused = nil }
                    .accessibilityIdentifier(which == .username ? "settings.username" : "settings.displayName")
            }
            .font(.body)

            markView(mark)
                .frame(width: 24, height: 24)
                .accessibilityIdentifier(which == .username ? "settings.usernameMark" : "settings.displayNameMark")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { focused = which }
        .animation(.easeOut(duration: 0.15), value: mark)
    }

    @ViewBuilder
    private func markView(_ mark: Mark) -> some View {
        switch mark {
        case .none:
            Color.clear
        case .busy:
            ProgressView()
                .controlSize(.small)
                .tint(muted)
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

    private func visibilityRow(
        _ row: MosaicVisibilityRow,
        kind: String,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(isOn: Binding(
            get: { row.isPublic },
            set: { onChange($0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .foregroundStyle(.white)
                Text(row.canChange ? (row.isPublic ? "Public" : "Private") : "Waiting to sync")
                    .font(.footnote)
                    .foregroundStyle(muted)
            }
        }
        .tint(.green)
        .disabled(!row.canChange)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("\(kind) \(row.title)")
    }

    private func commit(_ which: EditField) async {
        guard profileLoaded, saving != which else { return }
        switch which {
        case .displayName:
            let name = MosaicSettingsList.displayName(from: displayName)
            guard name != savedDisplayName else {
                displayName = savedDisplayName
                return
            }
            await saveName()
        case .username:
            let name = MosaicSettingsList.username(from: username)
            guard name != savedUsername,
                  MosaicSettingsList.usernameProblems(name).isEmpty,
                  availability != .taken
            else { return }
            await saveUsername(name)
        }
    }

    private func checkUsername() async {
        let name = username
        guard profileLoaded, MosaicSettingsList.usernameProblems(name).isEmpty else {
            availability = .unknown
            return
        }
        guard name != savedUsername else {
            availability = .available
            return
        }
        availability = .checking
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled,
              let config = SupabaseSyncConfig.current(),
              let userID = account.session?.userID,
              let token = await account.accessToken()
        else { return }
        let available = try? await MosaicSettingsClient(config: config)
            .isUsernameAvailable(name, userID: userID, accessToken: token)
        guard !Task.isCancelled, name == username else { return }
        switch available {
        case true?: availability = .available
        case false?: availability = .taken
        case nil: availability = .unknown
        }
    }

    private func saveUsername(_ name: String) async {
        saving = .username
        defer { saving = nil }
        guard let config = SupabaseSyncConfig.current(),
              let userID = account.session?.userID,
              let token = await account.accessToken()
        else { return }
        do {
            try await MosaicSettingsClient(config: config).saveUsername(name, userID: userID, accessToken: token)
            savedUsername = name
            usernameMessage = ""
            if username == name {
                availability = .available
            }
        } catch MosaicUsernameError.taken {
            if username == name {
                availability = .taken
            }
        } catch {
            usernameMessage = "The username could not be saved."
        }
    }

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        guard let config = SupabaseSyncConfig.current(),
              let userID = account.session?.userID,
              let token = await account.accessToken()
        else {
            status = "Settings are available after you sign in."
            return
        }
        let client = MosaicSettingsClient(config: config)
        do {
            let profile = try await client.loadProfile(userID: userID, accessToken: token)
            username = profile.username
            savedUsername = profile.username
            let name = MosaicSettingsList.displayName(from: profile.displayName)
            displayName = name
            savedDisplayName = name
            profileLoaded = true
            availability = .available
            let remote = try await client.loadBoards(userID: userID, accessToken: token)
            let listed = MosaicSettingsList.rows(snapshot: store.snapshot, remote: remote)
            mosaic = listed.mosaic
            pursuits = listed.pursuits
        } catch {
            status = "Settings could not be loaded."
        }
    }

    private func saveName() async {
        let name = MosaicSettingsList.displayName(from: displayName)
        displayName = name
        saving = .displayName
        defer { saving = nil }
        guard let config = SupabaseSyncConfig.current(),
              let userID = account.session?.userID,
              let token = await account.accessToken()
        else { return }
        do {
            try await MosaicSettingsClient(config: config).saveDisplayName(name, userID: userID, accessToken: token)
            savedDisplayName = name
            status = ""
        } catch {
            displayName = savedDisplayName
            status = "The display name could not be saved."
        }
    }

    private func setMosaicPublic(_ isPublic: Bool) async {
        guard var mosaic else { return }
        let previous = mosaic.isPublic
        mosaic.isPublic = isPublic
        self.mosaic = mosaic
        guard await applyVisibility(id: mosaic.id, isPublic: isPublic) else {
            mosaic.isPublic = previous
            self.mosaic = mosaic
            return
        }
    }

    private func setPursuit(_ id: UUID, isPublic: Bool) async {
        guard let index = pursuits.firstIndex(where: { $0.id == id }) else { return }
        let previous = pursuits[index].isPublic
        pursuits[index].isPublic = isPublic
        guard await applyVisibility(id: id, isPublic: isPublic) else {
            pursuits[index].isPublic = previous
            return
        }
    }

    private func applyVisibility(id: UUID, isPublic: Bool) async -> Bool {
        guard let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken()
        else { return false }
        do {
            try await MosaicSettingsClient(config: config).setVisibility(id: id, isPublic: isPublic, accessToken: token)
            status = ""
            return true
        } catch {
            status = "That privacy setting could not be saved."
            return false
        }
    }
}

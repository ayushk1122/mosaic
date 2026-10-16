import PhotosUI
import SwiftUI
import UIKit

/// Who can see a board. The Mosaic uses only public and private.
enum MosaicVisibilityLevel: String, CaseIterable, Identifiable, Sendable {
    case `public`
    case `private`
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .public: "Public"
        case .private: "Private"
        case .hidden: "Hidden"
        }
    }

    static func parse(_ raw: String?, role: String) -> MosaicVisibilityLevel {
        if let raw, let level = MosaicVisibilityLevel(rawValue: raw) {
            return level
        }
        return role == "mosaic" ? .private : .hidden
    }
}

struct MosaicRemoteBoard: Equatable, Sendable {
    var id: UUID
    var role: String
    var title: String
    var level: MosaicVisibilityLevel
}

struct MosaicVisibilityRow: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var level: MosaicVisibilityLevel
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
            level: remoteMosaic?.level ?? .private,
            canChange: remoteMosaic != nil
        )

        var used: Set<UUID> = []
        var pursuits: [MosaicVisibilityRow] = []
        for pursuit in snapshot.pursuits where pursuit.role == .pursuit {
            guard let id = ComposerBoardSync.uuid(pursuit.id) else { continue }
            used.insert(id)
            let remoteMatch = remote.first { $0.id == id && $0.role == "pursuit" }
            let title = ComposerTitle.singleLine(pursuit.title)
            pursuits.append(
                MosaicVisibilityRow(
                    id: id,
                    title: title.isEmpty ? "Pursuit" : title,
                    level: remoteMatch?.level ?? .hidden,
                    canChange: remoteMatch != nil
                )
            )
        }
        for board in remote where board.role == "pursuit" && !used.contains(board.id) {
            let title = ComposerTitle.singleLine(board.title)
            pursuits.append(
                MosaicVisibilityRow(
                    id: board.id,
                    title: title.isEmpty ? "Pursuit" : title,
                    level: board.level,
                    canChange: true
                )
            )
        }
        return (mosaic, pursuits)
    }

    /// The server's level for each board that can be changed, to compare unsaved choices against.
    static func savedLevels(_ rows: [MosaicVisibilityRow]) -> [UUID: MosaicVisibilityLevel] {
        var levels: [UUID: MosaicVisibilityLevel] = [:]
        for row in rows where row.canChange {
            levels[row.id] = row.level
        }
        return levels
    }

    /// Privacy choices made since the last save.
    static func changedLevels(
        _ rows: [MosaicVisibilityRow],
        saved: [UUID: MosaicVisibilityLevel]
    ) -> [MosaicVisibilityRow] {
        rows.filter { row in
            guard row.canChange, let level = saved[row.id] else { return false }
            return level != row.level
        }
    }
}

enum MosaicAvatar {
    static let side: CGFloat = 512

    static func path(userID: UUID, pictureID: UUID) -> String {
        "\(userID.uuidString.lowercased())/\(pictureID.uuidString.lowercased()).jpg"
    }

    static let maxZoom: CGFloat = 4

    /// `pan` is how far the photo's center sits from the circle's center, in circle diameters.
    /// The photo always covers the circle, so the pan is held to what the zoom leaves room for.
    static func clampedPan(_ pan: CGSize, imageSize: CGSize, zoom: CGFloat) -> CGSize {
        let short = min(imageSize.width, imageSize.height)
        guard short > 0 else { return .zero }
        let roomX = max(0, (imageSize.width / short * zoom - 1) / 2)
        let roomY = max(0, (imageSize.height / short * zoom - 1) / 2)
        return CGSize(width: min(max(pan.width, -roomX), roomX), height: min(max(pan.height, -roomY), roomY))
    }

    /// The square of the photo, in its own points, that shows inside the circle.
    static func cropRect(imageSize: CGSize, zoom: CGFloat, pan: CGSize) -> CGRect {
        let short = min(imageSize.width, imageSize.height)
        let zoom = min(max(zoom, 1), maxZoom)
        let pan = clampedPan(pan, imageSize: imageSize, zoom: zoom)
        let crop = short / zoom
        let center = CGPoint(x: imageSize.width / 2 - pan.width * crop, y: imageSize.height / 2 - pan.height * crop)
        return CGRect(x: center.x - crop / 2, y: center.y - crop / 2, width: crop, height: crop)
    }

    /// The framed square, 512 points on a side, as JPEG. With no zoom or pan it is the center square.
    static func jpeg(from image: UIImage, zoom: CGFloat = 1, pan: CGSize = .zero) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let crop = cropRect(imageSize: size, zoom: zoom, pan: pan)
        let scale = side / crop.width
        let drawRect = CGRect(x: -crop.minX * scale, y: -crop.minY * scale,
                              width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: drawRect)
        }
        return rendered.jpegData(compressionQuality: 0.85)
    }
}

/// Frames a new profile picture: drag to move it and pinch to zoom inside the circle.
struct MosaicAvatarCropper: View {
    let image: UIImage
    var onCancel: () -> Void
    var onSave: (Data) -> Void

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var dragStart: CGSize?
    @State private var pinchStart: CGFloat?

    private let circle: CGFloat = 280

    private var displaySize: CGSize {
        let short = max(min(image.size.width, image.size.height), 1)
        return CGSize(width: image.size.width / short * circle * zoom, height: image.size.height / short * circle * zoom)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Move and scale")
                    .font(.headline)
                HStack {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("settings.avatarCropCancel")
                    Spacer()
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Spacer(minLength: 0)
            // The photo is drawn in overlays so its size, which grows with zoom, never widens the screen.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: circle + 120)
                .overlay {
                    photo
                        .opacity(0.3)
                }
                .overlay {
                    photo
                        .frame(width: circle, height: circle)
                        .clipShape(Circle())
                }
                .overlay {
                    Circle()
                        .stroke(.white, lineWidth: 2)
                        .frame(width: circle, height: circle)
                }
                .clipped()
                .contentShape(Rectangle())
                .gesture(drag.simultaneously(with: pinch))
                .accessibilityElement()
                .accessibilityLabel("Profile picture framing")
            Spacer(minLength: 0)

            Button {
                if let jpeg = MosaicAvatar.jpeg(from: image, zoom: zoom, pan: pan) {
                    onSave(jpeg)
                }
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(MosaicBrand.inkBlack)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .accessibilityIdentifier("settings.avatarCropDone")
        }
        .background(MosaicBrand.inkBlack.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private var photo: some View {
        Image(uiImage: image)
            .resizable()
            .frame(width: displaySize.width, height: displaySize.height)
            .offset(x: pan.width * circle, y: pan.height * circle)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? pan
                dragStart = start
                let moved = CGSize(width: start.width + value.translation.width / circle,
                                   height: start.height + value.translation.height / circle)
                pan = MosaicAvatar.clampedPan(moved, imageSize: image.size, zoom: zoom)
            }
            .onEnded { _ in dragStart = nil }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? zoom
                pinchStart = start
                zoom = min(max(start * value.magnification, 1), MosaicAvatar.maxZoom)
                pan = MosaicAvatar.clampedPan(pan, imageSize: image.size, zoom: zoom)
            }
            .onEnded { _ in pinchStart = nil }
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

    func loadProfile(
        userID: UUID,
        accessToken: String
    ) async throws -> (username: String, displayName: String, avatarPath: String?) {
        let rows = try await get(
            url: Self.profileURL(base: config.url, userID: userID),
            accessToken: accessToken
        )
        guard let row = rows.first else { throw SupabaseDocumentSyncError.unexpectedResponse }
        let username = row["username"] as? String ?? ""
        let displayName = row["display_name"] as? String ?? ""
        return (username, displayName, row["avatar_path"] as? String)
    }

    /// Uploads a new picture, points the profile at it, then removes the old one.
    func saveAvatar(_ jpeg: Data, replacing old: String?, userID: UUID, accessToken: String) async throws -> String {
        let path = MosaicAvatar.path(userID: userID, pictureID: UUID())
        var upload = URLRequest(url: Self.avatarObjectURL(base: config.url, path: path))
        upload.httpMethod = "POST"
        upload.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        upload.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        upload.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        upload.httpBody = jpeg
        try await send(upload)

        var patch = URLRequest(url: Self.profileURL(base: config.url, userID: userID))
        patch.httpMethod = "PATCH"
        patch.setValue("application/json", forHTTPHeaderField: "Content-Type")
        patch.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        patch.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        patch.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        patch.httpBody = try JSONSerialization.data(withJSONObject: ["avatar_path": path])
        try await send(patch)

        if let old, old != path {
            var remove = URLRequest(url: Self.avatarObjectURL(base: config.url, path: old))
            remove.httpMethod = "DELETE"
            remove.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            remove.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await session.data(for: remove)
        }
        return path
    }

    func loadAvatar(path: String, accessToken: String) async throws -> Data {
        var request = URLRequest(url: Self.avatarReadURL(base: config.url, path: path))
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    static func avatarObjectURL(base: URL, path: String) -> URL {
        base.appending(path: "storage/v1/object/avatars/\(path)")
    }

    static func avatarReadURL(base: URL, path: String) -> URL {
        base.appending(path: "storage/v1/object/authenticated/avatars/\(path)")
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
                level: MosaicVisibilityLevel.parse(row["visibility"] as? String, role: role)
            )
        }
    }

    func setVisibility(id: UUID, level: MosaicVisibilityLevel, accessToken: String) async throws {
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
            "p_visibility": level.rawValue
        ])
        try await send(request)
    }

    static func profileURL(base: URL, userID: UUID) -> URL {
        var components = URLComponents(url: base.appending(path: "rest/v1/profiles"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "select", value: "username,display_name,avatar_path")
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
    @Environment(ComposerRemoteSync.self) private var remoteSync: ComposerRemoteSync?

    private struct AvatarCrop: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    private enum SaveState {
        case idle
        case saving
    }

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
    @Environment(MosaicPursuitPrivacy.self) private var pursuitPrivacy: MosaicPursuitPrivacy?
    @State private var mosaic: MosaicVisibilityRow?
    @State private var pursuits: [MosaicVisibilityRow] = []
    @State private var savedLevels: [UUID: MosaicVisibilityLevel] = [:]
    /// A framed picture waiting for Save.
    @State private var pendingAvatar: Data?
    @State private var confirmsClose = false
    @State private var status = ""
    @State private var saving: EditField?
    @State private var confirmsLogOut = false
    @State private var didLoad = false
    @State private var profileLoaded = false
    @State private var avatarPath: String?
    @State private var avatarImage: UIImage?
    @State private var avatarItem: PhotosPickerItem?
    @State private var savingAvatar = false
    @State private var avatarCrop: AvatarCrop?
    @State private var linkCopied = false
    @State private var saveState = SaveState.idle
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

    private var visibilityRows: [MosaicVisibilityRow] {
        (mosaic.map { [$0] } ?? []) + pursuits
    }

    /// Names, picture, and privacy all wait for Save.
    private var hasChanges: Bool {
        guard profileLoaded else { return false }
        return MosaicSettingsList.username(from: username) != savedUsername
            || MosaicSettingsList.displayName(from: displayName) != savedDisplayName
            || pendingAvatar != nil
            || !MosaicSettingsList.changedLevels(visibilityRows, saved: savedLevels).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    focused = nil
                    if hasChanges {
                        confirmsClose = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(saveState == .saving)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("settings.close")
                .alert("Save your changes?", isPresented: $confirmsClose) {
                    Button("Save") {
                        Task { await saveAll() }
                    }
                    Button("Discard", role: .destructive) {
                        dismiss()
                    }
                    Button("Keep editing", role: .cancel) {}
                } message: {
                    Text("You have changes that haven’t been saved.")
                }
                Spacer()
                saveButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text("Settings")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)

                    avatarPicker
                        .frame(maxWidth: .infinity)

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
                            mosaicRow(mosaic)
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
                                    pursuitRow(pursuit)
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
        .onChange(of: avatarItem) { _, item in
            guard let item else { return }
            Task { await pickAvatar(from: item) }
        }
        .fullScreenCover(item: $avatarCrop) { crop in
            MosaicAvatarCropper(image: crop.image) {
                avatarCrop = nil
            } onSave: { jpeg in
                avatarCrop = nil
                avatarImage = UIImage(data: jpeg)
                pendingAvatar = jpeg
            }
        }
    }

    private var saveButton: some View {
        Button {
            Task { await saveAll() }
        } label: {
            Group {
                switch saveState {
                case .idle:
                    Text("Save")
                case .saving:
                    ProgressView()
                        .tint(MosaicBrand.inkBlack)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MosaicBrand.inkBlack)
            .frame(minWidth: 64)
            .frame(height: 36)
            .padding(.horizontal, 4)
            .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!profileLoaded || saveState == .saving)
        .accessibilityIdentifier("settings.save")
    }

    /// Copies `mosaic://@username`, which opens this Mosaic in the app.
    private var copyLinkButton: some View {
        Button {
            guard let link = MosaicLink.url(username: savedUsername) else { return }
            UIPasteboard.general.string = link.absoluteString
            linkCopied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                linkCopied = false
            }
        } label: {
            Image(systemName: linkCopied ? "checkmark" : "square.on.square")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MosaicBrand.inkBlack)
                .frame(width: 28, height: 28)
                .background(.white, in: Circle())
                .overlay(Circle().stroke(MosaicBrand.inkBlack, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .disabled(MosaicLink.url(username: savedUsername) == nil)
        .accessibilityLabel(linkCopied ? "Mosaic link copied" : "Copy Mosaic link")
        .accessibilityIdentifier("settings.copyMosaicLink")
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $avatarItem, matching: .images, photoLibrary: .shared()) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(field)
                    if let avatarImage {
                        Image(uiImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                    }
                    if savingAvatar {
                        Circle()
                            .fill(Color.black.opacity(0.45))
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))

                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MosaicBrand.inkBlack)
                    .frame(width: 28, height: 28)
                    .background(.white, in: Circle())
                    .overlay(Circle().stroke(MosaicBrand.inkBlack, lineWidth: 3))
                    .offset(x: 2, y: 2)
            }
        }
        .buttonStyle(.plain)
        .disabled(!profileLoaded || savingAvatar)
        .accessibilityLabel(avatarImage == nil ? "Add profile picture" : "Change profile picture")
        .accessibilityIdentifier("settings.avatar")
        .overlay(alignment: .bottomLeading) {
            copyLinkButton
                .offset(x: -2, y: 2)
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

    private func mosaicRow(_ row: MosaicVisibilityRow) -> some View {
        Toggle(isOn: Binding(
            get: { row.level == .public },
            set: { isPublic in mosaic?.level = isPublic ? .public : .private }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .foregroundStyle(.white)
                Text(row.canChange ? row.level.title : "Waiting to sync")
                    .font(.footnote)
                    .foregroundStyle(muted)
            }
        }
        .tint(.green)
        .disabled(!row.canChange)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Mosaic \(row.title)")
    }

    private func pursuitRow(_ row: MosaicVisibilityRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .foregroundStyle(.white)
                if !row.canChange {
                    Text("Waiting to sync")
                        .font(.footnote)
                        .foregroundStyle(muted)
                }
            }
            Picker("Who can see \(row.title)", selection: Binding(
                get: { row.level },
                set: { level in
                    if let index = pursuits.firstIndex(where: { $0.id == row.id }) {
                        pursuits[index].level = level
                    }
                }
            )) {
                ForEach(MosaicVisibilityLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!row.canChange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pursuit \(row.title)")
    }

    /// Saves names, the picture, and privacy, pushes the boards now instead of after the usual pause,
    /// then closes. Anything that fails keeps the page open with its message.
    private func saveAll() async {
        guard saveState != .saving else { return }
        saveState = .saving
        defer { saveState = .idle }
        focused = nil
        status = ""
        usernameMessage = ""
        await commit(.username)
        await commit(.displayName)
        let namesSaved = MosaicSettingsList.username(from: username) == savedUsername
            && MosaicSettingsList.displayName(from: displayName) == savedDisplayName
        let avatarSaved = await uploadPendingAvatar()
        let levelsSaved = await applyChangedLevels()
        var synced = true
        if let remoteSync {
            synced = await remoteSync.syncNow(
                snapshot: store.snapshot,
                account: account,
                mediaFile: store.mediaURL(for:),
                protectingDocumentIDs: store.syncProtectedDocumentUUIDs
            )
        }
        if !namesSaved, status.isEmpty, usernameMessage.isEmpty {
            status = "Fix your username to save it."
        } else if !synced, status.isEmpty {
            status = "Your Mosaic couldn’t sync. Check your connection and try again."
        }
        guard namesSaved, avatarSaved, levelsSaved, synced else { return }
        dismiss()
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
            avatarPath = profile.avatarPath
            if let path = profile.avatarPath,
               let data = try? await client.loadAvatar(path: path, accessToken: token) {
                avatarImage = UIImage(data: data)
            }
            let remote = try await client.loadBoards(userID: userID, accessToken: token)
            let listed = MosaicSettingsList.rows(snapshot: store.snapshot, remote: remote)
            mosaic = listed.mosaic
            pursuits = listed.pursuits
            savedLevels = MosaicSettingsList.savedLevels(visibilityRows)
        } catch {
            status = "Settings could not be loaded."
        }
    }

    private func pickAvatar(from item: PhotosPickerItem) async {
        avatarItem = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let picked = MosaicThumbnail.image(data: data, maxPixelSize: 1536)
        else {
            status = "That photo could not be used."
            return
        }
        avatarCrop = AvatarCrop(image: picked)
    }

    private func uploadPendingAvatar() async -> Bool {
        guard let jpeg = pendingAvatar else { return true }
        guard let config = SupabaseSyncConfig.current(),
              let userID = account.session?.userID,
              let token = await account.accessToken()
        else {
            status = "The profile picture could not be saved."
            return false
        }
        savingAvatar = true
        defer { savingAvatar = false }
        do {
            let path = try await MosaicSettingsClient(config: config)
                .saveAvatar(jpeg, replacing: avatarPath, userID: userID, accessToken: token)
            avatarPath = path
            if let saved = UIImage(data: jpeg) {
                MosaicAvatarCache.store(saved, for: path)
            }
            pendingAvatar = nil
            return true
        } catch {
            status = "The profile picture could not be saved."
            return false
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

    /// Choices that fail stay unsaved, so a second Save tries them again.
    private func applyChangedLevels() async -> Bool {
        let changed = MosaicSettingsList.changedLevels(visibilityRows, saved: savedLevels)
        guard !changed.isEmpty else { return true }
        guard let config = SupabaseSyncConfig.current(),
              let token = await account.accessToken()
        else {
            status = "Your privacy settings could not be saved."
            return false
        }
        let client = MosaicSettingsClient(config: config)
        var allSaved = true
        for row in changed {
            do {
                try await client.setVisibility(id: row.id, level: row.level, accessToken: token)
                savedLevels[row.id] = row.level
                pursuitPrivacy?.set(row.level, for: row.id)
            } catch {
                allSaved = false
            }
        }
        if !allSaved {
            status = "Some privacy settings could not be saved."
        }
        return allSaved
    }
}

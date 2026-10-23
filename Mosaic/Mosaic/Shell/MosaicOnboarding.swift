import Foundation

struct MosaicOnboardingStatus: Equatable, Sendable {
    var onboardedAt: Date?
    var username: String
    var displayName: String
    var birthday: Date?

    var isOnboarded: Bool { onboardedAt != nil }
}

enum MosaicOnboardingRoute: Equatable {
    case loading
    case needsSetup
    case retry
    case readyForPreparation
}

enum MosaicOnboardingCache {
    /// Versioned so caches written before placeholder accounts were reopened are re-checked with the server.
    private static func key(_ userID: UUID) -> String {
        "mosaic.onboarded.v2.\(userID.uuidString.lowercased())"
    }

    static func markComplete(_ userID: UUID) {
        UserDefaults.standard.set(true, forKey: key(userID))
    }

    static func isComplete(_ userID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(userID))
    }

    static func clear(_ userID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(userID))
    }
}

enum MosaicOnboardingRouter {
    /// Chooses the next shell screen after sign-in.
    static func route(
        cachedComplete: Bool,
        hasLocalAccount: Bool,
        status: MosaicOnboardingStatus?
    ) -> MosaicOnboardingRoute {
        if cachedComplete || status?.isOnboarded == true {
            return .readyForPreparation
        }
        if let status, !status.isOnboarded {
            return .needsSetup
        }
        if hasLocalAccount {
            return .readyForPreparation
        }
        if status == nil {
            return .retry
        }
        return .needsSetup
    }
}

enum MosaicOnboardingError: Error, Equatable {
    case usernameTaken
    case alreadyOnboarded
    case invalidInput
    case requestFailed

    static func from(status: Int, message: String) -> MosaicOnboardingError {
        if status == 409 || message.contains("23505") || message.contains("username taken") {
            return .usernameTaken
        }
        if message.contains("already onboarded") {
            return .alreadyOnboarded
        }
        if message.contains("22023") || message.contains("invalid") {
            return .invalidInput
        }
        return .requestFailed
    }
}

struct MosaicOnboardingClient: Sendable {
    var config: SupabaseSyncConfig
    var session: URLSession = .shared

    func status(accessToken: String) async throws -> MosaicOnboardingStatus? {
        let data = try await rpc(name: "onboarding_status", body: [:], accessToken: accessToken)
        return try Self.status(from: data)
    }

    /// Saves the profile. A retry after an earlier success counts as done, not as a failure.
    func complete(
        username: String,
        displayName: String,
        birthday: Date,
        accessToken: String
    ) async throws {
        let formatter = Self.birthdayFormatter
        let body: [String: Any] = [
            "p_username": username,
            "p_display_name": displayName,
            "p_birthday": formatter.string(from: birthday)
        ]
        do {
            _ = try await rpc(name: "complete_onboarding", body: body, accessToken: accessToken)
        } catch MosaicOnboardingError.alreadyOnboarded {
            guard try await status(accessToken: accessToken)?.isOnboarded == true else {
                throw MosaicOnboardingError.requestFailed
            }
        }
    }

    func updateBirthday(_ birthday: Date, accessToken: String) async throws {
        let body: [String: Any] = [
            "p_birthday": Self.birthdayFormatter.string(from: birthday)
        ]
        _ = try await rpc(name: "update_private_birthday", body: body, accessToken: accessToken)
    }

    static let birthdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func status(from data: Data) throws -> MosaicOnboardingStatus? {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        guard let row = rows.first else { return nil }
        let username = row["username"] as? String ?? ""
        let displayName = row["display_name"] as? String ?? ""
        let onboardedAt = (row["onboarded_at"] as? String).flatMap(isoDate(from:))
        let birthday = (row["birthday"] as? String).flatMap(birthdayFormatter.date(from:))
        return MosaicOnboardingStatus(
            onboardedAt: onboardedAt,
            username: username,
            displayName: displayName,
            birthday: birthday
        )
    }

    private static func isoDate(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private func rpc(name: String, body: [String: Any], accessToken: String) async throws -> Data {
        let endpoint = config.url
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("rpc")
            .appendingPathComponent(name)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await MosaicAccount.send(request, session: session)
        guard let http = response as? HTTPURLResponse else {
            throw MosaicOnboardingError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MosaicOnboardingError.from(
                status: http.statusCode,
                message: String(data: data, encoding: .utf8) ?? ""
            )
        }
        return data
    }
}

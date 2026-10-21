import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct MosaicSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: UUID
}

enum MosaicPKCE {
    static let redirect = "mosaic://login-callback"

    static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        }
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class MosaicAppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    var onCredential: ((ASAuthorizationAppleIDCredential) -> Void)?
    var onFailure: ((Error?) -> Void)?

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            onFailure?(nil)
            return
        }
        onCredential?(credential)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onFailure?(error)
    }
}

private final class MosaicAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding, ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
            return window ?? ASPresentationAnchor(frame: .zero)
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
            return window ?? ASPresentationAnchor(frame: .zero)
        }
    }
}

enum MosaicAuthResponse {
    static func session(from data: Data, now: Date = .now) throws -> MosaicSession {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any],
              let userID = (user["id"] as? String).flatMap(UUID.init(uuidString:))
        else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return MosaicSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(expiresIn),
            userID: userID
        )
    }
}

/// Distinguishes a revoked/invalid refresh token from a temporary network failure.
enum MosaicAuthFailure: Error, Equatable {
    case transport
    case permanent
}

/// OTP send failed because the identifier is not registered (sign-in only).
enum MosaicOTPError: Error, Equatable {
    case notRegistered
    case requestFailed
}

enum MosaicPasswordLoginError: Error, Equatable {
    case rejected
    case rateLimited
    case requestFailed
}

enum MosaicAuthErrorClassification {
    /// Permanent when the refresh token itself is rejected; transport for offline/5xx/unknown.
    static func isPermanentFailure(status: Int, body: Data) -> Bool {
        if status == 401 || status == 403 { return true }
        guard status == 400 else { return false }
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            let error = (json["error"] as? String)?.lowercased() ?? ""
            let description = (json["error_description"] as? String)?.lowercased() ?? ""
            if error == "invalid_grant" { return true }
            if description.contains("refresh token") { return true }
            if description.contains("session") && (description.contains("not found") || description.contains("expired")) {
                return true
            }
        }
        let text = String(data: body, encoding: .utf8)?.lowercased() ?? ""
        return text.contains("invalid_grant")
            || text.contains("invalid refresh token")
            || text.contains("refresh token not found")
            || text.contains("refresh token already used")
    }
}

enum MosaicSessionKeychain {
    private static let service = "com.ayushkrishnappa.Mosaic.session"
    private static let account = "supabase"

    static func load() -> MosaicSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let session = try? JSONDecoder().decode(MosaicSession.self, from: data)
        else {
            return nil
        }
        return session
    }

    static func save(_ session: MosaicSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
@Observable
final class MosaicAccount {
    private(set) var session: MosaicSession?
    private(set) var lastError: String?
    /// True while Google or Apple has handed back and the session is being fetched, so the
    /// sign-in screen can show progress instead of looking idle.
    private(set) var isFinishingSignIn = false
    private var tokenRefresh: Task<MosaicSession, Error>?
    private var tokenRefreshID: UUID?
    private var config: SupabaseSyncConfig?
    private var webSession: ASWebAuthenticationSession?
    private var codeVerifier: String?
    private var appleNonce: String?
    private var appleSignInDelegate: MosaicAppleSignInDelegate?
    private let presenter = MosaicAuthPresenter()

    init(config: SupabaseSyncConfig? = SupabaseSyncConfig.current()) {
        self.config = config
    }

    func restore() async {
        guard config != nil, let stored = MosaicSessionKeychain.load() else { return }
        // A cached account opens immediately. Network operations refresh the token lazily.
        session = stored
    }

    func signInWithPassword(identifier: String, password: String) async -> Bool {
        lastError = nil
        guard let config else {
            lastError = "Mosaic is not connected to a project yet."
            return false
        }
        guard !password.isEmpty else {
            lastError = "Enter your password."
            return false
        }
        let cleaned = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let data: Data
            if cleaned.contains("@"), !cleaned.hasPrefix("@") {
                data = try await post(
                    config: config,
                    path: "auth/v1/token",
                    query: "grant_type=password",
                    body: ["email": cleaned.lowercased(), "password": password],
                    accessToken: nil
                )
            } else {
                data = try await postUsernameLogin(
                    config: config,
                    username: MosaicSettingsList.username(from: cleaned),
                    password: password
                )
            }
            let signedIn = try MosaicAuthResponse.session(from: data)
            store(session: signedIn)
            return true
        } catch MosaicPasswordLoginError.rateLimited {
            lastError = "Too many attempts. Wait a few minutes and try again."
            return false
        } catch {
            lastError = passwordMessage(for: error)
            return false
        }
    }

    /// Usernames go through the `username-login` Edge Function, which looks up the email
    /// server-side so it is never exposed to the app.
    private func postUsernameLogin(config: SupabaseSyncConfig, username: String, password: String) async throws -> Data {
        var request = URLRequest(url: config.url.appending(path: "functions/v1/username-login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "username": username,
            "password": password
        ])
        let (data, response) = try await Self.send(request)
        guard let http = response as? HTTPURLResponse else {
            throw MosaicPasswordLoginError.requestFailed
        }
        if http.statusCode == 429 {
            throw MosaicPasswordLoginError.rateLimited
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MosaicPasswordLoginError.rejected
        }
        return data
    }

    /// Attaches a password to the signed-in auth user (OAuth / OTP) so username login works later.
    func setPassword(_ password: String) async -> Bool {
        lastError = nil
        guard let config else {
            lastError = "Mosaic is not connected to a project yet."
            return false
        }
        guard password.count >= 6 else {
            lastError = "Use a password with at least 6 characters."
            return false
        }
        guard let token = await accessToken() else {
            lastError = "Your session expired. Sign in again."
            return false
        }
        do {
            try await putUser(
                config: config,
                body: ["password": password],
                accessToken: token
            )
            return true
        } catch {
            lastError = "Couldn’t save your password. Try again."
            return false
        }
    }

    func signInWithApple() {
        // A second tap would replace the nonce the first sheet is still using, and that sign-in would fail.
        guard appleSignInDelegate == nil, !isFinishingSignIn else { return }
        lastError = nil
        guard config != nil else {
            lastError = "Mosaic is not connected to a project yet."
            return
        }
        let nonce = MosaicAppleNonce.random()
        appleNonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = MosaicAppleNonce.sha256(nonce)
        let delegate = MosaicAppleSignInDelegate()
        delegate.onCredential = { [weak self] credential in
            Task { @MainActor in
                await self?.completeApple(credential: credential)
            }
        }
        delegate.onFailure = { [weak self] error in
            Task { @MainActor in
                self?.appleSignInDelegate = nil
                if let error = error as? ASAuthorizationError, error.code == .canceled {
                    self?.present("Apple sign-in was cancelled.")
                } else {
                    self?.lastError = "Apple sign-in did not finish. Turn on the Apple provider in Supabase."
                }
            }
        }
        appleSignInDelegate = delegate
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = delegate
        controller.presentationContextProvider = presenter
        controller.performRequests()
    }

    private func completeApple(credential: ASAuthorizationAppleIDCredential) async {
        isFinishingSignIn = true
        defer {
            appleSignInDelegate = nil
            isFinishingSignIn = false
        }
        guard let config,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce = appleNonce
        else {
            lastError = "Apple sign-in did not return a token."
            return
        }
        do {
            let data = try await post(
                config: config,
                path: "auth/v1/token",
                query: "grant_type=id_token",
                body: [
                    "provider": "apple",
                    "id_token": idToken,
                    "nonce": nonce
                ],
                accessToken: nil
            )
            let signedIn = try MosaicAuthResponse.session(from: data)
            store(session: signedIn)
        } catch {
            lastError = "Apple sign-in was rejected. Turn on the Apple provider in Supabase."
        }
    }

    private func store(session signedIn: MosaicSession) {
        session = signedIn
        MosaicSessionKeychain.save(signedIn)
    }

    func sendEmailCode(_ email: String, createUser: Bool) async {
        lastError = nil
        guard let config else {
            lastError = "Mosaic is not connected to a project yet."
            return
        }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), trimmed.contains(".") else {
            lastError = "Enter a valid email address."
            return
        }
        do {
            _ = try await postOTP(
                config: config,
                path: "auth/v1/otp",
                body: MosaicPhoneNumber.sendEmailOTPBody(email: trimmed, createUser: createUser),
                createUser: createUser
            )
        } catch MosaicOTPError.notRegistered {
            lastError = "No Mosaic account uses that email. Try Sign up instead."
        } catch {
            lastError = otpMessage(for: error)
        }
    }

    func verifyEmailCode(email: String, code: String) async -> Bool {
        lastError = nil
        guard let config else {
            lastError = "Mosaic is not connected to a project yet."
            return false
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let token = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 6 else {
            lastError = "Enter the 6-digit code."
            return false
        }
        do {
            let data = try await postOTP(
                config: config,
                path: "auth/v1/verify",
                body: MosaicPhoneNumber.verifyEmailOTPBody(email: trimmedEmail, token: token),
                createUser: true
            )
            let signedIn = try MosaicAuthResponse.session(from: data)
            store(session: signedIn)
            return true
        } catch {
            lastError = otpMessage(for: error)
            return false
        }
    }

    func sendPhoneCode(_ rawPhone: String, createUser: Bool) async {
        lastError = nil
        guard let config else {
            lastError = "Mosaic is not connected to a project yet."
            return
        }
        guard let phone = MosaicPhoneNumber.normalized(rawPhone) else {
            lastError = "Enter a valid phone number."
            return
        }
        do {
            _ = try await postOTP(
                config: config,
                path: "auth/v1/otp",
                body: MosaicPhoneNumber.sendOTPBody(phone: phone, createUser: createUser),
                createUser: createUser
            )
        } catch MosaicOTPError.notRegistered {
            lastError = "No Mosaic account uses that number. Try Sign up instead."
        } catch {
            lastError = otpMessage(for: error)
        }
    }

    func verifyPhoneCode(rawPhone: String, code: String) async -> Bool {
        lastError = nil
        guard let config else {
            lastError = "Mosaic is not connected to a project yet."
            return false
        }
        guard let phone = MosaicPhoneNumber.normalized(rawPhone) else {
            lastError = "Enter a valid phone number."
            return false
        }
        let token = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 6 else {
            lastError = "Enter the 6-digit code."
            return false
        }
        do {
            let data = try await postOTP(
                config: config,
                path: "auth/v1/verify",
                body: MosaicPhoneNumber.verifySMSBody(phone: phone, token: token),
                createUser: true
            )
            let signedIn = try MosaicAuthResponse.session(from: data)
            store(session: signedIn)
            return true
        } catch {
            lastError = otpMessage(for: error)
            return false
        }
    }

    func signInWithGoogle() {
        // A second tap would replace the verifier the first sheet is still using, and that sign-in would fail.
        guard webSession == nil, !isFinishingSignIn else { return }
        lastError = nil
        guard let config else {
            lastError = "Mosaic is not connected to a project yet."
            return
        }
        let verifier = MosaicPKCE.verifier()
        codeVerifier = verifier
        guard let url = Self.googleAuthorizeURL(config: config, challenge: MosaicPKCE.challenge(for: verifier)) else {
            lastError = "Google sign-in could not start."
            return
        }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "mosaic") { [weak self] callback, error in
            Task { @MainActor in
                self?.completeGoogle(callback: callback, error: error, config: config)
            }
        }
        session.presentationContextProvider = presenter
        session.prefersEphemeralWebBrowserSession = false
        webSession = session
        if !session.start() {
            webSession = nil
            lastError = "Google sign-in could not open."
        }
    }

    private func completeGoogle(callback: URL?, error: Error?, config: SupabaseSyncConfig) {
        webSession = nil
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
            present("Google sign-in was cancelled.")
            return
        }
        guard let callback, let verifier = codeVerifier else {
            present("Google sign-in did not finish.")
            return
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let description = items.first(where: { $0.name == "error_description" })?.value {
            present(description.replacingOccurrences(of: "+", with: " "))
            return
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            present("Google sign-in did not return a code. Turn on the Google provider in Supabase and allow the redirect mosaic://login-callback.")
            return
        }
        isFinishingSignIn = true
        Task {
            defer { isFinishingSignIn = false }
            do {
                let signedIn = try await exchangePKCE(code: code, verifier: verifier, config: config)
                store(session: signedIn)
            } catch is MosaicAuthFailure {
                lastError = message(for: .requestFailed)
            } catch let error as SupabaseDocumentSyncError {
                lastError = message(for: error)
            } catch {
                lastError = "Google sign-in did not finish."
            }
        }
    }

    static func googleAuthorizeURL(config: SupabaseSyncConfig, challenge: String) -> URL? {
        var components = URLComponents(url: config.url.appending(path: "auth/v1/authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: MosaicPKCE.redirect),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256")
        ]
        return components?.url
    }

    func present(_ message: String) {
        lastError = message
    }

    func clearLastError() {
        lastError = nil
    }

    /// Ends the session on this phone. The boards stay on the device.
    func signOut() async {
        let ending = session
        tokenRefresh?.cancel()
        tokenRefresh = nil
        tokenRefreshID = nil
        session = nil
        lastError = nil
        MosaicSessionKeychain.clear()
        if let ending {
            MosaicOnboardingCache.clear(ending.userID)
        }
        guard let config, let ending else { return }
        var components = URLComponents(url: config.url.appending(path: "auth/v1/logout"), resolvingAgainstBaseURL: false)
        components?.query = "scope=local"
        guard let url = components?.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(ending.accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await Self.send(request)
    }

    func accessToken() async -> String? {
        guard config != nil, let current = session else { return nil }
        guard current.expiresAt < Date().addingTimeInterval(60) else { return current.accessToken }
        // Downloads and uploads can start together; share one refresh to avoid rotating twice.
        let task: Task<MosaicSession, Error>
        if let tokenRefresh {
            task = tokenRefresh
        } else {
            task = Task { try await self.refresh(current) }
            tokenRefresh = task
            tokenRefreshID = UUID()
        }
        let refreshID = tokenRefreshID
        defer {
            if tokenRefreshID == refreshID {
                tokenRefresh = nil
                tokenRefreshID = nil
            }
        }
        do {
            let refreshed = try await task.value
            guard !task.isCancelled, session?.userID == current.userID else { return nil }
            session = refreshed
            MosaicSessionKeychain.save(refreshed)
            return refreshed.accessToken
        } catch MosaicAuthFailure.permanent {
            // Boards stay on disk under Accounts/{userID}; only the dead session is cleared.
            clearSessionForReauthentication()
            return nil
        } catch {
            // A failed connection must not sign the user out of their cached boards.
            return nil
        }
    }

    /// Drops the cached session so the sign-in screen can recover. Local boards are untouched.
    private func clearSessionForReauthentication() {
        tokenRefresh?.cancel()
        tokenRefresh = nil
        tokenRefreshID = nil
        session = nil
        MosaicSessionKeychain.clear()
        lastError = "Your session expired. Sign in again to keep syncing. Boards on this phone are still here."
    }

    private func exchangePKCE(code: String, verifier: String, config: SupabaseSyncConfig) async throws -> MosaicSession {
        let data = try await post(
            config: config,
            path: "auth/v1/token",
            query: "grant_type=pkce",
            body: [
                "auth_code": code,
                "code_verifier": verifier
            ],
            accessToken: nil
        )
        return try MosaicAuthResponse.session(from: data)
    }

    private func refresh(_ session: MosaicSession) async throws -> MosaicSession {
        guard let config else { throw SupabaseDocumentSyncError.requestFailed }
        let data = try await post(
            config: config,
            path: "auth/v1/token",
            query: "grant_type=refresh_token",
            body: ["refresh_token": session.refreshToken],
            accessToken: nil
        )
        return try MosaicAuthResponse.session(from: data)
    }

    private func postOTP(
        config: SupabaseSyncConfig,
        path: String,
        body: [String: Any],
        createUser: Bool
    ) async throws -> Data {
        var request = URLRequest(url: config.url.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await Self.send(request)
        guard let http = response as? HTTPURLResponse else {
            throw MosaicOTPError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            if !createUser, Self.looksLikeUnknownAccount(status: http.statusCode, body: data) {
                throw MosaicOTPError.notRegistered
            }
            throw MosaicOTPError.requestFailed
        }
        return data
    }

    nonisolated static func looksLikeUnknownAccount(status: Int, body: Data) -> Bool {
        let message = String(data: body, encoding: .utf8)?.lowercased() ?? ""
        if status == 422 || status == 400 {
            return message.contains("user not found")
                || message.contains("signup is disabled")
                || message.contains("signups not allowed for otp")
                || message.contains("otp disabled")
        }
        return false
    }

    private func otpMessage(for error: Error) -> String {
        if error is MosaicOTPError || error is SupabaseDocumentSyncError {
            return "That code didn’t work. Try again or request a new one."
        }
        return "Sign-in didn’t finish. Check your connection and try again."
    }

    private func passwordMessage(for error: Error) -> String {
        switch error {
        case MosaicAuthFailure.permanent, MosaicPasswordLoginError.rejected:
            "Email, username, or password didn’t match. If you signed up with Google, Apple, or a code, continue with that instead."
        default:
            // Offline or a server hiccup; the details were fine as far as anyone knows.
            "Couldn’t reach Mosaic. Check your connection and try again."
        }
    }

    /// Sends once more when the connection drops before a reply. The first request after the app
    /// sits idle often lands on a connection the server already closed, which a retry gets past.
    nonisolated static func send(_ request: URLRequest, session: URLSession = .shared) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where retriesOnce(error.code) {
            try await Task.sleep(for: .milliseconds(300))
            return try await session.data(for: request)
        }
    }

    nonisolated static func retriesOnce(_ code: URLError.Code) -> Bool {
        code == .networkConnectionLost || code == .timedOut
    }

    private func putUser(
        config: SupabaseSyncConfig,
        body: [String: String],
        accessToken: String
    ) async throws {
        var request = URLRequest(url: config.url.appending(path: "auth/v1/user"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await Self.send(request)
        guard let http = response as? HTTPURLResponse else {
            throw MosaicAuthFailure.transport
        }
        guard (200..<300).contains(http.statusCode) else {
            if MosaicAuthErrorClassification.isPermanentFailure(status: http.statusCode, body: data) {
                throw MosaicAuthFailure.permanent
            }
            throw MosaicAuthFailure.transport
        }
    }

    private func post(
        config: SupabaseSyncConfig,
        path: String,
        query: String,
        body: [String: String],
        accessToken: String?
    ) async throws -> Data {
        var components = URLComponents(url: config.url.appending(path: path), resolvingAgainstBaseURL: false)
        components?.query = query
        guard let url = components?.url else { throw SupabaseDocumentSyncError.requestFailed }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await Self.send(request)
        guard let http = response as? HTTPURLResponse else {
            throw MosaicAuthFailure.transport
        }
        guard (200..<300).contains(http.statusCode) else {
            if MosaicAuthErrorClassification.isPermanentFailure(status: http.statusCode, body: data) {
                throw MosaicAuthFailure.permanent
            }
            throw MosaicAuthFailure.transport
        }
        return data
    }

    private func message(for error: SupabaseDocumentSyncError) -> String {
        switch error {
        case .requestFailed:
            "Google sign-in was rejected. In Supabase, turn on the Google provider and allow the redirect mosaic://login-callback."
        case .unexpectedResponse:
            "Google sign-in returned an unexpected response."
        case .revisionConflict, .mosaicExists, .documentTooLarge:
            "Google sign-in did not finish."
        }
    }
}

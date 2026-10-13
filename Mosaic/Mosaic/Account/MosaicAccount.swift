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

private final class MosaicAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
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

enum MosaicSessionKeychain {
    private static let service = "com.ayushkrishnappa.Spendant.Mosaic.session"
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
    private var config: SupabaseSyncConfig?
    private var webSession: ASWebAuthenticationSession?
    private var codeVerifier: String?
    private let presenter = MosaicAuthPresenter()

    init(config: SupabaseSyncConfig? = SupabaseSyncConfig.current()) {
        self.config = config
    }

    func restore() async {
        guard config != nil, var stored = MosaicSessionKeychain.load() else { return }
        if stored.expiresAt < Date().addingTimeInterval(60) {
            do {
                stored = try await refresh(stored)
                MosaicSessionKeychain.save(stored)
            } catch {
                MosaicSessionKeychain.clear()
                return
            }
        }
        session = stored
    }

    func signInWithGoogle() {
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
            lastError = "Google sign-in could not open."
        }
    }

    private func completeGoogle(callback: URL?, error: Error?, config: SupabaseSyncConfig) {
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
        Task {
            do {
                let signedIn = try await exchangePKCE(code: code, verifier: verifier, config: config)
                session = signedIn
                MosaicSessionKeychain.save(signedIn)
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

    /// Ends the session on this phone. The boards stay on the device.
    func signOut() async {
        let ending = session
        session = nil
        lastError = nil
        MosaicSessionKeychain.clear()
        guard let config, let ending else { return }
        var components = URLComponents(url: config.url.appending(path: "auth/v1/logout"), resolvingAgainstBaseURL: false)
        components?.query = "scope=local"
        guard let url = components?.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(ending.accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    func accessToken() async -> String? {
        guard let config, var current = session else { return nil }
        if current.expiresAt < Date().addingTimeInterval(60) {
            do {
                current = try await refresh(current)
                session = current
                MosaicSessionKeychain.save(current)
            } catch {
                session = nil
                MosaicSessionKeychain.clear()
                return nil
            }
        }
        return current.accessToken
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
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseDocumentSyncError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseDocumentSyncError.requestFailed
        }
        return data
    }

    private func message(for error: SupabaseDocumentSyncError) -> String {
        switch error {
        case .requestFailed:
            "Google sign-in was rejected. In Supabase, turn on the Google provider and allow the redirect mosaic://login-callback."
        case .unexpectedResponse:
            "Google sign-in returned an unexpected response."
        case .revisionConflict, .mosaicExists:
            "Google sign-in did not finish."
        }
    }
}

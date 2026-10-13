import Foundation

/// Present when the app has a Supabase project URL and anon key.
/// The service-role key is never read here.
struct SupabaseSyncConfig: Equatable, Sendable {
    var url: URL
    var anonKey: String

    static func current(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) -> SupabaseSyncConfig? {
        let urlString = nonempty(environment["SUPABASE_URL"])
            ?? nonempty(bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String)
        let anonKey = nonempty(environment["SUPABASE_ANON_KEY"])
            ?? nonempty(bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String)
        guard let urlString, let url = URL(string: urlString), let anonKey else { return nil }
        return SupabaseSyncConfig(url: url, anonKey: anonKey)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

enum SupabaseDocumentSyncError: Error, Equatable {
    case revisionConflict
    case mosaicExists
    case requestFailed
    case unexpectedResponse
}

/// Talks to the `save_document` and `own_mosaic_id` functions.
struct SupabaseDocumentSync: Sendable {
    var config: SupabaseSyncConfig
    var session: URLSession = .shared

    func readDocument(id: UUID, accessToken: String) async throws -> Data {
        try await rpc(name: "read_document", body: ["p_id": id.uuidString.lowercased()], accessToken: accessToken)
    }

    func ownMosaicID(accessToken: String) async throws -> UUID? {
        let data = try await rpc(name: "own_mosaic_id", body: [:], accessToken: accessToken)
        return Self.mosaicID(from: data)
    }

    func save(push: ComposerDocumentPush, accessToken: String) async throws -> Int64 {
        let body = try Self.saveBody(push)
        let data = try await rpc(name: "save_document", body: body, accessToken: accessToken)
        return try Self.revision(from: data)
    }

    static func saveBody(_ push: ComposerDocumentPush) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(push.document.body)
        let bodyObject = try JSONSerialization.jsonObject(with: bodyData)
        var payload: [String: Any] = [
            "p_id": push.document.id.uuidString.lowercased(),
            "p_role": push.document.role.rawValue,
            "p_title": push.document.title,
            "p_body": bodyObject,
            "p_expected_revision": push.expectedRevision
        ]
        if let parentID = push.document.parentID {
            payload["p_parent_id"] = parentID.uuidString.lowercased()
        } else {
            payload["p_parent_id"] = NSNull()
        }
        return payload
    }

    static func optionalRevision(from data: Data) -> Int64? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let rows = json as? [[String: Any]] {
            guard let value = rows.first?["revision"] as? NSNumber else { return nil }
            return value.int64Value
        }
        if let value = json as? NSNumber {
            return value.int64Value
        }
        return nil
    }

    static func revision(from data: Data) throws -> Int64 {
        let json = try JSONSerialization.jsonObject(with: data)
        if let rows = json as? [[String: Any]], let value = rows.first?["revision"] as? NSNumber {
            return value.int64Value
        }
        if let value = json as? NSNumber {
            return value.int64Value
        }
        throw SupabaseDocumentSyncError.unexpectedResponse
    }

    static func mosaicID(from data: Data) -> UUID? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if json is NSNull { return nil }
        if let text = json as? String { return UUID(uuidString: text) }
        return nil
    }

    static func error(from data: Data, status: Int) -> SupabaseDocumentSyncError {
        let message = String(data: data, encoding: .utf8) ?? ""
        if message.contains("revision conflict") || message.contains("P0001") {
            return .revisionConflict
        }
        if message.contains("mosaic exists") || message.contains("23505") {
            return .mosaicExists
        }
        if status == 409 {
            return .revisionConflict
        }
        return .requestFailed
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
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseDocumentSyncError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(from: data, status: http.statusCode)
        }
        return data
    }
}

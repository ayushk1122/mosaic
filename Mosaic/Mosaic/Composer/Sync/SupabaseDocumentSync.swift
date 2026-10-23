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
    /// The save expected a board the server no longer has: another device deleted it.
    case documentDeleted
    case mosaicExists
    /// Over the server's body size limit; retrying won't help until something is removed.
    case documentTooLarge
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
        // A malformed response must not be treated as a new account.
        if String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null" {
            return nil
        }
        guard let id = Self.mosaicID(from: data) else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        return id
    }

    /// Fetch only the landing board so the editor can open before all Pursuits arrive.
    func ownDocument(id: UUID, ownerID: UUID, accessToken: String) async throws -> ComposerRestoredDocument {
        var components = URLComponents(url: config.url.appending(path: "rest/v1/documents"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "owner_id", value: "eq.\(ownerID.uuidString.lowercased())"),
            URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())"),
            URLQueryItem(name: "select", value: "id,owner_id,parent_id,role,title,body,revision")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SupabaseDocumentSyncError.requestFailed
        }
        let rows = try JSONDecoder().decode([ComposerRestoredDocument].self, from: data)
        guard rows.count == 1, let row = rows.first, row.id == id, row.ownerID == ownerID, row.revision > 0 else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        return row
    }

    /// Owner-only restoration includes revisions from the same rows as the board bodies.
    /// Keep paging until an empty page, even if the server caps responses below our limit.
    func ownDocuments(ownerID: UUID, accessToken: String) async throws -> [ComposerRestoredDocument] {
        var result: [ComposerRestoredDocument] = []
        var seen = Set<UUID>()
        while true {
            try Task.checkCancellation()
            var components = URLComponents(url: config.url.appending(path: "rest/v1/documents"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "owner_id", value: "eq.\(ownerID.uuidString.lowercased())"),
                URLQueryItem(name: "select", value: "id,owner_id,parent_id,role,title,body,revision"),
                URLQueryItem(name: "order", value: "id.asc"),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "offset", value: String(result.count))
            ]
            var request = URLRequest(url: components.url!)
            request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw SupabaseDocumentSyncError.requestFailed
            }
            let page = try JSONDecoder().decode([ComposerRestoredDocument].self, from: data)
            guard !page.isEmpty else { return result }
            for row in page {
                guard row.ownerID == ownerID, row.revision > 0, seen.insert(row.id).inserted else {
                    throw SupabaseDocumentSyncError.unexpectedResponse
                }
            }
            result.append(contentsOf: page)
        }
    }

    /// Each of the owner's boards and its revision: the cheap check for edits made on another device.
    func ownRevisions(ownerID: UUID, accessToken: String) async throws -> [UUID: Int64] {
        struct Row: Decodable {
            var id: UUID
            var revision: Int64
        }
        var result: [UUID: Int64] = [:]
        var offset = 0
        while true {
            try Task.checkCancellation()
            var components = URLComponents(url: config.url.appending(path: "rest/v1/documents"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "owner_id", value: "eq.\(ownerID.uuidString.lowercased())"),
                URLQueryItem(name: "select", value: "id,revision"),
                URLQueryItem(name: "order", value: "id.asc"),
                URLQueryItem(name: "limit", value: "500"),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            var request = URLRequest(url: components.url!)
            request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw SupabaseDocumentSyncError.requestFailed
            }
            let page = try JSONDecoder().decode([Row].self, from: data)
            guard !page.isEmpty else { return result }
            for row in page {
                result[row.id] = row.revision
            }
            offset += page.count
        }
    }

    /// The owner's boards with these ids, in batches so the request stays short.
    func ownDocuments(ownerID: UUID, ids: [UUID], accessToken: String) async throws -> [ComposerRestoredDocument] {
        var result: [ComposerRestoredDocument] = []
        for start in stride(from: 0, to: ids.count, by: 40) {
            try Task.checkCancellation()
            let batch = ids[start..<min(start + 40, ids.count)]
            let list = batch.map { $0.uuidString.lowercased() }.joined(separator: ",")
            var components = URLComponents(url: config.url.appending(path: "rest/v1/documents"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "owner_id", value: "eq.\(ownerID.uuidString.lowercased())"),
                URLQueryItem(name: "id", value: "in.(\(list))"),
                URLQueryItem(name: "select", value: "id,owner_id,parent_id,role,title,body,revision")
            ]
            var request = URLRequest(url: components.url!)
            request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw SupabaseDocumentSyncError.requestFailed
            }
            let rows = try JSONDecoder().decode([ComposerRestoredDocument].self, from: data)
            guard rows.allSatisfy({ $0.ownerID == ownerID && $0.revision > 0 && batch.contains($0.id) }) else {
                throw SupabaseDocumentSyncError.unexpectedResponse
            }
            result.append(contentsOf: rows)
        }
        return result
    }

    func downloadOriginal(ownerID: UUID, assetID: UUID, accessToken: String) async throws -> Data {
        let path = ComposerMediaCatalog.objectPath(ownerID: ownerID, assetID: assetID, name: "original")
        let url = config.url.appending(path: "storage/v1/object/authenticated/media").appending(path: path)
        var request = URLRequest(url: url)
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
            throw ComposerRestoreError.mediaUnavailable
        }
        return data
    }

    func save(push: ComposerDocumentPush, accessToken: String) async throws -> Int64 {
        let body = try Self.saveBody(push)
        let data = try await rpc(name: "save_document", body: body, accessToken: accessToken)
        return try Self.revision(from: data)
    }

    /// Every board row the signed-in owner still has on the server.
    func listOwnDocumentIDs(ownerID: UUID, accessToken: String) async throws -> [UUID] {
        let url = Self.ownDocumentsURL(base: config.url, ownerID: ownerID)
        var request = URLRequest(url: url)
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SupabaseDocumentSyncError.requestFailed
        }
        return try Self.documentIDs(from: data)
    }

    /// Removes dead boards. Child rows cascade when their parent is deleted.
    func deleteDocuments(ids: [UUID], accessToken: String) async throws {
        guard !ids.isEmpty else { return }
        _ = try await rpc(
            name: "delete_documents",
            body: ["p_ids": ids.map { $0.uuidString.lowercased() }],
            accessToken: accessToken
        )
    }

    /// Drops media rows that pointed at boards about to be deleted.
    func deleteMedia(forDocumentIDs ids: [UUID], accessToken: String) async throws {
        guard !ids.isEmpty else { return }
        let url = Self.deleteMediaURL(base: config.url, documentIDs: ids)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SupabaseDocumentSyncError.requestFailed
        }
    }

    static func ownDocumentsURL(base: URL, ownerID: UUID) -> URL {
        var components = URLComponents(url: base.appending(path: "rest/v1/documents"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "owner_id", value: "eq.\(ownerID.uuidString.lowercased())"),
            URLQueryItem(name: "select", value: "id")
        ]
        return components?.url ?? base
    }

    static func deleteDocumentsBody(ids: [UUID]) -> [String: Any] {
        ["p_ids": ids.map { $0.uuidString.lowercased() }]
    }

    static func deleteMediaURL(base: URL, documentIDs: [UUID]) -> URL {
        var components = URLComponents(url: base.appending(path: "rest/v1/media_assets"), resolvingAgainstBaseURL: false)
        let list = documentIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")
        components?.queryItems = [
            URLQueryItem(name: "document_id", value: "in.(\(list))")
        ]
        return components?.url ?? base
    }

    static func documentIDs(from data: Data) throws -> [UUID] {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let rows = json as? [[String: Any]] else {
            throw SupabaseDocumentSyncError.unexpectedResponse
        }
        return rows.compactMap { row in
            (row["id"] as? String).flatMap(UUID.init(uuidString:))
        }
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
        guard let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { return nil }
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
        let json = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        if let rows = json as? [[String: Any]], let value = rows.first?["revision"] as? NSNumber {
            return value.int64Value
        }
        if let value = json as? NSNumber {
            return value.int64Value
        }
        throw SupabaseDocumentSyncError.unexpectedResponse
    }

    static func mosaicID(from data: Data) -> UUID? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { return nil }
        if json is NSNull { return nil }
        if let text = json as? String { return UUID(uuidString: text) }
        return nil
    }

    static func error(from data: Data, status: Int) -> SupabaseDocumentSyncError {
        let message = String(data: data, encoding: .utf8) ?? ""
        if message.contains("document deleted") || message.contains("MS404") {
            return .documentDeleted
        }
        if message.contains("revision conflict") || message.contains("P0001") {
            return .revisionConflict
        }
        if message.contains("mosaic exists") || message.contains("23505") {
            return .mosaicExists
        }
        if message.contains("document body too large") {
            return .documentTooLarge
        }
        // Other 409s (a parent board not found yet, say) are not revision conflicts; treating them
        // as one wrote a spurious conflict copy and retried.
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

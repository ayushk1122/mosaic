import AVFoundation
import Foundation
import UIKit

struct ComposerMediaUploadPayload: Equatable, Sendable {
    var kind: String
    var status: String
    var contentType: String
    var original: Data
    var displayJPEG: Data?
    var thumbJPEG: Data?
    var width: Int?
    var height: Int?
    var durationMilliseconds: Int?
}

enum ComposerMediaPreparer {
    static func prepare(fileAt url: URL) async -> ComposerMediaUploadPayload? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        if ComposerMediaKind.isVideo(url.lastPathComponent) {
            return await video(originalURL: url, original: data)
        }
        return photo(original: data, contentType: ComposerMediaKind.contentType(for: url.lastPathComponent))
    }

    static func photo(original: Data, contentType: String) -> ComposerMediaUploadPayload? {
        guard let image = UIImage(data: original) else { return nil }
        let pixelWidth = Int((image.size.width * image.scale).rounded())
        let pixelHeight = Int((image.size.height * image.scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let displaySize = ComposerMediaScale.fitted(
            width: pixelWidth,
            height: pixelHeight,
            longEdge: ComposerMediaScale.displayLongEdge
        )
        let thumbSize = ComposerMediaScale.fitted(
            width: pixelWidth,
            height: pixelHeight,
            longEdge: ComposerMediaScale.thumbLongEdge
        )
        guard let display = jpeg(image, width: displaySize.width, height: displaySize.height, quality: 0.92),
              let thumb = jpeg(image, width: thumbSize.width, height: thumbSize.height, quality: 0.8)
        else { return nil }
        return ComposerMediaUploadPayload(
            kind: "photo",
            status: "ready",
            contentType: contentType,
            original: original,
            displayJPEG: display,
            thumbJPEG: thumb,
            width: pixelWidth,
            height: pixelHeight,
            durationMilliseconds: nil
        )
    }

    private static func video(originalURL: URL, original: Data) async -> ComposerMediaUploadPayload? {
        let asset = AVURLAsset(url: originalURL)
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        let size = await pixelSize(of: asset)
        if let milliseconds = ComposerMediaScale.videoMilliseconds(seconds: seconds) {
            return ComposerMediaUploadPayload(
                kind: "video",
                status: "processing",
                contentType: ComposerMediaKind.contentType(for: originalURL.lastPathComponent),
                original: original,
                displayJPEG: nil,
                thumbJPEG: nil,
                width: size?.width,
                height: size?.height,
                durationMilliseconds: milliseconds
            )
        }
        guard seconds > 10 else { return nil }
        let trimmed = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: trimmed) }
        do {
            let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
            guard let export else { return nil }
            export.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 600))
            try await export.export(to: trimmed, as: .mp4)
            guard let data = try? Data(contentsOf: trimmed), !data.isEmpty else { return nil }
            return ComposerMediaUploadPayload(
                kind: "video",
                status: "processing",
                contentType: "video/mp4",
                original: data,
                displayJPEG: nil,
                thumbJPEG: nil,
                width: size?.width,
                height: size?.height,
                durationMilliseconds: ComposerMediaScale.videoLimitMilliseconds
            )
        } catch {
            return nil
        }
    }

    private static func pixelSize(of asset: AVURLAsset) async -> (width: Int, height: Int)? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        guard let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return nil }
        let oriented = natural.applying(transform)
        let width = Int(abs(oriented.width).rounded())
        let height = Int(abs(oriented.height).rounded())
        guard width > 0, height > 0 else { return nil }
        return (width, height)
    }

    private static func jpeg(_ image: UIImage, width: Int, height: Int, quality: CGFloat) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        return renderer.jpegData(withCompressionQuality: quality) { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}

enum ComposerMediaKind {
    static func isVideo(_ fileName: String) -> Bool {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "mov", "mp4", "m4v":
            true
        default:
            false
        }
    }

    static func contentType(for fileName: String) -> String {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "jpg", "jpeg":
            "image/jpeg"
        case "png":
            "image/png"
        case "heic", "heif":
            "image/heic"
        case "gif":
            "image/gif"
        case "webp":
            "image/webp"
        case "mov":
            "video/quicktime"
        case "mp4", "m4v":
            "video/mp4"
        default:
            "application/octet-stream"
        }
    }
}

struct SupabaseMediaSync: Sendable {
    var config: SupabaseSyncConfig
    var session: URLSession = .shared

    func upload(
        prepared: ComposerMediaUploadPayload,
        ownerID: UUID,
        assetID: UUID,
        documentID: UUID,
        accessToken: String
    ) async throws {
        let originalPath = ComposerMediaCatalog.objectPath(ownerID: ownerID, assetID: assetID, name: "original")
        try await put(
            data: prepared.original,
            path: originalPath,
            contentType: prepared.contentType,
            accessToken: accessToken
        )
        var displayPath: String?
        var thumbPath: String?
        if let display = prepared.displayJPEG {
            let path = ComposerMediaCatalog.objectPath(ownerID: ownerID, assetID: assetID, name: "display")
            try await put(data: display, path: path, contentType: "image/jpeg", accessToken: accessToken)
            displayPath = path
        }
        if let thumb = prepared.thumbJPEG {
            let path = ComposerMediaCatalog.objectPath(ownerID: ownerID, assetID: assetID, name: "thumb")
            try await put(data: thumb, path: path, contentType: "image/jpeg", accessToken: accessToken)
            thumbPath = path
        }
        try await insert(
            prepared: prepared,
            ownerID: ownerID,
            assetID: assetID,
            documentID: documentID,
            originalPath: originalPath,
            displayPath: displayPath,
            thumbPath: thumbPath,
            accessToken: accessToken
        )
    }

    static func insertBody(
        prepared: ComposerMediaUploadPayload,
        ownerID: UUID,
        assetID: UUID,
        documentID: UUID,
        originalPath: String,
        displayPath: String?,
        thumbPath: String?
    ) -> [String: Any] {
        var body: [String: Any] = [
            "id": assetID.uuidString.lowercased(),
            "owner_id": ownerID.uuidString.lowercased(),
            "document_id": documentID.uuidString.lowercased(),
            "kind": prepared.kind,
            "status": prepared.status,
            "original_path": originalPath,
            "byte_size": prepared.original.count,
            "content_type": prepared.contentType
        ]
        if let displayPath { body["display_path"] = displayPath }
        if let thumbPath { body["thumb_path"] = thumbPath }
        if let width = prepared.width { body["width"] = width }
        if let height = prepared.height { body["height"] = height }
        if let duration = prepared.durationMilliseconds { body["duration_ms"] = duration }
        return body
    }

    private func put(data: Data, path: String, contentType: String, accessToken: String) async throws {
        let root = config.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/storage/v1/object/media/\(path)") else {
            throw SupabaseDocumentSyncError.requestFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            _ = responseData
            throw SupabaseDocumentSyncError.requestFailed
        }
    }

    private func insert(
        prepared: ComposerMediaUploadPayload,
        ownerID: UUID,
        assetID: UUID,
        documentID: UUID,
        originalPath: String,
        displayPath: String?,
        thumbPath: String?,
        accessToken: String
    ) async throws {
        let endpoint = config.url
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("media_assets")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.insertBody(
            prepared: prepared,
            ownerID: ownerID,
            assetID: assetID,
            documentID: documentID,
            originalPath: originalPath,
            displayPath: displayPath,
            thumbPath: thumbPath
        ))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            _ = data
            throw SupabaseDocumentSyncError.requestFailed
        }
    }
}

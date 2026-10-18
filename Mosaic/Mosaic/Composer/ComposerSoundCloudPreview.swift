import Foundation
import UIKit

/// SoundCloud publishes title and artwork through oEmbed without requiring an API key.
enum ComposerSoundCloudPreview {
    struct Preview {
        var title: String?
        var image: UIImage?
    }

    static func isTrustedImageHost(_ host: String) -> Bool {
        let name = host.lowercased()
        return name == "i1.sndcdn.com"
            || name == "i2.sndcdn.com"
            || name == "i3.sndcdn.com"
            || name == "i4.sndcdn.com"
            || name.hasSuffix(".sndcdn.com")
            || name == "soundcloud.com"
            || name.hasSuffix(".soundcloud.com")
    }

    /// `https://on.soundcloud.com/<code>` — what the SoundCloud app copies when sharing a track.
    static func shareLink(from input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: text),
              parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.host?.lowercased() == "on.soundcloud.com" else { return nil }
        let path = parts.path.split(separator: "/").map(String.init)
        guard path.count == 1,
              (4...64).contains(path[0].count),
              path[0].range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://on.soundcloud.com/\(path[0])")
    }

    /// Follows the share link's redirect. A HEAD request reads where it lands without downloading
    /// the page; a server that refuses HEAD gets one ordinary request instead.
    static func resolveShareLink(_ url: URL) async -> URL? {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        for method in ["HEAD", "GET"] {
            var request = URLRequest(url: url, timeoutInterval: 12)
            request.httpMethod = method
            request.setValue("Mozilla/5.0 (compatible; MosaicLinkPreview/1.0)", forHTTPHeaderField: "User-Agent")
            guard let (_, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse else { return nil }
            if method == "HEAD", http.statusCode == 405 || http.statusCode == 501 { continue }
            guard (200..<400).contains(http.statusCode),
                  let final = http.url,
                  final.scheme?.lowercased() == "https",
                  let host = final.host?.lowercased(),
                  host == "soundcloud.com" || host == "www.soundcloud.com" || host == "m.soundcloud.com"
            else { return nil }
            return final
        }
        return nil
    }

    static func oEmbedURL(for contentURL: URL) -> URL? {
        var parts = URLComponents(string: "https://soundcloud.com/oembed")
        parts?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "url", value: contentURL.absoluteString)
        ]
        return parts?.url
    }

    static func preview(fromJSON data: Data) -> (title: String?, imageURL: URL?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let title = (json["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTitle = (title?.isEmpty == false) ? title : nil
        var imageURL: URL?
        if let raw = json["thumbnail_url"] as? String,
           let url = URL(string: raw),
           url.scheme?.lowercased() == "https",
           let host = url.host,
           isTrustedImageHost(host) {
            imageURL = url
        }
        if cleanedTitle == nil && imageURL == nil { return nil }
        return (cleanedTitle, imageURL)
    }

    static func fetch(for url: URL) async -> Preview? {
        guard let oEmbed = oEmbedURL(for: url) else { return nil }
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: oEmbed, timeoutInterval: 12)
        request.setValue("Mozilla/5.0 (compatible; MosaicLinkPreview/1.0)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let parsed = preview(fromJSON: data) else { return nil }
        var preview = Preview(title: parsed.title)
        if let imageURL = parsed.imageURL,
           let (imageData, imageResponse) = try? await session.data(for: URLRequest(url: imageURL, timeoutInterval: 12)),
           (imageResponse as? HTTPURLResponse)?.statusCode == 200,
           imageData.count < 20_000_000 {
            preview.image = UIImage(data: imageData)
        }
        return preview.title == nil && preview.image == nil ? nil : preview
    }
}

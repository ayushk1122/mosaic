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

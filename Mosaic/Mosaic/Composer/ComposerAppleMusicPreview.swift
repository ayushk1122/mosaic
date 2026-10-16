import Foundation
import UIKit

/// Apple Music pages expose title and artwork in Open Graph tags. Artwork is only loaded from
/// Apple's media CDN.
enum ComposerAppleMusicPreview {
    struct Preview {
        var title: String?
        var image: UIImage?
    }

    static let userAgent = "Mozilla/5.0 (compatible; MosaicLinkPreview/1.0)"

    static func isTrustedImageHost(_ host: String) -> Bool {
        let name = host.lowercased()
        return name.hasSuffix(".mzstatic.com") || name == "mzstatic.com"
    }

    static func metaTags(inHTML html: String) -> [String: String] {
        var tags: [String: String] = [:]
        var rest = html[...]
        while let start = rest.range(of: "<meta "),
              let end = rest.range(of: ">", range: start.upperBound..<rest.endIndex) {
            let tag = rest[start.lowerBound..<end.lowerBound]
            if let key = attribute("property", in: tag) ?? attribute("name", in: tag),
               let content = attribute("content", in: tag), tags[key] == nil {
                tags[key] = decodeEntities(content)
            }
            rest = rest[end.upperBound...]
        }
        return tags
    }

    static func imageURL(in tags: [String: String]) -> URL? {
        guard let raw = tags["og:image"] ?? tags["og:image:secure_url"] ?? tags["twitter:image"],
              let url = URL(string: raw), url.scheme?.lowercased() == "https",
              let host = url.host, isTrustedImageHost(host) else { return nil }
        return url
    }

    static func title(in tags: [String: String]) -> String? {
        let candidates = [tags["og:title"], tags["twitter:title"], tags["apple:title"]]
        for raw in candidates {
            let cleaned = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cleaned.isEmpty, cleaned.lowercased() != "apple music" else { continue }
            return cleaned
        }
        return nil
    }

    static func fetch(for url: URL) async -> Preview? {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        var page = URLRequest(url: url, timeoutInterval: 12)
        page.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (html, response) = try? await session.data(for: page),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let tags = metaTags(inHTML: String(decoding: html, as: UTF8.self))
        var preview = Preview(title: title(in: tags))
        if let imageURL = imageURL(in: tags),
           let (data, imageResponse) = try? await session.data(for: URLRequest(url: imageURL, timeoutInterval: 12)),
           (imageResponse as? HTTPURLResponse)?.statusCode == 200,
           data.count < 20_000_000 {
            preview.image = UIImage(data: data)
        }
        return preview.title == nil && preview.image == nil ? nil : preview
    }

    private static func attribute(_ name: String, in tag: Substring) -> String? {
        for quote in ["\"", "'"] {
            if let start = tag.range(of: " \(name)=\(quote)"),
               let end = tag.range(of: quote, range: start.upperBound..<tag.endIndex) {
                return String(tag[start.upperBound..<end.lowerBound])
            }
        }
        return nil
    }

    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = text[...]
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            guard let semi = rest[amp...].firstIndex(of: ";"),
                  let decoded = entity(String(rest[rest.index(after: amp)..<semi])) else {
                result.append("&")
                rest = rest[rest.index(after: amp)...]
                continue
            }
            result.append(decoded)
            rest = rest[rest.index(after: semi)...]
        }
        return result + rest
    }

    private static func entity(_ name: String) -> Character? {
        switch name {
        case "amp": return "&"
        case "quot": return "\""
        case "apos": return "'"
        case "lt": return "<"
        case "gt": return ">"
        default:
            let number = name.hasPrefix("#x") || name.hasPrefix("#X")
                ? UInt32(name.dropFirst(2), radix: 16)
                : name.hasPrefix("#") ? UInt32(name.dropFirst()) : nil
            return number.flatMap(Unicode.Scalar.init).map(Character.init)
        }
    }
}

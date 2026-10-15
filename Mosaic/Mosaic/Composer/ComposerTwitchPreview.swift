import UIKit

/// Twitch builds its pages in the browser, so Link Presentation gets no title or thumbnail. Twitch
/// writes them into the page only for link-preview bots, so clips and VODs are read that way.
/// Short `clips.twitch.tv` links and missing videos get Twitch's generic logo, which is skipped.
enum ComposerTwitchPreview {
    struct Preview {
        var title: String?
        var image: UIImage?
    }

    static let userAgent = "Mozilla/5.0 (compatible; MosaicLinkPreview/1.0)"

    /// `og:` and `twitter:` tags by name. The first tag with a name wins.
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

    /// Only Twitch's own image host is trusted, and its generic logo is not a thumbnail.
    static func imageURL(in tags: [String: String]) -> URL? {
        guard let raw = tags["og:image"] ?? tags["twitter:image"],
              let url = URL(string: raw), url.scheme == "https",
              url.host?.lowercased() == "static-cdn.jtvnw.net",
              !url.path.hasPrefix("/ttv-static-metadata/") else { return nil }
        return url
    }

    /// Clips and VODs are titled "Title - channel on Twitch"; generic pages ("Twitch", "VOD - Twitch")
    /// aren't, so they give no title.
    static func title(in tags: [String: String]) -> String? {
        guard let full = tags["og:title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              full.hasSuffix(" on Twitch"),
              let dash = full.range(of: " - ", options: .backwards) else { return nil }
        let title = full[..<dash.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    /// Twitch answers the first request for a VOD it hasn't served lately with its generic page,
    /// and the real one about a second later, so the page is asked for a few times.
    static func fetch(for url: URL, attempts: Int = 4) async -> Preview? {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        var page = URLRequest(url: url, timeoutInterval: 12)
        page.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        var tags: [String: String] = [:]
        for attempt in 0..<attempts {
            if attempt > 0 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return nil }
            }
            guard let (html, response) = try? await session.data(for: page),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            tags = metaTags(inHTML: String(decoding: html, as: UTF8.self))
            if imageURL(in: tags) != nil { break }
        }
        var preview = Preview(title: title(in: tags))
        if let imageURL = imageURL(in: tags),
           let (data, response) = try? await session.data(for: URLRequest(url: imageURL, timeoutInterval: 12)),
           (response as? HTTPURLResponse)?.statusCode == 200,
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

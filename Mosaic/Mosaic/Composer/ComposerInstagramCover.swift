import UIKit

/// Instagram's link preview image is often a square crop or a small poster. The public embed page
/// carries the full, uncropped image, so Instagram covers come from there when it's reachable.
enum ComposerInstagramCover {
    static func embedURL(for postURL: URL) -> URL? {
        let path = postURL.path.split(separator: "/").map(String.init)
        guard path.count == 2, ["p", "reel", "reels", "tv"].contains(path[0]),
              path[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { return nil }
        return URL(string: "https://www.instagram.com/p/\(path[1])/embed/")
    }

    /// Only Instagram's own image hosts are trusted.
    static func imageURL(inEmbedHTML html: String) -> URL? {
        guard let marker = html.range(of: "EmbeddedMediaImage"),
              let tagStart = html.range(of: "<img", options: .backwards, range: html.startIndex..<marker.lowerBound),
              let tagEnd = html.range(of: ">", range: marker.upperBound..<html.endIndex) else { return nil }
        let tag = html[tagStart.lowerBound..<tagEnd.lowerBound]
        guard let srcStart = tag.range(of: " src=\""),
              let srcEnd = tag.range(of: "\"", range: srcStart.upperBound..<tag.endIndex) else { return nil }
        let raw = tag[srcStart.upperBound..<srcEnd.lowerBound].replacingOccurrences(of: "&amp;", with: "&")
        guard let url = URL(string: raw), url.scheme == "https", let host = url.host?.lowercased(),
              host.hasSuffix(".cdninstagram.com") || host.hasSuffix(".fbcdn.net") else { return nil }
        return url
    }

    static func fetch(for postURL: URL) async -> UIImage? {
        guard let embed = embedURL(for: postURL) else { return nil }
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        var page = URLRequest(url: embed, timeoutInterval: 12)
        page.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                      forHTTPHeaderField: "User-Agent")
        guard let (html, _) = try? await session.data(for: page),
              let imageURL = imageURL(inEmbedHTML: String(decoding: html, as: UTF8.self)),
              let (data, response) = try? await session.data(for: URLRequest(url: imageURL, timeoutInterval: 12)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 20_000_000 else { return nil }
        return UIImage(data: data)
    }
}

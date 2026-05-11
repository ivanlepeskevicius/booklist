import Foundation

struct ImportService {

    struct ParsedBookmark: Identifiable {
        let id = UUID()
        let title: String
        let url: String
        var folderPath: String?
    }

    // MARK: - Netscape HTML (Chrome, Safari, Firefox, Edge)

    /// Parses a Netscape Bookmark File Format HTML string into flat ParsedBookmark list.
    static func parseNetscapeHTML(_ html: String) -> [ParsedBookmark] {
        var results: [ParsedBookmark] = []
        var folderStack: [String] = []

        // Tokenize: find all H3 (folder), A (link), and /DL (folder close) tags.
        let pattern = #"(?i)<H3[^>]*>([^<]+)</H3>|<A\s+HREF="([^"]+)"[^>]*>([^<]*)</A>|</DL>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return results }

        let ns = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: ns) {
            // H3 folder name
            if let r = Range(match.range(at: 1), in: html), !html[r].isEmpty {
                folderStack.append(String(html[r]).trimmingCharacters(in: .whitespaces))
                continue
            }
            // A href + title
            if let hrefRange = Range(match.range(at: 2), in: html),
               let titleRange = Range(match.range(at: 3), in: html) {
                let url   = String(html[hrefRange])
                let title = String(html[titleRange]).trimmingCharacters(in: .whitespaces)
                guard url.hasPrefix("http://") || url.hasPrefix("https://") else { continue }
                let path  = folderStack.isEmpty ? nil : folderStack.joined(separator: " / ")
                results.append(ParsedBookmark(title: title.isEmpty ? url : title,
                                              url: url,
                                              folderPath: path))
                continue
            }
            // /DL closes the current folder level
            if !folderStack.isEmpty { folderStack.removeLast() }
        }

        return results
    }

    // MARK: - Arc shared folder

    /// Fetches an Arc shared folder URL and returns its bookmarks.
    /// Tries __NEXT_DATA__ JSON extraction first, falls back to link scraping.
    static func fetchArcFolder(urlString: String) async throws -> [ParsedBookmark] {
        guard let url = URL(string: urlString) else {
            throw ImportError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                         + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
                         + "Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.noContent
        }

        // --- Try __NEXT_DATA__ JSON first ---
        if let json = extractNextData(from: html) {
            var results: [ParsedBookmark] = []
            extractBookmarks(from: json, into: &results)
            if !results.isEmpty { return results }
        }

        // --- Fallback: scrape external links ---
        let baseHost = url.host
        let scraped = scrapeExternalLinks(from: html, baseHost: baseHost)
        if scraped.isEmpty { throw ImportError.noBookmarksFound }
        return scraped
    }

    // MARK: - Private helpers

    /// Extracts the parsed __NEXT_DATA__ JSON object from a Next.js page.
    private static func extractNextData(from html: String) -> Any? {
        let pattern = #"<script id="__NEXT_DATA__"[^>]*type="application/json"[^>]*>(\{.+?\})</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        let jsonString = String(html[range])
        return try? JSONSerialization.jsonObject(with: Data(jsonString.utf8))
    }

    /// Recursively walks an Any (JSON) tree and collects objects that look like bookmarks
    /// (have a "url" / "URL" key that starts with http).
    private static func extractBookmarks(from obj: Any, into results: inout [ParsedBookmark]) {
        if let dict = obj as? [String: Any] {
            let urlValue = (dict["url"] ?? dict["URL"] ?? dict["href"]) as? String
            if let urlStr = urlValue,
               urlStr.hasPrefix("http://") || urlStr.hasPrefix("https://") {
                let title = (dict["title"] ?? dict["name"] ?? dict["label"]) as? String ?? urlStr
                results.append(ParsedBookmark(title: title, url: urlStr))
                // Don't recurse into a bookmark node — avoids double-counting nested keys
                return
            }
            for value in dict.values { extractBookmarks(from: value, into: &results) }
        } else if let array = obj as? [Any] {
            for item in array { extractBookmarks(from: item, into: &results) }
        }
    }

    /// Last-resort: scrape all <a href> links that are on a different host than the page itself.
    private static func scrapeExternalLinks(from html: String, baseHost: String?) -> [ParsedBookmark] {
        let pattern = #"<a\s[^>]*href=["']([^"']+)["'][^>]*>([^<]*)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }

        var seen = Set<String>()
        var results: [ParsedBookmark] = []
        let ns = NSRange(html.startIndex..., in: html)

        for match in regex.matches(in: html, range: ns) {
            guard let hrefRange  = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { continue }
            let urlStr = String(html[hrefRange])
            guard urlStr.hasPrefix("http://") || urlStr.hasPrefix("https://") else { continue }
            guard let host = URL(string: urlStr)?.host, host != baseHost else { continue }
            guard !seen.contains(urlStr) else { continue }
            seen.insert(urlStr)
            let title = String(html[titleRange]).trimmingCharacters(in: .whitespaces)
            results.append(ParsedBookmark(title: title.isEmpty ? urlStr : title, url: urlStr))
        }
        return results
    }

    // MARK: - Errors

    enum ImportError: LocalizedError {
        case invalidURL
        case noContent
        case noBookmarksFound

        var errorDescription: String? {
            switch self {
            case .invalidURL:         return "The URL entered doesn't look valid."
            case .noContent:          return "Couldn't load the page. Check your connection."
            case .noBookmarksFound:   return "No bookmarks were found at that URL."
            }
        }
    }
}

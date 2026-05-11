import Foundation
import AppKit

/// Fetches a webpage and extracts its main readable content as a formatted AttributedString.
/// Colors are stripped so the result adapts correctly to light and dark mode.
actor ReaderService {
    static let shared = ReaderService()
    private init() {}

    /// Cache of cleaned (noise-stripped) HTML keyed by URL string.
    /// Re-rendering with different font settings uses this cache instead of the network.
    private var cleanedCache: [String: String] = [:]

    // MARK: - Public API

    /// Fetches the page, caches the cleaned HTML, and builds a styled AttributedString.
    func fetchReadableContent(
        from urlString: String,
        fontName: String = "",
        baseFontSize: Int = 15
    ) async throws -> AttributedString {
        let cleaned = try await cleanedHTML(for: urlString)
        return try await buildAttributedString(from: cleaned, fontName: fontName, baseFontSize: baseFontSize)
    }

    /// Rebuilds from the cached cleaned HTML without a network fetch.
    /// Returns nil if the URL has not been fetched yet in this session.
    func rebuildFromCache(
        url urlString: String,
        fontName: String,
        baseFontSize: Int
    ) async throws -> AttributedString? {
        guard let cleaned = cleanedCache[urlString] else { return nil }
        return try await buildAttributedString(from: cleaned, fontName: fontName, baseFontSize: baseFontSize)
    }

    // MARK: - Private — fetching and caching

    private func cleanedHTML(for urlString: String) async throws -> String {
        if let cached = cleanedCache[urlString] { return cached }
        let raw = try await fetchRawHTML(from: urlString)
        var content = extractPrimaryContent(raw)
        content = stripNoiseTags(content)
        content = collapseBlankLines(content)
        cleanedCache[urlString] = content
        return content
    }

    private func fetchRawHTML(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1) else {
            throw URLError(.cannotDecodeContentData)
        }
        return html
    }

    // MARK: - Private — styled AttributedString

    private func buildAttributedString(
        from cleanedHTML: String,
        fontName: String,
        baseFontSize: Int
    ) async throws -> AttributedString {
        let bodySize  = baseFontSize
        let h1Size    = Int((Double(baseFontSize) * 1.40).rounded())
        let h2Size    = Int((Double(baseFontSize) * 1.13).rounded())
        let smallSize = max(Int((Double(baseFontSize) * 0.93).rounded()), 10)
        let codeSize  = max(Int((Double(baseFontSize) * 0.87).rounded()), 10)

        // Code always uses a monospace font regardless of the user's body font choice.
        let fontStack = fontName.isEmpty
            ? "-apple-system, BlinkMacSystemFont, sans-serif"
            : "\"\(fontName)\", -apple-system, sans-serif"

        let css = """
          body  { font-family: \(fontStack);
                  font-size: \(bodySize)px; line-height: 1.75; word-wrap: break-word; }
          h1    { font-size: \(h1Size)px; font-weight: 700; margin: 0 0 10px; line-height: 1.3; }
          h2    { font-size: \(h2Size)px; font-weight: 600; margin: 20px 0 6px; line-height: 1.4; }
          h3    { font-size: \(bodySize)px; font-weight: 600; margin: 16px 0 4px; }
          h4,h5,h6 { font-size: \(smallSize)px; font-weight: 600; margin: 12px 0 4px; }
          p     { margin: 0 0 12px; }
          ul,ol { margin: 0 0 12px; padding-left: 22px; }
          li    { margin: 2px 0; line-height: 1.65; }
          blockquote { margin: 14px 0; padding: 10px 14px;
                       border-left: 3px solid #999; font-style: italic; }
          pre   { margin: 0 0 12px; padding: 12px 16px;
                  background: rgba(128,128,128,0.08); border-radius: 6px;
                  white-space: pre-wrap; overflow-wrap: break-word; }
          code  { font-family: "SF Mono", Menlo, monospace; font-size: \(codeSize)px;
                  background: rgba(128,128,128,0.08); padding: 1px 4px; border-radius: 3px; }
          pre code { background: none; padding: 0; }
          a     { text-decoration: none; color: inherit; }
          img, figure, picture, video, audio,
          [role="banner"], [role="navigation"], [role="complementary"],
          [aria-hidden="true"] { display: none; }
        """
        let styled = "<html><head><meta charset=\"utf-8\"><style>\(css)</style></head><body>\(cleanedHTML)</body></html>"

        // NSAttributedString HTML parsing must run on the main thread
        return try await MainActor.run {
            guard let data = styled.data(using: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }

            let nsAttr = try NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: NSUTF8StringEncoding
                ],
                documentAttributes: nil
            )

            // Strip colors and link styling so text adapts to dark mode
            let mutable = NSMutableAttributedString(attributedString: nsAttr)
            let fullRange = NSRange(location: 0, length: mutable.length)
            mutable.removeAttribute(.foregroundColor, range: fullRange)
            mutable.removeAttribute(.backgroundColor, range: fullRange)
            mutable.removeAttribute(.underlineStyle, range: fullRange)
            mutable.removeAttribute(.link, range: fullRange)

            return try AttributedString(mutable, including: \.appKit)
        }
    }

    // MARK: - Private — HTML extraction helpers

    /// Returns the content of the first <article> or <main> tag, falling back to <body>.
    private func extractPrimaryContent(_ html: String) -> String {
        for tag in ["article", "main", "body"] {
            if let extracted = firstTagContent(tag, in: html) {
                return extracted
            }
        }
        return html
    }

    private func firstTagContent(_ tag: String, in html: String) -> String? {
        let pattern = "(?is)<\(tag)(\\s[^>]*)?>.*?</\(tag)>"
        guard let range = html.range(of: pattern, options: .regularExpression) else { return nil }
        return String(html[range])
    }

    /// Removes tag blocks whose content would distract from the article text.
    private func stripNoiseTags(_ html: String) -> String {
        let tags = [
            // Layout / navigation chrome
            "script", "style", "nav", "header", "footer", "aside",
            "iframe", "noscript", "svg", "dialog",
            // Form and interactive controls (render as garbage text)
            "form", "button", "select", "option", "input", "textarea",
            // Tables often display as a jumbled stream of text without layout
            "table", "thead", "tbody", "tfoot", "tr", "th", "td",
        ]
        var result = html
        for tag in tags {
            // Remove opening-to-closing block (including all nested content)
            result = result.replacingOccurrences(
                of: "(?is)<\(tag)(\\s[^>]*)?>.*?</\(tag)>",
                with: " ",
                options: .regularExpression
            )
            // Remove self-closing / void occurrences
            result = result.replacingOccurrences(
                of: "(?i)<\(tag)[^>]*/?>" ,
                with: " ",
                options: .regularExpression
            )
        }
        return result
    }

    /// Collapses runs of blank lines and empty paragraph tags left by stripped elements.
    private func collapseBlankLines(_ html: String) -> String {
        var result = html
        // 3+ consecutive <br> tags → at most 2
        result = result.replacingOccurrences(
            of: "(?i)(<br\\s*/?>\\s*){3,}",
            with: "<br><br>",
            options: .regularExpression
        )
        // Runs of completely empty <p> elements → remove them
        result = result.replacingOccurrences(
            of: "(?i)(<p[^>]*>\\s*</p>\\s*)+",
            with: "",
            options: .regularExpression
        )
        // Empty <li> items left when their child elements were stripped → remove them
        result = result.replacingOccurrences(
            of: "(?is)<li[^>]*>\\s*</li>",
            with: "",
            options: .regularExpression
        )
        return result
    }
}

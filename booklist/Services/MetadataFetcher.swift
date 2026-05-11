import Foundation

// MARK: - Result type

struct PageMetadata {
    let title: String
    let description: String?
    let faviconURL: String?
    /// All candidate images, ordered by relevance: OG image first, then Twitter card, then <img> tags.
    let imageURLs: [String]
    /// Auto-extracted price for e-commerce pages (from JSON-LD or OG Commerce meta tags); nil otherwise.
    let price: String?
}

// MARK: - Errors

enum MetadataFetchError: LocalizedError {
    case invalidURL
    case network(Error)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That doesn't look like a valid URL."
        case .network(let e):
            if let nsErr = e as NSError?, nsErr.domain == "HTTP" {
                switch nsErr.code {
                case 403, 429: return "This site blocks automated requests — you can still fill in the details manually."
                case 404:      return "Page not found (404)."
                default:       return "Server returned HTTP \(nsErr.code)."
                }
            }
            return "Couldn't reach the page: \(e.localizedDescription)"
        case .decodingFailed:
            return "Couldn't read the page content."
        }
    }
}

// MARK: - Fetcher

struct MetadataFetcher {

    /// Fetches the HTML at `urlString` and returns extracted metadata.
    static func fetch(urlString: String) async throws -> PageMetadata {
        guard let url = URL(string: urlString) else {
            throw MetadataFetchError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        // Match Safari's real request headers as closely as possible.
        // More complete headers help bypass lighter bot-detection systems.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        request.setValue("navigate",  forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("document",  forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("none",      forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("?1",        forHTTPHeaderField: "Sec-Fetch-User")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw MetadataFetchError.network(error)
        }

        if let http = response as? HTTPURLResponse {
            let code = http.statusCode
            // 403 / 429 = bot-protection wall. Try to parse the response anyway — some
            // pages still embed JSON-LD even in their error responses. If nothing useful
            // comes back, the caller already shows a manual-entry fallback.
            if code == 404 || (code >= 400 && code != 403 && code != 429) || code >= 500 {
                throw MetadataFetchError.network(
                    NSError(domain: "HTTP", code: code,
                            userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(code)."])
                )
            }
        }

        let html = decoded(data: data, response: response)
        return parse(html: html, baseURL: url)
    }

    // MARK: - Charset detection

    /// Decodes `data` respecting the HTTP Content-Type charset, then falls back to
    /// UTF-8 → Windows-1252 (common for European retailers) → ISO-8859-1.
    private static func decoded(data: Data, response: URLResponse) -> String {
        if let http = response as? HTTPURLResponse,
           let charsetName = http.textEncodingName {
            let cfEnc = CFStringConvertIANACharSetNameToEncoding(charsetName as CFString)
            if cfEnc != kCFStringEncodingInvalidId {
                let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
                if let s = String(data: data, encoding: String.Encoding(rawValue: nsEnc)) {
                    return s
                }
            }
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: - HTML parsing

    private static func parse(html: String, baseURL: URL) -> PageMetadata {
        let title = ogMeta("og:title", in: html)
            ?? titleTag(in: html)
            ?? baseURL.host
            ?? "Untitled"

        let description = ogMeta("og:description", in: html)
            ?? namedMeta("description", in: html)

        let faviconURL = faviconHref(in: html, baseURL: baseURL)
            ?? "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")/favicon.ico"

        let price = extractPrice(from: html)

        var images: [String] = []
        func addImage(_ raw: String?) {
            guard let raw,
                  let resolved = resolveURL(raw, baseURL: baseURL),
                  !images.contains(resolved) else { return }
            images.append(resolved)
        }
        addImage(ogMeta("og:image",         in: html))
        addImage(ogMeta("og:image:url",     in: html))
        addImage(namedMeta("twitter:image",     in: html))
        addImage(namedMeta("twitter:image:src", in: html))
        for src in imgSrcs(in: html) {
            addImage(src)
            if images.count >= 24 { break }
        }

        return PageMetadata(
            title: clean(title),
            description: description.map(clean),
            faviconURL: faviconURL,
            imageURLs: images,
            price: price
        )
    }

    // MARK: - Price extraction

    /// Tries JSON-LD first (most reliable), then OG Commerce / itemprop meta tags.
    private static func extractPrice(from html: String) -> String? {
        if let price = jsonLDPrice(in: html)       { return price }
        if let price = metaTagPrice(in: html)      { return price }
        return nil
    }

    // -- JSON-LD --

    private static func jsonLDPrice(in html: String) -> String? {
        let scripts = allCaptures(
            "<script[^>]+type=[\"']application/ld\\+json[\"'][^>]*>([\\s\\S]*?)</script>",
            in: html, options: .caseInsensitive
        )
        for raw in scripts {
            guard let data = raw.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
                  let obj  = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let dict  = obj as? [String: Any],  let p = priceFromLDObject(dict)  { return p }
            if let array = obj as? [[String: Any]] {
                for dict in array { if let p = priceFromLDObject(dict) { return p } }
            }
        }
        return nil
    }

    private static func priceFromLDObject(_ obj: [String: Any]) -> String? {
        // Recurse into @graph arrays
        if let graph = obj["@graph"] as? [[String: Any]] {
            for item in graph { if let p = priceFromLDObject(item) { return p } }
        }
        let type = (obj["@type"] as? String ?? "").lowercased()
        if type == "product" {
            return priceFromOffers(obj["offers"])
        }
        if type == "offer" || type == "aggregateoffer" {
            return formatOffer(obj)
        }
        return nil
    }

    private static func priceFromOffers(_ offers: Any?) -> String? {
        if let single = offers as? [String: Any]   { return formatOffer(single) }
        if let list   = offers as? [[String: Any]] { return list.compactMap(formatOffer).first }
        return nil
    }

    private static func formatOffer(_ offer: [String: Any]) -> String? {
        let raw: String
        if      let s = offer["price"] as? String { raw = s }
        else if let d = offer["price"] as? Double { raw = String(format: "%.2f", d) }
        else if let i = offer["price"] as? Int    { raw = String(i) }
        else { return nil }

        guard !raw.isEmpty, raw != "0", raw != "0.0", raw != "0.00" else { return nil }
        let currency = offer["priceCurrency"] as? String ?? ""
        return formattedPrice(raw, currency: currency)
    }

    // -- OG Commerce / itemprop meta tags --

    private static func metaTagPrice(in html: String) -> String? {
        // Facebook Open Graph Commerce: <meta property="product:price:amount" content="299.00">
        if let amount = ogMeta("product:price:amount", in: html) {
            let currency = ogMeta("product:price:currency", in: html) ?? ""
            return formattedPrice(amount, currency: currency)
        }
        // <meta property="og:price:amount" content="...">
        if let amount = ogMeta("og:price:amount", in: html) {
            let currency = ogMeta("og:price:currency", in: html) ?? ""
            return formattedPrice(amount, currency: currency)
        }
        // <meta itemprop="price" content="..."> (both attribute orderings)
        let itempropPatterns = [
            "<meta[^>]+itemprop=[\"']price[\"'][^>]+content=[\"']([^\"'<>]+)[\"']",
            "<meta[^>]+content=[\"']([^\"'<>]+)[\"'][^>]+itemprop=[\"']price[\"']",
        ]
        return itempropPatterns.lazy.compactMap { firstCapture($0, in: html, options: .caseInsensitive) }.first
    }

    // -- Currency formatting --

    private static func formattedPrice(_ amount: String, currency: String) -> String {
        let symbol: String
        switch currency.uppercased() {
        case "EUR": symbol = "€"
        case "USD": symbol = "$"
        case "GBP": symbol = "£"
        case "JPY", "CNY": symbol = "¥"
        case "CAD": symbol = "CA$"
        case "AUD": symbol = "A$"
        case "CHF": symbol = "CHF "
        case "":    symbol = ""
        default:    symbol = "\(currency) "
        }
        return symbol + amount
    }

    // MARK: - Meta tag extractors

    /// Extracts `content` from `<meta property="KEY" content="VALUE">` (both attribute orderings).
    private static func ogMeta(_ property: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            "<meta[^>]+property=[\"']\\(escaped)[\"'][^>]+content=[\"']([^\"'<>]+)[\"']",
            "<meta[^>]+content=[\"']([^\"'<>]+)[\"'][^>]+property=[\"']\\(escaped)[\"']",
        ]
        return patterns.lazy.compactMap { firstCapture($0, in: html) }.first
    }

    /// Extracts `content` from `<meta name="KEY" content="VALUE">` (both attribute orderings).
    private static func namedMeta(_ name: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            "<meta[^>]+name=[\"']\\(escaped)[\"'][^>]+content=[\"']([^\"'<>]+)[\"']",
            "<meta[^>]+content=[\"']([^\"'<>]+)[\"'][^>]+name=[\"']\\(escaped)[\"']",
        ]
        return patterns.lazy.compactMap { firstCapture($0, in: html, options: .caseInsensitive) }.first
    }

    private static func titleTag(in html: String) -> String? {
        firstCapture("<title[^>]*>([^<]+)</title>", in: html, options: .caseInsensitive)
    }

    private static func faviconHref(in html: String, baseURL: URL) -> String? {
        let pattern = "<link[^>]+rel=[\"'][^\"']*icon[^\"']*[\"'][^>]+href=[\"']([^\"'<>]+)[\"']"
        guard let href = firstCapture(pattern, in: html, options: .caseInsensitive) else { return nil }
        return resolveURL(href, baseURL: baseURL)
    }

    private static func imgSrcs(in html: String) -> [String] {
        let skipWords = ["pixel", "spacer", "blank", "transparent", "tracking", "beacon"]
        return allCaptures("<img[^>]+src=[\"']([^\"'<>]+)[\"']", in: html, options: .caseInsensitive)
            .filter { src in
                !src.hasPrefix("data:")
                && !src.hasSuffix(".svg")
                && !skipWords.contains(where: { src.lowercased().contains($0) })
            }
    }

    // MARK: - URL resolution

    private static func resolveURL(_ raw: String, baseURL: URL) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        if trimmed.hasPrefix("//") { return (baseURL.scheme ?? "https") + ":" + trimmed }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteString
    }

    // MARK: - Regex utilities

    private static func firstCapture(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func allCaptures(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    // MARK: - Text cleanup

    private static func clean(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.contains("  ") { result = result.replacingOccurrences(of: "  ", with: " ") }
        return result
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

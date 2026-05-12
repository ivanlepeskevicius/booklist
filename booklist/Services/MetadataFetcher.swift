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
    /// Non-nil when the page is a Reddit post — used to generate a synthetic card image.
    let redditSubreddit: String?
    let redditAuthor: String?
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

        // Reddit posts: bypass bot protection using their public JSON API
        if isRedditPostURL(url), let meta = try? await fetchRedditPost(url: url) {
            return meta
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
            description: description.map { clean($0) },
            faviconURL: faviconURL,
            imageURLs: images,
            price: price,
            redditSubreddit: nil,
            redditAuthor: nil
        )
    }

    // MARK: - Price extraction

    /// Tries each extraction strategy in order of reliability.
    private static func extractPrice(from html: String) -> String? {
        if let p = jsonLDPrice(in: html)            { return p }
        if let p = metaTagPrice(in: html)           { return p }
        if let p = itempropElementPrice(in: html)   { return p }
        if let p = dataAttributePrice(in: html)     { return p }
        if let p = visiblePriceText(in: html)       { return p }
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
        if let list   = offers as? [[String: Any]] { return list.compactMap { formatOffer($0) }.first }
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
        if let p = itempropPatterns.lazy.compactMap({ firstCapture($0, in: html, options: .caseInsensitive) }).first { return p }
        // <meta name="price" content="..."> (used by some simpler storefronts)
        if let amount = namedMeta("price", in: html), looksLikePrice(amount) { return amount }
        return nil
    }

    // -- Microdata: itemprop="price" on visible elements --

    /// Extracts price from non-meta elements carrying `itemprop="price"`.
    /// Checks the `content=` attribute first (numeric source-of-truth), then visible text.
    private static func itempropElementPrice(in html: String) -> String? {
        for pattern in [
            "<[a-z][^>]+itemprop=[\"']price[\"'][^>]+content=[\"']([^\"'<>]+)[\"']",
            "<[a-z][^>]+content=[\"']([^\"'<>]+)[\"'][^>]+itemprop=[\"']price[\"']",
        ] {
            if let v = firstCapture(pattern, in: html, options: .caseInsensitive)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !v.isEmpty, v != "0", v != "0.0", v != "0.00" { return v }
        }
        // Visible text of span/strong/b/em — screen-reader spans (e.g. "a-offscreen") contain the clean value
        let textPattern = "<(?:span|strong|b|em)[^>]+itemprop=[\"']price[\"'][^>]*>([^<]{1,30})</(?:span|strong|b|em)>"
        if let v = firstCapture(textPattern, in: html, options: .caseInsensitive)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           looksLikePrice(v) { return v }
        return nil
    }

    // -- data-price / data-product-price attributes --

    /// Covers Shopify, WooCommerce, and similar platforms that embed price in data attributes.
    private static func dataAttributePrice(in html: String) -> String? {
        for pattern in [
            #"data-price="([0-9][0-9.,]*)""#,
            #"data-product-price="([0-9][0-9.,]*)""#,
            #"data-current-price="([0-9][0-9.,]*)""#,
            #"data-sale-price="([0-9][0-9.,]*)""#,
        ] {
            if let v = firstCapture(pattern, in: html, options: .caseInsensitive)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !v.isEmpty, v != "0", v != "0.0", v != "0.00" { return v }
        }
        return nil
    }

    // -- Visible text in price-labelled DOM elements --

    /// Last-resort: scans for elements whose class/id contains "price" and extracts short text
    /// that looks like a monetary value. Skips elements labelled as strikethrough/original prices.
    private static func visiblePriceText(in html: String) -> String? {
        let skipWords = ["was", "original", "old", "compare", "strike", "crossed",
                         "before", "regular", "list", "rrp", "msrp", "retail", "from"]
        // Match opening tag with class/id containing "price", followed by short text content.
        // Uses a non-greedy match so nested tags don't bleed into the content capture.
        let pattern = #"<(?:span|div|strong|p|b|em|h[1-6])[^>]+(?:class|id)="[^"]*price[^"]*"[^>]*>\s*([^<\n]{1,30}?)\s*<"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: ns) {
            guard let fullRange = Range(match.range(at: 0), in: html),
                  let textRange = Range(match.range(at: 1), in: html) else { continue }
            let tag  = html[fullRange].lowercased()
            if skipWords.contains(where: { tag.contains($0) }) { continue }
            let text = String(html[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikePrice(text) { return text }
        }
        return nil
    }

    // -- Price validation helper --

    private static func looksLikePrice(_ text: String) -> Bool {
        guard !text.isEmpty, text.count < 25 else { return false }
        guard !text.contains("<"), !text.contains("\n") else { return false }
        guard text.contains(where: { $0.isNumber }) else { return false }
        // Require either a decimal separator or a currency symbol — avoids matching plain integers
        // that could be IDs, counts, or other numeric strings.
        let hasDecimal  = text.contains(".") || text.contains(",")
        let hasCurrency = text.contains(where: { "$€£¥₹₩".contains($0) })
        let hasCurrencyCode = firstCapture(#"\d\s+(?:USD|EUR|GBP|JPY|CAD|AUD|CHF|CNY|INR|KRW|MXN|BRL)\b"#, in: text) != nil
        return hasDecimal || hasCurrency || hasCurrencyCode
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
        let e = NSRegularExpression.escapedPattern(for: property)
        let q = "[\"']"
        let v = "([^\"'<>]+)"
        let patterns = [
            "<meta[^>]+property=" + q + e + q + "[^>]+content=" + q + v + q,
            "<meta[^>]+content=" + q + v + q + "[^>]+property=" + q + e + q,
        ]
        return patterns.lazy.compactMap { firstCapture($0, in: html) }.first
    }

    /// Extracts `content` from `<meta name="KEY" content="VALUE">` (both attribute orderings).
    private static func namedMeta(_ name: String, in html: String) -> String? {
        let e = NSRegularExpression.escapedPattern(for: name)
        let q = "[\"']"
        let v = "([^\"'<>]+)"
        let patterns = [
            "<meta[^>]+name=" + q + e + q + "[^>]+content=" + q + v + q,
            "<meta[^>]+content=" + q + v + q + "[^>]+name=" + q + e + q,
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
        let skipWords = ["pixel", "spacer", "blank", "transparent", "tracking", "beacon",
                         "-thumbnail", "_thumb", "/thumb/", "_small", "_tiny"]
        let minPx = 200

        // Capture the full attribute string of each <img> tag so we can inspect
        // width/height alongside src — plain src-only regex can't do this.
        return allCaptures("<img([^>]+)>", in: html, options: .caseInsensitive)
            .compactMap { attrs -> String? in
                guard let src = firstCapture("src=[\"']([^\"'<>]+)[\"']", in: attrs, options: .caseInsensitive),
                      !src.hasPrefix("data:"),
                      !src.hasSuffix(".svg"),
                      !skipWords.contains(where: { src.lowercased().contains($0) }) else { return nil }

                // Skip if explicit HTML width/height attribute is below threshold.
                if let w = firstCapture(#"\bwidth=["']?(\d+)["']?"#, in: attrs, options: .caseInsensitive).flatMap(Int.init), w < minPx { return nil }
                if let h = firstCapture(#"\bheight=["']?(\d+)["']?"#, in: attrs, options: .caseInsensitive).flatMap(Int.init), h < minPx { return nil }

                // Skip if URL contains a WxH size hint where both sides are tiny (e.g. "32x32").
                if tinyDimensionInURL(src) { return nil }

                return src
            }
    }

    /// Returns true when the URL contains a `WxH` pattern where both dimensions are < 150 px.
    private static func tinyDimensionInURL(_ url: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)[xX](\d+)"#) else { return false }
        let ns = NSRange(url.startIndex..., in: url)
        for match in regex.matches(in: url, range: ns) {
            guard let r1 = Range(match.range(at: 1), in: url),
                  let r2 = Range(match.range(at: 2), in: url),
                  let w = Int(url[r1]), let h = Int(url[r2]) else { continue }
            if w < 250 && h < 250 { return true }
        }
        return false
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

    // MARK: - Reddit JSON API

    private static func isRedditPostURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let isReddit = host == "reddit.com" || host == "www.reddit.com" || host == "old.reddit.com"
        let parts = url.pathComponents // ["/", "r", "subreddit", "comments", "id", ...]
        return isReddit && parts.count >= 5 && parts[1] == "r" && parts[3] == "comments"
    }

    private static func fetchRedditPost(url: URL) async throws -> PageMetadata {
        // Strip query params and ensure .json suffix
        let base = url.absoluteString.components(separatedBy: "?")[0]
        let jsonString = base.hasSuffix("/") ? base + ".json" : base + "/.json"
        guard let jsonURL = URL(string: jsonString) else { throw MetadataFetchError.invalidURL }

        var request = URLRequest(url: jsonURL, timeoutInterval: 20)
        // Reddit requires a descriptive User-Agent for API access
        request.setValue("booklist/1.0 macOS (by /u/booklist_app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw MetadataFetchError.network(
                NSError(domain: "HTTP", code: http.statusCode, userInfo: nil))
        }

        // Response is an array: [postListing, commentsListing]
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let children = (json.first?["data"] as? [String: Any])?["children"] as? [[String: Any]],
              let post = children.first?["data"] as? [String: Any]
        else { throw MetadataFetchError.decodingFailed }

        let title     = (post["title"]     as? String).map { clean($0) } ?? "Reddit Post"
        let selftext  = (post["selftext"]  as? String).flatMap { $0.isEmpty ? nil : clean($0) }
        let subreddit = post["subreddit"]  as? String ?? ""
        let author    = post["author"]     as? String ?? ""

        var images: [String] = []
        // High-res preview image (Reddit HTML-encodes the URL with &amp;)
        if let preview = post["preview"] as? [String: Any],
           let imgList  = preview["images"] as? [[String: Any]],
           var src      = (imgList.first?["source"] as? [String: Any])?["url"] as? String {
            src = src.replacingOccurrences(of: "&amp;", with: "&")
            images.append(src)
        }
        // Thumbnail fallback (skip Reddit placeholder strings like "self", "default")
        if let thumb = post["thumbnail"] as? String, thumb.hasPrefix("http") {
            images.append(thumb)
        }

        return PageMetadata(
            title: title,
            description: selftext,
            faviconURL: "https://www.reddit.com/favicon.ico",
            imageURLs: images,
            price: nil,
            redditSubreddit: subreddit.isEmpty ? nil : subreddit,
            redditAuthor: author.isEmpty ? nil : author
        )
    }

    // MARK: - Text cleanup

    private static func clean(_ text: String) -> String {
        var result = decodeHTMLEntities(text).trimmingCharacters(in: .whitespacesAndNewlines)
        while result.contains("  ") { result = result.replacingOccurrences(of: "  ", with: " ") }
        return result
    }

    /// Decodes HTML character references — numeric (&#225; / &#xE1;) and named (&aacute;).
    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text

        // Numeric decimal: &#225; → á  (process reversed to keep earlier ranges valid)
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range(at: 0), in: result),
                      let numRange = Range(match.range(at: 1), in: result),
                      let codePoint = UInt32(result[numRange]),
                      let scalar = Unicode.Scalar(codePoint) else { continue }
                result.replaceSubrange(range, with: String(scalar))
            }
        }

        // Numeric hex: &#xE1; or &#XE1; → á
        if let regex = try? NSRegularExpression(pattern: "&#[xX]([0-9a-fA-F]+);") {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range(at: 0), in: result),
                      let hexRange = Range(match.range(at: 1), in: result),
                      let codePoint = UInt32(result[hexRange], radix: 16),
                      let scalar = Unicode.Scalar(codePoint) else { continue }
                result.replaceSubrange(range, with: String(scalar))
            }
        }

        // Named entities — common, basic, and typographic
        let namedEntities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "),
            // Uppercase accented Latin
            ("&Agrave;", "À"), ("&Aacute;", "Á"), ("&Acirc;", "Â"), ("&Atilde;", "Ã"),
            ("&Auml;",   "Ä"), ("&Aring;",  "Å"), ("&AElig;", "Æ"), ("&Ccedil;", "Ç"),
            ("&Egrave;", "È"), ("&Eacute;", "É"), ("&Ecirc;", "Ê"), ("&Euml;",   "Ë"),
            ("&Igrave;", "Ì"), ("&Iacute;", "Í"), ("&Icirc;", "Î"), ("&Iuml;",   "Ï"),
            ("&ETH;",    "Ð"), ("&Ntilde;", "Ñ"), ("&Ograve;", "Ò"), ("&Oacute;", "Ó"),
            ("&Ocirc;",  "Ô"), ("&Otilde;", "Õ"), ("&Ouml;",  "Ö"),
            ("&Oslash;", "Ø"), ("&Ugrave;", "Ù"), ("&Uacute;", "Ú"), ("&Ucirc;", "Û"),
            ("&Uuml;",   "Ü"), ("&Yacute;", "Ý"), ("&THORN;", "Þ"),
            // Lowercase accented Latin
            ("&agrave;", "à"), ("&aacute;", "á"), ("&acirc;", "â"), ("&atilde;", "ã"),
            ("&auml;",   "ä"), ("&aring;",  "å"), ("&aelig;", "æ"), ("&ccedil;", "ç"),
            ("&egrave;", "è"), ("&eacute;", "é"), ("&ecirc;", "ê"), ("&euml;",   "ë"),
            ("&igrave;", "ì"), ("&iacute;", "í"), ("&icirc;", "î"), ("&iuml;",   "ï"),
            ("&eth;",    "ð"), ("&ntilde;", "ñ"), ("&ograve;", "ò"), ("&oacute;", "ó"),
            ("&ocirc;",  "ô"), ("&otilde;", "õ"), ("&ouml;",  "ö"),
            ("&oslash;", "ø"), ("&ugrave;", "ù"), ("&uacute;", "ú"), ("&ucirc;", "û"),
            ("&uuml;",   "ü"), ("&yacute;", "ý"), ("&thorn;", "þ"), ("&yuml;",  "ÿ"),
            ("&szlig;",  "ß"),
            // Math / symbols
            ("&times;",  "×"), ("&divide;", "÷"), ("&plusmn;", "±"),
            ("&frac12;", "½"), ("&frac14;", "¼"), ("&frac34;", "¾"),
            ("&deg;",    "°"), ("&micro;",  "µ"), ("&para;",   "¶"), ("&middot;", "·"),
            ("&acute;",  "´"), ("&cedil;",  "¸"), ("&ordm;",   "º"), ("&ordf;",  "ª"),
            // Currency
            ("&euro;",   "€"), ("&pound;",  "£"), ("&yen;",    "¥"), ("&cent;",  "¢"),
            // Typographic
            ("&copy;",   "©"), ("&reg;",    "®"), ("&trade;",  "™"),
            ("&mdash;",  "—"), ("&ndash;",  "–"), ("&hellip;", "…"),
            ("&lsquo;",  "\u{2018}"), ("&rsquo;", "\u{2019}"),
            ("&ldquo;",  "\u{201C}"), ("&rdquo;", "\u{201D}"),
            ("&laquo;",  "«"), ("&raquo;",  "»"),
        ]
        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        return result
    }
}

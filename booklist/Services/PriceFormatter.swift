import Foundation

/// Normalises prices so they always use the user's preferred currency, whatever format
/// the shop page used ("18 EUR", "18 €", "€18", "EUR 18,99"…).
nonisolated enum PriceFormatter {

    /// The numeric part of a price string, keeping its decimal/thousands separators:
    /// "18 EUR" → "18", "1.299,99 €" → "1.299,99", "$ 1 299.00" → "1299.00".
    /// Returns nil when there's no number at all.
    static func amount(in raw: String) -> String? {
        // Digit groups separated by (non-breaking) spaces, or a run of digits with . and , —
        // always starting and ending on a digit so trailing punctuation is dropped.
        let pattern = #"\d{1,3}(?:[ \u{00A0}\u{202F}]\d{3})+(?:[.,]\d+)?|\d(?:[\d.,]*\d)?"#
        guard let range = raw.range(of: pattern, options: .regularExpression) else { return nil }
        return raw[range].filter { !$0.isWhitespace }
    }

    /// The price as it should be stored: preferred currency symbol + amount ("€18").
    /// Text without any number is kept as typed (e.g. "Free"); empty stays empty.
    static func normalized(_ raw: String, symbol: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = amount(in: trimmed) else { return trimmed }
        return symbol + amount
    }
}

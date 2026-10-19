import Testing
@testable import booklist

@Suite("PriceFormatter")
struct PriceFormatterTests {

    // MARK: - Feedback cases: page currency text must not override the preferred currency

    @Test("\"18 EUR\" is stored with the preferred symbol, not the page's code")
    func currencyCodeAfter() {
        #expect(PriceFormatter.normalized("18 EUR", symbol: "€") == "€18")
    }

    @Test("\"18 €\" is stored with the symbol in front, like every other price")
    func symbolAfter() {
        #expect(PriceFormatter.normalized("18 €", symbol: "€") == "€18")
    }

    @Test("Already-normalised prices are unchanged")
    func alreadyNormalised() {
        #expect(PriceFormatter.normalized("€18", symbol: "€") == "€18")
    }

    // MARK: - Amount extraction

    @Test("Bare numbers get the preferred symbol")
    func bareNumber() {
        #expect(PriceFormatter.normalized("29.99", symbol: "$") == "$29.99")
    }

    @Test("Code before the amount")
    func currencyCodeBefore() {
        #expect(PriceFormatter.normalized("EUR 18,99", symbol: "€") == "€18,99")
    }

    @Test("European thousands and decimal separators are kept")
    func europeanSeparators() {
        #expect(PriceFormatter.amount(in: "1.299,99 €") == "1.299,99")
    }

    @Test("Space-separated thousands are joined")
    func spaceThousands() {
        #expect(PriceFormatter.amount(in: "1 299,00 €") == "1299,00")
        #expect(PriceFormatter.amount(in: "1\u{00A0}299 €") == "1299")   // non-breaking space
    }

    @Test("Trailing punctuation is dropped")
    func trailingPunctuation() {
        #expect(PriceFormatter.amount(in: "18.") == "18")
    }

    // MARK: - No number

    @Test("Text without a number is kept as typed")
    func noNumber() {
        #expect(PriceFormatter.normalized("Free", symbol: "€") == "Free")
        #expect(PriceFormatter.amount(in: "Free") == nil)
    }

    @Test("Empty and whitespace-only input stays empty")
    func empty() {
        #expect(PriceFormatter.normalized("", symbol: "€") == "")
        #expect(PriceFormatter.normalized("   ", symbol: "€") == "")
    }
}

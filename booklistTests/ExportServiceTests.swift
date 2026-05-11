import Testing
import Foundation
@testable import booklist

@Suite("ExportService")
struct ExportServiceTests {

    // MARK: - Helper

    private func item(
        title: String = "Title",
        url: String = "https://example.com",
        note: String? = nil,
        price: String? = nil,
        isWishlistItem: Bool = false,
        imageURL: String? = nil,
        tags: [String] = [],
        folderPath: String? = nil
    ) -> ExportService.ExportItem {
        ExportService.ExportItem(
            title: title, url: url, note: note, price: price,
            isWishlistItem: isWishlistItem, imageURL: imageURL,
            tags: tags, folderPath: folderPath
        )
    }

    // MARK: - HTML structure

    @Test("Output starts with DOCTYPE declaration")
    func containsDOCTYPE() {
        let html = ExportService.generateHTML(items: [], title: "Test")
        #expect(html.contains("<!DOCTYPE html>"))
    }

    @Test("Export title appears in <title> tag")
    func titleTag() {
        let html = ExportService.generateHTML(items: [], title: "My Export")
        #expect(html.contains("<title>My Export</title>"))
    }

    @Test("Export title appears in <h1> tag")
    func titleH1() {
        let html = ExportService.generateHTML(items: [], title: "My Export")
        #expect(html.contains("<h1>My Export</h1>"))
    }

    @Test("__BOOKLIST_DATA__ script tag is present")
    func booklistDataTagPresent() {
        let html = ExportService.generateHTML(items: [], title: "X")
        #expect(html.contains(#"<script id="__BOOKLIST_DATA__" type="application/json">"#))
    }

    // MARK: - Item count subtitle

    @Test("Zero items shows '0 items'")
    func zeroItemCount() {
        let html = ExportService.generateHTML(items: [], title: "T")
        #expect(html.contains("0 items"))
    }

    @Test("One item uses singular '1 item'")
    func oneItemSingular() {
        let html = ExportService.generateHTML(items: [item()], title: "T")
        #expect(html.contains("1 item"))
        #expect(!html.contains("1 items"))
    }

    @Test("Two items uses plural '2 items'")
    func twoItemsPlural() {
        let html = ExportService.generateHTML(items: [item(), item()], title: "T")
        #expect(html.contains("2 items"))
    }

    // MARK: - Card content

    @Test("Card href contains the item URL")
    func cardHref() {
        let html = ExportService.generateHTML(items: [item(url: "https://swift.org")], title: "T")
        #expect(html.contains(#"href="https://swift.org""#))
    }

    @Test("Card title appears in card body")
    func cardTitleInBody() {
        let html = ExportService.generateHTML(items: [item(title: "Swift Programming")], title: "T")
        #expect(html.contains("Swift Programming"))
    }

    @Test("Note element is rendered when note is non-nil")
    func noteRenderedWhenPresent() {
        let html = ExportService.generateHTML(items: [item(note: "Great resource")], title: "T")
        #expect(html.contains("card-note"))
        #expect(html.contains("Great resource"))
    }

    @Test("Note element is absent when note is nil")
    func noteAbsentWhenNil() {
        let html = ExportService.generateHTML(items: [item(note: nil)], title: "T")
        #expect(!html.contains("card-note"))
    }

    @Test("Price element is rendered when price is non-nil")
    func priceRenderedWhenPresent() {
        let html = ExportService.generateHTML(items: [item(price: "$29.99")], title: "T")
        #expect(html.contains("card-price"))
        #expect(html.contains("$29.99"))
    }

    @Test("Price element is absent when price is nil")
    func priceAbsentWhenNil() {
        let html = ExportService.generateHTML(items: [item(price: nil)], title: "T")
        #expect(!html.contains("card-price"))
    }

    @Test("Image tag is rendered when imageURL is non-nil")
    func imageTagWhenPresent() {
        let html = ExportService.generateHTML(
            items: [item(imageURL: "https://img.example.com/photo.jpg")], title: "T")
        #expect(html.contains("<img"))
        #expect(html.contains("https://img.example.com/photo.jpg"))
    }

    @Test("Image tag is absent when imageURL is nil")
    func imageTagAbsentWhenNil() {
        let html = ExportService.generateHTML(items: [item(imageURL: nil)], title: "T")
        #expect(!html.contains("<img"))
    }

    @Test("Tags are rendered as #name spans inside a tags div")
    func tagsRendered() {
        let html = ExportService.generateHTML(
            items: [item(tags: ["swift", "ios"])], title: "T")
        #expect(html.contains("#swift"))
        #expect(html.contains("#ios"))
        #expect(html.contains(#"class="tag""#))
        #expect(html.contains(#"class="tags""#))
    }

    @Test("Tags div is absent when tags array is empty")
    func tagsDivAbsentWhenEmpty() {
        let html = ExportService.generateHTML(items: [item(tags: [])], title: "T")
        #expect(!html.contains(#"class="tags""#))
    }

    @Test("Wishlist card carries 'wishlist' CSS class")
    func wishlistCardClass() {
        let html = ExportService.generateHTML(items: [item(isWishlistItem: true)], title: "T")
        #expect(html.contains(#"class="card wishlist""#))
    }

    @Test("Regular bookmark card does not carry 'wishlist' CSS class")
    func regularCardClass() {
        let html = ExportService.generateHTML(items: [item(isWishlistItem: false)], title: "T")
        #expect(html.contains(#"class="card""#))
        #expect(!html.contains("wishlist"))
    }

    // MARK: - HTML escaping

    @Test("Ampersand in title is escaped to &amp;")
    func escapeAmpersand() {
        let html = ExportService.generateHTML(items: [item(title: "Cats & Dogs")], title: "T")
        #expect(html.contains("Cats &amp; Dogs"))
        #expect(!html.contains("Cats & Dogs"))
    }

    @Test("Less-than in title is escaped to &lt;")
    func escapeLessThan() {
        let html = ExportService.generateHTML(items: [item(title: "A < B")], title: "T")
        #expect(html.contains("A &lt; B"))
        #expect(!html.contains("A < B"))
    }

    @Test("Greater-than in title is escaped to &gt;")
    func escapeGreaterThan() {
        let html = ExportService.generateHTML(items: [item(title: "B > A")], title: "T")
        #expect(html.contains("B &gt; A"))
        #expect(!html.contains("B > A"))
    }

    @Test("Double-quote in note is escaped to &quot;")
    func escapeQuote() {
        let html = ExportService.generateHTML(
            items: [item(note: #"He said "hello""#)], title: "T")
        #expect(html.contains("He said &quot;hello&quot;"))
    }

    @Test("Special chars in export title are escaped in both <title> and <h1>")
    func escapeExportTitle() {
        let html = ExportService.generateHTML(items: [], title: "A & B < C")
        #expect(html.contains("<title>A &amp; B &lt; C</title>"))
        #expect(html.contains("<h1>A &amp; B &lt; C</h1>"))
    }

    // MARK: - Embedded JSON round-trip

    @Test("__BOOKLIST_DATA__ JSON decodes back to the original items")
    func embeddedJSONRoundTrip() throws {
        let items = [
            item(title: "One", url: "https://one.com", note: "A note",
                 price: "$5", isWishlistItem: true,
                 imageURL: "https://img.com/1.jpg", tags: ["a", "b"],
                 folderPath: "Folder"),
            item(title: "Two", url: "https://two.com")
        ]
        let html = ExportService.generateHTML(items: items, title: "Export")

        // Extract JSON from the script tag
        let pattern = #"<script id="__BOOKLIST_DATA__" type="application/json">(.+?)</script>"#
        let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let ns = NSRange(html.startIndex..., in: html)
        let match = try #require(regex.firstMatch(in: html, range: ns))
        let range = try #require(Range(match.range(at: 1), in: html))
        let jsonStr = String(html[range]).trimmingCharacters(in: .whitespaces)

        let decoded = try JSONDecoder().decode([ExportService.ExportItem].self,
                                               from: Data(jsonStr.utf8))

        #expect(decoded.count == 2)
        #expect(decoded[0].title == "One")
        #expect(decoded[0].url == "https://one.com")
        #expect(decoded[0].note == "A note")
        #expect(decoded[0].price == "$5")
        #expect(decoded[0].isWishlistItem == true)
        #expect(decoded[0].imageURL == "https://img.com/1.jpg")
        #expect(decoded[0].tags == ["a", "b"])
        #expect(decoded[0].folderPath == "Folder")
        #expect(decoded[1].title == "Two")
        #expect(decoded[1].note == nil)
        #expect(decoded[1].tags.isEmpty == true)
    }

    @Test("Empty items array produces valid JSON array [] in script tag")
    func emptyItemsEmbeddedJSON() throws {
        let html = ExportService.generateHTML(items: [], title: "Empty")
        let pattern = #"<script id="__BOOKLIST_DATA__" type="application/json">(.+?)</script>"#
        let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let ns = NSRange(html.startIndex..., in: html)
        let match = try #require(regex.firstMatch(in: html, range: ns))
        let range = try #require(Range(match.range(at: 1), in: html))
        let jsonStr = String(html[range]).trimmingCharacters(in: .whitespaces)

        let decoded = try JSONDecoder().decode([ExportService.ExportItem].self,
                                               from: Data(jsonStr.utf8))
        #expect(decoded.isEmpty)
    }
}

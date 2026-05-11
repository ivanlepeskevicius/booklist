import Testing
@testable import booklist

/// Verifies that a full ExportService.generateHTML → ImportService.parseBooklistHTML
/// cycle preserves every field with complete fidelity.
@Suite("Export → Import Round Trip")
struct RoundTripTests {

    // MARK: - Helper

    /// Runs the full round-trip and returns the parsed bookmarks, or nil if detection failed.
    private func roundTrip(_ items: [ExportService.ExportItem]) -> [ImportService.ParsedBookmark]? {
        let html = ExportService.generateHTML(items: items, title: "Test Export")
        return ImportService.parseBooklistHTML(html)
    }

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

    // MARK: - Detection

    @Test("parseBooklistHTML detects output from generateHTML")
    func detectionSucceeds() {
        let result = roundTrip([item()])
        #expect(result != nil)
    }

    @Test("Round-trip item count matches original")
    func countMatches() throws {
        let result = try #require(roundTrip([item(), item(), item()]))
        #expect(result.count == 3)
    }

    // MARK: - Full field preservation

    @Test("All fields of a fully populated item survive round-trip")
    func fullItemAllFields() throws {
        let original = item(
            title: "My Bookmark",
            url: "https://example.com/article",
            note: "Important article about Swift",
            price: "$9.99",
            isWishlistItem: true,
            imageURL: "https://img.example.com/photo.jpg",
            tags: ["swift", "ios", "programming"],
            folderPath: "Reading List"
        )
        let result = try #require(roundTrip([original]))
        let parsed = try #require(result.first)

        #expect(parsed.title == "My Bookmark")
        #expect(parsed.url == "https://example.com/article")
        #expect(parsed.note == "Important article about Swift")
        #expect(parsed.price == "$9.99")
        #expect(parsed.isWishlistItem == true)
        #expect(parsed.imageURL == "https://img.example.com/photo.jpg")
        #expect(parsed.tags == ["swift", "ios", "programming"])
        #expect(parsed.folderPath == "Reading List")
    }

    @Test("Minimal item with all-nil optionals survives round-trip")
    func minimalItemNilFields() throws {
        let original = item(title: "Minimal", url: "https://minimal.com")
        let result = try #require(roundTrip([original]))
        let parsed = try #require(result.first)

        #expect(parsed.title == "Minimal")
        #expect(parsed.url == "https://minimal.com")
        #expect(parsed.note == nil)
        #expect(parsed.price == nil)
        #expect(parsed.isWishlistItem == false)
        #expect(parsed.imageURL == nil)
        #expect(parsed.tags.isEmpty)
        #expect(parsed.folderPath == nil)
    }

    // MARK: - Individual field round-trips

    @Test("isWishlistItem true round-trips correctly")
    func wishlistItemTrue() throws {
        let result = try #require(roundTrip([item(isWishlistItem: true)]))
        #expect(result.first?.isWishlistItem == true)
    }

    @Test("isWishlistItem false round-trips correctly")
    func wishlistItemFalse() throws {
        let result = try #require(roundTrip([item(isWishlistItem: false)]))
        #expect(result.first?.isWishlistItem == false)
    }

    @Test("Non-nil folderPath round-trips correctly")
    func folderPathNonNil() throws {
        let result = try #require(roundTrip([item(folderPath: "Design / Assets")]))
        #expect(result.first?.folderPath == "Design / Assets")
    }

    @Test("nil folderPath round-trips as nil")
    func folderPathNil() throws {
        let result = try #require(roundTrip([item(folderPath: nil)]))
        #expect(result.first?.folderPath == nil)
    }

    @Test("Tags array round-trips in original order")
    func tagsOrder() throws {
        let result = try #require(roundTrip([item(tags: ["zzz", "aaa", "mmm"])]))
        #expect(result.first?.tags == ["zzz", "aaa", "mmm"])
    }

    @Test("Empty tags array round-trips as empty")
    func emptyTags() throws {
        let result = try #require(roundTrip([item(tags: [])]))
        #expect(result.first?.tags.isEmpty == true)
    }

    @Test("Note with newlines round-trips correctly")
    func noteWithNewlines() throws {
        let multiLineNote = "Line one\nLine two\nLine three"
        let result = try #require(roundTrip([item(note: multiLineNote)]))
        #expect(result.first?.note == multiLineNote)
    }

    // MARK: - Special characters

    @Test("Ampersand in title round-trips as raw &")
    func ampersandInTitle() throws {
        // The HTML card body escapes to &amp; but the JSON payload stores raw &
        // so re-importing should give back the original unescaped string
        let result = try #require(roundTrip([item(title: "Cats & Dogs")]))
        #expect(result.first?.title == "Cats & Dogs")
    }

    @Test("Less-than in title round-trips as raw <")
    func lessThanInTitle() throws {
        let result = try #require(roundTrip([item(title: "A < B")]))
        #expect(result.first?.title == "A < B")
    }

    @Test("Double-quote in note round-trips as raw \"")
    func quoteInNote() throws {
        let result = try #require(roundTrip([item(note: #"He said "hello""#)]))
        #expect(result.first?.note == #"He said "hello""#)
    }

    @Test("Unicode characters in title and note round-trip correctly")
    func unicodeRoundTrip() throws {
        let result = try #require(roundTrip([item(
            title: "日本語タイトル 🎌",
            note: "Émojis: 🚀🌍✨"
        )]))
        #expect(result.first?.title == "日本語タイトル 🎌")
        #expect(result.first?.note == "Émojis: 🚀🌍✨")
    }

    // MARK: - Multiple items

    @Test("Multiple items round-trip in original order")
    func multipleItemsOrder() throws {
        let originals = [
            item(title: "First", url: "https://first.com"),
            item(title: "Second", url: "https://second.com"),
            item(title: "Third", url: "https://third.com")
        ]
        let result = try #require(roundTrip(originals))
        #expect(result.count == 3)
        #expect(result[0].title == "First")
        #expect(result[1].title == "Second")
        #expect(result[2].title == "Third")
    }

    @Test("Mixed wishlist and bookmark items all round-trip")
    func mixedItemTypes() throws {
        let originals = [
            item(title: "Wishlist Item", price: "$49.99", isWishlistItem: true),
            item(title: "Regular Bookmark", note: "Good read", isWishlistItem: false)
        ]
        let result = try #require(roundTrip(originals))
        #expect(result.count == 2)
        #expect(result[0].isWishlistItem == true)
        #expect(result[0].price == "$49.99")
        #expect(result[1].isWishlistItem == false)
        #expect(result[1].note == "Good read")
    }

    @Test("10 diverse items all survive round-trip")
    func largeSetRoundTrip() throws {
        let originals = (1...10).map { i in
            item(
                title: "Item \(i)",
                url: "https://item\(i).example.com",
                note: i.isMultiple(of: 2) ? "Note \(i)" : nil,
                tags: ["tag\(i)"],
                folderPath: i.isMultiple(of: 3) ? "Folder \(i)" : nil
            )
        }
        let result = try #require(roundTrip(originals))
        #expect(result.count == 10)
        for (i, parsed) in result.enumerated() {
            #expect(parsed.title == "Item \(i + 1)")
            #expect(parsed.url == "https://item\(i + 1).example.com")
            #expect(parsed.tags == ["tag\(i + 1)"])
        }
    }
}

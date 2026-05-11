import Testing
@testable import booklist

@Suite("ImportService")
struct ImportServiceTests {

    // MARK: - parseNetscapeHTML

    @Suite("parseNetscapeHTML")
    struct NetscapeTests {

        @Test("Empty HTML returns empty array")
        func emptyHTML() {
            let result = ImportService.parseNetscapeHTML("<!DOCTYPE html><html></html>")
            #expect(result.isEmpty)
        }

        @Test("Single flat bookmark is parsed")
        func singleFlatBookmark() {
            let html = """
            <DL>
                <DT><A HREF="https://example.com">Example Site</A>
            </DL>
            """
            let result = ImportService.parseNetscapeHTML(html)
            #expect(result.count == 1)
            #expect(result[0].url == "https://example.com")
            #expect(result[0].title == "Example Site")
            #expect(result[0].folderPath == nil)
        }

        @Test("Multiple flat bookmarks are all parsed")
        func multipleFlatBookmarks() {
            let html = """
            <DL>
                <DT><A HREF="https://apple.com">Apple</A>
                <DT><A HREF="https://swift.org">Swift</A>
                <DT><A HREF="https://github.com">GitHub</A>
            </DL>
            """
            let result = ImportService.parseNetscapeHTML(html)
            #expect(result.count == 3)
            #expect(result.map(\.url) == ["https://apple.com", "https://swift.org", "https://github.com"])
        }

        @Test("Bookmark with empty title falls back to URL as title")
        func emptyTitleFallsBackToURL() {
            let html = #"<A HREF="https://example.com"></A>"#
            let result = ImportService.parseNetscapeHTML(html)
            #expect(result.count == 1)
            #expect(result[0].title == "https://example.com")
        }

        @Test("Non-http links are filtered out")
        func nonHttpLinksFiltered() {
            let html = """
            <DT><A HREF="javascript:void(0)">Script</A>
            <DT><A HREF="about:blank">About</A>
            <DT><A HREF="ftp://files.example.com">FTP</A>
            <DT><A HREF="https://real.com">Real</A>
            """
            let result = ImportService.parseNetscapeHTML(html)
            #expect(result.count == 1)
            #expect(result[0].url == "https://real.com")
        }

        @Test("http:// links are accepted alongside https://")
        func httpAlsoAccepted() {
            let html = #"<A HREF="http://legacy.example.com">Legacy</A>"#
            let result = ImportService.parseNetscapeHTML(html)
            #expect(result.count == 1)
            #expect(result[0].url == "http://legacy.example.com")
        }

        @Test("Bookmark inside a folder carries folder name as folderPath")
        func singleFolderLevel() {
            let html = """
            <H3>Design</H3>
            <DL>
                <DT><A HREF="https://figma.com">Figma</A>
            </DL>
            """
            let result = ImportService.parseNetscapeHTML(html)
            #expect(result.count == 1)
            #expect(result[0].folderPath == "Design")
        }

        @Test("Nested folders join with ' / ' separator")
        func nestedFolders() {
            let html = """
            <H3>Work</H3>
            <DL>
                <H3>Design</H3>
                <DL>
                    <DT><A HREF="https://figma.com">Figma</A>
                </DL>
            </DL>
            """
            let result = ImportService.parseNetscapeHTML(html)
            #expect(result.count == 1)
            #expect(result[0].folderPath == "Work / Design")
        }

        @Test("Three levels of nesting")
        func threeLevelsDeep() {
            let html = """
            <H3>A</H3>
            <DL>
                <H3>B</H3>
                <DL>
                    <H3>C</H3>
                    <DL>
                        <DT><A HREF="https://deep.com">Deep</A>
                    </DL>
                </DL>
            </DL>
            """
            let result = ImportService.parseNetscapeHTML(html)
            #expect(result.count == 1)
            #expect(result[0].folderPath == "A / B / C")
        }

        @Test("Multiple sibling folders parsed independently")
        func siblingFolders() {
            let html = """
            <H3>Folder A</H3>
            <DL>
                <DT><A HREF="https://a.com">A</A>
            </DL>
            <H3>Folder B</H3>
            <DL>
                <DT><A HREF="https://b.com">B</A>
            </DL>
            """
            let result = ImportService.parseNetscapeHTML(html)
            #expect(result.count == 2)
            #expect(result[0].folderPath == "Folder A")
            #expect(result[1].folderPath == "Folder B")
        }

        @Test("Bookmarks before and after a folder have nil folderPath")
        func bookmarksOutsideFolderHaveNilPath() {
            let html = """
            <DT><A HREF="https://root.com">Root</A>
            <H3>Folder</H3>
            <DL>
                <DT><A HREF="https://inside.com">Inside</A>
            </DL>
            <DT><A HREF="https://after.com">After</A>
            """
            let result = ImportService.parseNetscapeHTML(html)
            #expect(result.count == 3)
            #expect(result[0].folderPath == nil)
            #expect(result[1].folderPath == "Folder")
            #expect(result[2].folderPath == nil)
        }

        @Test("Folder attributes (ADD_DATE etc.) don't break parsing")
        func folderWithAttributes() {
            let html = """
            <H3 ADD_DATE="1234567890" LAST_MODIFIED="1234567891">My Folder</H3>
            <DL>
                <DT><A HREF="https://example.com" ADD_DATE="1234" ICON="data:...">Link</A>
            </DL>
            """
            let result = ImportService.parseNetscapeHTML(html)
            #expect(result.count == 1)
            #expect(result[0].folderPath == "My Folder")
            #expect(result[0].url == "https://example.com")
        }

        @Test("Case-insensitive tag matching")
        func caseInsensitiveTags() {
            let html = """
            <h3>Lowercase Folder</h3>
            <dl>
                <dt><a href="https://example.com">Example</a>
            </dl>
            """
            let result = ImportService.parseNetscapeHTML(html)
            #expect(result.count == 1)
            #expect(result[0].folderPath == "Lowercase Folder")
        }
    }

    // MARK: - parseBooklistHTML

    @Suite("parseBooklistHTML")
    struct BooklistHTMLTests {

        @Test("Returns nil for plain HTML without booklist tag")
        func returnsNilForPlainHTML() {
            let html = "<!DOCTYPE html><html><body><p>Nothing here</p></body></html>"
            #expect(ImportService.parseBooklistHTML(html) == nil)
        }

        @Test("Returns nil when __BOOKLIST_DATA__ script tag is absent")
        func returnsNilForNetscapeExport() {
            // Looks like an export but has no __BOOKLIST_DATA__ block
            let html = """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <DL><p>
                <DT><A HREF="https://example.com">Example</A>
            </DL>
            """
            #expect(ImportService.parseBooklistHTML(html) == nil)
        }

        @Test("Returns nil when JSON array is empty")
        func returnsNilForEmptyArray() {
            let html = """
            <script id="__BOOKLIST_DATA__" type="application/json">[]</script>
            """
            #expect(ImportService.parseBooklistHTML(html) == nil)
        }

        @Test("Returns nil for malformed JSON")
        func returnsNilForMalformedJSON() {
            let html = """
            <script id="__BOOKLIST_DATA__" type="application/json">NOT_JSON</script>
            """
            #expect(ImportService.parseBooklistHTML(html) == nil)
        }

        @Test("Parses a minimal item with only title and url")
        func parsesMinimalItem() {
            let json = """
            [{"title":"Minimal","url":"https://minimal.com","note":null,"price":null,\
            "isWishlistItem":false,"imageURL":null,"tags":[],"folderPath":null}]
            """
            let html = "<script id=\"__BOOKLIST_DATA__\" type=\"application/json\">\(json)</script>"
            let result = ImportService.parseBooklistHTML(html)
            #expect(result?.count == 1)
            #expect(result?[0].title == "Minimal")
            #expect(result?[0].url == "https://minimal.com")
            #expect(result?[0].note == nil)
            #expect(result?[0].price == nil)
            #expect(result?[0].isWishlistItem == false)
            #expect(result?[0].imageURL == nil)
            #expect(result?[0].tags.isEmpty == true)
            #expect(result?[0].folderPath == nil)
        }

        @Test("Parses a fully populated item preserving all fields")
        func parsesFullItem() {
            let json = """
            [{"title":"My Bookmark","url":"https://example.com","note":"A note",\
            "price":"$9.99","isWishlistItem":true,\
            "imageURL":"https://img.example.com/photo.jpg",\
            "tags":["swift","ios"],"folderPath":"My Folder"}]
            """
            let html = "<script id=\"__BOOKLIST_DATA__\" type=\"application/json\">\(json)</script>"
            let result = ImportService.parseBooklistHTML(html)
            #expect(result?.count == 1)
            let item = result![0]
            #expect(item.title == "My Bookmark")
            #expect(item.url == "https://example.com")
            #expect(item.note == "A note")
            #expect(item.price == "$9.99")
            #expect(item.isWishlistItem == true)
            #expect(item.imageURL == "https://img.example.com/photo.jpg")
            #expect(item.tags == ["swift", "ios"])
            #expect(item.folderPath == "My Folder")
        }

        @Test("Parses multiple items preserving order")
        func parsesMultipleItems() {
            let json = """
            [
                {"title":"First","url":"https://first.com","note":null,"price":null,\
                "isWishlistItem":false,"imageURL":null,"tags":[],"folderPath":null},
                {"title":"Second","url":"https://second.com","note":null,"price":null,\
                "isWishlistItem":false,"imageURL":null,"tags":[],"folderPath":null}
            ]
            """
            let html = "<script id=\"__BOOKLIST_DATA__\" type=\"application/json\">\(json)</script>"
            let result = ImportService.parseBooklistHTML(html)
            #expect(result?.count == 2)
            #expect(result?[0].title == "First")
            #expect(result?[1].title == "Second")
        }

        @Test("isWishlistItem false on minimal item")
        func wishlistFalseByDefault() {
            let json = """
            [{"title":"T","url":"https://t.com","note":null,"price":null,\
            "isWishlistItem":false,"imageURL":null,"tags":[],"folderPath":null}]
            """
            let html = "<script id=\"__BOOKLIST_DATA__\" type=\"application/json\">\(json)</script>"
            let result = ImportService.parseBooklistHTML(html)
            #expect(result?[0].isWishlistItem == false)
        }

        @Test("Tags array is preserved in order")
        func tagsPreservedInOrder() {
            let json = """
            [{"title":"T","url":"https://t.com","note":null,"price":null,\
            "isWishlistItem":false,"imageURL":null,\
            "tags":["zzz","aaa","mmm"],"folderPath":null}]
            """
            let html = "<script id=\"__BOOKLIST_DATA__\" type=\"application/json\">\(json)</script>"
            let result = ImportService.parseBooklistHTML(html)
            #expect(result?[0].tags == ["zzz", "aaa", "mmm"])
        }
    }
}

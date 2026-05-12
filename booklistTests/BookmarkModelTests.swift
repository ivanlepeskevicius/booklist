import Testing
import SwiftData
import Foundation
@testable import booklist

// Shadow Testing.Tag so our SwiftData Tag model is unambiguous throughout this file.
private typealias Tag = booklist.Tag

@Suite("Bookmark + Folder model computed properties")
struct BookmarkModelTests {

    // MARK: - Helper

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Bookmark.self, Folder.self, Tag.self,
            configurations: config
        )
        return ModelContext(container)
    }

    // MARK: - Bookmark.tagSortKey

    @Suite("Bookmark.tagSortKey")
    struct TagSortKeyTests {

        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(
                for: Bookmark.self, Folder.self, Tag.self,
                configurations: config
            )
            return ModelContext(container)
        }

        @Test("No tags returns empty string")
        func noTags() throws {
            let context = try makeContext()
            let bm = Bookmark(title: "T", url: "https://t.com", tags: [])
            context.insert(bm)
            #expect(bm.tagSortKey == "")
        }

        @Test("Single tag returns that tag's name")
        func singleTag() throws {
            let context = try makeContext()
            let tag = Tag(name: "swift")
            context.insert(tag)
            let bm = Bookmark(title: "T", url: "https://t.com", tags: [tag])
            context.insert(bm)
            #expect(bm.tagSortKey == "swift")
        }

        @Test("Multiple tags returns alphabetically first name")
        func multipleTagsFirstAlphabetically() throws {
            let context = try makeContext()
            let tagA = Tag(name: "zebra")
            let tagB = Tag(name: "apple")
            let tagC = Tag(name: "mango")
            context.insert(tagA); context.insert(tagB); context.insert(tagC)
            let bm = Bookmark(title: "T", url: "https://t.com", tags: [tagA, tagB, tagC])
            context.insert(bm)
            #expect(bm.tagSortKey == "apple")
        }

        @Test("Tags in reverse alphabetical order still returns first alphabetically")
        func reverseOrderStillSortsCorrectly() throws {
            let context = try makeContext()
            let tagZ = Tag(name: "z-tag")
            let tagA = Tag(name: "a-tag")
            context.insert(tagZ); context.insert(tagA)
            let bm = Bookmark(title: "T", url: "https://t.com", tags: [tagZ, tagA])
            context.insert(bm)
            #expect(bm.tagSortKey == "a-tag")
        }

        @Test("Case-sensitive comparison: uppercase sorts before lowercase")
        func caseSensitiveOrder() throws {
            let context = try makeContext()
            let tagUpper = Tag(name: "Apple")
            let tagLower = Tag(name: "banana")
            context.insert(tagUpper); context.insert(tagLower)
            let bm = Bookmark(title: "T", url: "https://t.com", tags: [tagLower, tagUpper])
            context.insert(bm)
            // Swift string comparison: uppercase A (65) < lowercase b (98)
            #expect(bm.tagSortKey == "Apple")
        }
    }

    // MARK: - Bookmark.lastOpenedDateForSorting

    @Suite("Bookmark.lastOpenedDateForSorting")
    struct LastOpenedDateForSortingTests {

        @Test("nil lastOpenedDate returns .distantPast")
        func nilReturnsDistantPast() {
            let bm = Bookmark(title: "T", url: "https://t.com")
            #expect(bm.lastOpenedDate == nil)
            #expect(bm.lastOpenedDateForSorting == .distantPast)
        }

        @Test("Non-nil lastOpenedDate returns that exact date")
        func nonNilReturnsExactDate() {
            let bm = Bookmark(title: "T", url: "https://t.com")
            let date = Date(timeIntervalSince1970: 1_000_000)
            bm.lastOpenedDate = date
            #expect(bm.lastOpenedDateForSorting == date)
        }

        @Test(".distantPast sorts before any real date")
        func distantPastSortsFirst() {
            let unread = Bookmark(title: "Unread", url: "https://a.com")
            let opened = Bookmark(title: "Opened", url: "https://b.com")
            opened.lastOpenedDate = Date()
            #expect(unread.lastOpenedDateForSorting < opened.lastOpenedDateForSorting)
        }
    }

    // MARK: - Folder.childrenIfAny

    @Suite("Folder.childrenIfAny")
    struct ChildrenIfAnyTests {

        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(
                for: Bookmark.self, Folder.self, Tag.self,
                configurations: config
            )
            return ModelContext(container)
        }

        @Test("Folder with no children returns nil")
        func noChildrenReturnsNil() throws {
            let context = try makeContext()
            let folder = Folder(name: "Leaf")
            context.insert(folder)
            #expect(folder.childrenIfAny == nil)
        }

        @Test("Folder with one child returns a single-element array")
        func oneChildReturnsArray() throws {
            let context = try makeContext()
            let parent = Folder(name: "Parent")
            let child = Folder(name: "Child", sortOrder: 0)
            child.parent = parent
            context.insert(parent)
            context.insert(child)
            let result = try #require(parent.childrenIfAny)
            #expect(result.count == 1)
            #expect(result[0].name == "Child")
        }

        @Test("Multiple children are returned sorted by sortOrder ascending")
        func childrenSortedBySortOrder() throws {
            let context = try makeContext()
            let parent = Folder(name: "Parent")
            let c1 = Folder(name: "Third", sortOrder: 2)
            let c2 = Folder(name: "First", sortOrder: 0)
            let c3 = Folder(name: "Second", sortOrder: 1)
            c1.parent = parent
            c2.parent = parent
            c3.parent = parent
            context.insert(parent)
            context.insert(c1); context.insert(c2); context.insert(c3)

            let result = try #require(parent.childrenIfAny)
            #expect(result.count == 3)
            #expect(result[0].sortOrder == 0)
            #expect(result[1].sortOrder == 1)
            #expect(result[2].sortOrder == 2)
            #expect(result[0].name == "First")
            #expect(result[1].name == "Second")
            #expect(result[2].name == "Third")
        }

        @Test("childrenIfAny returns nil after all children are removed")
        func nilAfterChildrenRemoved() throws {
            let context = try makeContext()
            let parent = Folder(name: "Parent")
            let child = Folder(name: "Child")
            child.parent = parent
            context.insert(parent)
            context.insert(child)
            // Verify child is there
            #expect(parent.childrenIfAny != nil)
            // Remove child
            child.parent = nil
            #expect(parent.childrenIfAny == nil)
        }
    }

    // MARK: - Tag.randomColor

    @Suite("Tag.randomColor")
    struct TagRandomColorTests {

        @Test("palette has 28 entries")
        func paletteCount() {
            #expect(Tag.palette.count == 28)
        }

        @Test("randomColor returns a value from the palette")
        func returnsValueInPalette() {
            #expect(Tag.palette.contains(Tag.randomColor()))
        }

        @Test("randomColor always returns palette values over 100 calls")
        func alwaysInPaletteOverManyCalls() {
            for _ in 0..<100 {
                #expect(Tag.palette.contains(Tag.randomColor()))
            }
        }
    }
}

import Testing
import SwiftData
import Foundation
@testable import booklist

private typealias Tag = booklist.Tag

@Suite("BookmarkBulkActions")
struct BookmarkBulkActionsTests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Bookmark.self, Folder.self, Tag.self,
            configurations: config
        )
        return ModelContext(container)
    }

    // MARK: - move

    @Test("move assigns every bookmark to the folder")
    func moveToFolder() throws {
        let ctx = try makeContext()
        let folder = Folder(name: "Reading")
        let a = Bookmark(title: "A", url: "https://a.com")
        let b = Bookmark(title: "B", url: "https://b.com")
        [a, b].forEach(ctx.insert)
        ctx.insert(folder)

        BookmarkBulkActions.move([a, b], to: folder)

        #expect(a.collection?.id == folder.id)
        #expect(b.collection?.id == folder.id)
    }

    @Test("move to nil sends bookmarks back to Inbox")
    func moveToInbox() throws {
        let ctx = try makeContext()
        let folder = Folder(name: "Reading")
        ctx.insert(folder)
        let a = Bookmark(title: "A", url: "https://a.com", collection: folder)
        ctx.insert(a)

        BookmarkBulkActions.move([a], to: nil)

        #expect(a.collection == nil)
    }

    // MARK: - delete

    @Test("delete removes the bookmarks and ⌘Z (undo) brings them back")
    @MainActor
    func deleteIsUndoable() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Bookmark.self, Folder.self, Tag.self,
            configurations: config
        )
        let ctx = container.mainContext
        let undoManager = UndoManager()
        ctx.undoManager = undoManager

        let a = Bookmark(title: "A", url: "https://a.com")
        let b = Bookmark(title: "B", url: "https://b.com")
        [a, b].forEach(ctx.insert)
        try ctx.save()
        undoManager.removeAllActions()   // mirror app launch: inserts aren't undoable

        BookmarkBulkActions.delete([a, b], from: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<Bookmark>()) == 0)

        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(try ctx.fetchCount(FetchDescriptor<Bookmark>()) == 2)
    }

    @Test("isAlive turns false once a bookmark is deleted (guards the reader panel)")
    @MainActor
    func isAliveAfterDelete() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Bookmark.self, Folder.self, Tag.self,
            configurations: config
        )
        let ctx = container.mainContext
        let bookmark = Bookmark(title: "A", url: "https://a.com")
        ctx.insert(bookmark)
        try ctx.save()
        #expect(bookmark.isAlive)

        BookmarkBulkActions.delete([bookmark], from: ctx)
        #expect(!bookmark.isAlive)
    }

    // MARK: - allHave

    @Test("allHave is true only when every bookmark has the tag")
    func allHave() throws {
        let ctx = try makeContext()
        let tag = Tag(name: "design", color: "#FF0000")
        ctx.insert(tag)
        let tagged = Bookmark(title: "A", url: "https://a.com", tags: [tag])
        let untagged = Bookmark(title: "B", url: "https://b.com")
        [tagged, untagged].forEach(ctx.insert)

        #expect(BookmarkBulkActions.allHave(tag, [tagged]))
        #expect(!BookmarkBulkActions.allHave(tag, [tagged, untagged]))
    }

    @Test("allHave is false for an empty selection")
    func allHaveEmpty() throws {
        let ctx = try makeContext()
        let tag = Tag(name: "design", color: "#FF0000")
        ctx.insert(tag)
        #expect(!BookmarkBulkActions.allHave(tag, []))
    }

    // MARK: - setTag

    @Test("enabling a tag adds it only where missing — no duplicates")
    func enableAddsWithoutDuplicates() throws {
        let ctx = try makeContext()
        let tag = Tag(name: "design", color: "#FF0000")
        ctx.insert(tag)
        let tagged = Bookmark(title: "A", url: "https://a.com", tags: [tag])
        let untagged = Bookmark(title: "B", url: "https://b.com")
        [tagged, untagged].forEach(ctx.insert)

        BookmarkBulkActions.setTag(tag, on: [tagged, untagged], to: true)

        #expect(tagged.tags.filter { $0.id == tag.id }.count == 1)
        #expect(untagged.tags.contains { $0.id == tag.id })
    }

    @Test("disabling a tag removes it from all bookmarks and keeps other tags")
    func disableRemovesOnlyThatTag() throws {
        let ctx = try makeContext()
        let design = Tag(name: "design", color: "#FF0000")
        let later = Tag(name: "later", color: "#00FF00")
        [design, later].forEach(ctx.insert)
        let a = Bookmark(title: "A", url: "https://a.com", tags: [design, later])
        let b = Bookmark(title: "B", url: "https://b.com", tags: [design])
        [a, b].forEach(ctx.insert)

        BookmarkBulkActions.setTag(design, on: [a, b], to: false)

        #expect(!a.tags.contains { $0.id == design.id })
        #expect(!b.tags.contains { $0.id == design.id })
        #expect(a.tags.contains { $0.id == later.id })
    }
}

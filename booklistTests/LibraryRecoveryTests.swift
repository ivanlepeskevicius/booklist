import Foundation
import SwiftData
import Testing
@testable import booklist

private typealias Tag = booklist.Tag

/// Recovering the library from betas that stored it in the App Group container.
@Suite("Library recovery from earlier betas")
@MainActor
struct LibraryRecoveryTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: Bookmark.self, Folder.self, Tag.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        // A new context retains its container; `mainContext` doesn't, so the container would be
        // freed when this function returns.
        return ModelContext(container)
    }

    /// An "old beta" library: a nested folder, two tags, three bookmarks.
    private func oldLibrary() throws -> SyncData {
        let old = try makeContext()
        let design = Folder(name: "Design")
        let ui = Folder(name: "UI", parent: design)
        let tool = Tag(name: "tool"), music = Tag(name: "Music")
        [design, ui].forEach(old.insert)
        [tool, music].forEach(old.insert)
        let saved = Bookmark(title: "Figma", url: "https://figma.com",
                             imageURLs: ["https://figma.com/og.png"],
                             selectedImageURL: "file:///old/path/Images/AAAA.jpg", collection: ui, tags: [tool])
        let wish = Bookmark(title: "Headphones", url: "https://shop.example/h", itemType: .wishlistItem,
                            price: "€349.00", tags: [music])
        let plain = Bookmark(title: "Notes", url: "https://notes.example")
        [saved, wish, plain].forEach(old.insert)
        try old.save()
        return try SyncService.buildSnapshot(context: old)
    }

    @Test("Everything comes back with folders, nesting, tags and wishlist data")
    func fullRecovery() throws {
        let context = try makeContext()
        let result = try LibraryRecovery.merge(try oldLibrary(), into: context, imageExists: { _ in false })

        #expect(result.bookmarks == 3 && result.folders == 2 && result.tags == 2)
        let bookmarks = try context.fetch(FetchDescriptor<Bookmark>())
        let figma = try #require(bookmarks.first { $0.title == "Figma" })
        #expect(figma.collection?.name == "UI")
        #expect(figma.collection?.parent?.name == "Design")
        #expect(figma.tags.map(\.name) == ["tool"])
        let wish = try #require(bookmarks.first { $0.title == "Headphones" })
        #expect(wish.itemType == .wishlistItem && wish.price == "€349.00")
    }

    @Test("Items already in the library are kept, nothing is duplicated, recovering twice adds nothing")
    func mergeKeepsCurrentLibrary() throws {
        let context = try makeContext()
        let newSince = Bookmark(title: "Saved in the new build", url: "https://new.example")
        context.insert(newSince)
        context.insert(Tag(name: "TOOL"))   // same tag name, different case and ID
        try context.save()

        let snapshot = try oldLibrary()
        _ = try LibraryRecovery.merge(snapshot, into: context, imageExists: { _ in false })
        let second = try LibraryRecovery.merge(snapshot, into: context, imageExists: { _ in false })

        #expect(second.bookmarks == 0 && second.folders == 0 && second.tags == 0)
        #expect(try context.fetchCount(FetchDescriptor<Bookmark>()) == 4)
        #expect(try context.fetch(FetchDescriptor<Bookmark>()).contains { $0.title == "Saved in the new build" })
        let tagNames = try context.fetch(FetchDescriptor<Tag>()).map { $0.name.lowercased() }
        #expect(tagNames.filter { $0 == "tool" }.count == 1)
    }

    @Test("A saved image that's gone falls back to the page's web image")
    func missingImageFallsBackToWeb() {
        let (url, relinked) = LibraryRecovery.recoveredImage(
            selected: "file:///old/path/Images/AAAA.jpg",
            candidates: ["file:///x.jpg", "https://figma.com/og.png"], imageExists: { _ in false })
        #expect(url == "https://figma.com/og.png" && relinked)
    }

    @Test("A saved image still on disk is kept, pointing at this app's image folder")
    func presentImageKept() {
        let (url, relinked) = LibraryRecovery.recoveredImage(
            selected: "file:///old/path/Images/AAAA.jpg", candidates: [], imageExists: { $0 == "AAAA.jpg" })
        #expect(url == ImageStore.directory.appendingPathComponent("AAAA.jpg").absoluteString)
        #expect(!relinked)
    }

    @Test("Remote images and bookmarks without images are left as they are")
    func remoteUntouched() {
        #expect(LibraryRecovery.recoveredImage(selected: "https://a.example/i.png", candidates: [], imageExists: { _ in false }).url
                == "https://a.example/i.png")
        #expect(LibraryRecovery.recoveredImage(selected: nil, candidates: ["https://b.example"], imageExists: { _ in false }).url == nil)
    }

    @Test("A folder without a library is reported, not silently ignored")
    func folderWithoutStore() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("no-library-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(throws: LibraryRecovery.RecoveryError.self) {
            try LibraryRecovery.recover(from: empty, into: try makeContext())
        }
    }
}

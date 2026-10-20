import Foundation
import SwiftData
import Testing
@testable import booklist

private typealias Tag = booklist.Tag

/// Large-library stress for the data layer: bulk actions, undo, export/import and sync at
/// 5,000 items. Checks nothing is lost or duplicated and that each step stays fast.
@Suite("Stress: large library", .serialized)
@MainActor
struct StressTests {

    nonisolated private static let itemCount = 5_000

    @MainActor
    private struct Library {
        let container: ModelContainer
        let bookmarks: [Bookmark]
        let folders: [Folder]
        let tags: [Tag]
        var context: ModelContext { container.mainContext }
    }

    private func makeLibrary(count: Int = itemCount) throws -> Library {
        let container = try ModelContainer(
            for: Bookmark.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let tags = (0..<40).map { Tag(name: "tag-\($0)") }
        tags.forEach(context.insert)
        var folders: [Folder] = []
        for i in 0..<20 {
            let root = Folder(name: "Folder \(i)", sortOrder: i)
            let child = Folder(name: "Folder \(i).A", parent: root)
            let grandchild = Folder(name: "Folder \(i).A.1", parent: child)
            [root, child, grandchild].forEach(context.insert)
            folders += [root, child, grandchild]
        }
        let bookmarks = (0..<count).map { i in
            Bookmark(
                title: "Item \(i) — \(String(repeating: "lorem ", count: i % 20))",
                url: "https://example\(i % 97).com/item/\(i)",
                note: i % 3 == 0 ? String(repeating: "note line\n", count: i % 40) : nil,
                imageURLs: ["https://example.com/\(i).jpg"],
                selectedImageURL: "https://example.com/\(i).jpg",
                itemType: i % 7 == 0 ? .wishlistItem : .bookmark,
                price: i % 7 == 0 ? "€\(i).99" : nil,
                collection: i % 5 == 0 ? nil : folders[i % folders.count],
                tags: [tags[i % tags.count], tags[(i * 7) % tags.count]]
            )
        }
        bookmarks.forEach(context.insert)
        try context.save()
        return Library(container: container, bookmarks: bookmarks, folders: folders, tags: tags)
    }

    private func seconds(_ work: () throws -> Void) rethrows -> Double {
        let start = ContinuousClock.now
        try work()
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    @Test("Bulk move and tag 5,000 items: scattered → folder → folder → Inbox, tag on and off")
    func bulkMoveAndTag() throws {
        let library = try makeLibrary()
        let all = library.bookmarks
        let first = library.folders[7], second = library.folders[11]
        let tag = library.tags[3]

        // Each step was ~9 s before batching from the folder/tag side; budget 2 s each.
        let toFolder = seconds { BookmarkBulkActions.move(all, to: first) }
        #expect(all.allSatisfy { $0.collection?.id == first.id })
        let folderToFolder = seconds { BookmarkBulkActions.move(all, to: second) }
        #expect(all.allSatisfy { $0.collection?.id == second.id })
        #expect(first.bookmarks.isEmpty && second.bookmarks.count == Self.itemCount)
        let toInbox = seconds { BookmarkBulkActions.move(all, to: nil) }
        #expect(all.allSatisfy { $0.collection == nil })
        #expect(second.bookmarks.isEmpty)

        let tagOn = seconds { BookmarkBulkActions.setTag(tag, on: all, to: true) }
        #expect(BookmarkBulkActions.allHave(tag, all))
        #expect(tag.bookmarks.count == Self.itemCount)
        let tagOff = seconds { BookmarkBulkActions.setTag(tag, on: Array(all.prefix(2_500)), to: false) }
        #expect(all.prefix(2_500).allSatisfy { bm in !bm.tags.contains { $0.id == tag.id } })
        #expect(all.suffix(2_500).allSatisfy { bm in bm.tags.contains { $0.id == tag.id } })
        let save = try seconds { try library.context.save() }

        for (step, time) in [("to folder", toFolder), ("folder to folder", folderToFolder), ("to Inbox", toInbox),
                             ("tag on", tagOn), ("tag off", tagOff), ("save", save)] {
            #expect(time < 2, "\(step) took \(time)s")
        }
    }

    @Test("Delete 5,000 items and undo brings every one back with its folder and tags")
    func bulkDeleteAndUndo() throws {
        let library = try makeLibrary()
        let undoManager = UndoManager()
        library.context.undoManager = undoManager
        let sample = library.bookmarks[1234]
        let sampleID = sample.id
        let sampleFolderID = sample.collection?.id
        let sampleTagIDs = Set(sample.tags.map(\.id))

        var countAfterDelete = -1
        let elapsed = try seconds {
            BookmarkBulkActions.delete(library.bookmarks, from: library.context)
            countAfterDelete = try library.context.fetchCount(FetchDescriptor<Bookmark>())
            undoManager.undo()
        }
        #expect(countAfterDelete == 0)
        #expect(try library.context.fetchCount(FetchDescriptor<Bookmark>()) == Self.itemCount)
        let restored = try #require(try library.context.fetch(
            FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == sampleID })).first)
        #expect(restored.collection?.id == sampleFolderID)
        #expect(Set(restored.tags.map(\.id)) == sampleTagIDs)
        #expect(elapsed < 20, "delete + undo took \(elapsed)s")
    }

    @Test("Export 5,000 items to HTML and re-import them losslessly")
    func exportImportRoundTrip() throws {
        let library = try makeLibrary()
        var html = ""
        var parsed: [ImportService.ParsedBookmark]?
        let elapsed = seconds {
            let items = ExportService.makeExportItems(from: library.bookmarks)
            html = ExportService.generateHTML(items: items, title: "Stress")
            parsed = ImportService.parseBooklistHTML(html)
        }
        let items = try #require(parsed)
        #expect(items.count == Self.itemCount)
        #expect(Set(items.map(\.url)).count == Self.itemCount)
        #expect(items.filter(\.isWishlistItem).count == library.bookmarks.filter { $0.itemType == .wishlistItem }.count)
        #expect(elapsed < 15, "export + import took \(elapsed)s for \(html.utf8.count / 1_000_000) MB")
    }

    @Test("Sync: snapshot → JSON → restore keeps counts and relationships, repeatedly")
    func syncRoundTrip() throws {
        let library = try makeLibrary()
        let data = try JSONEncoder().encode(try SyncService.buildSnapshot(context: library.context))

        let target = try makeLibrary(count: 0)
        let elapsed = try seconds {
            // Launch-time import can run on every start — repeated restores must not duplicate.
            for _ in 0..<3 {
                let snapshot = try JSONDecoder().decode(SyncData.self, from: data)
                try SyncService.restore(syncData: snapshot, context: target.context)
                try target.context.save()
            }
        }
        let context = target.context
        #expect(try context.fetchCount(FetchDescriptor<Bookmark>()) == Self.itemCount)
        #expect(try context.fetchCount(FetchDescriptor<Folder>()) == library.folders.count)
        #expect(try context.fetchCount(FetchDescriptor<Tag>()) == library.tags.count)

        let original = library.bookmarks[4321]
        let originalID = original.id
        let copy = try #require(try context.fetch(
            FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == originalID })).first)
        #expect(copy.collection?.name == original.collection?.name)
        #expect(copy.collection?.parent?.name == original.collection?.parent?.name)
        #expect(Set(copy.tags.map(\.name)) == Set(original.tags.map(\.name)))
        #expect(elapsed < 30, "3 restores took \(elapsed)s for \(data.count / 1_000_000) MB")
    }

    @Test("Deeply nested folders (depth 200) flatten without overflowing the stack")
    func deepFolderTree() throws {
        let library = try makeLibrary(count: 0)
        var parent: Folder?
        var chain: [Folder] = []
        for depth in 0..<200 {
            let folder = Folder(name: "Level \(depth)", parent: parent)
            library.context.insert(folder)
            chain.append(folder)
            parent = folder
        }
        let all = library.folders + chain
        let flattened = FolderTree.flattened(all)
        #expect(flattened.count == all.count)
        #expect(flattened.last(where: { $0.folder.id == chain.last?.id })?.path.hasPrefix("Level 0") == true)
        // Moving the root of the chain into its own deepest descendant must be refused.
        #expect(!FolderTree.canMove(chain[0], into: chain[199], folders: all))
    }
}

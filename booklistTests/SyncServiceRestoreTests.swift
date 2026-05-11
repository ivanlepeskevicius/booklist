import Testing
import SwiftData
import Foundation
@testable import booklist

@Suite("SyncService restore + buildSnapshot")
struct SyncServiceRestoreTests {

    // MARK: - Helper

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Bookmark.self, Folder.self, Tag.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private var fixedDate: Date { Date(timeIntervalSince1970: 1_000_000) }

    private func makeFolderSnap(id: UUID = UUID(), name: String = "Folder",
                                icon: String = "folder", color: String = "#000",
                                sortOrder: Int = 0, parentID: UUID? = nil) -> SyncService.FolderSnap {
        SyncService.FolderSnap(id: id, name: name, icon: icon,
                               color: color, sortOrder: sortOrder, parentID: parentID)
    }

    private func makeTagSnap(id: UUID = UUID(), name: String = "Tag",
                             color: String = "#AAA") -> SyncService.TagSnap {
        SyncService.TagSnap(id: id, name: name, color: color)
    }

    private func makeBookmarkSnap(id: UUID = UUID(), title: String = "Title",
                                  url: String = "https://example.com",
                                  collectionID: UUID? = nil,
                                  tagIDs: [UUID] = [],
                                  itemType: String = "bookmark",
                                  isPinned: Bool = false,
                                  isRead: Bool = false) -> SyncService.BookmarkSnap {
        SyncService.BookmarkSnap(
            id: id, title: title, url: url,
            pageDescription: nil, note: nil, faviconURL: nil,
            imageURLs: [], selectedImageURL: nil,
            itemType: itemType, price: nil,
            dateAdded: fixedDate, lastOpenedDate: nil,
            isPinned: isPinned, isRead: isRead,
            collectionID: collectionID, tagIDs: tagIDs
        )
    }

    private func syncData(folders: [SyncService.FolderSnap] = [],
                          tags: [SyncService.TagSnap] = [],
                          bookmarks: [SyncService.BookmarkSnap] = []) -> SyncService.SyncData {
        SyncService.SyncData(version: 1, exportedAt: fixedDate,
                             folders: folders, tags: tags, bookmarks: bookmarks)
    }

    // MARK: - restore: empty snapshot

    @Test("Restoring an empty snapshot leaves context with zero objects")
    func restoreEmpty() throws {
        let context = try makeContext()
        try SyncService.restore(syncData: syncData(), context: context)

        #expect(try context.fetch(FetchDescriptor<Folder>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Tag>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Bookmark>()).isEmpty)
    }

    // MARK: - restore: folders

    @Test("Restored folder has all fields preserved")
    func restoredFolderFields() throws {
        let id = UUID()
        let snap = makeFolderSnap(id: id, name: "Reading", icon: "book",
                                  color: "#4A90E2", sortOrder: 3)
        let context = try makeContext()
        try SyncService.restore(syncData: syncData(folders: [snap]), context: context)

        let folders = try context.fetch(FetchDescriptor<Folder>())
        #expect(folders.count == 1)
        let f = try #require(folders.first)
        #expect(f.id == id)
        #expect(f.name == "Reading")
        #expect(f.icon == "book")
        #expect(f.color == "#4A90E2")
        #expect(f.sortOrder == 3)
        #expect(f.parent == nil)
    }

    @Test("Restored folder parent link is wired in two-pass")
    func restoredFolderParentLink() throws {
        let parentID = UUID()
        let childID = UUID()
        let snaps = [
            makeFolderSnap(id: parentID, name: "Parent"),
            makeFolderSnap(id: childID, name: "Child", parentID: parentID)
        ]
        let context = try makeContext()
        try SyncService.restore(syncData: syncData(folders: snaps), context: context)

        let folders = try context.fetch(FetchDescriptor<Folder>())
        let child = try #require(folders.first { $0.id == childID })
        #expect(child.parent?.id == parentID)
    }

    @Test("Top-level folder parent is nil after restore")
    func restoredTopLevelFolderNilParent() throws {
        let snap = makeFolderSnap(name: "Root", parentID: nil)
        let context = try makeContext()
        try SyncService.restore(syncData: syncData(folders: [snap]), context: context)

        let folder = try #require(try context.fetch(FetchDescriptor<Folder>()).first)
        #expect(folder.parent == nil)
    }

    // MARK: - restore: tags

    @Test("Restored tag has all fields preserved")
    func restoredTagFields() throws {
        let id = UUID()
        let snap = makeTagSnap(id: id, name: "swift", color: "#F05138")
        let context = try makeContext()
        try SyncService.restore(syncData: syncData(tags: [snap]), context: context)

        let tags = try context.fetch(FetchDescriptor<Tag>())
        #expect(tags.count == 1)
        let t = try #require(tags.first)
        #expect(t.id == id)
        #expect(t.name == "swift")
        #expect(t.color == "#F05138")
    }

    // MARK: - restore: bookmarks

    @Test("Restored bookmark has all fields preserved")
    func restoredBookmarkFields() throws {
        let id = UUID()
        let snap = SyncService.BookmarkSnap(
            id: id, title: "Swift.org", url: "https://swift.org",
            pageDescription: "Official Swift docs",
            note: "Great reference", faviconURL: "https://swift.org/favicon.ico",
            imageURLs: ["https://img1.com"],
            selectedImageURL: "https://img1.com",
            itemType: "wishlistItem", price: "$0",
            dateAdded: fixedDate, lastOpenedDate: nil,
            isPinned: true, isRead: true,
            collectionID: nil, tagIDs: []
        )
        let context = try makeContext()
        try SyncService.restore(syncData: syncData(bookmarks: [snap]), context: context)

        let bookmarks = try context.fetch(FetchDescriptor<Bookmark>())
        #expect(bookmarks.count == 1)
        let bm = try #require(bookmarks.first)
        #expect(bm.id == id)
        #expect(bm.title == "Swift.org")
        #expect(bm.url == "https://swift.org")
        #expect(bm.pageDescription == "Official Swift docs")
        #expect(bm.note == "Great reference")
        #expect(bm.faviconURL == "https://swift.org/favicon.ico")
        #expect(bm.imageURLs == ["https://img1.com"])
        #expect(bm.selectedImageURL == "https://img1.com")
        #expect(bm.itemType == .wishlistItem)
        #expect(bm.price == "$0")
        #expect(bm.isPinned == true)
        #expect(bm.isRead == true)
    }

    @Test("Restored bookmark is linked to its folder")
    func restoredBookmarkFolderLink() throws {
        let folderID = UUID()
        let context = try makeContext()
        try SyncService.restore(syncData: syncData(
            folders: [makeFolderSnap(id: folderID)],
            bookmarks: [makeBookmarkSnap(collectionID: folderID)]
        ), context: context)

        let bm = try #require(try context.fetch(FetchDescriptor<Bookmark>()).first)
        #expect(bm.collection?.id == folderID)
    }

    @Test("Restored bookmark with nil collectionID has no folder")
    func restoredBookmarkNilFolder() throws {
        let context = try makeContext()
        try SyncService.restore(syncData: syncData(
            bookmarks: [makeBookmarkSnap(collectionID: nil)]
        ), context: context)

        let bm = try #require(try context.fetch(FetchDescriptor<Bookmark>()).first)
        #expect(bm.collection == nil)
    }

    @Test("Restored bookmark is linked to its tags")
    func restoredBookmarkTagLinks() throws {
        let tagID1 = UUID()
        let tagID2 = UUID()
        let context = try makeContext()
        try SyncService.restore(syncData: syncData(
            tags: [makeTagSnap(id: tagID1, name: "a"), makeTagSnap(id: tagID2, name: "b")],
            bookmarks: [makeBookmarkSnap(tagIDs: [tagID1, tagID2])]
        ), context: context)

        let bm = try #require(try context.fetch(FetchDescriptor<Bookmark>()).first)
        let restoredTagIDs = Set(bm.tags.map(\.id))
        #expect(restoredTagIDs == Set([tagID1, tagID2]))
    }

    @Test("Restore deletes pre-existing data before inserting")
    func restoreClearsExistingData() throws {
        let context = try makeContext()
        // Pre-populate
        context.insert(Bookmark(title: "Old", url: "https://old.com"))
        context.insert(Tag(name: "OldTag"))
        context.insert(Folder(name: "OldFolder"))
        try context.save()

        // Restore with a completely different single bookmark
        let newID = UUID()
        try SyncService.restore(syncData: syncData(
            bookmarks: [makeBookmarkSnap(id: newID, title: "New")]
        ), context: context)

        let bookmarks = try context.fetch(FetchDescriptor<Bookmark>())
        let tags = try context.fetch(FetchDescriptor<Tag>())
        let folders = try context.fetch(FetchDescriptor<Folder>())
        #expect(bookmarks.count == 1)
        #expect(bookmarks[0].id == newID)
        #expect(tags.isEmpty)
        #expect(folders.isEmpty)
    }

    @Test("Unknown itemType raw value falls back to .bookmark")
    func unknownItemTypeFallsBack() throws {
        let snap = makeBookmarkSnap(itemType: "unknownFutureType")
        let context = try makeContext()
        try SyncService.restore(syncData: syncData(bookmarks: [snap]), context: context)

        let bm = try #require(try context.fetch(FetchDescriptor<Bookmark>()).first)
        #expect(bm.itemType == .bookmark)
    }

    // MARK: - buildSnapshot

    @Test("Empty context produces snapshot with all-empty collections")
    func buildSnapshotEmpty() throws {
        let context = try makeContext()
        let snap = try SyncService.buildSnapshot(context: context)

        #expect(snap.version == SyncService.SyncData.currentVersion)
        #expect(snap.folders.isEmpty)
        #expect(snap.tags.isEmpty)
        #expect(snap.bookmarks.isEmpty)
    }

    @Test("buildSnapshot captures folder fields including sortOrder")
    func buildSnapshotFolder() throws {
        let context = try makeContext()
        let folder = Folder(name: "Design", icon: "paintbrush", color: "#FF6B6B", sortOrder: 2)
        context.insert(folder)

        let snap = try SyncService.buildSnapshot(context: context)
        #expect(snap.folders.count == 1)
        let fs = snap.folders[0]
        #expect(fs.id == folder.id)
        #expect(fs.name == "Design")
        #expect(fs.icon == "paintbrush")
        #expect(fs.color == "#FF6B6B")
        #expect(fs.sortOrder == 2)
        #expect(fs.parentID == nil)
    }

    @Test("buildSnapshot captures folder parentID")
    func buildSnapshotFolderParentID() throws {
        let context = try makeContext()
        let parent = Folder(name: "Parent")
        let child = Folder(name: "Child")
        child.parent = parent
        context.insert(parent)
        context.insert(child)

        let snap = try SyncService.buildSnapshot(context: context)
        let childSnap = try #require(snap.folders.first { $0.name == "Child" })
        #expect(childSnap.parentID == parent.id)
    }

    @Test("buildSnapshot captures tag fields")
    func buildSnapshotTag() throws {
        let context = try makeContext()
        let tag = Tag(name: "swift", color: "#F05138")
        context.insert(tag)

        let snap = try SyncService.buildSnapshot(context: context)
        #expect(snap.tags.count == 1)
        #expect(snap.tags[0].id == tag.id)
        #expect(snap.tags[0].name == "swift")
        #expect(snap.tags[0].color == "#F05138")
    }

    @Test("buildSnapshot captures bookmark fields and collectionID")
    func buildSnapshotBookmark() throws {
        let context = try makeContext()
        let folder = Folder(name: "Dev")
        context.insert(folder)
        let bm = Bookmark(title: "Swift", url: "https://swift.org",
                          note: "Great", collection: folder)
        bm.isPinned = true
        context.insert(bm)

        let snap = try SyncService.buildSnapshot(context: context)
        #expect(snap.bookmarks.count == 1)
        let bs = snap.bookmarks[0]
        #expect(bs.id == bm.id)
        #expect(bs.title == "Swift")
        #expect(bs.url == "https://swift.org")
        #expect(bs.note == "Great")
        #expect(bs.isPinned == true)
        #expect(bs.collectionID == folder.id)
    }

    @Test("buildSnapshot captures bookmark tagIDs")
    func buildSnapshotBookmarkTagIDs() throws {
        let context = try makeContext()
        let tag1 = Tag(name: "a")
        let tag2 = Tag(name: "b")
        context.insert(tag1)
        context.insert(tag2)
        let bm = Bookmark(title: "T", url: "https://t.com", tags: [tag1, tag2])
        context.insert(bm)

        let snap = try SyncService.buildSnapshot(context: context)
        let bs = try #require(snap.bookmarks.first)
        #expect(Set(bs.tagIDs) == Set([tag1.id, tag2.id]))
    }

    // MARK: - Full round-trip: buildSnapshot → restore → buildSnapshot

    @Test("buildSnapshot and restore are inverses: full round-trip")
    func buildRestoreRoundTrip() throws {
        let context = try makeContext()
        let tag = Tag(name: "swift", color: "#F05138")
        let folder = Folder(name: "Dev", icon: "code", color: "#4A90E2", sortOrder: 1)
        let bm = Bookmark(title: "Swift.org", url: "https://swift.org",
                          note: "Good", collection: folder, tags: [tag])
        bm.isPinned = true
        context.insert(tag)
        context.insert(folder)
        context.insert(bm)

        let original = try SyncService.buildSnapshot(context: context)
        try SyncService.restore(syncData: original, context: context)
        let restored = try SyncService.buildSnapshot(context: context)

        #expect(restored.folders.count == original.folders.count)
        #expect(restored.tags.count == original.tags.count)
        #expect(restored.bookmarks.count == original.bookmarks.count)
        #expect(restored.bookmarks[0].title == original.bookmarks[0].title)
        #expect(restored.bookmarks[0].isPinned == original.bookmarks[0].isPinned)
        #expect(restored.bookmarks[0].collectionID == original.bookmarks[0].collectionID)
        #expect(Set(restored.bookmarks[0].tagIDs) == Set(original.bookmarks[0].tagIDs))
    }

    // MARK: - Error paths

    @Test("importIfNewer returns false when no sync folder is configured")
    func importIfNewerNoFolder() throws {
        // Ensure no bookmark is stored
        UserDefaults.standard.removeObject(forKey: "syncFolderBookmark")
        let context = try makeContext()
        let result = try SyncService.importIfNewer(context: context)
        #expect(result == false)
    }

    @Test("export throws noSyncFolder when no sync folder is configured")
    func exportThrowsNoSyncFolder() throws {
        UserDefaults.standard.removeObject(forKey: "syncFolderBookmark")
        let context = try makeContext()
        #expect(throws: SyncService.SyncError.noSyncFolder) {
            try SyncService.export(context: context)
        }
    }

    @Test("syncFileName constant is the expected filename")
    func syncFileNameConstant() {
        #expect(SyncService.syncFileName == "booklist-sync.json")
    }
}

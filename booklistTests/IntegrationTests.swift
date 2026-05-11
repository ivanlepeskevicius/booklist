import Testing
import SwiftData
import Foundation
@testable import booklist

// Shadow Testing.Tag so our SwiftData Tag model is unambiguous throughout this file.
private typealias Tag = booklist.Tag

// MARK: - File-scope helpers (shared by both suites)

private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Bookmark.self, Folder.self, Tag.self,
                              configurations: config)
}

private func makeSyncEncoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return e
}

private func makeSyncDecoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}

/// Encodes `syncData` and writes it to a unique temp file. Caller must delete.
private func writeTempSyncFile(_ syncData: SyncService.SyncData) throws -> URL {
    let data = try makeSyncEncoder().encode(syncData)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("test-sync-\(UUID().uuidString).json")
    try data.write(to: url, options: .atomic)
    return url
}

/// Reads and decodes a SyncData snapshot from `url`.
private func readSyncFile(at url: URL) throws -> SyncService.SyncData {
    let data = try Data(contentsOf: url)
    return try makeSyncDecoder().decode(SyncService.SyncData.self, from: data)
}

// MARK: - Suite 1: SyncService file I/O

@Suite("SyncService file I/O integration")
struct SyncFileIOTests {

    // MARK: Full cycle

    @Test("Full round-trip via file: all fields of folder, tag, and bookmark are preserved")
    func fullRoundTripViaFile() throws {
        let srcCtx = ModelContext(try makeContainer())

        let tag    = Tag(name: "swift", color: "#F05138")
        let folder = Folder(name: "Dev", icon: "code", color: "#4A90E2", sortOrder: 1)
        let bm     = Bookmark(title: "Swift.org", url: "https://swift.org",
                              note: "Official site", collection: folder, tags: [tag])
        bm.isPinned = true
        srcCtx.insert(tag)
        srcCtx.insert(folder)
        srcCtx.insert(bm)

        let fileURL = try writeTempSyncFile(SyncService.buildSnapshot(context: srcCtx))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let dstCtx = ModelContext(try makeContainer())
        try SyncService.restore(syncData: readSyncFile(at: fileURL), context: dstCtx)

        let folders   = try dstCtx.fetch(FetchDescriptor<Folder>())
        let tags      = try dstCtx.fetch(FetchDescriptor<Tag>())
        let bookmarks = try dstCtx.fetch(FetchDescriptor<Bookmark>())

        #expect(folders.count == 1)
        #expect(tags.count == 1)
        #expect(bookmarks.count == 1)

        let f = try #require(folders.first)
        #expect(f.name == "Dev")
        #expect(f.icon == "code")
        #expect(f.color == "#4A90E2")
        #expect(f.sortOrder == 1)

        let t = try #require(tags.first)
        #expect(t.name == "swift")
        #expect(t.color == "#F05138")

        let b = try #require(bookmarks.first)
        #expect(b.title == "Swift.org")
        #expect(b.url == "https://swift.org")
        #expect(b.note == "Official site")
        #expect(b.isPinned == true)
        #expect(b.collection?.name == "Dev")
        #expect(b.tags.first?.name == "swift")
    }

    @Test("Empty database: snapshot file round-trips to an empty context")
    func emptyDatabaseViaFile() throws {
        let srcCtx = ModelContext(try makeContainer())

        let fileURL = try writeTempSyncFile(SyncService.buildSnapshot(context: srcCtx))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let dstCtx = ModelContext(try makeContainer())
        try SyncService.restore(syncData: readSyncFile(at: fileURL), context: dstCtx)

        #expect(try dstCtx.fetch(FetchDescriptor<Folder>()).isEmpty)
        #expect(try dstCtx.fetch(FetchDescriptor<Tag>()).isEmpty)
        #expect(try dstCtx.fetch(FetchDescriptor<Bookmark>()).isEmpty)
    }

    @Test("Nested folder parent link is preserved through the file")
    func nestedFolderHierarchyViaFile() throws {
        let srcCtx = ModelContext(try makeContainer())

        let parent = Folder(name: "Parent")
        let child  = Folder(name: "Child")
        child.parent = parent
        srcCtx.insert(parent)
        srcCtx.insert(child)

        let fileURL = try writeTempSyncFile(SyncService.buildSnapshot(context: srcCtx))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let dstCtx = ModelContext(try makeContainer())
        try SyncService.restore(syncData: readSyncFile(at: fileURL), context: dstCtx)

        let folders       = try dstCtx.fetch(FetchDescriptor<Folder>())
        let restoredChild  = try #require(folders.first { $0.name == "Child" })
        let restoredParent = try #require(folders.first { $0.name == "Parent" })
        #expect(restoredChild.parent?.id == restoredParent.id)
    }

    @Test("Tag links on a bookmark survive the file round-trip")
    func bookmarkTagLinksViaFile() throws {
        let srcCtx = ModelContext(try makeContainer())

        let tag1 = Tag(name: "design")
        let tag2 = Tag(name: "swift")
        let bm   = Bookmark(title: "T", url: "https://t.com", tags: [tag1, tag2])
        srcCtx.insert(tag1)
        srcCtx.insert(tag2)
        srcCtx.insert(bm)

        let fileURL = try writeTempSyncFile(SyncService.buildSnapshot(context: srcCtx))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let dstCtx = ModelContext(try makeContainer())
        try SyncService.restore(syncData: readSyncFile(at: fileURL), context: dstCtx)

        let b = try #require(try dstCtx.fetch(FetchDescriptor<Bookmark>()).first)
        #expect(Set(b.tags.map(\.name)) == Set(["design", "swift"]))
    }

    @Test("Wishlist item type and price are preserved through the file")
    func wishlistItemTypeViaFile() throws {
        let srcCtx = ModelContext(try makeContainer())
        let bm = Bookmark(title: "Bag", url: "https://shop.com",
                          itemType: .wishlistItem, price: "€49")
        srcCtx.insert(bm)

        let fileURL = try writeTempSyncFile(SyncService.buildSnapshot(context: srcCtx))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let dstCtx = ModelContext(try makeContainer())
        try SyncService.restore(syncData: readSyncFile(at: fileURL), context: dstCtx)

        let b = try #require(try dstCtx.fetch(FetchDescriptor<Bookmark>()).first)
        #expect(b.itemType == .wishlistItem)
        #expect(b.price == "€49")
    }

    @Test("Multiple bookmarks all survive the file round-trip")
    func multipleBookmarksViaFile() throws {
        let srcCtx = ModelContext(try makeContainer())
        let urls = ["https://a.com", "https://b.com", "https://c.com"]
        urls.enumerated().forEach { i, url in
            srcCtx.insert(Bookmark(title: "\(i)", url: url))
        }

        let fileURL = try writeTempSyncFile(SyncService.buildSnapshot(context: srcCtx))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let dstCtx = ModelContext(try makeContainer())
        try SyncService.restore(syncData: readSyncFile(at: fileURL), context: dstCtx)

        let restored = try dstCtx.fetch(FetchDescriptor<Bookmark>())
        #expect(restored.count == 3)
        #expect(Set(restored.map(\.url)) == Set(urls))
    }

    // MARK: JSON structure

    @Test("Written JSON file contains the expected top-level keys")
    func jsonFileContainsExpectedKeys() throws {
        let srcCtx  = ModelContext(try makeContainer())
        let fileURL = try writeTempSyncFile(SyncService.buildSnapshot(context: srcCtx))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        )
        #expect(json["version"]    != nil)
        #expect(json["exportedAt"] != nil)
        #expect(json["folders"]    != nil)
        #expect(json["tags"]       != nil)
        #expect(json["bookmarks"]  != nil)
    }

    @Test("version field in the JSON file matches SyncData.currentVersion")
    func jsonFileVersionMatchesConstant() throws {
        let srcCtx  = ModelContext(try makeContainer())
        let fileURL = try writeTempSyncFile(SyncService.buildSnapshot(context: srcCtx))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let json    = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        )
        let version = try #require(json["version"] as? Int)
        #expect(version == SyncService.SyncData.currentVersion)
    }
}

// MARK: - Suite 2: SwiftData → Export chain

@Suite("SwiftData → Export chain integration")
struct SwiftDataExportChainTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try makeContainer())
    }

    // MARK: makeExportItems

    @Test("makeExportItems maps all scalar fields from a SwiftData Bookmark")
    func makeExportItemsScalarFields() throws {
        let ctx = try makeContext()
        let bm  = Bookmark(title: "Swift Docs", url: "https://docs.swift.org",
                           note: "Essential reference",
                           selectedImageURL: "https://img.com/cover.jpg",
                           itemType: .wishlistItem, price: "$0")
        ctx.insert(bm)

        let items = ExportService.makeExportItems(from: [bm])
        let item  = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.title          == "Swift Docs")
        #expect(item.url            == "https://docs.swift.org")
        #expect(item.note           == "Essential reference")
        #expect(item.imageURL       == "https://img.com/cover.jpg")
        #expect(item.isWishlistItem == true)
        #expect(item.price          == "$0")
    }

    @Test("makeExportItems maps tag names from SwiftData relationships")
    func makeExportItemsTagNames() throws {
        let ctx  = try makeContext()
        let tag1 = Tag(name: "design")
        let tag2 = Tag(name: "swift")
        ctx.insert(tag1)
        ctx.insert(tag2)
        let bm = Bookmark(title: "T", url: "https://t.com", tags: [tag1, tag2])
        ctx.insert(bm)

        let item = try #require(ExportService.makeExportItems(from: [bm]).first)
        #expect(Set(item.tags) == Set(["design", "swift"]))
    }

    @Test("makeExportItems captures folder name as folderPath")
    func makeExportItemsFolderName() throws {
        let ctx    = try makeContext()
        let folder = Folder(name: "Reading")
        ctx.insert(folder)
        let bm = Bookmark(title: "T", url: "https://t.com", collection: folder)
        ctx.insert(bm)

        let item = try #require(ExportService.makeExportItems(from: [bm]).first)
        #expect(item.folderPath == "Reading")
    }

    @Test("makeExportItems sets folderPath to nil when bookmark has no folder")
    func makeExportItemsNilFolder() throws {
        let ctx = try makeContext()
        let bm  = Bookmark(title: "T", url: "https://t.com")
        ctx.insert(bm)

        let item = try #require(ExportService.makeExportItems(from: [bm]).first)
        #expect(item.folderPath == nil)
    }

    // MARK: Full chain

    @Test("Full chain: SwiftData Bookmark → makeExportItems → generateHTML → parseBooklistHTML")
    func fullChainSingleItem() throws {
        let ctx    = try makeContext()
        let tag    = Tag(name: "swift")
        let folder = Folder(name: "Dev")
        ctx.insert(tag)
        ctx.insert(folder)
        let bm = Bookmark(title: "Swift Forums", url: "https://forums.swift.org",
                          note: "Great community", collection: folder, tags: [tag])
        ctx.insert(bm)

        let items  = ExportService.makeExportItems(from: [bm])
        let html   = ExportService.generateHTML(items: items, title: "Export")
        let parsed = try #require(ImportService.parseBooklistHTML(html))

        #expect(parsed.count == 1)
        let p = try #require(parsed.first)
        #expect(p.title      == "Swift Forums")
        #expect(p.url        == "https://forums.swift.org")
        #expect(p.note       == "Great community")
        #expect(p.folderPath == "Dev")
        #expect(p.tags       == ["swift"])
    }

    @Test("Full chain preserves count and URLs for multiple bookmarks")
    func fullChainMultipleItems() throws {
        let ctx  = try makeContext()
        let bms  = ["https://a.com", "https://b.com", "https://c.com"].map {
            Bookmark(title: $0, url: $0)
        }
        bms.forEach { ctx.insert($0) }

        let items  = ExportService.makeExportItems(from: bms)
        let html   = ExportService.generateHTML(items: items, title: "My List")
        let parsed = try #require(ImportService.parseBooklistHTML(html))

        #expect(parsed.count == 3)
        #expect(Set(parsed.map(\.url)) == Set(["https://a.com", "https://b.com", "https://c.com"]))
    }

    @Test("Wishlist flag and price survive the full SwiftData → HTML → ParsedBookmark chain")
    func wishlistThroughFullChain() throws {
        let ctx = try makeContext()
        let bm  = Bookmark(title: "Bag", url: "https://shop.com",
                           itemType: .wishlistItem, price: "€49")
        ctx.insert(bm)

        let items  = ExportService.makeExportItems(from: [bm])
        let html   = ExportService.generateHTML(items: items, title: "Wishlist")
        let parsed = try #require(ImportService.parseBooklistHTML(html))

        let p = try #require(parsed.first)
        #expect(p.isWishlistItem == true)
        #expect(p.price          == "€49")
    }
}

import Testing
import Foundation
@testable import booklist

/// Tests for SyncService's Codable snapshot types using the same
/// encoder/decoder strategy that SyncService uses (ISO 8601 dates).
@Suite("SyncData Codable")
struct SyncDataTests {

    // MARK: - Encoder / decoder matching SyncService

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    /// Encode then decode — the core round-trip helper.
    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try decode(T.self, from: encode(value))
    }

    /// A fixed Date with no sub-second component so ISO 8601 round-trips exactly.
    private var fixedDate: Date { Date(timeIntervalSince1970: 1_000_000) }
    private var fixedDate2: Date { Date(timeIntervalSince1970: 2_000_000) }

    // MARK: - TagSnap

    @Suite("TagSnap")
    struct TagSnapTests: SyncDataTestHelpers {

        @Test("All fields round-trip correctly")
        func allFields() throws {
            let id = UUID()
            let snap = SyncService.TagSnap(id: id, name: "Design", color: "#FF6B6B")
            let decoded = try roundTrip(snap)

            #expect(decoded.id == id)
            #expect(decoded.name == "Design")
            #expect(decoded.color == "#FF6B6B")
        }

        @Test("Empty name and color strings round-trip")
        func emptyStrings() throws {
            let snap = SyncService.TagSnap(id: UUID(), name: "", color: "")
            let decoded = try roundTrip(snap)
            #expect(decoded.name == "")
            #expect(decoded.color == "")
        }

        @Test("Unicode name round-trips correctly")
        func unicodeName() throws {
            let snap = SyncService.TagSnap(id: UUID(), name: "🎨 Art", color: "#ABC123")
            let decoded = try roundTrip(snap)
            #expect(decoded.name == "🎨 Art")
        }
    }

    // MARK: - FolderSnap

    @Suite("FolderSnap")
    struct FolderSnapTests: SyncDataTestHelpers {

        @Test("All fields round-trip with nil parentID")
        func nilParentID() throws {
            let id = UUID()
            let snap = SyncService.FolderSnap(
                id: id, name: "Reading", icon: "book",
                color: "#4A90E2", sortOrder: 2, parentID: nil
            )
            let decoded = try roundTrip(snap)

            #expect(decoded.id == id)
            #expect(decoded.name == "Reading")
            #expect(decoded.icon == "book")
            #expect(decoded.color == "#4A90E2")
            #expect(decoded.sortOrder == 2)
            #expect(decoded.parentID == nil)
        }

        @Test("Non-nil parentID round-trips correctly")
        func nonNilParentID() throws {
            let parentID = UUID()
            let snap = SyncService.FolderSnap(
                id: UUID(), name: "Child", icon: "folder",
                color: "#808080", sortOrder: 0, parentID: parentID
            )
            let decoded = try roundTrip(snap)
            #expect(decoded.parentID == parentID)
        }

        @Test("sortOrder zero and non-zero both round-trip")
        func sortOrders() throws {
            let snap0 = SyncService.FolderSnap(id: UUID(), name: "A", icon: "x", color: "#000", sortOrder: 0, parentID: nil)
            let snap5 = SyncService.FolderSnap(id: UUID(), name: "B", icon: "x", color: "#000", sortOrder: 5, parentID: nil)
            #expect(try roundTrip(snap0).sortOrder == 0)
            #expect(try roundTrip(snap5).sortOrder == 5)
        }
    }

    // MARK: - BookmarkSnap

    @Suite("BookmarkSnap")
    struct BookmarkSnapTests: SyncDataTestHelpers {

        private var fixedDate: Date { Date(timeIntervalSince1970: 1_000_000) }

        @Test("Minimal bookmark (all optionals nil) round-trips")
        func minimalBookmark() throws {
            let id = UUID()
            let snap = SyncService.BookmarkSnap(
                id: id, title: "Title", url: "https://example.com",
                pageDescription: nil, note: nil, faviconURL: nil,
                imageURLs: [], selectedImageURL: nil,
                itemType: "bookmark", price: nil,
                dateAdded: fixedDate, lastOpenedDate: nil,
                isPinned: false, isRead: false,
                collectionID: nil, tagIDs: []
            )
            let decoded = try roundTrip(snap)

            #expect(decoded.id == id)
            #expect(decoded.title == "Title")
            #expect(decoded.url == "https://example.com")
            #expect(decoded.pageDescription == nil)
            #expect(decoded.note == nil)
            #expect(decoded.faviconURL == nil)
            #expect(decoded.imageURLs.isEmpty)
            #expect(decoded.selectedImageURL == nil)
            #expect(decoded.itemType == "bookmark")
            #expect(decoded.price == nil)
            #expect(decoded.lastOpenedDate == nil)
            #expect(decoded.isPinned == false)
            #expect(decoded.isRead == false)
            #expect(decoded.collectionID == nil)
            #expect(decoded.tagIDs.isEmpty)
        }

        @Test("Fully populated bookmark round-trips with all fields")
        func fullyPopulated() throws {
            let collectionID = UUID()
            let tagID1 = UUID()
            let tagID2 = UUID()
            let snap = SyncService.BookmarkSnap(
                id: UUID(), title: "Swift Docs", url: "https://swift.org",
                pageDescription: "Official Swift docs",
                note: "Great reference", faviconURL: "https://swift.org/favicon.ico",
                imageURLs: ["https://img1.com", "https://img2.com"],
                selectedImageURL: "https://img1.com",
                itemType: "wishlistItem", price: "$0.00",
                dateAdded: fixedDate, lastOpenedDate: fixedDate,
                isPinned: true, isRead: true,
                collectionID: collectionID, tagIDs: [tagID1, tagID2]
            )
            let decoded = try roundTrip(snap)

            #expect(decoded.title == "Swift Docs")
            #expect(decoded.pageDescription == "Official Swift docs")
            #expect(decoded.note == "Great reference")
            #expect(decoded.faviconURL == "https://swift.org/favicon.ico")
            #expect(decoded.imageURLs == ["https://img1.com", "https://img2.com"])
            #expect(decoded.selectedImageURL == "https://img1.com")
            #expect(decoded.itemType == "wishlistItem")
            #expect(decoded.price == "$0.00")
            #expect(decoded.isPinned == true)
            #expect(decoded.isRead == true)
            #expect(decoded.collectionID == collectionID)
            #expect(decoded.tagIDs == [tagID1, tagID2])
        }

        @Test("lastOpenedDate nil round-trips as nil")
        func lastOpenedDateNil() throws {
            let snap = SyncService.BookmarkSnap(
                id: UUID(), title: "T", url: "https://t.com",
                pageDescription: nil, note: nil, faviconURL: nil,
                imageURLs: [], selectedImageURL: nil,
                itemType: "bookmark", price: nil,
                dateAdded: fixedDate, lastOpenedDate: nil,
                isPinned: false, isRead: false, collectionID: nil, tagIDs: []
            )
            #expect(try roundTrip(snap).lastOpenedDate == nil)
        }

        @Test("lastOpenedDate non-nil round-trips correctly")
        func lastOpenedDateNonNil() throws {
            let opened = Date(timeIntervalSince1970: 1_500_000)
            let snap = SyncService.BookmarkSnap(
                id: UUID(), title: "T", url: "https://t.com",
                pageDescription: nil, note: nil, faviconURL: nil,
                imageURLs: [], selectedImageURL: nil,
                itemType: "bookmark", price: nil,
                dateAdded: fixedDate, lastOpenedDate: opened,
                isPinned: false, isRead: false, collectionID: nil, tagIDs: []
            )
            let decoded = try roundTrip(snap)
            // ISO 8601 has 1-second precision; compare with tolerance
            #expect(abs(decoded.lastOpenedDate!.timeIntervalSince(opened)) < 1.0)
        }

        @Test("dateAdded round-trips with ISO 8601 precision")
        func dateAddedISO8601() throws {
            let snap = SyncService.BookmarkSnap(
                id: UUID(), title: "T", url: "https://t.com",
                pageDescription: nil, note: nil, faviconURL: nil,
                imageURLs: [], selectedImageURL: nil,
                itemType: "bookmark", price: nil,
                dateAdded: fixedDate, lastOpenedDate: nil,
                isPinned: false, isRead: false, collectionID: nil, tagIDs: []
            )
            let decoded = try roundTrip(snap)
            #expect(abs(decoded.dateAdded.timeIntervalSince(fixedDate)) < 1.0)
        }

        @Test("tagIDs array with multiple entries round-trips in order")
        func tagIDsOrder() throws {
            let ids = [UUID(), UUID(), UUID()]
            let snap = SyncService.BookmarkSnap(
                id: UUID(), title: "T", url: "https://t.com",
                pageDescription: nil, note: nil, faviconURL: nil,
                imageURLs: [], selectedImageURL: nil,
                itemType: "bookmark", price: nil,
                dateAdded: fixedDate, lastOpenedDate: nil,
                isPinned: false, isRead: false, collectionID: nil, tagIDs: ids
            )
            #expect(try roundTrip(snap).tagIDs == ids)
        }
    }

    // MARK: - SyncData

    @Suite("SyncData")
    struct SyncDataContainerTests: SyncDataTestHelpers {

        private var fixedDate: Date { Date(timeIntervalSince1970: 1_000_000) }

        @Test("currentVersion is 1")
        func currentVersion() {
            #expect(SyncService.SyncData.currentVersion == 1)
        }

        @Test("Empty SyncData round-trips with all empty collections")
        func emptySyncData() throws {
            let syncData = SyncService.SyncData(
                version: SyncService.SyncData.currentVersion,
                exportedAt: fixedDate,
                folders: [], tags: [], bookmarks: []
            )
            let decoded = try roundTrip(syncData)

            #expect(decoded.version == SyncService.SyncData.currentVersion)
            #expect(decoded.folders.isEmpty)
            #expect(decoded.tags.isEmpty)
            #expect(decoded.bookmarks.isEmpty)
        }

        @Test("exportedAt date round-trips with ISO 8601 precision")
        func exportedAtDate() throws {
            let syncData = SyncService.SyncData(
                version: 1, exportedAt: fixedDate,
                folders: [], tags: [], bookmarks: []
            )
            let decoded = try roundTrip(syncData)
            #expect(abs(decoded.exportedAt.timeIntervalSince(fixedDate)) < 1.0)
        }

        @Test("version field is preserved")
        func versionPreserved() throws {
            let syncData = SyncService.SyncData(
                version: 1, exportedAt: fixedDate,
                folders: [], tags: [], bookmarks: []
            )
            #expect(try roundTrip(syncData).version == 1)
        }

        @Test("Multiple folders round-trip with parent links intact")
        func foldersWithParentLinks() throws {
            let parentID = UUID()
            let childID = UUID()
            let folders = [
                SyncService.FolderSnap(id: parentID, name: "Parent", icon: "folder", color: "#AAA", sortOrder: 0, parentID: nil),
                SyncService.FolderSnap(id: childID, name: "Child", icon: "folder", color: "#BBB", sortOrder: 1, parentID: parentID)
            ]
            let syncData = SyncService.SyncData(
                version: 1, exportedAt: fixedDate,
                folders: folders, tags: [], bookmarks: []
            )
            let decoded = try roundTrip(syncData)

            #expect(decoded.folders.count == 2)
            #expect(decoded.folders[0].parentID == nil)
            #expect(decoded.folders[1].parentID == parentID)
        }

        @Test("Tags and bookmarks all round-trip within SyncData")
        func fullSyncData() throws {
            let tagID = UUID()
            let folderID = UUID()
            let tags = [SyncService.TagSnap(id: tagID, name: "swift", color: "#F05138")]
            let bookmarks = [
                SyncService.BookmarkSnap(
                    id: UUID(), title: "Swift.org", url: "https://swift.org",
                    pageDescription: nil, note: nil, faviconURL: nil,
                    imageURLs: [], selectedImageURL: nil,
                    itemType: "bookmark", price: nil,
                    dateAdded: fixedDate, lastOpenedDate: nil,
                    isPinned: false, isRead: false,
                    collectionID: folderID, tagIDs: [tagID]
                )
            ]
            let syncData = SyncService.SyncData(
                version: 1, exportedAt: fixedDate,
                folders: [SyncService.FolderSnap(id: folderID, name: "Dev", icon: "code", color: "#000", sortOrder: 0, parentID: nil)],
                tags: tags, bookmarks: bookmarks
            )
            let decoded = try roundTrip(syncData)

            #expect(decoded.tags.count == 1)
            #expect(decoded.tags[0].name == "swift")
            #expect(decoded.bookmarks.count == 1)
            #expect(decoded.bookmarks[0].title == "Swift.org")
            #expect(decoded.bookmarks[0].collectionID == folderID)
            #expect(decoded.bookmarks[0].tagIDs == [tagID])
            #expect(decoded.folders[0].id == folderID)
        }
    }
}

// MARK: - Shared helper protocol (avoids repeating encode/decode in nested suites)

protocol SyncDataTestHelpers {}

extension SyncDataTestHelpers {
    func roundTrip<T: Codable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: encoder.encode(value))
    }
}

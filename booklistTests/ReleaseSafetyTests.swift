import Foundation
import Security
import SwiftData
import Testing
@testable import booklist

private typealias Tag = booklist.Tag

/// Guards against updates that lose the user's library (beta 1.2 (3) did: removing the App Group
/// moved SwiftData's store). Every beta must keep the store where it was, keep entitlements that
/// work with the free signing account, and still open libraries written by earlier releases.
@Suite("Release safety: updates keep the library")
@MainActor
struct ReleaseSafetyTests {

    // MARK: - Where the library lives

    @Test("The library stays in the app's own container, never an App Group container")
    func storeLocation() {
        let path = booklistApp.storeConfiguration(inMemory: false).url.path
        #expect(!path.contains("/Group Containers/"), "Store moved to \(path)")
        #expect(path.hasSuffix("/Library/Application Support/default.store"), "Store moved to \(path)")
    }

    // MARK: - Entitlements

    private func entitlement(_ key: String) -> CFTypeRef? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, key as CFString, nil)
    }

    @Test("No capabilities that need a provisioning profile (they stop betas launching on testers' Macs)",
          arguments: [
            "com.apple.security.application-groups",
            "com.apple.developer.icloud-container-identifiers",
            "com.apple.developer.ubiquity-kvstore-identifier",
            "com.apple.developer.aps-environment",
            "com.apple.developer.associated-domains",
          ])
    func noProfileOnlyEntitlements(_ key: String) {
        #expect(entitlement(key) == nil, "\(key) needs a provisioning profile — free-account betas won't launch on other Macs")
    }

    @Test("Still sandboxed — the container (and so the library) belongs to the sandboxed app")
    func sandboxed() {
        #expect((entitlement("com.apple.security.app-sandbox") as? Bool) == true)
    }

    // MARK: - Libraries from earlier releases

    @Test("A library written by 1.2 opens with every bookmark, folder, tag and field intact")
    func opensLibraryFrom1_2() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-1.2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appendingPathComponent("default.store")
        #expect(!LibraryFixture_1_2.storeData.isEmpty)
        try LibraryFixture_1_2.storeData.write(to: storeURL)

        let container = try ModelContainer(for: booklistApp.schema, configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(container)
        let bookmarks = try context.fetch(FetchDescriptor<Bookmark>())
        #expect(bookmarks.count == 40)
        #expect(try context.fetchCount(FetchDescriptor<Folder>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<Tag>()) == 2)

        let byTitle = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.title, $0) })
        let wish = try #require(byTitle["Fixture 5"])
        #expect(wish.itemType == .wishlistItem && wish.price == "€5.99")
        #expect(wish.tags.map(\.name) == ["want-to-buy"])
        let nested = try #require(byTitle["Fixture 2"])
        #expect(nested.collection?.name == "UI Components" && nested.collection?.parent?.name == "Design")
        #expect(nested.tags.map(\.name) == ["tool"])
        #expect(byTitle["Fixture 3"]?.note == "Note line 1\nNote line 2 for 3")
        #expect(byTitle["Fixture 7"]?.isPinned == true)
        #expect(byTitle["Fixture 6"]?.lastOpenedDate != nil)
        #expect(byTitle["Fixture 1"]?.collection?.name == "Design")

        // And it can still be written to after opening.
        context.insert(Bookmark(title: "Added after update", url: "https://new.example"))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Bookmark>()) == 41)
    }
}

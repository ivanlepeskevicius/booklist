import Foundation
import SwiftData
import Testing
@testable import booklist

private typealias Tag = booklist.Tag

/// Automatic backups and the guards that keep a good copy from being replaced by an empty one.
/// Writes only to scratch folders, never the app's real Backups folder.
@Suite("Backups")
@MainActor
struct BackupServiceTests {

    private func context(bookmarks: Int) throws -> ModelContext {
        let container = try ModelContainer(for: Bookmark.self, Folder.self, Tag.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        for i in 0..<bookmarks { context.insert(Bookmark(title: "B\(i)", url: "https://b.example/\(i)")) }
        try context.save()
        return context
    }

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("backups-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("A backup holds the whole library and reads back")
    func roundTrip() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try #require(BackupService.backUp(context: try context(bookmarks: 25), in: dir))
        #expect(try BackupService.read(url).bookmarks.count == 25)
    }

    @Test("An empty library is never backed up (it would push out the good backups)")
    func skipsEmptyLibrary() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(BackupService.backUp(context: try context(bookmarks: 0), in: dir) == nil)
        #expect(BackupService.backups(in: dir).isEmpty)
    }

    @Test("Only one backup a day at launch; the newest 7 are kept")
    func rotation() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = try context(bookmarks: 3)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(BackupService.backupIfDue(context: library, now: start, in: dir) != nil)
        #expect(BackupService.backupIfDue(context: library, now: start.addingTimeInterval(3600), in: dir) == nil)
        for day in 1...10 {
            BackupService.backupIfDue(context: library, now: start.addingTimeInterval(Double(day) * 86_400), in: dir)
        }
        let kept = BackupService.backups(in: dir)
        #expect(kept.count == 7)
        #expect(kept.first?.date == start.addingTimeInterval(10 * 86_400))   // newest kept
    }

    @Test("Backup file names carry their date")
    func fileNames() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let name = BackupService.fileName(for: date)
        #expect(name.hasPrefix("booklist-backup-") && name.hasSuffix(".json"))
        #expect(BackupService.date(fromFileName: name) == date)
        #expect(BackupService.date(fromFileName: "booklist-sync.json") == nil)
    }

    @Test("Sync never replaces a snapshot that has bookmarks with an empty library")
    func syncOverwriteGuard() {
        #expect(!SyncService.mayOverwrite(existingBookmarkCount: 120, newBookmarkCount: 0))
        #expect(SyncService.mayOverwrite(existingBookmarkCount: 120, newBookmarkCount: 3))
        #expect(SyncService.mayOverwrite(existingBookmarkCount: nil, newBookmarkCount: 0))
        #expect(SyncService.mayOverwrite(existingBookmarkCount: 0, newBookmarkCount: 0))
    }

    @Test("The backup-folder prompt shows once per version, and never once sync is set up")
    func promptRules() {
        #expect(BackupFolderPrompt.shouldAsk(syncEnabled: false, askedVersion: nil, currentVersion: "1.2 (5)"))
        #expect(!BackupFolderPrompt.shouldAsk(syncEnabled: false, askedVersion: "1.2 (5)", currentVersion: "1.2 (5)"))
        #expect(BackupFolderPrompt.shouldAsk(syncEnabled: false, askedVersion: "1.2 (4)", currentVersion: "1.2 (5)"))
        #expect(!BackupFolderPrompt.shouldAsk(syncEnabled: true, askedVersion: nil, currentVersion: "1.2 (5)"))
    }
}

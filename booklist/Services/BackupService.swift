import AppKit
import UniformTypeIdentifiers
import Foundation
import SwiftData

/// Automatic local backups of the whole library (the sync JSON format), so an update that opens
/// the wrong or an empty database never costs the user their data again (see beta 1.2 (3)).
///
/// - One backup when the app starts (at most every 20 h) and one on quit, the newest 7 kept,
///   in the app's own Application Support/Backups folder.
/// - Never writes a backup of an empty library — that would push the good ones out.
/// - File › Restore from Backup… replaces the library with a chosen backup, after backing up
///   the current library first.
///
/// These live inside the app's container, so they don't survive macOS replacing that container;
/// the sync folder (asked for by `BackupFolderPrompt`) covers that case.
enum BackupService {

    nonisolated static let keep = 7
    nonisolated static let minimumInterval: TimeInterval = 20 * 60 * 60
    nonisolated private static let prefix = "booklist-backup-"

    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Writing

    /// Writes a backup unless the library is empty or the newest backup is recent enough.
    @MainActor
    @discardableResult
    static func backupIfDue(context: ModelContext, now: Date = Date(), in directory: URL = directory) -> URL? {
        guard isDue(newest: backups(in: directory).first?.date, now: now) else { return nil }
        return backUp(context: context, now: now, in: directory)
    }

    /// Writes a backup now (unless the library is empty) and prunes old ones.
    @MainActor
    @discardableResult
    static func backUp(context: ModelContext, now: Date = Date(), in directory: URL = directory) -> URL? {
        guard let snapshot = try? SyncService.buildSnapshot(context: context), !snapshot.bookmarks.isEmpty,
              let data = try? encoder.encode(snapshot) else { return nil }
        let url = directory.appendingPathComponent(fileName(for: now))
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        for old in filesToDelete(backups(in: directory).map(\.url), keep: keep) {
            try? FileManager.default.removeItem(at: old)
        }
        return url
    }

    // MARK: - Restoring

    @MainActor
    static func runRestoreInteractively(into context: ModelContext) {
        let panel = NSOpenPanel()
        panel.title = "Restore from Backup"
        panel.message = "booklist makes a backup every day and when you quit. Pick the one to go back to."
        panel.prompt = "Restore"
        panel.allowedContentTypes = [.json]
        panel.directoryURL = directory
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let snapshot = try read(url)
            let confirm = NSAlert()
            confirm.messageText = "Replace your library with this backup?"
            confirm.informativeText = "The backup from \(snapshot.exportedAt.formatted(date: .abbreviated, time: .shortened)) has "
                + "\(snapshot.bookmarks.count) bookmarks. Your current library is backed up first, so you can go back."
            confirm.addButton(withTitle: "Restore")
            confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }

            backUp(context: context)
            try SyncService.restore(syncData: snapshot, context: context)
            context.undoManager?.removeAllActions()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't restore this backup"
            alert.runModal()
        }
    }

    // MARK: - Helpers (internal for tests)

    nonisolated static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    nonisolated static func read(_ url: URL) throws -> SyncData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SyncData.self, from: Data(contentsOf: url))
    }

    /// "booklist-backup-2026-10-22-1830.json" — sortable, and readable in the open panel.
    nonisolated static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return prefix + formatter.string(from: date) + ".json"
    }

    nonisolated static func date(fromFileName name: String) -> Date? {
        guard name.hasPrefix(prefix), name.hasSuffix(".json") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.date(from: String(name.dropFirst(prefix.count).dropLast(".json".count)))
    }

    /// Backups in `directory`, newest first.
    nonisolated static func backups(in directory: URL) -> [(url: URL, date: Date)] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .compactMap { url in date(fromFileName: url.lastPathComponent).map { (url, $0) } }
            .sorted { $0.date > $1.date }
    }

    nonisolated static func isDue(newest: Date?, now: Date) -> Bool {
        guard let newest else { return true }
        return now.timeIntervalSince(newest) >= minimumInterval
    }

    /// Everything but the `keep` newest (file names sort by date).
    nonisolated static func filesToDelete(_ files: [URL], keep: Int) -> [URL] {
        let sorted = files.sorted { $0.lastPathComponent > $1.lastPathComponent }
        return Array(sorted.dropFirst(keep))
    }
}

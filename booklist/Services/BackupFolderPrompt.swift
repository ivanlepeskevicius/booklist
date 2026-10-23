import AppKit
import Foundation
import SwiftData

/// Asks once per app version (until set up) for a folder *outside* the app — iCloud Drive,
/// Documents… — where the sync feature keeps a copy of the library. Local backups live in the
/// app's container and don't survive macOS replacing that container; this copy does. Because
/// the chosen folder is remembered inside the container too, a folder that already holds a
/// booklist backup is offered back to the user (merged, nothing current is lost).
enum BackupFolderPrompt {

    private static let askedVersionKey = "backupFolderPromptVersion"

    nonisolated static func shouldAsk(syncEnabled: Bool, askedVersion: String?, currentVersion: String) -> Bool {
        !syncEnabled && askedVersion != currentVersion
    }

    static var currentVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    @MainActor
    static func runIfNeeded(context: ModelContext) {
        guard !LaunchMode.isUITesting, !LaunchMode.isHostingTests,
              shouldAsk(syncEnabled: SyncService.isEnabled,
                        askedVersion: UserDefaults.standard.string(forKey: askedVersionKey),
                        currentVersion: currentVersion) else { return }
        UserDefaults.standard.set(currentVersion, forKey: askedVersionKey)

        let ask = NSAlert()
        ask.messageText = "Keep a backup of your library?"
        ask.informativeText = "Choose a folder outside booklist — for example in iCloud Drive or Documents. "
            + "booklist saves your bookmarks there every time you quit, so a new version (or a new Mac) "
            + "can always bring them back. You can change this later in Settings → Sync."
        ask.addButton(withTitle: "Choose Folder…")
        ask.addButton(withTitle: "Not Now")
        guard ask.runModal() == .alertFirstButtonReturn, let folder = SyncService.chooseSyncFolder() else { return }
        setUp(folder: folder, context: context)
    }

    /// Offers an existing backup in `folder`, then turns sync on and saves the library there.
    @MainActor
    private static func setUp(folder: URL, context: ModelContext) {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let file = folder.appendingPathComponent(SyncService.syncFileName)

        if let snapshot = try? BackupService.read(file), !snapshot.bookmarks.isEmpty {
            let offer = NSAlert()
            offer.messageText = "This folder already has a booklist backup"
            offer.informativeText = "It has \(snapshot.bookmarks.count) bookmarks, saved "
                + "\(snapshot.exportedAt.formatted(date: .abbreviated, time: .shortened)). "
                + "Add them to your library? Bookmarks you already have are kept and not duplicated."
            offer.addButton(withTitle: "Add Them")
            offer.addButton(withTitle: "Skip")
            if offer.runModal() == .alertFirstButtonReturn {
                _ = try? LibraryRecovery.merge(snapshot, into: context)
                try? context.save()
            } else {
                // Keep it as a separate file — the export below would otherwise replace it.
                let keptName = "booklist-sync-before-\(BackupService.fileName(for: Date()).dropFirst("booklist-backup-".count))"
                try? FileManager.default.copyItem(at: file, to: folder.appendingPathComponent(keptName))
            }
        }
        SyncService.isEnabled = true
        try? SyncService.export(context: context)
    }
}

import Foundation
import SwiftData
import AppKit

/// Manages export/import of all app data to a user-chosen sync folder.
///
/// The sync file (`booklist-sync.json`) can live in iCloud Drive, Dropbox,
/// or any synced folder. On quit the app saves a snapshot; on launch it
/// restores from the snapshot if it's newer than the local copy.
///
/// No iCloud or developer entitlements needed — the user picks the folder
/// once via an Open Panel, and the app stores a security-scoped bookmark
/// for persistent access between launches.
struct SyncService {

    // MARK: - Snapshot type aliases (preserve SyncService.XYZ namespace)
    typealias SyncData = booklist.SyncData
    typealias FolderSnap = booklist.FolderSnap
    typealias TagSnap = booklist.TagSnap
    typealias BookmarkSnap = booklist.BookmarkSnap

    // MARK: - Keys

    private static let bookmarkDataKey = "syncFolderBookmark"
    private static let lastSyncDateKey = "lastSyncDate"
    static let syncFileName = "booklist-sync.json"

    // MARK: - Public state

    /// Always false under UI tests (`-uiTesting`): their throwaway sample data must never be
    /// exported over the user's real sync file on quit, or imported from it on launch.
    static var isEnabled: Bool {
        get { !LaunchMode.isUITesting && UserDefaults.standard.bool(forKey: "syncEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "syncEnabled") }
    }

    static var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: lastSyncDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncDateKey) }
    }

    /// The resolved sync folder URL, or nil if not configured / stale.
    static var syncFolderURL: URL? { resolveBookmark() }

    /// A human-friendly path string for display in Settings.
    static var syncFolderDisplayName: String {
        guard let url = resolveBookmark() else { return "Not configured" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - Folder picker

    /// Shows an NSOpenPanel so the user can choose a sync folder.
    /// Stores a persistent security-scoped bookmark on success.
    /// Returns the chosen URL, or nil if the user cancelled.
    @discardableResult
    static func chooseSyncFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title                  = "Choose Sync Folder"
        panel.message                = "Pick a folder in your iCloud Drive, Dropbox, or any synced location. Your data will be saved as \"\(syncFileName)\" inside it."
        panel.canChooseDirectories   = true
        panel.canChooseFiles         = false
        panel.canCreateDirectories   = true
        panel.allowsMultipleSelection = false
        panel.prompt                 = "Select Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try? saveBookmark(for: url)
        return url
    }

    // MARK: - Export

    /// Writes a full JSON snapshot to the sync folder. Updates `lastSyncDate`.
    static func export(context: ModelContext) throws {
        guard let folderURL = resolveBookmark() else { throw SyncError.noSyncFolder }
        let secured = folderURL.startAccessingSecurityScopedResource()
        defer { if secured { folderURL.stopAccessingSecurityScopedResource() } }

        let syncData = try buildSnapshot(context: context)
        let encoder  = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting     = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(syncData)

        try data.write(to: folderURL.appendingPathComponent(syncFileName), options: .atomic)
        lastSyncDate = syncData.exportedAt
    }

    // MARK: - Import

    /// Reads the sync file and restores data if the file is newer than our last sync.
    /// Returns `true` if an import happened, `false` if skipped (already up to date).
    @discardableResult
    static func importIfNewer(context: ModelContext) throws -> Bool {
        guard let folderURL = resolveBookmark() else { return false }
        let secured = folderURL.startAccessingSecurityScopedResource()
        defer { if secured { folderURL.stopAccessingSecurityScopedResource() } }

        let fileURL = folderURL.appendingPathComponent(syncFileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let syncData = try decoder.decode(SyncData.self, from: Data(contentsOf: fileURL))

        // Skip if our local copy is already at or ahead of the file
        if let last = lastSyncDate, syncData.exportedAt <= last { return false }

        try restore(syncData: syncData, context: context)
        lastSyncDate = syncData.exportedAt
        return true
    }

    // MARK: - Snapshot builder

    static func buildSnapshot(context: ModelContext) throws -> SyncData {
        let folders   = try context.fetch(FetchDescriptor<Folder>())
        let tags      = try context.fetch(FetchDescriptor<Tag>())
        let bookmarks = try context.fetch(FetchDescriptor<Bookmark>())

        return SyncData(
            version:    SyncData.currentVersion,
            exportedAt: Date(),
            folders: folders.map {
                FolderSnap(id: $0.id, name: $0.name, icon: $0.icon,
                           color: $0.color, sortOrder: $0.sortOrder,
                           parentID: $0.parent?.id)
            },
            tags: tags.map {
                TagSnap(id: $0.id, name: $0.name, color: $0.color)
            },
            bookmarks: bookmarks.map { bm in
                BookmarkSnap(
                    id:               bm.id,
                    title:            bm.title,
                    url:              bm.url,
                    pageDescription:  bm.pageDescription,
                    note:             bm.note,
                    faviconURL:       bm.faviconURL,
                    imageURLs:        bm.imageURLs,
                    selectedImageURL: bm.selectedImageURL,
                    itemType:         bm.itemType.rawValue,
                    price:            bm.price,
                    dateAdded:        bm.dateAdded,
                    lastOpenedDate:   bm.lastOpenedDate,
                    isPinned:         bm.isPinned,
                    isRead:           bm.isRead,
                    collectionID:     bm.collection?.id,
                    tagIDs:           bm.tags.map(\.id)
                )
            }
        )
    }

    // MARK: - Restore

    static func restore(syncData: SyncData, context: ModelContext) throws {
        // Delete existing records (bookmarks first to cleanly nullify relationships)
        try context.fetch(FetchDescriptor<Bookmark>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<Tag>()).forEach      { context.delete($0) }
        try context.fetch(FetchDescriptor<Folder>()).forEach   { context.delete($0) }

        // Folders — first pass: create without parent links
        var folderMap: [UUID: Folder] = [:]
        for snap in syncData.folders {
            let f = Folder(name: snap.name, icon: snap.icon,
                           color: snap.color, sortOrder: snap.sortOrder)
            f.id = snap.id
            context.insert(f)
            folderMap[snap.id] = f
        }
        // Second pass: wire parent links
        for snap in syncData.folders {
            if let parentID = snap.parentID {
                folderMap[snap.id]?.parent = folderMap[parentID]
            }
        }

        // Tags
        var tagMap: [UUID: Tag] = [:]
        for snap in syncData.tags {
            let t = Tag(name: snap.name, color: snap.color)
            t.id = snap.id
            context.insert(t)
            tagMap[snap.id] = t
        }

        // Bookmarks
        for snap in syncData.bookmarks {
            let bm = Bookmark(
                title:            snap.title,
                url:              snap.url,
                pageDescription:  snap.pageDescription,
                note:             snap.note,
                faviconURL:       snap.faviconURL,
                imageURLs:        snap.imageURLs,
                selectedImageURL: snap.selectedImageURL,
                itemType:         ItemType(rawValue: snap.itemType) ?? .bookmark,
                price:            snap.price,
                collection:       snap.collectionID.flatMap { folderMap[$0] },
                tags:             snap.tagIDs.compactMap { tagMap[$0] }
            )
            bm.id             = snap.id
            bm.dateAdded      = snap.dateAdded
            bm.lastOpenedDate = snap.lastOpenedDate
            bm.isPinned       = snap.isPinned
            bm.isRead         = snap.isRead
            context.insert(bm)
        }

        try context.save()
    }

    // MARK: - Security-scoped bookmark helpers

    private static func saveBookmark(for url: URL) throws {
        // Prefer security-scoped bookmark (sandboxed); fall back to basic (non-sandboxed).
        let data: Data
        if let secureData = try? url.bookmarkData(options: .withSecurityScope,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) {
            data = secureData
        } else {
            data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        UserDefaults.standard.set(data, forKey: bookmarkDataKey)
    }

    private static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkDataKey) else { return nil }
        var isStale = false
        // Try security-scoped first (sandboxed builds), then plain bookmark (non-sandboxed).
        let url = (try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                            relativeTo: nil, bookmarkDataIsStale: &isStale))
               ?? (try? URL(resolvingBookmarkData: data, options: [],
                            relativeTo: nil, bookmarkDataIsStale: &isStale))
        if let url, isStale { try? saveBookmark(for: url) }
        return url
    }

    // MARK: - Errors

    enum SyncError: LocalizedError {
        case noSyncFolder

        var errorDescription: String? {
            switch self {
            case .noSyncFolder:
                return "No sync folder configured. Choose one in Settings → Sync."
            }
        }
    }
}

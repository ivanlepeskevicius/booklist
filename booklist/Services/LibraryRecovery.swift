import AppKit
import Foundation
import SwiftData

/// Brings back the library from betas up to 1.2 (2).
///
/// Those builds had an App Group entitlement, and SwiftData puts its default store in the app
/// group's container when one exists (`~/Library/Group Containers/group.lepi.booklist/…`).
/// Removing the entitlement (it broke launching on testers' Macs) made the app open a fresh
/// store in its own container, so the library looked empty. The sandbox only lets the app read
/// the old folder once the user picks it in an open panel.
///
/// The old store is copied first and read from the copy — the original is never modified, so it
/// stays as a backup. Items are *merged* (anything already in the library is kept and skipped).
enum LibraryRecovery {

    struct Result {
        var bookmarks = 0, folders = 0, tags = 0, imagesRelinked = 0
    }

    enum RecoveryError: LocalizedError {
        case noStore
        var errorDescription: String? {
            "That folder doesn't contain a booklist library (default.store)."
        }
    }

    /// Where betas ≤ 1.2 (2) kept the library. The real home folder, not the sandbox's.
    static var oldLibraryFolder: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Group Containers/group.lepi.booklist/Library/Application Support", isDirectory: true)
    }

    /// Asks the user for the old library folder, then merges it into `context`.
    @MainActor
    static func runInteractively(into context: ModelContext) {
        let panel = NSOpenPanel()
        panel.title = "Recover Library from Earlier Beta"
        panel.message = "Your earlier library is in this folder — click Open to bring it back. Nothing in it is changed."
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = oldLibraryFolder
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let alert = NSAlert()
        do {
            let result = try recover(from: folder, into: context)
            alert.messageText = result.bookmarks == 0 && result.folders == 0
                ? "Nothing new to recover"
                : "Recovered \(result.bookmarks) bookmark\(result.bookmarks == 1 ? "" : "s")"
            alert.informativeText = "\(result.folders) folders and \(result.tags) tags were added. Items already in your library were kept as they are."
                + (result.imagesRelinked > 0 ? " \(result.imagesRelinked) card images will be loaded again from the web." : "")
        } catch {
            alert.alertStyle = .warning
            alert.messageText = "Couldn't recover the library"
            alert.informativeText = error.localizedDescription
        }
        alert.runModal()
    }

    /// Copies the store out of `folder`, reads the copy and merges it into `context`.
    @MainActor
    static func recover(from folder: URL, into context: ModelContext) throws -> Result {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.appendingPathComponent("default.store").path) else { throw RecoveryError.noStore }
        let copyFolder = fm.temporaryDirectory.appendingPathComponent("library-recovery-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: copyFolder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: copyFolder) }
        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            let source = folder.appendingPathComponent(name)
            if fm.fileExists(atPath: source.path) {
                try fm.copyItem(at: source, to: copyFolder.appendingPathComponent(name))
            }
        }

        let oldContainer = try ModelContainer(
            for: Bookmark.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(url: copyFolder.appendingPathComponent("default.store"))
        )
        let snapshot = try SyncService.buildSnapshot(context: ModelContext(oldContainer))
        let result = try merge(snapshot, into: context)
        try context.save()
        return result
    }

    /// Adds the snapshot's folders, tags and bookmarks that `context` doesn't have yet (by ID; tags
    /// also by name, so there are no duplicate tags). Existing items are left untouched.
    @MainActor
    static func merge(_ data: SyncData, into context: ModelContext,
                      imageExists: (String) -> Bool = defaultImageExists) throws -> Result {
        var result = Result()

        var folders = Dictionary(try context.fetch(FetchDescriptor<Folder>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var newFolders: [UUID: Folder] = [:]
        for snap in data.folders where folders[snap.id] == nil {
            let folder = Folder(name: snap.name, icon: snap.icon, color: snap.color, sortOrder: snap.sortOrder)
            folder.id = snap.id
            context.insert(folder)
            folders[snap.id] = folder
            newFolders[snap.id] = folder
            result.folders += 1
        }
        for snap in data.folders {
            if let folder = newFolders[snap.id], let parentID = snap.parentID {
                folder.parent = folders[parentID]
            }
        }

        let existingTags = try context.fetch(FetchDescriptor<Tag>())
        var tags = Dictionary(existingTags.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var tagsByName = Dictionary(existingTags.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        for snap in data.tags where tags[snap.id] == nil {
            if let sameName = tagsByName[snap.name.lowercased()] {
                tags[snap.id] = sameName
                continue
            }
            let tag = Tag(name: snap.name, color: snap.color)
            tag.id = snap.id
            context.insert(tag)
            tags[snap.id] = tag
            tagsByName[snap.name.lowercased()] = tag
            result.tags += 1
        }

        let existingBookmarkIDs = Set(try context.fetch(FetchDescriptor<Bookmark>()).map(\.id))
        for snap in data.bookmarks where !existingBookmarkIDs.contains(snap.id) {
            let (image, relinked) = recoveredImage(selected: snap.selectedImageURL, candidates: snap.imageURLs, imageExists: imageExists)
            let bookmark = Bookmark(
                title: snap.title, url: snap.url, pageDescription: snap.pageDescription, note: snap.note,
                faviconURL: snap.faviconURL, imageURLs: snap.imageURLs, selectedImageURL: image,
                itemType: ItemType(rawValue: snap.itemType) ?? .bookmark, price: snap.price,
                collection: snap.collectionID.flatMap { folders[$0] },
                tags: snap.tagIDs.compactMap { tags[$0] }
            )
            bookmark.id = snap.id
            bookmark.dateAdded = snap.dateAdded
            bookmark.lastOpenedDate = snap.lastOpenedDate
            bookmark.isPinned = snap.isPinned
            bookmark.isRead = snap.isRead
            context.insert(bookmark)
            result.bookmarks += 1
            if relinked { result.imagesRelinked += 1 }
        }
        return result
    }

    /// A saved (local) card image that no longer exists falls back to the page's image on the
    /// web, so the card isn't left blank. Remote and still-present images are kept as they are.
    nonisolated static func recoveredImage(selected: String?, candidates: [String],
                                           imageExists: (String) -> Bool) -> (url: String?, relinked: Bool) {
        guard let selected, let url = URL(string: selected), url.isFileURL else { return (selected, false) }
        if imageExists(url.lastPathComponent) {
            // Same file name in this app's image folder (its path may differ from the old one).
            return (ImageStore.directory.appendingPathComponent(url.lastPathComponent).absoluteString, false)
        }
        let remote = candidates.first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
        return (remote, remote != nil)
    }

    nonisolated static func defaultImageExists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: ImageStore.directory.appendingPathComponent(fileName).path)
    }
}

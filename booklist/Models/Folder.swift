import Foundation
import SwiftData

/// A user-created container for bookmarks. Folders can be nested infinitely.
/// Note: named Folder (not Collection) to avoid conflict with Swift's Collection protocol.
@Model
final class Folder {
    var id: UUID
    var name: String
    var icon: String    // emoji (e.g. "🎵") or SF Symbol name (e.g. "music.note")
    var color: String   // hex string, e.g. "#FF6B6B"
    var sortOrder: Int

    /// nil = this is a top-level folder.
    var parent: Folder?

    /// Nullify so children's parent becomes nil on deletion.
    /// FolderRowView handles recursive deletion manually to avoid cascade-while-observed crashes.
    @Relationship(deleteRule: .nullify, inverse: \Folder.parent)
    var children: [Folder]

    /// When this folder is deleted, bookmarks move to Inbox (collection becomes nil).
    @Relationship(deleteRule: .nullify, inverse: \Bookmark.collection)
    var bookmarks: [Bookmark]

    /// Returns children sorted by sortOrder, or nil if this folder has no children.
    /// Used by OutlineGroup / recursive FolderRowView to determine leaf vs. parent nodes.
    var childrenIfAny: [Folder]? {
        let sorted = children.sorted { $0.sortOrder < $1.sortOrder }
        return sorted.isEmpty ? nil : sorted
    }

    init(
        name: String,
        icon: String = "folder",
        color: String = "#8B8B8B",
        sortOrder: Int = 0,
        parent: Folder? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.color = color
        self.sortOrder = sortOrder
        self.parent = parent
        self.children = []
        self.bookmarks = []
    }
}

// MARK: - Cycle-safe folder tree traversal

/// Module-internal helpers for traversing the folder hierarchy.
/// All methods carry a `seen` set so corrupt data with circular parent
/// references terminates safely instead of stack-overflowing.
enum FolderTree {

    /// Returns the set of IDs for `rootID` and all its descendants.
    static func subtreeIDs(
        rootID: UUID,
        in folders: [Folder],
        seen: Set<UUID> = []
    ) -> Set<UUID> {
        guard !seen.contains(rootID) else { return [] }
        var result: Set<UUID> = [rootID]
        let nextSeen = seen.union([rootID])
        for folder in folders where folder.parent?.id == rootID {
            result.formUnion(subtreeIDs(rootID: folder.id, in: folders, seen: nextSeen))
        }
        return result
    }

    /// Returns true when `targetID` equals `ancestorID` or is a descendant of it.
    static func contains(
        targetID: UUID,
        in ancestorID: UUID,
        folders: [Folder],
        seen: Set<UUID> = []
    ) -> Bool {
        guard !seen.contains(ancestorID) else { return false }
        if ancestorID == targetID { return true }
        let nextSeen = seen.union([ancestorID])
        return folders
            .filter { $0.parent?.id == ancestorID }
            .contains { contains(targetID: targetID, in: $0.id, folders: folders, seen: nextSeen) }
    }

    /// All folders in depth-first tree order (siblings by sortOrder), each with a
    /// "Parent › Child" path label — for folder picker menus.
    static func flattened(_ folders: [Folder]) -> [(folder: Folder, path: String)] {
        var result: [(folder: Folder, path: String)] = []
        func walk(parentID: UUID?, prefix: String, seen: Set<UUID>) {
            let siblings = folders
                .filter { $0.parent?.id == parentID && !seen.contains($0.id) }
                .sorted { $0.sortOrder < $1.sortOrder }
            for folder in siblings {
                let path = prefix.isEmpty ? folder.name : "\(prefix) › \(folder.name)"
                result.append((folder, path))
                walk(parentID: folder.id, prefix: path, seen: seen.union([folder.id]))
            }
        }
        walk(parentID: nil, prefix: "", seen: [])
        return result
    }
}

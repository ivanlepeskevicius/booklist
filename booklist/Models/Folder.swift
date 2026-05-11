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

    @Relationship(deleteRule: .nullify, inverse: \Folder.parent)
    var children: [Folder]

    /// When this folder is deleted, bookmarks move to Inbox (collection becomes nil).
    @Relationship(deleteRule: .nullify, inverse: \Bookmark.collection)
    var bookmarks: [Bookmark]

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

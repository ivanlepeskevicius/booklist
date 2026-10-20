import SwiftUI
import SwiftData

/// "Move to Folder" and "Tags" submenus for one or more bookmarks.
/// Shared by the card and list context menus so both view modes offer the same bulk actions.
struct BookmarkOrganizeMenu: View {
    let targets: [Bookmark]
    let folders: [Folder]
    let tags: [Tag]
    /// Short "Move to" / "Tags" labels with icons, for the selection bar (the count is shown next to it).
    var compact = false

    var body: some View {
        Menu {
            folderButton("Inbox (no folder)", folder: nil)
            if !folders.isEmpty { Divider() }
            ForEach(FolderTree.flattened(folders), id: \.folder.id) { entry in
                folderButton(entry.path, folder: entry.folder)
            }
        } label: {
            if compact {
                Label("Move to", systemImage: "folder")
            } else {
                Text(targets.count == 1 ? "Move to Folder" : "Move \(targets.count) Items to Folder")
            }
        }

        if !tags.isEmpty {
            Menu {
                // Checked = every target has the tag. Choosing an unchecked tag adds it to all
                // targets; choosing a checked one removes it from all.
                ForEach(tags) { tag in
                    Toggle("#\(tag.name)", isOn: Binding(
                        get: { BookmarkBulkActions.allHave(tag, targets) },
                        set: { BookmarkBulkActions.setTag(tag, on: targets, to: $0) }
                    ))
                }
            } label: {
                if compact {
                    Label("Tags", systemImage: "tag")
                } else {
                    Text("Tags")
                }
            }
        }
    }

    private func folderButton(_ title: String, folder: Folder?) -> some View {
        let isCurrent = targets.allSatisfy { $0.collection?.id == folder?.id }
        return Button {
            BookmarkBulkActions.move(targets, to: folder)
        } label: {
            if isCurrent {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

/// Actions on one or more bookmarks, shared by menus and keyboard shortcuts.
enum BookmarkBulkActions {
    /// Saves immediately so SwiftData registers the change with the undo manager — ⌘Z restores the items.
    static func delete(_ bookmarks: [Bookmark], from context: ModelContext) {
        bookmarks.forEach { context.delete($0) }
        try? context.save()
    }

    static func open(_ bookmarks: [Bookmark]) {
        for bookmark in bookmarks {
            guard let url = URL(string: bookmark.url) else { continue }
            bookmark.lastOpenedDate = Date()
            NSWorkspace.shared.open(url)
        }
    }

    /// Relationships are changed from the folder side in one batch per folder. Setting
    /// `collection` on each bookmark updates the folder's inverse array every time — quadratic:
    /// moving 5,000 items took ~9 s that way, ~0.4 s like this.
    static func move(_ bookmarks: [Bookmark], to folder: Folder?) {
        let moving = bookmarks.filter { $0.collection?.id != folder?.id }
        guard !moving.isEmpty else { return }
        let ids = Set(moving.map(\.id))
        var sources: [UUID: Folder] = [:]
        for case let source? in moving.map(\.collection) { sources[source.id] = source }
        for source in sources.values {
            source.bookmarks.removeAll { ids.contains($0.id) }
        }
        folder?.bookmarks.append(contentsOf: moving)
    }

    static func allHave(_ tag: Tag, _ bookmarks: [Bookmark]) -> Bool {
        !bookmarks.isEmpty && bookmarks.allSatisfy { bm in bm.tags.contains { $0.id == tag.id } }
    }

    /// Batched from the tag side for the same reason as `move` (~9 s → ~0.05 s for 5,000 items).
    static func setTag(_ tag: Tag, on bookmarks: [Bookmark], to enabled: Bool) {
        if enabled {
            let tagged = Set(tag.bookmarks.map(\.id))
            let missing = bookmarks.filter { !tagged.contains($0.id) }
            if !missing.isEmpty { tag.bookmarks.append(contentsOf: missing) }
        } else {
            let ids = Set(bookmarks.map(\.id))
            tag.bookmarks.removeAll { ids.contains($0.id) }
        }
    }
}

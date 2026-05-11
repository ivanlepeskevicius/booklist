import SwiftUI
import SwiftData

/// A recursive sidebar row for a Folder.
/// Context menu actions are handled by SidebarView via contextMenu(forSelectionType:).
/// Drop assignment is handled inline here to avoid environment-propagation issues in macOS List.
struct FolderRowView: View {
    let folder: Folder
    let allFolders: [Folder]
    @Binding var selection: SidebarSelection?

    @Environment(\.modelContext) private var modelContext
    @Query private var allBookmarks: [Bookmark]
    @State private var isDropTargeted = false

    private var children: [Folder] {
        allFolders
            .filter { $0.parent?.id == folder.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        rowContent
            // contentShape ensures the full row width is a drop target, not just the label text.
            .contentShape(Rectangle())
            .dropDestination(for: BookmarkTransfer.self) { items, _ in
                let ids = items.flatMap { $0.ids }
                for id in ids {
                    if let bookmark = allBookmarks.first(where: { $0.id == id }) {
                        bookmark.collection = folder
                    }
                }
                return true
            } isTargeted: { isDropTargeted = $0 }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    private var rowContent: some View {
        if children.isEmpty {
            folderLabel
                .tag(SidebarSelection.folder(folder.id))
        } else {
            DisclosureGroup {
                ForEach(children) { child in
                    FolderRowView(folder: child, allFolders: allFolders, selection: $selection)
                }
            } label: {
                folderLabel
            }
            .tag(SidebarSelection.folder(folder.id))
        }
    }

    private var folderLabel: some View {
        Label {
            Text(folder.name)
        } icon: {
            Image(systemName: folder.icon)
                .foregroundStyle(Color(hex: folder.color))
        }
    }
}

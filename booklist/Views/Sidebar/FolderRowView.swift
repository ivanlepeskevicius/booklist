import SwiftUI
import SwiftData

/// A recursive sidebar row for a Folder.
/// Context menu actions are handled by SidebarView via contextMenu(forSelectionType:).
/// Drop assignment is handled inline here to avoid environment-propagation issues in macOS List.
struct FolderRowView: View {
    let folder: Folder
    let allFolders: [Folder]
    @Binding var selection: SidebarSelection?
    /// IDs already rendered by ancestor rows — stops infinite recursion if data is circular.
    private let seenIDs: Set<UUID>

    init(folder: Folder, allFolders: [Folder], selection: Binding<SidebarSelection?>, seenIDs: Set<UUID> = []) {
        self.folder = folder
        self.allFolders = allFolders
        self._selection = selection
        self.seenIDs = seenIDs.union([folder.id])
    }

    @Environment(\.modelContext) private var modelContext
    @State private var isBookmarkDropTargeted = false
    @State private var folderDropZone: FolderDropZone?
    @State private var rowHeight: CGFloat = 0

    private var children: [Folder] {
        allFolders
            .filter { $0.parent?.id == folder.id && !seenIDs.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        rowContent
            // contentShape ensures the full row width is a drop target, not just the label text.
            .contentShape(Rectangle())
            // Bookmark drops → assign bookmarks to this folder
            .dropDestination(for: BookmarkTransfer.self) { items, _ in
                let idSet = Set(items.flatMap { $0.ids })
                guard !idSet.isEmpty else { return false }
                if let bookmarks = try? modelContext.fetch(FetchDescriptor<Bookmark>()) {
                    bookmarks
                        .filter { idSet.contains($0.id) }
                        .forEach { $0.collection = folder }
                }
                return true
            } isTargeted: { isBookmarkDropTargeted = $0 }
            .overlay {
                if isBookmarkDropTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isBookmarkDropTargeted)
    }

    @ViewBuilder
    private var rowContent: some View {
        if children.isEmpty {
            folderLabel
                .tag(SidebarSelection.folder(folder.id))
        } else {
            DisclosureGroup {
                ForEach(children) { child in
                    FolderRowView(folder: child, allFolders: allFolders, selection: $selection, seenIDs: seenIDs)
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
            if isSFSymbolName(folder.icon) {
                Image(systemName: folder.icon)
                    .foregroundStyle(Color(hex: folder.color))
            } else {
                Text(folder.icon)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
        // One drag does both reorder and nest (replaces List's onMove, which stops receiving
        // drags once rows are draggable): top quarter = above, middle = inside, bottom = below.
        .onDrag { FolderDrag.itemProvider(for: folder) }
        .onDrop(of: [.folderTransfer], delegate: FolderDropDelegate(
            target: folder, allFolders: allFolders, rowHeight: rowHeight, zone: $folderDropZone
        ))
        .folderDropIndicator(folderDropZone)
    }
}

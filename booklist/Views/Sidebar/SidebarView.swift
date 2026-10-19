import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarSelection?

    @Query private var allBookmarks: [Bookmark]
    @Query(sort: \Folder.sortOrder) private var allFolders: [Folder]

    @Environment(\.modelContext) private var modelContext

    // Toolbar / new root folder
    @State private var showingAddFolder = false

    // Context menu — Add Subfolder
    @State private var isAddingSubfolder    = false
    @State private var addSubfolderParentID: UUID? = nil

    // Context menu — Rename
    @State private var folderToEdit: Folder? = nil

    // Context menu — Delete
    @State private var folderToDelete: Folder? = nil
    @State private var showingDeleteConfirm = false

    // Drop target state for the Inbox row
    @State private var isInboxDropTargeted = false
    @State private var isLibraryDropTargeted = false

    private var inboxCount: Int {
        allBookmarks.filter { $0.collection == nil && $0.itemType == .bookmark }.count
    }

    private var wishlistCount: Int {
        allBookmarks.filter { $0.collection == nil && $0.itemType == .wishlistItem }.count
    }

    private var rootFolders: [Folder] {
        allFolders.filter { $0.parent == nil }
    }

    var body: some View {
        List(selection: $selection) {
            Label("Inbox", systemImage: "tray")
                .badge(inboxCount)
                .tag(SidebarSelection.inbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .dropDestination(for: BookmarkTransfer.self) { items, _ in
                    assignBookmarks(ids: items.flatMap { $0.ids }, to: nil)
                    return true
                } isTargeted: { isInboxDropTargeted = $0 }
                .overlay {
                    if isInboxDropTargeted {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }

            Label("Wishlist", systemImage: "cart")
                .badge(wishlistCount)
                .tag(SidebarSelection.wishlist)

            Label("All", systemImage: "square.stack")
                .tag(SidebarSelection.all)

            Section {
                Button {
                    showingAddFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .selectionDisabled()

                ForEach(rootFolders) { folder in
                    FolderRowView(folder: folder, allFolders: allFolders, selection: $selection)
                }
                .onMove { indices, destination in
                    reorderFolders(indices: indices, destination: destination, among: rootFolders)
                }
            } header: {
                // Dropping a folder on the "Library" header makes it top-level.
                Text("Library")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .dropDestination(for: FolderTransfer.self) { items, _ in
                        guard let id = items.first?.id,
                              let dragged = allFolders.first(where: { $0.id == id }) else { return false }
                        return FolderTree.move(dragged, into: nil, folders: allFolders)
                    } isTargeted: { isLibraryDropTargeted = $0 }
                    .overlay {
                        if isLibraryDropTargeted {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        // Context menus identified by row tag — correctly distinguishes nested folders.
        .contextMenu(forSelectionType: SidebarSelection.self) { selections in
            if selections.count == 1,
               case .folder(let id) = selections.first,
               let folder = allFolders.first(where: { $0.id == id }) {

                Button {
                    addSubfolderParentID = folder.id
                    isAddingSubfolder = true
                } label: {
                    Label("Add Subfolder", systemImage: "folder.badge.plus")
                }

                if folder.parent != nil {
                    Button {
                        FolderTree.move(folder, into: nil, folders: allFolders)
                    } label: {
                        Label("Promote to Library", systemImage: "arrow.up.to.line")
                    }
                }

                // Full paths in sidebar order, so same-named subfolders are distinguishable.
                let moveTargets = FolderTree.flattened(allFolders)
                    .filter { FolderTree.canMove(folder, into: $0.folder, folders: allFolders) }
                if !moveTargets.isEmpty {
                    Menu {
                        ForEach(moveTargets, id: \.folder.id) { target in
                            Button(target.path) {
                                FolderTree.move(folder, into: target.folder, folders: allFolders)
                            }
                        }
                    } label: {
                        Label("Move into…", systemImage: "folder")
                    }
                }

                Divider()

                let folderBookmarks = allBookmarks.filter { $0.collection?.id == folder.id }
                if !folderBookmarks.isEmpty {
                    ShareLink(
                        item: BookmarksExport(bookmarks: folderBookmarks, title: folder.name),
                        preview: SharePreview(folder.name)
                    ) {
                        Label("Share Folder", systemImage: "square.and.arrow.up")
                    }
                }

                Divider()

                Button {
                    folderToEdit = folder
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    folderToDelete = folder
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Folder", systemImage: "trash")
                }
            }
        } primaryAction: { _ in }
        .sheet(isPresented: $showingAddFolder) {
            FolderFormView(mode: .add(parentID: nil))
        }
        .sheet(isPresented: $isAddingSubfolder) {
            FolderFormView(mode: .add(parentID: addSubfolderParentID))
        }
        .sheet(item: $folderToEdit) { folder in
            FolderFormView(mode: .edit(folder))
        }
        .confirmationDialog(
            "Delete \"\(folderToDelete?.name ?? "")\"?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let folder = folderToDelete { deleteFolder(folder) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This folder and all its subfolders will be removed. Bookmarks will move to Inbox.")
        }
    }

    // MARK: - Folder reordering

    private func reorderFolders(indices: IndexSet, destination: Int, among sorted: [Folder]) {
        var mutable = sorted
        mutable.move(fromOffsets: indices, toOffset: destination)
        for (i, f) in mutable.enumerated() {
            f.sortOrder = i
        }
    }

    // MARK: - Bookmark assignment

    private func assignBookmarks(ids: [UUID], to folderID: UUID?) {
        let targetFolder = folderID.flatMap { id in allFolders.first { $0.id == id } }
        for id in ids {
            if let bookmark = allBookmarks.first(where: { $0.id == id }) {
                bookmark.collection = targetFolder
            }
        }
    }

    // MARK: - Folder deletion

    private func deleteFolder(_ folder: Folder) {
        if case .folder(let id) = selection, subtreeContains(id: id, parentID: folder.id) {
            selection = .inbox
        }
        deleteSubtree(folderID: folder.id)
    }

    private func deleteSubtree(folderID: UUID, seen: Set<UUID> = []) {
        guard !seen.contains(folderID) else { return }
        let nextSeen = seen.union([folderID])
        let directChildren = allFolders.filter { $0.parent?.id == folderID }
        for child in directChildren { deleteSubtree(folderID: child.id, seen: nextSeen) }
        if let target = allFolders.first(where: { $0.id == folderID }) {
            modelContext.delete(target)
        }
    }

    private func subtreeContains(id: UUID, parentID: UUID) -> Bool {
        FolderTree.contains(targetID: id, in: parentID, folders: allFolders)
    }
}

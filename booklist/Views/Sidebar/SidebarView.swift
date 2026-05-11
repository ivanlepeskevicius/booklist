import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarSelection?

    @Query private var allBookmarks: [Bookmark]
    @Query(sort: \Folder.sortOrder) private var allFolders: [Folder]

    @Environment(\.modelContext) private var modelContext

    // Toolbar / new root folder
    @State private var showingCapture   = false
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

    private var inboxCount: Int {
        allBookmarks.filter { $0.collection == nil }.count
    }

    private var rootFolders: [Folder] {
        allFolders.filter { $0.parent == nil }
    }

    var body: some View {
        List(selection: $selection) {
            Label("Inbox", systemImage: "tray")
                .badge(inboxCount)
                .tag(SidebarSelection.inbox)
                .dropDestination(for: BookmarkTransfer.self) { items, _ in
                    assignBookmarks(ids: items.flatMap { $0.ids }, to: nil)
                    return true
                } isTargeted: { isInboxDropTargeted = $0 }
                .overlay {
                    if isInboxDropTargeted {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.accentColor, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }

            Label("All", systemImage: "square.stack")
                .tag(SidebarSelection.all)

            Section {
                ForEach(rootFolders) { folder in
                    FolderRowView(folder: folder, allFolders: allFolders, selection: $selection)
                }

                Button {
                    showingAddFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .selectionDisabled()
            } header: {
                Text("Library")
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        // Provide the drop handler to all FolderRowView descendants via the environment.
        .environment(\.assignBookmarksToFolder) { ids, folderID in
            assignBookmarks(ids: ids, to: folderID)
        }
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCapture = true
                } label: {
                    Label("New Capture", systemImage: "plus")
                }
                .help("Save a new link (⌘N)")
            }
        }
        .sheet(isPresented: $showingCapture) {
            CaptureView()
        }
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

    private func deleteSubtree(folderID: UUID) {
        let directChildren = allFolders.filter { $0.parent?.id == folderID }
        for child in directChildren { deleteSubtree(folderID: child.id) }
        if let target = allFolders.first(where: { $0.id == folderID }) {
            modelContext.delete(target)
        }
    }

    private func subtreeContains(id: UUID, parentID: UUID) -> Bool {
        if parentID == id { return true }
        let directChildren = allFolders.filter { $0.parent?.id == parentID }
        return directChildren.contains { subtreeContains(id: id, parentID: $0.id) }
    }
}

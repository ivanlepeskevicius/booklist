import SwiftUI
import SwiftData

/// List layout — sortable table with favicon, title+note, domain, date, and icon actions.
struct BookmarkListView: View {
    let bookmarks: [Bookmark]
    let onManage: (Bookmark) -> Void
    @Binding var selectedIDs: Set<UUID>

    @Environment(\.modelContext) private var modelContext
    @State private var sortOrder = [KeyPathComparator<Bookmark>(\Bookmark.dateAdded, order: .reverse)]
    @State private var showDeleteConfirmFor: Bookmark?

    private var sortedBookmarks: [Bookmark] {
        bookmarks.sorted(using: sortOrder)
    }

    var body: some View {
        Table(sortedBookmarks, selection: $selectedIDs, sortOrder: $sortOrder) {
            // Title + note column — also the drag handle for the row.
            TableColumn("Title", value: \Bookmark.title) { bookmark in
                HStack(spacing: 8) {
                    faviconView(bookmark)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bookmark.title)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if let note = bookmark.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                // Dragging the title cell drags all selected rows, or just this one if unselected.
                .draggable(
                    selectedIDs.contains(bookmark.id)
                        ? BookmarkTransfer(ids: Array(selectedIDs))
                        : BookmarkTransfer(ids: [bookmark.id])
                )
            }

            // Domain column (sortable by url)
            TableColumn("Source", value: \Bookmark.url) { bookmark in
                Text(URL(string: bookmark.url)?.host ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 140, max: 180)

            // Date column (sortable by dateAdded)
            TableColumn("Saved", value: \Bookmark.dateAdded) { bookmark in
                Text(bookmark.dateAdded.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
            }
            .width(90)

            // Actions column (not sortable)
            TableColumn("") { bookmark in
                HStack(spacing: 2) {
                    Button {
                        guard let url = URL(string: bookmark.url) else { return }
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Open in browser")

                    Button { onManage(bookmark) } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderless)
                    .help("Edit")

                    Button(role: .destructive) {
                        showDeleteConfirmFor = bookmark
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("Delete")
                }
            }
            .width(76)
        }
        .confirmationDialog(
            "Delete \"\(showDeleteConfirmFor?.title ?? "")\"?",
            isPresented: Binding(
                get: { showDeleteConfirmFor != nil },
                set: { if !$0 { showDeleteConfirmFor = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let b = showDeleteConfirmFor { modelContext.delete(b) }
                showDeleteConfirmFor = nil
            }
            Button("Cancel", role: .cancel) { showDeleteConfirmFor = nil }
        } message: {
            Text("This cannot be undone.")
        }
    }

    @ViewBuilder
    private func faviconView(_ bookmark: Bookmark) -> some View {
        if let urlStr = bookmark.faviconURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "globe").foregroundStyle(.secondary)
            }
            .frame(width: 16, height: 16)
        } else {
            Image(systemName: "link")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16, height: 16)
        }
    }
}

import SwiftUI
import SwiftData

/// List layout — sortable table with favicon, title+note, domain, date, and icon actions.
struct BookmarkListView: View {
    let bookmarks: [Bookmark]
    let onManage: (Bookmark) -> Void
    let onRead: (Bookmark) -> Void
    @Binding var selectedIDs: Set<UUID>
    var onTagTap: ((Tag) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query private var allFolders: [Folder]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var sortOrder = [KeyPathComparator<BookmarkRow>(\BookmarkRow.dateAdded, order: .reverse)]

    @AppStorage("listShowSource")     private var listShowSource     = true
    @AppStorage("listShowSaved")      private var listShowSaved      = true
    @AppStorage("listShowLastOpened") private var listShowLastOpened = true
    @AppStorage("listShowPrice")      private var listShowPrice      = true
    @AppStorage("listShowTags")       private var listShowTags       = true

    /// What one row shows, copied out of the bookmark when the list is built. Cells read only these
    /// values: every SwiftData property a cell reads is change-tracked, and the table re-registers the
    /// tracking of all its rows each time a row scrolls into view — measured 220 ms per scroll step at
    /// 1,000 bookmarks and 415 ms at 3,000. Rows are rebuilt whenever the library changes; being
    /// Equatable lets the table redraw just the rows whose values changed.
    struct BookmarkRow: Identifiable, Equatable {
        let id: UUID
        let bookmark: Bookmark
        let title: String
        let note: String?
        let url: String
        let host: String
        let faviconURL: String?
        let dateAdded: Date
        let lastOpenedDate: Date?
        let lastOpenedSortKey: Date
        let isBookmark: Bool
        let price: String?
        let tags: [TagChip]
        let tagCount: Int
        let tagSortKey: String

        init(_ bookmark: Bookmark) {
            id = bookmark.id
            self.bookmark = bookmark
            title = bookmark.title
            note = bookmark.note
            url = bookmark.url
            host = URL(string: bookmark.url)?.host ?? "—"
            faviconURL = bookmark.faviconURL
            dateAdded = bookmark.dateAdded
            lastOpenedDate = bookmark.lastOpenedDate
            lastOpenedSortKey = bookmark.lastOpenedDateForSorting
            let itemType = bookmark.itemType
            isBookmark = itemType == .bookmark
            price = itemType == .wishlistItem ? bookmark.price.flatMap { $0.isEmpty ? nil : $0 } : nil
            let allTags = bookmark.tags
            tags = allTags.prefix(3).map { TagChip($0) }
            tagCount = allTags.count
            tagSortKey = allTags.map(\.name).min() ?? ""
        }
    }

    struct TagChip: Identifiable, Equatable {
        let tag: Tag
        let name: String
        let color: String
        var id: PersistentIdentifier { tag.persistentModelID }

        init(_ tag: Tag) {
            self.tag = tag
            name = tag.name
            color = tag.color
        }
    }

    private var sortedRows: [BookmarkRow] {
        bookmarks.map { BookmarkRow($0) }.sorted(using: sortOrder)
    }

    var body: some View {
        Table(sortedRows, selection: $selectedIDs, sortOrder: $sortOrder) {
            // Title + note column — also the drag handle for the row.
            TableColumn("Title", value: \BookmarkRow.title) { row in
                HStack(spacing: 8) {
                    faviconView(row.faviconURL)
                    VStack(alignment: .leading, spacing: 2) {
                        Button {
                            open(row.bookmark)
                        } label: {
                            Text(row.title)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                        .buttonStyle(.link)

                        if let note = row.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                // Dragging the title cell drags all selected rows, or just this one if unselected.
                .draggable(
                    selectedIDs.contains(row.id)
                        ? BookmarkTransfer(ids: Array(selectedIDs))
                        : BookmarkTransfer(ids: [row.id])
                )
            }

            if listShowSource {
                // Domain column (sortable by url)
                TableColumn("Source", value: \BookmarkRow.url) { row in
                    Text(row.host)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 140, max: 180)
            }

            if listShowSaved {
                // Date column (sortable by dateAdded)
                TableColumn("Saved", value: \BookmarkRow.dateAdded) { row in
                    Text(row.dateAdded.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }
                .width(90)
            }

            if listShowLastOpened {
                // Last Opened column (never-opened items sort as the oldest)
                TableColumn("Last Opened", value: \BookmarkRow.lastOpenedSortKey) { row in
                    if let date = row.lastOpenedDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never")
                            .foregroundStyle(.tertiary)
                    }
                }
                .width(min: 80, ideal: 110, max: 130)
            }

            if listShowPrice {
                // Price column — only populated for wishlist items
                TableColumn("Price") { row in
                    if let price = row.price {
                        Text(price)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .width(min: 60, ideal: 90, max: 120)
            }

            if listShowTags {
                TableColumn("Tags", value: \BookmarkRow.tagSortKey) { row in
                    if !row.tags.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(row.tags) { chip in
                                Button { onTagTap?(chip.tag) } label: {
                                    Text("#\(chip.name)")
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color(hex: chip.color).opacity(0.15),
                                                    in: Capsule())
                                        .foregroundStyle(Color(hex: chip.color))
                                }
                                .buttonStyle(.plain)
                                .help("Filter by #\(chip.name)")
                            }
                            if row.tagCount > 3 {
                                Text("+\(row.tagCount - 3)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .width(min: 80, ideal: 160, max: 200)
            }

            // Actions column (not sortable)
            TableColumn("") { row in
                HStack(spacing: 2) {
                    if row.isBookmark {
                        Button { onRead(row.bookmark) } label: {
                            Image(systemName: "eyeglasses")
                        }
                        .buttonStyle(.borderless)
                        .help("Reader view")
                    }

                    Button {
                        open(row.bookmark)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Open in browser")

                    Button { onManage(row.bookmark) } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderless)
                    .help("Edit")

                    Button(role: .destructive) {
                        delete([row.bookmark])
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("Delete (⌘Z to undo)")
                }
            }
            .width(100)
        }
        // Mirrors the card context menu so both view modes offer the same actions.
        .contextMenu(forSelectionType: UUID.self) { selection in
            let targets = bookmarks.filter { selection.contains($0.id) }
            if let single = targets.first, targets.count == 1 {
                if single.itemType == .bookmark {
                    Button("Open in Reader") { onRead(single) }
                }
                Button("Open in Browser") { open(single) }
                Divider()
                Button("Edit") { onManage(single) }
            } else if !targets.isEmpty {
                Button("Open \(targets.count) Items in Browser") { targets.forEach(open) }
                Divider()
            }
            if !targets.isEmpty {
                BookmarkOrganizeMenu(targets: targets, folders: allFolders, tags: allTags)
                let shareTitle = targets.count == 1 ? targets[0].title : "\(targets.count) Items"
                ShareLink(
                    item: BookmarksExport(bookmarks: targets, title: shareTitle),
                    preview: SharePreview(shareTitle)
                ) {
                    Label(targets.count == 1 ? "Share" : "Share \(targets.count) Items",
                          systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(targets.count == 1 ? "Delete" : "Delete \(targets.count) Items", role: .destructive) {
                    delete(targets)
                }
            }
        } primaryAction: { selection in
            // Double-click / Return opens the row(s) in the browser.
            BookmarkBulkActions.open(bookmarks.filter { selection.contains($0.id) })
        }
    }

    private func delete(_ targets: [Bookmark]) {
        selectedIDs.subtract(targets.map(\.id))
        BookmarkBulkActions.delete(targets, from: modelContext)
    }

    private func open(_ bookmark: Bookmark) {
        BookmarkBulkActions.open([bookmark])
    }

    @ViewBuilder
    private func faviconView(_ faviconURL: String?) -> some View {
        if let urlStr = faviconURL, let url = URL(string: urlStr) {
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

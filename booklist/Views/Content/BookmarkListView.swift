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
    @State private var sortOrder = [KeyPathComparator<Bookmark>(\Bookmark.dateAdded, order: .reverse)]

    @AppStorage("listShowSource")     private var listShowSource     = true
    @AppStorage("listShowSaved")      private var listShowSaved      = true
    @AppStorage("listShowLastOpened") private var listShowLastOpened = true
    @AppStorage("listShowPrice")      private var listShowPrice      = true
    @AppStorage("listShowTags")       private var listShowTags       = true

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
                        Button {
                            open(bookmark)
                        } label: {
                            Text(bookmark.title)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                        .buttonStyle(.link)

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

            if listShowSource {
                // Domain column (sortable by url)
                TableColumn("Source", value: \Bookmark.url) { bookmark in
                    Text(URL(string: bookmark.url)?.host ?? "—")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 140, max: 180)
            }

            if listShowSaved {
                // Date column (sortable by dateAdded)
                TableColumn("Saved", value: \Bookmark.dateAdded) { bookmark in
                    Text(bookmark.dateAdded.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }
                .width(90)
            }

            if listShowLastOpened {
                // Last Opened column (sortable via lastOpenedDateForSorting proxy)
                TableColumn("Last Opened", value: \Bookmark.lastOpenedDateForSorting) { bookmark in
                    if let date = bookmark.lastOpenedDate {
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
                TableColumn("Price") { bookmark in
                    if bookmark.itemType == .wishlistItem, let price = bookmark.price, !price.isEmpty {
                        Text(price)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .width(min: 60, ideal: 90, max: 120)
            }

            if listShowTags {
                TableColumn("Tags", value: \Bookmark.tagSortKey) { bookmark in
                    if !bookmark.tags.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(bookmark.tags.prefix(3)) { tag in
                                Button { onTagTap?(tag) } label: {
                                    Text("#\(tag.name)")
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color(hex: tag.color).opacity(0.15),
                                                    in: Capsule())
                                        .foregroundStyle(Color(hex: tag.color))
                                }
                                .buttonStyle(.plain)
                                .help("Filter by #\(tag.name)")
                            }
                            if bookmark.tags.count > 3 {
                                Text("+\(bookmark.tags.count - 3)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .width(min: 80, ideal: 160, max: 200)
            }

            // Actions column (not sortable)
            TableColumn("") { bookmark in
                HStack(spacing: 2) {
                    if bookmark.itemType == .bookmark {
                        Button { onRead(bookmark) } label: {
                            Image(systemName: "eyeglasses")
                        }
                        .buttonStyle(.borderless)
                        .help("Reader view")
                    }

                    Button {
                        open(bookmark)
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
                        delete([bookmark])
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

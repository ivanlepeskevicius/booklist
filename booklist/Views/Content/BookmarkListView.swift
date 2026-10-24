import SwiftUI
import SwiftData

/// List layout — sortable columns with favicon, title+note, domain, dates, price, tags and icon actions.
///
/// Virtualized by hand like the masonry: every row is `rowHeight` tall and only the rows near the
/// visible area are built. SwiftUI's `Table` was used before; it measures each row's height as it
/// appears and re-corrects its scroll position, and scrolling back up a 5,000-bookmark list blocked
/// for up to 90 s and grew to 4 GB (~200 ms per step at 1,000). A scroll step now costs the rows on
/// screen, whatever the library size.
struct BookmarkListView: View {
    let bookmarks: [Bookmark]
    let onManage: (Bookmark) -> Void
    let onRead: (Bookmark) -> Void
    @Binding var selectedIDs: Set<UUID>
    var onTagTap: ((Tag) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query private var allFolders: [Folder]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var sortColumn = SortColumn.saved
    @State private var sortAscending = false
    @State private var rowsMemo = RowsMemo()
    /// Built part of the list, in `MasonryView.bandHeight` steps (one screen of overscan each way).
    @State private var builtBands = 0...4
    @State private var anchorID: UUID?
    /// The row arrow keys move from — the last one clicked or reached by keyboard.
    @State private var leadID: UUID?
    @FocusState private var isFocused: Bool

    @AppStorage("listShowSource")     private var listShowSource     = true
    @AppStorage("listShowSaved")      private var listShowSaved      = true
    @AppStorage("listShowLastOpened") private var listShowLastOpened = true
    @AppStorage("listShowPrice")      private var listShowPrice      = true
    @AppStorage("listShowTags")       private var listShowTags       = true

    private var columns: ListColumns {
        ListColumns(source: listShowSource, saved: listShowSaved, lastOpened: listShowLastOpened,
                    price: listShowPrice, tags: listShowTags)
    }

    enum SortColumn { case title, source, saved, lastOpened, tags }

    /// What one row shows, copied out of the bookmark when the list is built, so building and
    /// sorting rows never reads SwiftData properties again (each read is slow and change-tracked).
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
            note = bookmark.note.flatMap { $0.isEmpty ? nil : $0 }
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

    /// Rows are rebuilt and sorted only when the library or the sort changes — the body also runs
    /// on every selection change and every band of scrolling.
    final class RowsMemo {
        struct Key: Equatable {
            let library: UnsafeRawPointer?
            let count: Int
            let column: SortColumn
            let ascending: Bool
        }
        var key: Key?
        /// Kept alive so its address (in the key) can't be reused by a different array.
        var source: [Bookmark] = []
        var rows: [BookmarkRow] = []
    }

    private var sortedRows: [BookmarkRow] {
        let key = RowsMemo.Key(library: bookmarks.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) },
                               count: bookmarks.count, column: sortColumn, ascending: sortAscending)
        if rowsMemo.key != key {
            rowsMemo.rows = sorted(bookmarks.map { BookmarkRow($0) })
            rowsMemo.source = bookmarks
            rowsMemo.key = key
        }
        return rowsMemo.rows
    }

    private func sorted(_ rows: [BookmarkRow]) -> [BookmarkRow] {
        let ascending = sortAscending
        func text(_ a: String, _ b: String) -> Bool {
            a.localizedStandardCompare(b) == (ascending ? .orderedAscending : .orderedDescending)
        }
        func date(_ a: Date, _ b: Date) -> Bool { ascending ? a < b : a > b }
        switch sortColumn {
        case .title:      return rows.sorted { text($0.title, $1.title) }
        case .source:     return rows.sorted { text($0.url, $1.url) }
        case .tags:       return rows.sorted { text($0.tagSortKey, $1.tagSortKey) }
        case .saved:      return rows.sorted { date($0.dateAdded, $1.dateAdded) }
        case .lastOpened: return rows.sorted { date($0.lastOpenedSortKey, $1.lastOpenedSortKey) }
        }
    }

    var body: some View {
        let rows = sortedRows
        let rowsPerBand = Int(MasonryView.bandHeight / ListMetrics.rowHeight)
        let first = min(rows.count, builtBands.lowerBound * rowsPerBand)
        let last = min(rows.count, (builtBands.upperBound + 1) * rowsPerBand)
        // Worked out once per render, not once per row.
        let selectedRows = selectedIDs.isEmpty ? [] : rows.filter { selectedIDs.contains($0.id) }.map(\.bookmark)
        let selectionSignature = selectedIDs.hashValue
        let dragIDs = Array(selectedIDs)
        let columns = columns
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    RowsLayout(rowHeight: ListMetrics.rowHeight, firstRow: first, totalRows: rows.count) {
                        ForEach(first..<last, id: \.self) { index in
                            let row = rows[index]
                            let isSelected = selectedIDs.contains(row.id)
                            BookmarkListRow(
                                row: row, isOdd: !index.isMultiple(of: 2), isSelected: isSelected,
                                selectionSignature: isSelected ? selectionSignature : 0, columns: columns,
                                targets: isSelected ? selectedRows : [row.bookmark], dragIDs: dragIDs,
                                folders: allFolders, tags: allTags,
                                onSelect: { cmdHeld, shiftHeld in
                                    // The memo's current rows, not `rows`: an unchanged row isn't
                                    // rebuilt (Equatable), so its closure can outlive a re-sort or edit.
                                    select(row.id, cmdHeld: cmdHeld, shiftHeld: shiftHeld, rows: rowsMemo.rows)
                                    isFocused = true
                                },
                                onManage: onManage, onRead: onRead, onDelete: delete, onTagTap: onTagTap
                            )
                            .equatable()
                            .id(row.id)
                        }
                    }
                }
                .onScrollGeometryChange(for: ClosedRange<Int>.self) { geometry in
                    MasonryView.bands(forVisible: geometry.visibleRect)
                } action: { _, bands in
                    builtBands = bands
                }
                .focusable()
                .focusEffectDisabled()
                .focused($isFocused)
                // Edit › Select All / ⌘A while the list has focus.
                .onCommand(#selector(NSResponder.selectAll(_:))) {
                    selectedIDs = Set(rows.map(\.id))
                }
                // ↑/↓ = move the selection; Shift+arrow = extend it.
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    moveSelection(down: press.key == .downArrow, extending: press.modifiers.contains(.shift),
                                  rows: rows, proxy: proxy)
                    return .handled
                }
                // Return opens the selected row(s) in the browser, like double-click.
                .onKeyPress(.return) {
                    guard !selectedRows.isEmpty else { return .ignored }
                    BookmarkBulkActions.open(selectedRows)
                    return .handled
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            headerButton("Title", .title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 24)   // past the favicon
            if listShowSource { headerButton("Source", .source).frame(width: ListMetrics.source, alignment: .leading) }
            if listShowSaved { headerButton("Saved", .saved).frame(width: ListMetrics.saved, alignment: .leading) }
            if listShowLastOpened {
                headerButton("Last Opened", .lastOpened).frame(width: ListMetrics.lastOpened, alignment: .leading)
            }
            if listShowPrice { Text("Price").frame(width: ListMetrics.price, alignment: .leading) }
            if listShowTags { headerButton("Tags", .tags).frame(width: ListMetrics.tags, alignment: .leading) }
            Color.clear.frame(width: ListMetrics.actions, height: 1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, ListMetrics.horizontalPadding)
        .frame(height: 28)
    }

    /// Click to sort by the column; click again to reverse. Text columns start A–Z, dates newest first.
    private func headerButton(_ title: String, _ column: SortColumn) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = [.title, .source, .tags].contains(column)
            }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rows

    // MARK: - Selection

    private func select(_ id: UUID, cmdHeld: Bool, shiftHeld: Bool, rows: [BookmarkRow]) {
        leadID = id
        if shiftHeld, let anchor = anchorID,
           let anchorIndex = rows.firstIndex(where: { $0.id == anchor }),
           let clickedIndex = rows.firstIndex(where: { $0.id == id }) {
            let range = min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)
            let rangeIDs = Set(rows[range].map(\.id))
            selectedIDs = cmdHeld ? selectedIDs.union(rangeIDs) : rangeIDs
        } else if cmdHeld {
            if selectedIDs.contains(id) { selectedIDs.remove(id) }
            else { selectedIDs.insert(id) }
            anchorID = id
        } else {
            selectedIDs = [id]
            anchorID = id
        }
    }

    private func moveSelection(down: Bool, extending: Bool, rows: [BookmarkRow], proxy: ScrollViewProxy) {
        guard !rows.isEmpty else { return }
        let lead = leadID.flatMap { selectedIDs.contains($0) ? $0 : nil }
            ?? (selectedIDs.count == 1 ? selectedIDs.first : nil)
        let targetIndex: Int
        if let lead, let index = rows.firstIndex(where: { $0.id == lead }) {
            targetIndex = min(rows.count - 1, max(0, index + (down ? 1 : -1)))
        } else {
            targetIndex = 0
        }
        let target = rows[targetIndex].id
        if extending {
            selectedIDs.insert(target)
            if anchorID == nil { anchorID = lead ?? target }
        } else {
            selectedIDs = [target]
            anchorID = target
        }
        leadID = target
        // The next row is next to one on screen, so it's within the built area.
        proxy.scrollTo(target)
    }

    private func delete(_ targets: [Bookmark]) {
        selectedIDs.subtract(targets.map(\.id))
        BookmarkBulkActions.delete(targets, from: modelContext)
    }

}

/// Places the built rows at their positions in the whole list. Its height is the whole list's,
/// so the scroll view knows the full length even though few rows are built.
struct RowsLayout: Layout {
    let rowHeight: CGFloat
    let firstRow: Int
    let totalRows: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: rowHeight * CGFloat(totalRows))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (offset, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY + CGFloat(firstRow + offset) * rowHeight),
                          proposal: ProposedViewSize(width: bounds.width, height: rowHeight))
        }
    }
}

/// Which optional columns are shown (Settings › Display).
struct ListColumns: Equatable {
    var source = true, saved = true, lastOpened = true, price = true, tags = true
}

/// Shared sizes, so the header lines up with the rows.
enum ListMetrics {
    static let rowHeight: CGFloat = 40
    static let horizontalPadding: CGFloat = 12
    static let source: CGFloat = 140
    static let saved: CGFloat = 90
    static let lastOpened: CGFloat = 100
    static let price: CGFloat = 80
    static let tags: CGFloat = 160
    static let actions: CGFloat = 100
}

/// One row of the list. Equatable on what it shows, so when the built rows shift while
/// scrolling SwiftUI skips every row that didn't change instead of rebuilding all of them
/// (measured: 150 ms per scroll step at 5,000 bookmarks before).
struct BookmarkListRow: View, Equatable {
    let row: BookmarkListView.BookmarkRow
    let isOdd: Bool
    let isSelected: Bool
    /// Changes whenever the selection does — only set on selected rows (their menu and drag
    /// cover the whole selection).
    let selectionSignature: Int
    let columns: ListColumns
    /// The bookmarks the context menu and double-click act on.
    let targets: [Bookmark]
    let dragIDs: [UUID]
    let folders: [Folder]
    let tags: [Tag]
    let onSelect: (_ cmdHeld: Bool, _ shiftHeld: Bool) -> Void
    let onManage: (Bookmark) -> Void
    let onRead: (Bookmark) -> Void
    let onDelete: ([Bookmark]) -> Void
    let onTagTap: ((Tag) -> Void)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row && lhs.isOdd == rhs.isOdd && lhs.isSelected == rhs.isSelected
            && lhs.selectionSignature == rhs.selectionSignature && lhs.columns == rhs.columns
            // Any folder/tag change gives the queries a new array; comparing buffers keeps the
            // "Move to Folder" / "Tags" menus current. Both sides hold their array, so no reuse.
            && sameBuffer(lhs.folders, rhs.folders) && sameBuffer(lhs.tags, rhs.tags)
    }

    private static func sameBuffer<T>(_ a: [T], _ b: [T]) -> Bool {
        a.withUnsafeBufferPointer { pa in b.withUnsafeBufferPointer { pb in pa.baseAddress == pb.baseAddress } }
            && a.count == b.count
    }

    var body: some View {
        HStack(spacing: 8) {
            titleCell
                .frame(maxWidth: .infinity, alignment: .leading)
            if columns.source {
                Text(row.host)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: ListMetrics.source, alignment: .leading)
            }
            if columns.saved {
                Text(row.dateAdded.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: ListMetrics.saved, alignment: .leading)
            }
            if columns.lastOpened {
                Group {
                    if let date = row.lastOpenedDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                    } else {
                        Text("Never").foregroundStyle(.tertiary)
                    }
                }
                .lineLimit(1)
                .frame(width: ListMetrics.lastOpened, alignment: .leading)
            }
            if columns.price {
                Text(row.price ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: ListMetrics.price, alignment: .leading)
            }
            if columns.tags {
                tagsCell
                    .frame(width: ListMetrics.tags, alignment: .leading)
            }
            actionsCell
                .frame(width: ListMetrics.actions, alignment: .trailing)
        }
        .padding(.horizontal, ListMetrics.horizontalPadding)
        .frame(height: ListMetrics.rowHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.22))
                    .padding(.horizontal, 4)
            } else if isOdd {
                Color.primary.opacity(0.035)
            }
        }
        .contentShape(Rectangle())
        // Click selects (⌘ toggles, ⇧ extends); double-click opens, like the old table.
        .onTapGesture {
            let event = NSApp.currentEvent
            if (event?.clickCount ?? 1) >= 2 {
                BookmarkBulkActions.open(targets)
                return
            }
            let flags = event?.modifierFlags ?? []
            onSelect(flags.contains(.command), flags.contains(.shift))
        }
        // Mirrors the card context menu so both view modes offer the same actions.
        .contextMenu { contextMenu }
    }

    private var titleCell: some View {
        HStack(spacing: 8) {
            favicon
            VStack(alignment: .leading, spacing: 2) {
                // Link-styled text rather than a `.link` Button: the button swallowed right-clicks,
                // so the row's context menu never opened on the title.
                Text(row.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.link)
                    .pointerStyle(.link)
                    .onTapGesture { BookmarkBulkActions.open([row.bookmark]) }
                    .accessibilityAddTraits(.isLink)

                if let note = row.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        // Dragging the title drags all selected rows, or just this one if unselected.
        .draggable(
            isSelected ? BookmarkTransfer(ids: dragIDs) : BookmarkTransfer(ids: [row.id])
        )
    }

    @ViewBuilder
    private var tagsCell: some View {
        if !row.tags.isEmpty {
            HStack(spacing: 3) {
                ForEach(row.tags) { chip in
                    Button { onTagTap?(chip.tag) } label: {
                        Text("#\(chip.name)")
                            .font(.caption2)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(hex: chip.color).opacity(0.15), in: Capsule())
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

    private var actionsCell: some View {
        HStack(spacing: 2) {
            if row.isBookmark {
                Button { onRead(row.bookmark) } label: {
                    Image(systemName: "eyeglasses")
                }
                .buttonStyle(.borderless)
                .help("Reader view")
            }

            Button {
                BookmarkBulkActions.open([row.bookmark])
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
                onDelete([row.bookmark])
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Delete (⌘Z to undo)")
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let single = targets.first, targets.count == 1 {
            if single.itemType == .bookmark {
                Button("Open in Reader") { onRead(single) }
            }
            Button("Open in Browser") { BookmarkBulkActions.open([single]) }
            Divider()
            Button("Edit") { onManage(single) }
        } else if !targets.isEmpty {
            Button("Open \(targets.count) Items in Browser") { BookmarkBulkActions.open(targets) }
            Divider()
        }
        if !targets.isEmpty {
            BookmarkOrganizeMenu(targets: targets, folders: folders, tags: tags)
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
                onDelete(targets)
            }
        }
    }


    @ViewBuilder
    private var favicon: some View {
        if let urlStr = row.faviconURL, let url = URL(string: urlStr) {
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

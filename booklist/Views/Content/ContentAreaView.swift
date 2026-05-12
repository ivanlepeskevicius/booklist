import SwiftUI
import SwiftData

struct ContentAreaView: View {
    let selection: SidebarSelection

    @Query(sort: \Bookmark.dateAdded, order: .reverse) private var allBookmarks: [Bookmark]
    @Query private var allFolders: [Folder]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @Environment(CaptureRouter.self) private var captureRouter

    @State private var showingCapture = false
    @State private var showingImport  = false

    @State private var searchText          = ""
    @State private var sortOption          = SortOption.recent
    @State private var viewMode            = ViewMode.masonry
    @State private var managingBookmark: Bookmark?
    @State private var readerBookmark: Bookmark?
    @State private var selectedBookmarkIDs: Set<UUID> = []
    @State private var selectedTagIDs: Set<UUID>      = []
    /// Changes each time the user picks "Random", producing a new stable shuffle order.
    @State private var shuffleNonce        = 0

    @FocusState private var isSearchFocused: Bool

    @AppStorage("showTitleOnCards")    private var showTitleOnCards = true
    @AppStorage("showDateOnCards")     private var showDateOnCards  = true
    @AppStorage("readerPanelWidth")    private var readerWidth: Double = 460
    @AppStorage("captureShortcutKey")  private var captureShortcutKey = "t"

    // MARK: - Derived data

    private var navigationTitle: String {
        switch selection {
        case .inbox:          return "Inbox"
        case .wishlist:       return "Wishlist"
        case .all:            return "All"
        case .folder(let id): return allFolders.first { $0.id == id }?.name ?? "Folder"
        }
    }

    private var displayedBookmarks: [Bookmark] {
        // 1. Filter by sidebar selection
        var result: [Bookmark]
        switch selection {
        case .inbox:
            // Only regular bookmarks with no folder
            result = allBookmarks.filter { $0.collection == nil && $0.itemType == .bookmark }
        case .wishlist:
            // Only unclassified wishlist items — mirrors Inbox behaviour
            result = allBookmarks.filter { $0.collection == nil && $0.itemType == .wishlistItem }
        case .all:
            result = allBookmarks
        case .folder(let id):
            let ids = subtreeFolderIDs(rootID: id)
            result = allBookmarks.filter { bm in
                guard let cid = bm.collection?.id else { return false }
                return ids.contains(cid)
            }
        }

        // 2. Filter by selected tags (OR logic — show bookmarks that have any selected tag)
        if !selectedTagIDs.isEmpty {
            result = result.filter { bm in
                bm.tags.contains { selectedTagIDs.contains($0.id) }
            }
        }

        // 3. Filter by search text
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) ||
                ($0.note?.lowercased().contains(q) == true) ||
                ($0.pageDescription?.lowercased().contains(q) == true) ||
                $0.url.lowercased().contains(q)
            }
        }

        // 4. Apply sort
        switch sortOption {
        case .recent:       break
        case .lastOpened:
            // Most recently opened first; never-opened items sink to the bottom,
            // ordered by date added among themselves.
            result.sort { a, b in
                switch (a.lastOpenedDate, b.lastOpenedDate) {
                case (let d1?, let d2?): return d1 > d2
                case (_?, nil):         return true
                case (nil, _?):         return false
                case (nil, nil):        return a.dateAdded > b.dateAdded
                }
            }
        case .alphabetical: result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .random:
            // Stable hash-based shuffle: same nonce → same order every render.
            // shuffleNonce is bumped each time the user picks "Random".
            result.sort { a, b in
                var h0 = Hasher(); h0.combine(a.id); h0.combine(shuffleNonce)
                var h1 = Hasher(); h1.combine(b.id); h1.combine(shuffleNonce)
                return h0.finalize() < h1.finalize()
            }
        }

        return result
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Main content area
            VStack(spacing: 0) {
                toolbar
                Divider()
                if !allTags.isEmpty {
                    tagFilterBar
                    Divider()
                }
                content
            }

            // Inline reader panel — slides in from the right, width is user-adjustable
            if let bookmark = readerBookmark {
                HStack(spacing: 0) {
                    ReaderDragHandle(width: $readerWidth)
                    ReaderView(bookmark: bookmark, onClose: { readerBookmark = nil })
                        .frame(width: CGFloat(readerWidth))
                        .id(bookmark.id)
                }
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: readerBookmark != nil)
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showingImport = true } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Import bookmarks")

                if !displayedBookmarks.isEmpty {
                    let shareTargets = selectedBookmarkIDs.isEmpty
                        ? displayedBookmarks
                        : displayedBookmarks.filter { selectedBookmarkIDs.contains($0.id) }
                    let shareTitle: String = {
                        if selectedBookmarkIDs.count == 1,
                           let bm = displayedBookmarks.first(where: { selectedBookmarkIDs.contains($0.id) }) {
                            return bm.title
                        } else if selectedBookmarkIDs.count > 1 {
                            return "\(selectedBookmarkIDs.count) Items"
                        }
                        return navigationTitle
                    }()
                    ShareLink(
                        item: BookmarksExport(bookmarks: shareTargets, title: shareTitle),
                        preview: SharePreview(shareTitle)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help(selectedBookmarkIDs.isEmpty
                          ? "Share \(navigationTitle)"
                          : "Share \(selectedBookmarkIDs.count) selected item\(selectedBookmarkIDs.count == 1 ? "" : "s")"
                    )
                }

                Button { showingCapture = true } label: {
                    Image(systemName: "plus")
                }
                .captureShortcut(captureShortcutKey)
                .help(captureShortcutKey == "none"
                      ? "Save a new link"
                      : "Save a new link (⌘\(captureShortcutKey.uppercased()))")

                SettingsLink {
                    Image(systemName: "gear")
                }
                .help("Settings (⌘,)")
            }
        }
        .sheet(item: $managingBookmark) { bookmark in
            ManagePanelView(bookmark: bookmark)
        }
        .sheet(isPresented: $showingCapture, onDismiss: {
            captureRouter.pendingURL   = nil
            captureRouter.pendingTitle = nil
        }) {
            CaptureView(
                initialURL:   captureRouter.pendingURL   ?? "",
                initialTitle: captureRouter.pendingTitle ?? ""
            )
        }
        .sheet(isPresented: $showingImport) {
            ImportView()
        }
        // Clear selection and close reader when navigating to a different sidebar item.
        .onChange(of: selection) {
            selectedBookmarkIDs = []
            selectedTagIDs = []
            readerBookmark = nil
        }
        // When reader is open and the user single-selects a different card, switch to it.
        .onChange(of: selectedBookmarkIDs) { _, newIDs in
            guard readerBookmark != nil,
                  newIDs.count == 1,
                  let id = newIDs.first,
                  let bm = displayedBookmarks.first(where: { $0.id == id }) else { return }
            readerBookmark = bm
        }
        // Auto-open capture when a URL arrives from the Share Extension / deep link.
        .onChange(of: captureRouter.pendingURL) { _, newURL in
            if newURL != nil { showingCapture = true }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                TextField("Search in \(navigationTitle)…", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .focusRing(when: isSearchFocused)

            // Sort picker
            Menu {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        sortOption = option
                        // Each tap of "Random" produces a new shuffle order.
                        if option == .random { shuffleNonce += 1 }
                    } label: {
                        if sortOption == option {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // View mode toggle
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.iconName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 68)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Content area

    @ViewBuilder
    private var content: some View {
        if displayedBookmarks.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch viewMode {
            case .masonry:
                MasonryView(
                    bookmarks: displayedBookmarks,
                    onManage: { managingBookmark = $0 },
                    onRead:   { readerBookmark   = $0 },
                    selectedIDs: $selectedBookmarkIDs
                )
            case .list:
                BookmarkListView(
                    bookmarks: displayedBookmarks,
                    onManage: { managingBookmark = $0 },
                    onRead:   { readerBookmark   = $0 },
                    selectedIDs: $selectedBookmarkIDs,
                    onTagTap: { tag in
                        if selectedTagIDs.contains(tag.id) { selectedTagIDs.remove(tag.id) }
                        else { selectedTagIDs.insert(tag.id) }
                    }
                )
            }
        }
    }

    // MARK: - Tag filter bar

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(allTags) { tag in
                    let isSelected = selectedTagIDs.contains(tag.id)
                    Button {
                        if isSelected { selectedTagIDs.remove(tag.id) }
                        else { selectedTagIDs.insert(tag.id) }
                    } label: {
                        Text("#\(tag.name)")
                            .font(.caption)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                isSelected
                                    ? Color(hex: tag.color)
                                    : Color(hex: tag.color).opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? .white : Color(hex: tag.color))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
    }

    // MARK: - Folder subtree

    private func subtreeFolderIDs(rootID: UUID) -> Set<UUID> {
        var result: Set<UUID> = [rootID]
        for child in allFolders where child.parent?.id == rootID {
            result.formUnion(subtreeFolderIDs(rootID: child.id))
        }
        return result
    }

    private var emptyState: some View {
        let isWishlist = selection == .wishlist
        return ContentUnavailableView(
            searchText.isEmpty ? "Nothing here yet" : "No results",
            systemImage: searchText.isEmpty
                ? (isWishlist ? "cart" : "bookmark")
                : "magnifyingglass",
            description: Text(
                searchText.isEmpty
                ? (isWishlist ? "Save your first wishlist item to get started." : "Save your first link to get started.")
                : "Try a different search term."
            )
        )
    }
}

// MARK: - Capture shortcut helper

private extension View {
    @ViewBuilder
    func captureShortcut(_ key: String) -> some View {
        if key != "none", let char = key.first {
            self.keyboardShortcut(KeyEquivalent(char), modifiers: .command)
        } else {
            self
        }
    }
}

// MARK: - Reader drag handle

/// A thin draggable divider that lets the user resize the reader panel.
/// Width is clamped between 300 and 800 pt; drag left to widen, right to narrow.
private struct ReaderDragHandle: View {
    @Binding var width: Double
    @State private var dragStartWidth: Double?

    var body: some View {
        Color(nsColor: .separatorColor)
            .frame(width: 1)
            .frame(width: 8)        // wider invisible hit area around the 1pt line
            .contentShape(Rectangle()) // required on macOS — Color.clear doesn't receive gestures
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() }
                else      { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == nil { dragStartWidth = width }
                        // Dragging left (negative delta) widens the reader; right narrows it.
                        width = max(300, min(800, (dragStartWidth ?? width) - value.translation.width))
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
    }
}

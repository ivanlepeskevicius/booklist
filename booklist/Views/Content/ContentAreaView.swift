import SwiftUI
import SwiftData

struct ContentAreaView: View {
    let selection: SidebarSelection
    /// Unsorted (sorting happens in `filteredAndSorted`). Owned by ContentView's single library
    /// query (see there) — not queried here.
    let allBookmarks: [Bookmark]
    @Query private var allFolders: [Folder]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @Environment(CaptureRouter.self) private var captureRouter
    @Environment(\.modelContext) private var modelContext

    @State private var showingCapture = false
    @State private var showingImport  = false

    @State private var searchText          = ""
    @AppStorage("sortOption") private var sortOption = SortOption.recent
    /// The live view mode (also driven by the View menu); per-item choices are kept in viewModeMemoryData.
    @AppStorage("viewMode")   private var viewMode   = ViewMode.masonry
    @AppStorage("viewModeBySelection") private var viewModeMemoryData = Data()
    @State private var managingBookmark: Bookmark?
    @State private var readerBookmark: Bookmark?
    @State private var selectedBookmarkIDs: Set<UUID> = []
    @State private var selectedTagIDs: Set<UUID>      = []
    /// Changes each time the user picks "Random", producing a new stable shuffle order.
    @State private var shuffleNonce        = 0
    /// `searchText` as it was 0.15 s after the last keystroke — what the list is filtered by, so
    /// typing doesn't refilter the whole library on every key.
    @State private var appliedSearch       = ""
    @State private var displayMemo         = DisplayMemo()

    @FocusState private var isSearchFocused: Bool

    @AppStorage("showTitleOnCards")    private var showTitleOnCards = true
    @AppStorage("showDateOnCards")     private var showDateOnCards  = true
    @AppStorage("readerPanelWidth")    private var readerWidth: Double = 460
    @AppStorage("captureShortcutKey")  private var captureShortcutKey = "t"
    @AppStorage("cardSizeScale")       private var cardSizeScale = 1.0

    // MARK: - Derived data

    private var navigationTitle: String {
        switch selection {
        case .inbox:          return "Inbox"
        case .wishlist:       return "Wishlist"
        case .all:            return "All"
        case .folder(let id): return allFolders.first { $0.id == id }?.name ?? "Folder"
        }
    }

    private var isFiltering: Bool { !searchText.isEmpty || !selectedTagIDs.isEmpty }

    /// Bookmarks belonging to the current sidebar selection, before search/tag filtering.
    private var scopedBookmarks: [Bookmark] {
        switch selection {
        case .inbox:
            // Only regular bookmarks with no folder
            return allBookmarks.filter { $0.collection == nil && $0.itemType == .bookmark }
        case .wishlist:
            // Only unclassified wishlist items — mirrors Inbox behaviour
            return allBookmarks.filter { $0.collection == nil && $0.itemType == .wishlistItem }
        case .all:
            return allBookmarks
        case .folder(let id):
            let ids = subtreeFolderIDs(rootID: id)
            return allBookmarks.filter { bm in
                guard let cid = bm.collection?.id else { return false }
                return ids.contains(cid)
            }
        }
    }

    private func filteredAndSorted(_ scoped: [Bookmark]) -> [Bookmark] {
        var result = scoped

        // Filter by selected tags (OR logic — show bookmarks that have any selected tag)
        if !selectedTagIDs.isEmpty {
            result = result.filter { bm in
                bm.tags.contains { selectedTagIDs.contains($0.id) }
            }
        }

        // Filter by search text. Tags are shown as "#name", so a leading "#" is ignored for tag matching.
        if !appliedSearch.isEmpty {
            let q = appliedSearch.lowercased()
            let tagQuery = q.hasPrefix("#") ? String(q.dropFirst()) : q
            result = result.filter {
                $0.title.lowercased().contains(q) ||
                ($0.note?.lowercased().contains(q) == true) ||
                ($0.pageDescription?.lowercased().contains(q) == true) ||
                $0.url.lowercased().contains(q) ||
                (!tagQuery.isEmpty && $0.tags.contains { $0.name.lowercased().contains(tagQuery) })
            }
        }

        // 4. Apply sort. Each bookmark's sort key is read once up front: reading a SwiftData
        // property is slow enough that reading it inside the comparator (~20,000 times for
        // 1,000 items) showed up in profiles.
        switch sortOption {
        case .recent:
            result = result.map { ($0.dateAdded, $0) }.sorted { $0.0 > $1.0 }.map(\.1)
        case .lastOpened:
            // Most recently opened first; never-opened items sink to the bottom,
            // ordered by date added among themselves.
            result = result.map { (opened: $0.lastOpenedDate, added: $0.dateAdded, bookmark: $0) }
                .sorted { a, b in
                    switch (a.opened, b.opened) {
                    case (let d1?, let d2?): return d1 > d2
                    case (_?, nil):         return true
                    case (nil, _?):         return false
                    case (nil, nil):        return a.added > b.added
                    }
                }
                .map(\.bookmark)
        case .alphabetical:
            result = result.map { ($0.title, $0) }
                .sorted { $0.0.localizedCompare($1.0) == .orderedAscending }
                .map(\.1)
        case .random:
            // Stable hash-based shuffle: same nonce → same order every render.
            // shuffleNonce is bumped each time the user picks "Random".
            result = result.map { bookmark -> (Int, Bookmark) in
                var hasher = Hasher(); hasher.combine(bookmark.id); hasher.combine(shuffleNonce)
                return (hasher.finalize(), bookmark)
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
        }

        return result
    }

    // MARK: - Memo

    /// The filtered, sorted list and the tags in view, kept until something they depend on changes.
    /// The body runs for many reasons (selection, hover state, sheets, every search keystroke);
    /// re-filtering 1,000+ bookmarks each time made the app sluggish on large libraries.
    /// Any change to the library gives `allBookmarks` a new array (the query re-fetches), so a
    /// different array buffer invalidates the memo — edits are never shown stale.
    final class DisplayMemo {
        struct Key: Equatable {
            var library: UnsafeRawPointer?, count: Int
            var folders: UnsafeRawPointer?
            var selection: SidebarSelection, search: String, tags: Set<UUID>
            var sort: SortOption, nonce: Int
        }
        var key: Key?
        /// The arrays the key's addresses came from, kept alive so a freed buffer's address can't
        /// be reused by a new array with the same count (which would look unchanged).
        var sources: ([Bookmark], [Folder]) = ([], [])
        var bookmarks: [Bookmark] = []
        var tagIDs: Set<UUID> = []
        /// Position of each bookmark in `bookmarks`, by ID.
        var positions: [UUID: Int] = [:]
    }

    private func displayed() -> (bookmarks: [Bookmark], tagIDs: Set<UUID>) {
        let key = DisplayMemo.Key(
            library: allBookmarks.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) },
            count: allBookmarks.count,
            folders: allFolders.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) },
            selection: selection, search: appliedSearch, tags: selectedTagIDs,
            sort: sortOption, nonce: shuffleNonce
        )
        if displayMemo.key != key {
            let scoped = scopedBookmarks
            displayMemo.bookmarks = filteredAndSorted(scoped)
            displayMemo.tagIDs = Set(scoped.flatMap { $0.tags.map(\.id) })
            displayMemo.positions = Dictionary(displayMemo.bookmarks.enumerated().map { ($1.id, $0) },
                                               uniquingKeysWith: { first, _ in first })
            displayMemo.sources = (allBookmarks, allFolders)
            displayMemo.key = key
        }
        return (displayMemo.bookmarks, displayMemo.tagIDs)
    }

    /// The selected bookmarks in display order. Looked up by position instead of scanning the list:
    /// the body runs on every selection change, and reading `id` on thousands of SwiftData models
    /// made each click or arrow key cost ~70 ms at 5,000 bookmarks.
    private func selectedBookmarks() -> [Bookmark] {
        let bookmarks = displayed().bookmarks
        return selectedBookmarkIDs.compactMap { displayMemo.positions[$0] }.sorted().map { bookmarks[$0] }
    }

    // MARK: - Body

    var body: some View {
        // Filtering + sorting is computed once per render and shared below,
        // rather than re-running for every place that needs the list.
        let (bookmarks, scopedTagIDs) = displayed()
        // Only offer tags that exist in this view (plus any still selected), so no chip leads nowhere.
        let visibleTags = allTags.filter { scopedTagIDs.contains($0.id) || selectedTagIDs.contains($0.id) }

        HStack(spacing: 0) {
            // Main content area
            VStack(spacing: 0) {
                if !visibleTags.isEmpty {
                    tagFilterBar(tags: visibleTags)
                    Divider()
                }
                content(for: bookmarks)
                    // safeAreaInset (not overlay) so the last cards can scroll above the bar.
                    .safeAreaInset(edge: .bottom) {
                        let selected = selectedBookmarks()
                        if selected.count >= 2 {
                            selectionBar(selected: selected, all: bookmarks)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: selectedBookmarkIDs.count >= 2)
            }

            // Inline reader panel — slides in from the right, width is user-adjustable.
            // isAlive guards the render between a delete and the onChange below clearing it.
            if let bookmark = readerBookmark, bookmark.isAlive {
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
        .background { keyboardShortcuts() }
        .navigationTitle(navigationTitle)
        .searchable(text: $searchText, prompt: "Search \(navigationTitle)")
        .task(id: searchText) {
            // Clearing applies at once; typing applies after a short pause.
            if !searchText.isEmpty {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
            }
            appliedSearch = searchText
        }
        .searchFocused($isSearchFocused)
        // Lets File › Import Bookmarks… open the import sheet in this window.
        .focusedSceneValue(\.showingImport, $showingImport)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("View as Masonry (⌘1) or List (⌘2)")

                viewOptionsMenu

                if !bookmarks.isEmpty {
                    let shareTargets = selectedBookmarkIDs.isEmpty ? bookmarks : selectedBookmarks()
                    let shareTitle: String = {
                        if selectedBookmarkIDs.count == 1, let bm = shareTargets.first {
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
            }
        }
        .sheet(item: $managingBookmark) { bookmark in
            ManagePanelView(bookmark: bookmark)
        }
        #if DEBUG
        .task {
            guard ProfileDriver.isEnabled else { return }
            for await note in NotificationCenter.default.notifications(named: ProfileDriver.manageNotification) {
                // Fetched, not looked up in allBookmarks: this task captured the (empty) list of the first frame.
                if let id = note.object as? UUID {
                    managingBookmark = try? modelContext.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == id })).first
                }
            }
        }
        .task {
            guard ProfileDriver.isEnabled else { return }
            for await note in NotificationCenter.default.notifications(named: ProfileDriver.selectCardsNotification) {
                if let ids = note.object as? Set<UUID> { selectedBookmarkIDs = ids }
            }
        }
        #endif
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
            searchText = ""
            readerBookmark = nil
        }
        // Per-item view mode: restore on navigation (items never set keep the current mode),
        // remember whenever it changes — from the toolbar or the View menu.
        .onChange(of: selection, initial: true) {
            if let saved = ViewModeMemory(data: viewModeMemoryData).mode(for: selection) {
                viewMode = saved
            }
        }
        .onChange(of: viewMode) {
            var memory = ViewModeMemory(data: viewModeMemoryData)
            memory.remember(viewMode, for: selection)
            viewModeMemoryData = memory.data
        }
        // When reader is open and the user single-selects a different card, switch to it.
        .onChange(of: selectedBookmarkIDs) { _, newIDs in
            guard readerBookmark != nil,
                  newIDs.count == 1,
                  let id = newIDs.first,
                  let bm = selectedBookmarks().first, bm.id == id else { return }
            readerBookmark = bm
        }
        // Auto-open capture when a URL arrives from the Share Extension / deep link.
        // `initial: true` catches requests made before this view existed (window was closed).
        .onChange(of: captureRouter.pendingURL, initial: true) { _, newURL in
            if newURL != nil { showingCapture = true }
        }
        // Close the reader if its bookmark was deleted by any path (hover trash, context menu,
        // ⌘⌫, sync restore…). Compares persistentModelID, which is safe on deleted models.
        .onChange(of: allBookmarks.map(\.persistentModelID)) { _, liveIDs in
            if let reader = readerBookmark,
               !reader.isAlive || !liveIDs.contains(reader.persistentModelID) {
                readerBookmark = nil
            }
        }
        // Menu bar / File menu "Save Link…"
        .onChange(of: captureRouter.isCaptureRequested, initial: true) { _, requested in
            guard requested else { return }
            captureRouter.isCaptureRequested = false
            showingCapture = true
        }
    }

    // MARK: - Selection bar

    /// Floating actions for a multi-selection: makes bulk move/tag/delete visible instead of
    /// hidden behind right-click.
    private func selectionBar(selected: [Bookmark], all: [Bookmark]) -> some View {
        HStack(spacing: 14) {
            Text("\(selected.count) selected")
                .font(.callout.weight(.semibold))
                .monospacedDigit()

            Divider().frame(height: 16)

            BookmarkOrganizeMenu(targets: selected, folders: allFolders, tags: allTags, compact: true)
                .fixedSize()

            Button(role: .destructive) {
                selectedBookmarkIDs = []
                BookmarkBulkActions.delete(selected, from: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete selected (⌘⌫) — ⌘Z to undo")

            Divider().frame(height: 16)

            if selected.count < all.count {
                Button("Select All") { selectedBookmarkIDs = Set(all.map(\.id)) }
                    .help("Select all (⌘A)")
            }
            Button("Done") { selectedBookmarkIDs = [] }
                .help("Clear selection (Esc)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.separator, lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.bottom, 16)
    }

    // MARK: - Keyboard shortcuts

    /// Invisible buttons that exist only to carry key equivalents for the main window.
    /// Shortcuts that would clash with typing are disabled while the search field is focused.
    private func keyboardShortcuts() -> some View {
        let selected = selectedBookmarks()
        return Group {
            Button("Search") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)

            Button("Open Selected") { BookmarkBulkActions.open(selected) }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(selected.isEmpty)

            Button("Delete Selected") {
                if let reader = readerBookmark, selected.contains(where: { $0.id == reader.id }) {
                    readerBookmark = nil
                }
                selectedBookmarkIDs = []
                BookmarkBulkActions.delete(selected, from: modelContext)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selected.isEmpty || isSearchFocused)

            // Esc steps back: close the reader first, then clear the selection.
            Button("Dismiss") {
                if readerBookmark != nil { readerBookmark = nil }
                else { selectedBookmarkIDs = [] }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(isSearchFocused || (readerBookmark == nil && selectedBookmarkIDs.isEmpty))
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Toolbar

    /// Sort order + card size in one toolbar menu (card size also lives in the View menu).
    private var viewOptionsMenu: some View {
        Menu {
            Section("Sort By") {
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
            }
            if viewMode == .masonry {
                Section("Card Size") {
                    ForEach(CardSize.allCases, id: \.self) { size in
                        Button {
                            cardSizeScale = size.scale
                        } label: {
                            if CardSize.matching(cardSizeScale) == size {
                                Label(size.label, systemImage: "checkmark")
                            } else {
                                Text(size.label)
                            }
                        }
                    }
                }
            }
        } label: {
            Label("View Options", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort and card size")
    }

    // MARK: - Content area

    @ViewBuilder
    private func content(for bookmarks: [Bookmark]) -> some View {
        if bookmarks.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch viewMode {
            case .masonry:
                MasonryView(
                    bookmarks: bookmarks,
                    onManage: { managingBookmark = $0 },
                    onRead:   { readerBookmark   = $0 },
                    selectedIDs: $selectedBookmarkIDs,
                    showsUnfiledDot: selection == .all
                )
            case .list:
                BookmarkListView(
                    bookmarks: bookmarks,
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

    private func tagFilterBar(tags: [Tag]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags) { tag in
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
        FolderTree.subtreeIDs(rootID: rootID, in: allFolders)
    }

    @ViewBuilder
    private var emptyState: some View {
        if isFiltering {
            ContentUnavailableView {
                Label("No results", systemImage: "magnifyingglass")
            } description: {
                Text("Nothing matches your search or tag filter.")
            } actions: {
                Button("Clear Filters") {
                    searchText = ""
                    selectedTagIDs = []
                }
            }
        } else if selection == .inbox && !allBookmarks.isEmpty {
            // An empty Inbox in a non-empty library is an achievement, not a blank state.
            ContentUnavailableView(
                "All caught up",
                systemImage: "checkmark.circle",
                description: Text("Everything in your Inbox has been filed.")
            )
        } else {
            let isWishlist = selection == .wishlist
            ContentUnavailableView(
                "Nothing here yet",
                systemImage: isWishlist ? "cart" : "bookmark",
                description: Text(isWishlist
                    ? "Save your first wishlist item to get started."
                    : "Save your first link to get started.")
            )
        }
    }
}

// MARK: - Focused values

extension FocusedValues {
    /// The focused window's "import sheet shown" state — published by ContentAreaView,
    /// set by File › Import Bookmarks…
    @Entry var showingImport: Binding<Bool>?
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

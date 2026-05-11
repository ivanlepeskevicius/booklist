import SwiftUI
import SwiftData

struct ContentAreaView: View {
    let selection: SidebarSelection

    @Query(sort: \Bookmark.dateAdded, order: .reverse) private var allBookmarks: [Bookmark]
    @Query private var allFolders: [Folder]

    @State private var searchText     = ""
    @State private var sortOption     = SortOption.recent
    @State private var viewMode       = ViewMode.masonry
    @State private var managingBookmark: Bookmark?
    @State private var selectedBookmarkIDs: Set<UUID> = []

    @AppStorage("showTitleOnCards") private var showTitleOnCards = true
    @AppStorage("showDateOnCards")  private var showDateOnCards  = true

    // MARK: - Derived data

    private var navigationTitle: String {
        switch selection {
        case .inbox:          return "Inbox"
        case .all:            return "All"
        case .folder(let id): return allFolders.first { $0.id == id }?.name ?? "Folder"
        }
    }

    private var displayedBookmarks: [Bookmark] {
        // 1. Filter by sidebar selection
        var result: [Bookmark]
        switch selection {
        case .inbox:
            result = allBookmarks.filter { $0.collection == nil }
        case .all:
            result = allBookmarks
        case .folder(let id):
            result = allBookmarks.filter { $0.collection?.id == id }
        }

        // 2. Filter by search text
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) ||
                ($0.note?.lowercased().contains(q) == true) ||
                ($0.pageDescription?.lowercased().contains(q) == true) ||
                $0.url.lowercased().contains(q)
            }
        }

        // 3. Apply sort
        switch sortOption {
        case .recent:       break
        case .alphabetical: result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .random:       result.shuffle()
        }

        return result
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .navigationTitle(navigationTitle)
        .sheet(item: $managingBookmark) { bookmark in
            ManagePanelView(bookmark: bookmark)
        }
        // Clear selection when navigating to a different sidebar item.
        .onChange(of: selection) {
            selectedBookmarkIDs = []
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

            // Sort picker
            Menu {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        sortOption = option
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
            .frame(width: 100)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Content area

    @ViewBuilder
    private var content: some View {
        if displayedBookmarks.isEmpty {
            emptyState
        } else {
            switch viewMode {
            case .masonry:
                MasonryView(
                    bookmarks: displayedBookmarks,
                    onManage: { managingBookmark = $0 },
                    selectedIDs: $selectedBookmarkIDs
                )
            case .grid:
                GridView(
                    bookmarks: displayedBookmarks,
                    onManage: { managingBookmark = $0 },
                    selectedIDs: $selectedBookmarkIDs
                )
            case .list:
                BookmarkListView(
                    bookmarks: displayedBookmarks,
                    onManage: { managingBookmark = $0 },
                    selectedIDs: $selectedBookmarkIDs
                )
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            searchText.isEmpty ? "Nothing here yet" : "No results",
            systemImage: searchText.isEmpty ? "bookmark" : "magnifyingglass",
            description: Text(
                searchText.isEmpty
                ? "Save your first link to get started."
                : "Try a different search term."
            )
        )
    }
}

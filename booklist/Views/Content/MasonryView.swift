import SwiftUI
import SwiftData

/// Pinterest-style masonry layout: multiple columns of variable-height cards.
/// Items are distributed round-robin across columns for simplicity in Phase 1.
struct MasonryView: View {
    let bookmarks: [Bookmark]
    let onManage: (Bookmark) -> Void
    @Binding var selectedIDs: Set<UUID>

    @Environment(\.modelContext) private var modelContext

    private let columnCount = 3
    private let spacing: CGFloat = 12
    private let padding: CGFloat = 16

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(0..<columnCount, id: \.self) { col in
                    LazyVStack(spacing: spacing) {
                        ForEach(columnBookmarks(col)) { bookmark in
                            BookmarkCardView(
                                bookmark: bookmark,
                                onOpen:   { open(bookmark) },
                                onDelete: { delete(bookmark) },
                                onManage: { onManage(bookmark) },
                                thumbnailStyle: .fit,
                                isSelected: selectedIDs.contains(bookmark.id),
                                selectedIDs: selectedIDs,
                                onSelect: { cmdHeld in select(bookmark.id, cmdHeld: cmdHeld) }
                            )
                        }
                    }
                }
            }
            .padding(padding)
        }
    }

    private func columnBookmarks(_ col: Int) -> [Bookmark] {
        bookmarks
            .enumerated()
            .filter { $0.offset % columnCount == col }
            .map(\.element)
    }

    private func select(_ id: UUID, cmdHeld: Bool) {
        if cmdHeld {
            if selectedIDs.contains(id) { selectedIDs.remove(id) }
            else { selectedIDs.insert(id) }
        } else {
            selectedIDs = [id]
        }
    }

    private func open(_ bookmark: Bookmark) {
        guard let url = URL(string: bookmark.url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func delete(_ bookmark: Bookmark) {
        modelContext.delete(bookmark)
    }
}

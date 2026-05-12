import SwiftUI
import SwiftData

/// Pinterest-style masonry layout: multiple columns of variable-height cards.
/// Items are distributed round-robin across columns for simplicity in Phase 1.
struct MasonryView: View {
    let bookmarks: [Bookmark]
    let onManage: (Bookmark) -> Void
    let onRead: (Bookmark) -> Void
    @Binding var selectedIDs: Set<UUID>

    @Environment(\.modelContext) private var modelContext
    @AppStorage("cardSizeScale") private var cardSizeScale = 1.0
    @State private var availableWidth: CGFloat = 0

    private let spacing: CGFloat = 12
    private let padding: CGFloat = 16

    /// Fewer, wider columns = bigger cards; more, narrower columns = smaller cards.
    private var columnCount: Int {
        switch cardSizeScale {
        case ..<0.80: return 5
        case ..<0.95: return 4
        case ..<1.15: return 3  // default
        case ..<1.35: return 2
        default:      return 1
        }
    }

    private var columnWidth: CGFloat {
        guard availableWidth > 0 else { return 200 }
        return (availableWidth - padding * 2 - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
    }

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
                                onRead:   bookmark.itemType == .bookmark ? { onRead(bookmark) } : nil,
                                thumbnailStyle: .fit,
                                isSelected: selectedIDs.contains(bookmark.id),
                                selectedIDs: selectedIDs,
                                onSelect: { cmdHeld in select(bookmark.id, cmdHeld: cmdHeld) },
                                shareBookmarks: shareTargets(for: bookmark)
                            )
                        }
                    }
                    .frame(width: availableWidth > 0 ? columnWidth : nil)
                }
            }
            .padding(padding)
        }
        // Background GeometryReader reads the ScrollView's settled width without
        // participating in its layout pass, breaking the feedback loop that the
        // original GeometryReader wrapper caused (hanging the main thread 40–127s).
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: MasonryWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(MasonryWidthKey.self) { width in
            if width > 0 { availableWidth = width }
        }
    }

    /// Returns the bookmarks that should be shared when the context menu is invoked on `bookmark`.
    /// If the card is part of the current selection, shares all selected; otherwise just this one.
    private func shareTargets(for bookmark: Bookmark) -> [Bookmark] {
        selectedIDs.contains(bookmark.id)
            ? bookmarks.filter { selectedIDs.contains($0.id) }
            : [bookmark]
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
        bookmark.lastOpenedDate = Date()
        NSWorkspace.shared.open(url)
    }

    private func delete(_ bookmark: Bookmark) {
        modelContext.delete(bookmark)
    }
}

private struct MasonryWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

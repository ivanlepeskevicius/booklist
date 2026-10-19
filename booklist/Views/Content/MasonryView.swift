import SwiftUI
import SwiftData

/// True masonry (variable-height Pinterest-style columns).
/// Uses the Layout protocol to place each item in the shortest column.
/// Not lazy — all card sizes are measured upfront — but for personal-scale collections
/// this is imperceptible and gives correct column heights without grid-row uniformity.
struct MasonryView: View {
    let bookmarks: [Bookmark]
    let onManage: (Bookmark) -> Void
    let onRead: (Bookmark) -> Void
    @Binding var selectedIDs: Set<UUID>
    var showsUnfiledDot: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Query private var allFolders: [Folder]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @AppStorage("cardSizeScale") private var cardSizeScale = 1.0
    @State private var anchorID: UUID?
    /// The card arrow keys move from — the last one clicked or reached by keyboard.
    /// Separate from `anchorID` so Shift+arrow can grow the selection while the anchor stays put.
    @State private var leadID: UUID?
    @State private var cardFrames = CardFrames()
    @FocusState private var isFocused: Bool

    private let spacing: CGFloat = 12
    private let padding: CGFloat = 16
    private static let coordinateSpace = "masonry"

    /// Card frames for arrow-key navigation. A plain class (not @Observable) so layout
    /// updates don't trigger re-renders — the frames are only read on key presses.
    private final class CardFrames {
        var byID: [UUID: CGRect] = [:]
    }

    /// Fewer, wider columns = bigger cards; more, narrower columns = smaller cards.
    private var columnCount: Int { MasonryLayout.columnCount(for: cardSizeScale) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                cards
                    .coordinateSpace(.named(Self.coordinateSpace))
                    .padding(padding)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            // Arrow = move the selection; Shift+arrow = add the next card to it.
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                moveSelection(press.key, extending: press.modifiers.contains(.shift), proxy: proxy)
                return .handled
            }
            // Space = reader (like Quick Look), Return = open in browser — single selection only.
            .onKeyPress(.space) {
                guard let bookmark = singleSelected, bookmark.itemType == .bookmark else { return .ignored }
                onRead(bookmark)
                return .handled
            }
            .onKeyPress(.return) {
                guard let bookmark = singleSelected else { return .ignored }
                open(bookmark)
                return .handled
            }
        }
    }

    private var singleSelected: Bookmark? {
        guard selectedIDs.count == 1, let id = selectedIDs.first else { return nil }
        return bookmarks.first { $0.id == id }
    }

    private var cards: some View {
        MasonryLayout(columns: columnCount, spacing: spacing) {
            ForEach(bookmarks) { bookmark in
                BookmarkCardView(
                    bookmark: bookmark,
                    onOpen:   { open(bookmark) },
                    onDelete: { delete($0) },
                    onManage: { onManage(bookmark) },
                    onRead:   bookmark.itemType == .bookmark ? { onRead(bookmark) } : nil,
                    thumbnailStyle: .fit,
                    isSelected: selectedIDs.contains(bookmark.id),
                    selectedIDs: selectedIDs,
                    onSelect: { cmdHeld, shiftHeld in
                        select(bookmark.id, cmdHeld: cmdHeld, shiftHeld: shiftHeld)
                        isFocused = true   // so arrow keys work right after a click
                    },
                    shareBookmarks: shareTargets(for: bookmark),
                    showsUnfiledDot: showsUnfiledDot,
                    folders: allFolders,
                    tags: allTags
                )
                .id(bookmark.id)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(Self.coordinateSpace))
                } action: { frame in
                    cardFrames.byID[bookmark.id] = frame
                }
            }
        }
    }

    // MARK: - Keyboard navigation

    private func moveSelection(_ key: KeyEquivalent, extending: Bool, proxy: ScrollViewProxy) {
        let target: UUID?
        let lead = leadID.flatMap { selectedIDs.contains($0) ? $0 : nil }
            ?? (selectedIDs.count == 1 ? selectedIDs.first : nil)
        if let current = lead {
            let direction: MasonryNavigation.Direction = switch key {
            case .upArrow:   .up
            case .downArrow: .down
            case .leftArrow: .left
            default:         .right
            }
            // Only cards still on screen — frames of removed bookmarks may linger.
            let visibleIDs = Set(bookmarks.map(\.id))
            let frames = cardFrames.byID.filter { visibleIDs.contains($0.key) }
            target = MasonryNavigation.neighbor(of: current, direction: direction, frames: frames)
        } else {
            // Nothing selected yet — any arrow starts at the first card.
            target = bookmarks.first?.id
        }

        guard let target else { return }
        if extending {
            selectedIDs.insert(target)
            if anchorID == nil { anchorID = lead ?? target }
        } else {
            selectedIDs = [target]
            anchorID = target
        }
        leadID = target
        proxy.scrollTo(target)
    }

    /// Returns the bookmarks that should be shared when the context menu is invoked on `bookmark`.
    /// If the card is part of the current selection, shares all selected; otherwise just this one.
    private func shareTargets(for bookmark: Bookmark) -> [Bookmark] {
        selectedIDs.contains(bookmark.id)
            ? bookmarks.filter { selectedIDs.contains($0.id) }
            : [bookmark]
    }

    private func select(_ id: UUID, cmdHeld: Bool, shiftHeld: Bool) {
        leadID = id
        if shiftHeld, let anchor = anchorID,
           let anchorIdx = bookmarks.firstIndex(where: { $0.id == anchor }),
           let clickedIdx = bookmarks.firstIndex(where: { $0.id == id }) {
            let range = min(anchorIdx, clickedIdx)...max(anchorIdx, clickedIdx)
            let rangeIDs = Set(bookmarks[range].map(\.id))
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

    private func open(_ bookmark: Bookmark) {
        guard let url = URL(string: bookmark.url) else { return }
        bookmark.lastOpenedDate = Date()
        NSWorkspace.shared.open(url)
    }

    private func delete(_ targets: [Bookmark]) {
        selectedIDs.subtract(targets.map(\.id))
        BookmarkBulkActions.delete(targets, from: modelContext)
    }
}

// MARK: - Arrow-key navigation

/// Finds the visual neighbour of a card for arrow-key navigation. Masonry cards have
/// different heights, so "the card below" can't be derived from list order — it's
/// computed from the cards' on-screen frames instead.
enum MasonryNavigation {
    enum Direction { case up, down, left, right }

    /// Tolerance for frames that touch or differ only by rounding.
    private static let epsilon: CGFloat = 1

    static func neighbor(of id: UUID, direction: Direction, frames: [UUID: CGRect]) -> UUID? {
        guard let current = frames[id] else { return nil }
        let others = frames.filter { $0.key != id }

        switch direction {
        case .down:
            // Same column (horizontal overlap), below; nearest first.
            return others
                .filter { overlapsHorizontally($0.value, current) && $0.value.minY >= current.maxY - epsilon }
                .min { $0.value.minY < $1.value.minY }?.key
        case .up:
            return others
                .filter { overlapsHorizontally($0.value, current) && $0.value.maxY <= current.minY + epsilon }
                .max { $0.value.maxY < $1.value.maxY }?.key
        case .right:
            let candidates = others.filter { $0.value.minX >= current.maxX - epsilon }
            guard let nearestX = candidates.map(\.value.minX).min() else { return nil }
            return closestVertically(to: current, in: candidates.filter { abs($0.value.minX - nearestX) < epsilon })
        case .left:
            let candidates = others.filter { $0.value.maxX <= current.minX + epsilon }
            guard let nearestX = candidates.map(\.value.maxX).max() else { return nil }
            return closestVertically(to: current, in: candidates.filter { abs($0.value.maxX - nearestX) < epsilon })
        }
    }

    private static func overlapsHorizontally(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX - epsilon && a.maxX > b.minX + epsilon
    }

    /// Within the adjacent column, the card whose vertical centre is closest to the current one.
    private static func closestVertically(to current: CGRect, in candidates: [UUID: CGRect]) -> UUID? {
        candidates.min { abs($0.value.midY - current.midY) < abs($1.value.midY - current.midY) }?.key
    }
}

// MARK: - Masonry layout engine

/// Places subviews in the shortest available column at each step,
/// producing a true variable-height masonry arrangement.
struct MasonryLayout: Layout {
    let columns: Int
    let spacing: CGFloat

    struct Cache {
        var itemSizes: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard !subviews.isEmpty, let totalWidth = proposal.width, totalWidth > 0 else { return .zero }

        let colWidth = itemWidth(in: totalWidth)
        cache.itemSizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: colWidth, height: nil)) }

        var colHeights = [CGFloat](repeating: 0, count: columns)
        for size in cache.itemSizes {
            colHeights[shortestColumn(in: colHeights)] += size.height + spacing
        }

        return CGSize(width: totalWidth, height: max(0, (colHeights.max() ?? 0) - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard !subviews.isEmpty else { return }

        let colWidth = itemWidth(in: bounds.width)
        var colHeights = [CGFloat](repeating: bounds.minY, count: columns)

        let sizes = cache.itemSizes.count == subviews.count
            ? cache.itemSizes
            : subviews.map { $0.sizeThatFits(ProposedViewSize(width: colWidth, height: nil)) }

        for (idx, subview) in subviews.enumerated() {
            let col = shortestColumn(in: colHeights)
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(col) * (colWidth + spacing), y: colHeights[col]),
                proposal: ProposedViewSize(width: colWidth, height: sizes[idx].height)
            )
            colHeights[col] += sizes[idx].height + spacing
        }
    }

    func itemWidth(in totalWidth: CGFloat) -> CGFloat {
        (totalWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    func shortestColumn(in heights: [CGFloat]) -> Int {
        heights.indices.min(by: { heights[$0] < heights[$1] }) ?? 0
    }

    static func columnCount(for scale: Double) -> Int {
        switch scale {
        case ..<0.80: return 5
        case ..<0.95: return 4
        case ..<1.15: return 3
        case ..<1.35: return 2
        default:      return 1
        }
    }
}

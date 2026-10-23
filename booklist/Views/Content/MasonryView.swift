import SwiftUI
import SwiftData

/// Pinterest-style columns: each card goes into the currently shortest column.
///
/// Built to stay light on large libraries (measured: the old all-cards-up-front layout froze
/// for 20–80 s and peaked at 2.4 GB from 500 items up):
/// - **Lazy columns** — each column is a `LazyVStack`, so only cards near the screen exist.
/// - **Batches** — the columns hold `batchSize` cards and grow as the user nears the bottom,
///   so placement work is bounded by how far they scroll, not by the library size.
/// - Placement uses *estimated* card heights (image aspect read from the file header, text
///   lines from the font sizes), so cards can be placed before they're built.
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
    @AppStorage("showTitleOnCards") private var showTitleOnCards = true
    @AppStorage("showDateOnCards")  private var showDateOnCards  = true
    @AppStorage("cardTitleSize")    private var cardTitleSize    = 14.0
    @AppStorage("cardNoteSize")     private var cardNoteSize     = 12.0
    @State private var anchorID: UUID?
    /// The card arrow keys move from — the last one clicked or reached by keyboard.
    /// Separate from `anchorID` so Shift+arrow can grow the selection while the anchor stays put.
    @State private var leadID: UUID?
    @State private var shownCount = MasonryView.batchSize
    @State private var availableWidth: CGFloat = 0
    @State private var placementMemo = PlacementMemo()
    @FocusState private var isFocused: Bool

    static let batchSize = 150
    private let spacing: CGFloat = 12
    private let padding: CGFloat = 16

    /// Fewer, wider columns = bigger cards; more, narrower columns = smaller cards.
    private var columnCount: Int { MasonryLayout.columnCount(for: cardSizeScale) }

    private var layout: MasonryLayout { MasonryLayout(columns: columnCount, spacing: spacing) }

    private var cardWidth: CGFloat { max(1, layout.itemWidth(in: availableWidth - padding * 2)) }

    /// Placement depends on the cards and the display settings, not on the selection — and the
    /// body runs on every click and arrow key. Recomputing it each time read several properties of
    /// every loaded card (all of them once scrolled to the bottom of a large library).
    final class PlacementMemo {
        struct Key: Equatable {
            var library: UnsafeRawPointer?, count: Int, shown: Int, width: CGFloat, columns: Int
            var showsTitle: Bool, showsDate: Bool, titleSize: Double, noteSize: Double
        }
        var key: Key?
        var placement = MasonryLayout.Placement(columns: [], frames: [])
    }

    /// Column assignment and estimated frames for the cards in the current batch.
    private var placement: MasonryLayout.Placement {
        let key = PlacementMemo.Key(
            library: bookmarks.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) },
            count: bookmarks.count, shown: shownCount, width: cardWidth, columns: columnCount,
            showsTitle: showTitleOnCards, showsDate: showDateOnCards,
            titleSize: cardTitleSize, noteSize: cardNoteSize
        )
        if placementMemo.key != key {
            placementMemo.placement = computePlacement()
            placementMemo.key = key
        }
        return placementMemo.placement
    }

    private func computePlacement() -> MasonryLayout.Placement {
        let shown = bookmarks.prefix(shownCount)
        let width = cardWidth
        let heights = shown.map { bookmark in
            MasonryEstimate.cardHeight(
                width: width,
                imageAspect: bookmark.selectedImageURL.flatMap { ImageStore.aspectRatio(ofLocalImage: $0) },
                hasImage: bookmark.selectedImageURL != nil,
                title: showTitleOnCards ? bookmark.title : nil, titleSize: cardTitleSize,
                note: bookmark.itemType == .bookmark ? bookmark.note : nil, noteSize: cardNoteSize,
                showsDate: showDateOnCards
            )
        }
        return layout.place(heights: heights, itemWidth: width)
    }

    var body: some View {
        let placement = placement
        let shown = Array(bookmarks.prefix(shownCount))
        // Worked out once per render, not once per selected card.
        let selectedInOrder = selectedIDs.count > 1 ? bookmarks.filter { selectedIDs.contains($0.id) } : []
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(placement.columns.indices, id: \.self) { column in
                        LazyVStack(spacing: spacing) {
                            // Identified by bookmark, not position, so a card's state (its image)
                            // never ends up on a different bookmark after a delete or reorder.
                            ForEach(placement.columns[column].map { shown[$0] }) { bookmark in
                                card(for: bookmark, selectedInOrder: selectedInOrder)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                .padding(padding)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            // Next batch when the user is within two screens of the bottom.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height * 3 >= geometry.contentSize.height
            } action: { _, nearBottom in
                if nearBottom { loadMore() }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            // Edit › Select All / ⌘A while the grid has focus (text fields keep their own Select All).
            .onCommand(#selector(NSResponder.selectAll(_:))) {
                selectedIDs = Set(bookmarks.map(\.id))
            }
            // Arrow = move the selection; Shift+arrow = add the next card to it.
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                moveSelection(press.key, extending: press.modifiers.contains(.shift),
                              placement: placement, shown: shown, proxy: proxy)
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

    private func loadMore() {
        guard shownCount < bookmarks.count else { return }
        shownCount += Self.batchSize
    }

    private var singleSelected: Bookmark? {
        guard selectedIDs.count == 1, let id = selectedIDs.first else { return nil }
        return bookmarks.first { $0.id == id }
    }

    private func card(for bookmark: Bookmark, selectedInOrder: [Bookmark]) -> some View {
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
            shareBookmarks: shareTargets(for: bookmark, selectedInOrder: selectedInOrder),
            showsUnfiledDot: showsUnfiledDot,
            folders: allFolders,
            tags: allTags
        )
        .id(bookmark.id)
    }

    // MARK: - Keyboard navigation

    private func moveSelection(_ key: KeyEquivalent, extending: Bool, placement: MasonryLayout.Placement,
                               shown: [Bookmark], proxy: ScrollViewProxy) {
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
            // Estimated frames cover every card in the batch, built or not — lazy columns only
            // create the cards near the screen.
            var frames: [UUID: CGRect] = [:]
            for (index, frame) in placement.frames.enumerated() { frames[shown[index].id] = frame }
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
    private func shareTargets(for bookmark: Bookmark, selectedInOrder: [Bookmark]) -> [Bookmark] {
        selectedIDs.count > 1 && selectedIDs.contains(bookmark.id) ? selectedInOrder : [bookmark]
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

// MARK: - Placement

/// Column maths for the masonry: widths, shortest-column placement and estimated frames.
nonisolated struct MasonryLayout {
    let columns: Int
    let spacing: CGFloat

    struct Placement {
        /// Item indices per column, top to bottom.
        var columns: [[Int]]
        /// Estimated frame of each item, by index (for arrow-key navigation).
        var frames: [CGRect]
    }

    /// Greedy shortest-column placement — the classic masonry rule.
    func place(heights: [CGFloat], itemWidth: CGFloat) -> Placement {
        var placement = Placement(columns: Array(repeating: [], count: max(1, columns)), frames: [])
        var columnHeights = [CGFloat](repeating: 0, count: max(1, columns))
        placement.frames.reserveCapacity(heights.count)
        for (index, height) in heights.enumerated() {
            let column = shortestColumn(in: columnHeights)
            placement.columns[column].append(index)
            placement.frames.append(CGRect(x: CGFloat(column) * (itemWidth + spacing), y: columnHeights[column],
                                           width: itemWidth, height: height))
            columnHeights[column] += height + spacing
        }
        return placement
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

/// Estimates a card's height from its content, mirroring BookmarkCardView's layout: image at
/// its aspect ratio (≤ 500 pt) or a 100 pt placeholder, then title (≤ 2 lines), note (≤ 5
/// lines) and date with 10 pt padding. Only needs to be close — it decides which column a card
/// goes in, not the card's real size.
nonisolated enum MasonryEstimate {
    static let defaultImageAspect: CGFloat = 4.0 / 3.0

    static func cardHeight(width: CGFloat, imageAspect: CGFloat?, hasImage: Bool,
                           title: String?, titleSize: Double, note: String?, noteSize: Double,
                           showsDate: Bool) -> CGFloat {
        let image = hasImage ? min(500, width / max(0.1, imageAspect ?? defaultImageAspect)) : 100
        var lines: [CGFloat] = []
        if let title, !title.isEmpty { lines.append(textHeight(title, width: width - 20, fontSize: titleSize, maxLines: 2)) }
        if let note, !note.isEmpty { lines.append(textHeight(note, width: width - 20, fontSize: noteSize, maxLines: 5)) }
        if showsDate { lines.append(13) }
        guard !lines.isEmpty else { return image }
        return image + 20 + lines.reduce(0, +) + CGFloat(lines.count - 1) * 5
    }

    static func textHeight(_ text: String, width: CGFloat, fontSize: Double, maxLines: Int) -> CGFloat {
        let charsPerLine = max(1, Int(width / (fontSize * 0.52)))
        let wrapped = text.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, ($1.count + charsPerLine - 1) / charsPerLine) }
        return CGFloat(min(maxLines, wrapped)) * fontSize * 1.25
    }
}

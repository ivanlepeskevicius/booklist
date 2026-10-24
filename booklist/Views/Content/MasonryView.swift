import SwiftUI
import SwiftData

/// Pinterest-style columns: each card goes into the currently shortest column.
///
/// Virtualized by hand: every card's frame is worked out up front (`MasonryEstimate` — image
/// shape from the file header or an earlier load, text lines from the font sizes) and only the
/// cards near the visible area are built, each placed at exactly its frame (`CardFramesLayout`).
/// SwiftUI's lazy stacks were used before; they re-measured and re-placed every loaded card on
/// each layout pass, and with images arriving while scrolling that froze the app for 15–75 s
/// (tester, beta 1.2 (6); reproduced on a copy of a real library). A layout pass now costs the
/// cards on screen, whatever the library size, and no card changes size once it's shown.
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
    /// Width inside the padding, measured on the cards' container.
    @State private var availableWidth: CGFloat = 0
    @State private var placementMemo = PlacementMemo()
    /// The part of the content that has cards built, in `bandHeight` steps: it only changes every
    /// few hundred points of scrolling, so scrolling doesn't re-render the view on every pixel.
    @State private var builtBands = 0...4
    @FocusState private var isFocused: Bool

    private let spacing: CGFloat = 12
    private let padding: CGFloat = 16
    static let bandHeight: CGFloat = 400

    /// Fewer, wider columns = bigger cards; more, narrower columns = smaller cards.
    private var columnCount: Int { MasonryLayout.columnCount(for: cardSizeScale) }

    private var layout: MasonryLayout { MasonryLayout(columns: columnCount, spacing: spacing) }

    private var cardWidth: CGFloat { max(1, layout.itemWidth(in: availableWidth)) }

    /// Placement depends on the cards and the display settings, not on the selection or the scroll
    /// position — and the body runs on every click, arrow key and band of scrolling.
    final class PlacementMemo {
        struct Key: Equatable {
            var library: UnsafeRawPointer?, count: Int, width: CGFloat, columns: Int
            var showsTitle: Bool, showsDate: Bool, titleSize: Double, noteSize: Double
        }
        var key: Key?
        /// Kept alive so its address (in the key) can't be reused by a different array.
        var source: [Bookmark] = []
        var items: [CardItem] = []
        var contentHeight: CGFloat = 0
    }

    /// A card with its bookmark's ID and frame copied out — the view never reads SwiftData
    /// properties of cards that aren't built (each read is slow and change-tracked).
    struct CardItem: Identifiable {
        let id: UUID
        let bookmark: Bookmark
        let frame: CGRect
    }

    /// Every card with its frame, in list order.
    private var cardItems: [CardItem] {
        let key = PlacementMemo.Key(
            library: bookmarks.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) },
            count: bookmarks.count, width: cardWidth, columns: columnCount,
            showsTitle: showTitleOnCards, showsDate: showDateOnCards,
            titleSize: cardTitleSize, noteSize: cardNoteSize
        )
        if placementMemo.key != key {
            let frames = computePlacement().frames
            placementMemo.items = zip(bookmarks, frames).map { CardItem(id: $0.id, bookmark: $0, frame: $1) }
            placementMemo.contentHeight = frames.map(\.maxY).max() ?? 0
            placementMemo.source = bookmarks
            placementMemo.key = key
        }
        return placementMemo.items
    }

    private func computePlacement() -> MasonryLayout.Placement {
        let width = cardWidth
        let heights = bookmarks.map { bookmark in
            MasonryEstimate.cardHeight(
                width: width,
                imageAspect: bookmark.selectedImageURL.flatMap { ImageStore.knownAspectRatio(of: $0) },
                hasImage: bookmark.selectedImageURL != nil,
                title: showTitleOnCards ? bookmark.title : nil, titleSize: cardTitleSize,
                note: bookmark.itemType == .bookmark ? bookmark.note : nil, noteSize: cardNoteSize,
                showsDate: showDateOnCards
            )
        }
        return layout.place(heights: heights, itemWidth: width)
    }

    /// Bands of content (one screen above and below the visible part included) to build cards for.
    static func bands(forVisible rect: CGRect) -> ClosedRange<Int> {
        let low = Int(((rect.minY - rect.height) / bandHeight).rounded(.down))
        let high = Int(((rect.maxY + rect.height) / bandHeight).rounded(.down))
        return max(0, low)...max(0, low, high)
    }

    #if DEBUG
    /// Counters for the profiling driver (DIAGNOSTIC — remove).
    static var bodyCount = 0, bandChanges = 0, widthChanges = 0
    #endif

    var body: some View {
        #if DEBUG
        let _ = Self.bodyCount += 1
        #endif
        let items = cardItems
        let top = CGFloat(builtBands.lowerBound) * Self.bandHeight
        let bottom = CGFloat(builtBands.upperBound + 1) * Self.bandHeight
        let built = items.filter { $0.frame.maxY >= top && $0.frame.minY <= bottom }
        // Worked out once per render, not once per selected card.
        let selectedInOrder = selectedIDs.count > 1 ? items.filter { selectedIDs.contains($0.id) }.map(\.bookmark) : []
        ScrollViewReader { proxy in
            ScrollView {
                CardFramesLayout(frames: built.map(\.frame), height: placementMemo.contentHeight) {
                    // Identified by bookmark, not position, so a card's state (its image)
                    // never ends up on a different bookmark after a delete or reorder.
                    ForEach(built) { item in
                        card(for: item, selectedInOrder: selectedInOrder)
                            .id(item.id)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                    #if DEBUG
                    Self.widthChanges += 1
                    #endif
                    availableWidth = $0
                }
                .padding(padding)
            }
            .onScrollGeometryChange(for: ClosedRange<Int>.self) { geometry in
                Self.bands(forVisible: geometry.visibleRect.offsetBy(dx: 0, dy: -padding))
            } action: { _, bands in
                #if DEBUG
                Self.bandChanges += 1
                #endif
                builtBands = bands
            }
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            // Edit › Select All / ⌘A while the grid has focus (text fields keep their own Select All).
            .onCommand(#selector(NSResponder.selectAll(_:))) {
                selectedIDs = Set(items.map(\.id))
            }
            // Arrow = move the selection; Shift+arrow = add the next card to it.
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                moveSelection(press.key, extending: press.modifiers.contains(.shift), items: items, proxy: proxy)
                return .handled
            }
            // Space = reader (like Quick Look), Return = open in browser — single selection only.
            .onKeyPress(.space) {
                guard let bookmark = singleSelected(in: items), bookmark.itemType == .bookmark else { return .ignored }
                onRead(bookmark)
                return .handled
            }
            .onKeyPress(.return) {
                guard let bookmark = singleSelected(in: items) else { return .ignored }
                open(bookmark)
                return .handled
            }
        }
    }

    private func singleSelected(in items: [CardItem]) -> Bookmark? {
        guard selectedIDs.count == 1, let id = selectedIDs.first else { return nil }
        return items.first { $0.id == id }?.bookmark
    }

    private func card(for item: CardItem, selectedInOrder: [Bookmark]) -> some View {
        let bookmark = item.bookmark
        return BookmarkCardView(
            bookmark: bookmark,
            onOpen:   { open(bookmark) },
            onDelete: { delete($0) },
            onManage: { onManage(bookmark) },
            onRead:   bookmark.itemType == .bookmark ? { onRead(bookmark) } : nil,
            thumbnailStyle: .fit,
            isSelected: selectedIDs.contains(item.id),
            selectedIDs: selectedIDs,
            onSelect: { cmdHeld, shiftHeld in
                select(item.id, cmdHeld: cmdHeld, shiftHeld: shiftHeld)
                isFocused = true   // so arrow keys work right after a click
            },
            shareBookmarks: shareTargets(for: item, selectedInOrder: selectedInOrder),
            showsUnfiledDot: showsUnfiledDot,
            folders: allFolders,
            tags: allTags,
            fixedHeight: item.frame.height
        )
    }

    // MARK: - Keyboard navigation

    private func moveSelection(_ key: KeyEquivalent, extending: Bool, items: [CardItem], proxy: ScrollViewProxy) {
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
            // Every card has a frame, built or not — only the cards near the screen are built.
            var frames: [UUID: CGRect] = [:]
            for item in items { frames[item.id] = item.frame }
            target = MasonryNavigation.neighbor(of: current, direction: direction, frames: frames)
        } else {
            // Nothing selected yet — any arrow starts at the first card.
            target = items.first?.id
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
        // The neighbour is next to a card on screen, so it's within the built area.
        proxy.scrollTo(target)
    }

    /// Returns the bookmarks that should be shared when the context menu is invoked on `bookmark`.
    /// If the card is part of the current selection, shares all selected; otherwise just this one.
    private func shareTargets(for item: CardItem, selectedInOrder: [Bookmark]) -> [Bookmark] {
        selectedIDs.count > 1 && selectedIDs.contains(item.id) ? selectedInOrder : [item.bookmark]
    }

    private func select(_ id: UUID, cmdHeld: Bool, shiftHeld: Bool) {
        leadID = id
        let items = cardItems
        if shiftHeld, let anchor = anchorID,
           let anchorIdx = items.firstIndex(where: { $0.id == anchor }),
           let clickedIdx = items.firstIndex(where: { $0.id == id }) {
            let range = min(anchorIdx, clickedIdx)...max(anchorIdx, clickedIdx)
            let rangeIDs = Set(items[range].map(\.id))
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

/// Places each card at its precomputed frame (same order as the subviews). Its height is the
/// whole masonry's, so the scroll view knows the full length even though few cards are built.
struct CardFramesLayout: Layout {
    let frames: [CGRect]
    let height: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? frames.map(\.maxX).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
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
        // Same result as wrapping every paragraph, but stops once `maxLines` is reached and never
        // counts more of a paragraph than fits — this runs for every card on every library change,
        // and counting whole long notes character by character was a measurable part of a save.
        let cap = charsPerLine * maxLines
        var wrapped = 0
        var rest = Substring(text)
        while wrapped < maxLines {
            // A paragraph with no line break in its first `cap` characters fills the card alone.
            let window = rest.prefix(cap + 1)
            guard let end = window.firstIndex(of: "\n") else {
                wrapped += max(1, (min(window.count, cap) + charsPerLine - 1) / charsPerLine)
                break
            }
            let length = rest.distance(from: rest.startIndex, to: end)
            wrapped += max(1, (length + charsPerLine - 1) / charsPerLine)
            rest = rest[rest.index(after: end)...]
        }
        return CGFloat(min(maxLines, wrapped)) * fontSize * 1.25
    }
}

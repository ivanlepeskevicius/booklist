import SwiftUI

/// How the thumbnail image is sized on a card.
enum CardThumbnailStyle {
    /// Crop-to-fill at a fixed height — used in the uniform grid.
    case fill
    /// Scale-to-fit at natural aspect ratio — used in masonry so cards have different heights.
    case fit
}

/// A single bookmark card used in masonry and grid layouts.
struct BookmarkCardView: View {
    let bookmark: Bookmark
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onManage: () -> Void
    /// Called when the user wants to open the reader view. nil = reader not available (wishlist items).
    var onRead: (() -> Void)? = nil
    var thumbnailStyle: CardThumbnailStyle = .fill
    /// Whether this card is part of the current selection.
    var isSelected: Bool = false
    /// The full set of selected IDs — used to build the multi-item drag payload.
    var selectedIDs: Set<UUID> = []
    /// Called on tap. Bool = was ⌘ held? (true → toggle, false → select only this).
    var onSelect: (Bool) -> Void = { _ in }
    /// The bookmarks to export when "Share" is chosen from the context menu.
    /// If this card is part of a selection, callers pass all selected bookmarks.
    var shareBookmarks: [Bookmark] = []

    @State private var isHovered         = false
    @State private var showDeleteConfirm = false

    @AppStorage("showTitleOnCards")   private var showTitleOnCards   = true
    @AppStorage("showDateOnCards")    private var showDateOnCards    = true
    @AppStorage("cardFontDesign")     private var cardFontDesign     = "system"
    @AppStorage("cardFontName")       private var cardFontName       = ""
    @AppStorage("cardTitleSize")      private var cardTitleSize      = 14.0
    @AppStorage("cardNoteSize")       private var cardNoteSize       = 12.0
    @AppStorage("staleDaysThreshold") private var staleDaysThreshold = 90

    private var fontDesign: Font.Design {
        switch cardFontDesign {
        case "rounded":    return .rounded
        case "serif":      return .serif
        case "monospaced": return .monospaced
        default:           return .default
        }
    }

    private func resolvedFont(size: CGFloat) -> Font {
        if !cardFontName.isEmpty {
            return .custom(cardFontName, size: size)
        }
        return .system(size: size, design: fontDesign)
    }

    /// True when a categorised item hasn't been opened within the user-configured threshold.
    private var isStale: Bool {
        guard bookmark.collection != nil else { return false }
        let threshold = Double(staleDaysThreshold) * 86_400
        let reference = bookmark.lastOpenedDate ?? bookmark.dateAdded
        return Date().timeIntervalSince(reference) > threshold
    }

    // Drag payload: all selected IDs when dragging a selected card, just this one otherwise.
    private var dragPayload: BookmarkTransfer {
        isSelected
            ? BookmarkTransfer(ids: Array(selectedIDs))
            : BookmarkTransfer(ids: [bookmark.id])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail
                .overlay(alignment: .topLeading) {
                    if bookmark.itemType == .wishlistItem {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.accentColor, in: Circle())
                            .padding(8)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if bookmark.itemType == .wishlistItem,
                       let price = bookmark.price, !price.isEmpty {
                        Text(price)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                            .padding(8)
                    }
                }
            if hasCardBody {
                cardBody
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Base border
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 0.5)
        }
        // Selection ring on top of the border
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .shadow(
            color: .black.opacity(isHovered ? 0.14 : 0.06),
            radius: isHovered ? 10 : 4,
            y: isHovered ? 4 : 2
        )
        // Status dot — mutually exclusive states share the same corner position:
        //   Red    = uncategorised (needs to be filed)
        //   Yellow = categorised but not opened in staleDaysThreshold days
        .overlay(alignment: .topTrailing) {
            if bookmark.collection == nil {
                Circle()
                    .fill(.red)
                    .frame(width: 9, height: 9)
                    .overlay { Circle().stroke(.background, lineWidth: 2) }
                    .padding(6)
            } else if isStale {
                Circle()
                    .fill(.yellow)
                    .frame(width: 9, height: 9)
                    .overlay { Circle().stroke(.background, lineWidth: 2) }
                    .padding(6)
            }
        }
        .overlay(alignment: .top) {
            if isHovered { hoverOverlay }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        // Tap selects the card; buttons in the hover overlay consume their own taps.
        .onTapGesture {
            let cmdHeld = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
            onSelect(cmdHeld)
        }
        .contextMenu { cardContextMenu }
        .draggable(dragPayload)
        .confirmationDialog(
            "Delete \"\(bookmark.title)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var cardContextMenu: some View {
        if let onRead {
            Button("Open in Reader") { onRead() }
        }
        Button("Open in Browser") { onOpen() }
        Divider()
        Button("Edit") { onManage() }
        let targets = shareBookmarks.isEmpty ? [bookmark] : shareBookmarks
        let shareTitle = targets.count == 1 ? targets[0].title : "\(targets.count) Items"
        ShareLink(
            item: BookmarksExport(bookmarks: targets, title: shareTitle),
            preview: SharePreview(shareTitle)
        ) {
            Label(targets.count == 1 ? "Share" : "Share \(targets.count) Items",
                  systemImage: "square.and.arrow.up")
        }
        Divider()
        Button("Delete", role: .destructive) { showDeleteConfirm = true }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnail: some View {
        if let urlString = bookmark.selectedImageURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    switch thumbnailStyle {
                    case .fill:
                        // Fixed height only — width comes from the parent (grid cell /
                        // LazyVStack column). Avoid maxWidth:.infinity inside the closure:
                        // AsyncImage does not reliably propagate the parent's width proposal
                        // into its phase closure, causing the image to resolve to an
                        // unbounded width and overflow the card at narrow column widths.
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 160)
                            .clipped()
                    case .fit:
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 500)
                            .clipped()
                    }
                default:
                    placeholderImage
                }
            }
            // Hard cap on the wrapper itself: second defensive layer in case the
            // inner frame is bypassed before layout settles.
            .frame(maxWidth: .infinity, maxHeight: thumbnailStyle == .fill ? 160 : 500)
            .clipped()
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let favURLStr = bookmark.faviconURL,
               let favURL = URL(string: favURLStr) {
                AsyncImage(url: favURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    placeholderIcon
                }
                .frame(width: 28, height: 28)
            } else {
                placeholderIcon
            }
        }
        .frame(height: 100)
    }

    private var placeholderIcon: some View {
        Image(systemName: "link")
            .font(.title2)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Card body

    private var hasCardBody: Bool {
        showTitleOnCards || bookmark.note != nil || showDateOnCards
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            if showTitleOnCards {
                Text(bookmark.title)
                    .font(resolvedFont(size: cardTitleSize))
                    .fontWeight(.medium)
                    .lineLimit(2)
            }

            if let note = bookmark.note, !note.isEmpty {
                Text(note)
                    .font(resolvedFont(size: cardNoteSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

            Spacer(minLength: 0)

            if showDateOnCards {
                Text(bookmark.dateAdded.formatted(date: .abbreviated, time: .omitted))
                    .font(resolvedFont(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
    }

    // MARK: - Hover overlay

    private var hoverOverlay: some View {
        HStack(spacing: 6) {
            if let onRead {
                actionButton("eyeglasses", "Reader view", action: onRead)
            }
            actionButton("arrow.up.right.square", "Open",   action: onOpen)
            actionButton("slider.horizontal.3",   "Edit",   action: onManage)
            actionButton("trash",                 "Delete") { showDeleteConfirm = true }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(8)
    }

    private func actionButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 32)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

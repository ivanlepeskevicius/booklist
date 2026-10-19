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
    /// Deletes the given bookmarks — just this card from the hover button, the whole selection from the context menu.
    let onDelete: ([Bookmark]) -> Void
    let onManage: () -> Void
    /// Called when the user wants to open the reader view. nil = reader not available (wishlist items).
    var onRead: (() -> Void)? = nil
    var thumbnailStyle: CardThumbnailStyle = .fill
    /// Whether this card is part of the current selection.
    var isSelected: Bool = false
    /// The full set of selected IDs — used to build the multi-item drag payload.
    var selectedIDs: Set<UUID> = []
    /// Called on tap. First Bool = ⌘ held, second = ⇧ held.
    var onSelect: (Bool, Bool) -> Void = { _, _ in }
    /// The bookmarks to export when "Share" is chosen from the context menu.
    /// If this card is part of a selection, callers pass all selected bookmarks.
    var shareBookmarks: [Bookmark] = []
    /// Show the "not in a folder" dot. Only useful where filed and unfiled items are mixed (the All view).
    var showsUnfiledDot: Bool = false
    /// Offered in the context menu's "Move to Folder" / "Tags" submenus.
    var folders: [Folder] = []
    var tags: [Tag] = []

    @State private var isHovered         = false
    @State private var thumbnailImage: NSImage?
    /// Width ÷ height of the last loaded image. Kept after the image is released off-screen
    /// so the card keeps its height and the masonry layout doesn't jump.
    @State private var thumbnailAspect: CGFloat?
    @State private var isOnScreen = false

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
                        Image(systemName: "cart.fill")
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
                // Bottom-leading is the one free corner: cart badge is top-left, price bottom-right,
                // status dot top-right, hover actions top-centre.
                .overlay(alignment: .bottomLeading) {
                    if showsSelectionCheck { selectionCheck }
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
        //   Accent = uncategorised (needs to be filed) — only when showsUnfiledDot
        //   Yellow = categorised but not opened in staleDaysThreshold days
        .overlay(alignment: .topTrailing) {
            if bookmark.collection == nil {
                if showsUnfiledDot {
                    statusDot(.accentColor, help: "Not in a folder yet")
                }
            } else if isStale {
                statusDot(.yellow, help: "Not opened in over \(staleDaysThreshold) days")
            }
        }
        .overlay(alignment: .top) {
            if isHovered { hoverOverlay }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        // Tap selects the card; buttons in the hover overlay consume their own taps.
        .onTapGesture {
            let flags     = NSApp.currentEvent?.modifierFlags ?? []
            let cmdHeld   = flags.contains(.command)
            let shiftHeld = flags.contains(.shift)
            onSelect(cmdHeld, shiftHeld)
        }
        .contextMenu { cardContextMenu }
        .draggable(dragPayload)
    }

    // MARK: - Selection checkmark

    /// Shown on hover and on selected cards, so multi-select works without ⌘/⇧ — like Photos.
    private var showsSelectionCheck: Bool { isHovered || isSelected }

    private var selectionCheck: some View {
        Button {
            onSelect(true, false)   // same as ⌘-click: toggle this card, keep the rest
        } label: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white, isSelected ? Color.accentColor : .white)
                .background(Circle().fill(.black.opacity(isSelected ? 0 : 0.25)))
                .shadow(color: .black.opacity(0.3), radius: 2)
        }
        .buttonStyle(.plain)
        .padding(8)
        .help(isSelected ? "Deselect" : "Select")
    }

    private func statusDot(_ color: Color, help: String) -> some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay { Circle().stroke(.background, lineWidth: 2) }
            .padding(6)
            .help(help)
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

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let image = thumbnailImage {
                switch thumbnailStyle {
                case .fill:
                    Image(nsImage: image).resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 160)
                        .clipped()
                case .fit:
                    Image(nsImage: image).resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 500)
                        .clipped()
                }
            } else if bookmark.selectedImageURL != nil, let aspect = thumbnailAspect {
                // Image released while off-screen — hold its exact size.
                Rectangle().fill(.quaternary)
                    .aspectRatio(aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: thumbnailStyle == .fill ? 160 : 500)
            } else {
                placeholderImage
            }
        }
        // Hard cap so a wide image can never overflow the card at narrow column widths.
        .frame(maxWidth: .infinity, maxHeight: thumbnailStyle == .fill ? 160 : 500)
        .clipped()
        .onScrollVisibilityChange(threshold: 0.01) { isOnScreen = $0 }
        // nil while off-screen, which releases the decoded image; masonry builds every card
        // up front, so without this memory would grow with the size of the library.
        .task(id: isOnScreen ? bookmark.selectedImageURL : nil) { await loadThumbnail() }
    }

    /// Loads the card image downsampled to card size (cached), instead of decoding it at full resolution.
    private func loadThumbnail() async {
        guard isOnScreen,
              let urlString = bookmark.selectedImageURL,
              let url = URL(string: urlString) else {
            thumbnailImage = nil
            return
        }
        let image = await ImageStore.thumbnail(for: url, maxPixelSize: 800)
        guard !Task.isCancelled else { return }
        thumbnailImage = image
        if let image, image.size.height > 0 {
            thumbnailAspect = image.size.width / image.size.height
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

    /// Wishlist cards stay minimal (image + price + title) — notes are hidden to reduce clutter (W5).
    private var visibleNote: String? {
        guard bookmark.itemType == .bookmark,
              let note = bookmark.note, !note.isEmpty else { return nil }
        return note
    }

    private var hasCardBody: Bool {
        showTitleOnCards || visibleNote != nil || showDateOnCards
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            if showTitleOnCards {
                Text(bookmark.title)
                    .font(resolvedFont(size: cardTitleSize))
                    .fontWeight(.medium)
                    .lineLimit(2)
            }

            if let note = visibleNote {
                Text(note)
                    .font(resolvedFont(size: cardNoteSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

            if showDateOnCards {
                Text(bookmark.dateAdded.formatted(date: .abbreviated, time: .omitted))
                    .font(resolvedFont(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
    }

    // MARK: - Hover overlay

    private struct HoverAction {
        let icon: String
        let label: String
        var color: Color = .primary
        let action: () -> Void
    }

    private var hoverActions: [HoverAction] {
        var actions: [HoverAction] = []
        if let onRead {
            actions.append(HoverAction(icon: "eyeglasses", label: "Reader view", action: onRead))
        }
        actions.append(HoverAction(icon: "arrow.up.right.square", label: "Open", action: onOpen))
        actions.append(HoverAction(icon: "slider.horizontal.3", label: "Edit", action: onManage))
        actions.append(HoverAction(icon: "trash", label: "Delete (⌘Z to undo)", color: .red) { onDelete([bookmark]) })
        return actions
    }

    /// Centred at the top of the card. ViewThatFits picks the largest layout that fits the card's
    /// width, so the bar never spills outside narrow cards (5 columns / small windows).
    private var hoverOverlay: some View {
        let actions = hoverActions
        let firstRow = (actions.count + 1) / 2
        return ViewThatFits(in: .horizontal) {
            hoverBar(inset: 8) { actionRow(actions, size: 32, spacing: 6) }
            hoverBar(inset: 5) { actionRow(actions, size: 26, spacing: 4) }
            hoverBar(inset: 5) {
                VStack(spacing: 4) {
                    actionRow(Array(actions.prefix(firstRow)), size: 26, spacing: 4)
                    actionRow(Array(actions.dropFirst(firstRow)), size: 26, spacing: 4)
                }
            }
        }
    }

    private func hoverBar(inset: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(inset)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(inset)
    }

    private func actionRow(_ actions: [HoverAction], size: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(actions.indices, id: \.self) { index in
                actionButton(actions[index], size: size)
            }
        }
    }

    private func actionButton(_ item: HoverAction, size: CGFloat) -> some View {
        Button(action: item.action) {
            Image(systemName: item.icon)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(item.color)
                .frame(width: size, height: size)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(item.label)
    }
}

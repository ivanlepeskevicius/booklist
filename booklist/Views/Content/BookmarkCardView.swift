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
    var thumbnailStyle: CardThumbnailStyle = .fill
    /// Whether this card is part of the current selection.
    var isSelected: Bool = false
    /// The full set of selected IDs — used to build the multi-item drag payload.
    var selectedIDs: Set<UUID> = []
    /// Called on tap. Bool = was ⌘ held? (true → toggle, false → select only this).
    var onSelect: (Bool) -> Void = { _ in }

    @State private var isHovered         = false
    @State private var showDeleteConfirm = false

    @AppStorage("showTitleOnCards") private var showTitleOnCards = true
    @AppStorage("showDateOnCards")  private var showDateOnCards  = true

    // Drag payload: all selected IDs when dragging a selected card, just this one otherwise.
    private var dragPayload: BookmarkTransfer {
        isSelected
            ? BookmarkTransfer(ids: Array(selectedIDs))
            : BookmarkTransfer(ids: [bookmark.id])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail
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
                    .strokeBorder(.accentColor, lineWidth: 2)
            }
        }
        .shadow(
            color: .black.opacity(isHovered ? 0.14 : 0.06),
            radius: isHovered ? 10 : 4,
            y: isHovered ? 4 : 2
        )
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
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(minHeight: 120, maxHeight: 180)
                            .clipped()
                    case .fit:
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                    }
                default:
                    placeholderImage
                }
            }
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
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
            }

            if let note = bookmark.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

            if showDateOnCards {
                Text(bookmark.dateAdded.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
    }

    // MARK: - Hover overlay

    private var hoverOverlay: some View {
        HStack(spacing: 6) {
            actionButton("arrow.up.right.square", "Open",   action: onOpen)
            actionButton("trash",                 "Delete") { showDeleteConfirm = true }
            actionButton("slider.horizontal.3",   "Edit",   action: onManage)
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

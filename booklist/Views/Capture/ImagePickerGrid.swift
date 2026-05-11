import SwiftUI

/// A grid of thumbnail images where exactly one can be selected.
/// Shows the first 6 images by default; a "Show more" button reveals the rest.
/// Set `scrollable: false` when embedded inside a Form/List that provides its own scrolling.
struct ImagePickerGrid: View {
    let imageURLs: [String]
    @Binding var selectedURL: String?
    var scrollable: Bool = true

    @State private var showAll = false

    private let pageSize = 6
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        let visibleURLs = showAll ? imageURLs : Array(imageURLs.prefix(pageSize))
        let remaining   = imageURLs.count - pageSize

        let content = VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(visibleURLs, id: \.self) { urlString in
                    ImagePickerCell(
                        urlString: urlString,
                        isSelected: selectedURL == urlString
                    ) {
                        selectedURL = urlString
                    }
                }
            }
            .padding(2) // room for selection border

            if !showAll && remaining > 0 {
                Button("Show \(remaining) more…") { showAll = true }
                    .font(.caption)
                    .buttonStyle(.link)
                    .padding(.leading, 2)
            }
        }

        if scrollable {
            ScrollView { content }.frame(maxHeight: 220)
        } else {
            content
        }
    }
}

// MARK: - Single cell

private struct ImagePickerCell: View {
    let urlString: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail — Color.clear owns the layout frame; AsyncImage goes in an
                // overlay so its natural (fill-mode) size never affects row height.
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 80)
                    .overlay {
                        AsyncImage(url: URL(string: urlString)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                ZStack {
                                    Rectangle().fill(.quaternary)
                                    Image(systemName: "photo")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
                }

                // Selection checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.system(size: 16, weight: .bold))
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.1), value: isSelected)
    }
}

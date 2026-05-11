import SwiftUI

/// A scrollable grid of thumbnail images where exactly one can be selected.
struct ImagePickerGrid: View {
    let imageURLs: [String]
    @Binding var selectedURL: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(imageURLs, id: \.self) { urlString in
                    ImagePickerCell(
                        urlString: urlString,
                        isSelected: selectedURL == urlString
                    ) {
                        selectedURL = urlString
                    }
                }
            }
            .padding(2) // room for selection border
        }
        .frame(maxHeight: 220)
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
                // Thumbnail
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
                .frame(height: 80)
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

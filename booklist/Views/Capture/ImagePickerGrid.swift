import SwiftUI
import AppKit

/// A grid of thumbnail images where exactly one can be selected.
/// Shows the first 6 images by default; a "Show more" button reveals the rest.
/// Set `scrollable: false` when embedded inside a Form/List that provides its own scrolling.
struct ImagePickerGrid: View {
    let imageURLs: [String]
    @Binding var selectedURL: String?
    var scrollable: Bool = true

    @State private var showAll    = false
    @State private var failedURLs: Set<String> = []

    private let pageSize = 6
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var validURLs: [String] { imageURLs.filter { !failedURLs.contains($0) } }

    var body: some View {
        let visibleURLs = showAll ? validURLs : Array(validURLs.prefix(pageSize))
        let remaining   = validURLs.count - pageSize

        let content = VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(visibleURLs, id: \.self) { urlString in
                    ImagePickerCell(
                        urlString: urlString,
                        isSelected: selectedURL == urlString,
                        onSelect: { selectedURL = urlString },
                        onFail: {
                            failedURLs.insert(urlString)
                            if selectedURL == urlString {
                                selectedURL = validURLs.first { !failedURLs.contains($0) }
                            }
                        }
                    )
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
            ScrollView { content }.frame(maxHeight: 320)
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
    let onFail: () -> Void

    @State private var loadedImage: NSImage?
    @State private var isLoading  = true
    @State private var hasFailed  = false

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120)
                    .background(.quaternary)
                    .overlay {
                        if let img = loadedImage {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else if isLoading {
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
                    }

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
        .task(id: urlString) { await load() }
    }

    @MainActor
    private func load() async {
        isLoading   = true
        loadedImage = nil
        guard let url = URL(string: urlString),
              let image = await ImageStore.thumbnail(for: url, maxPixelSize: 400)
        else { fail(); return }

        // Reject images that are too small to look sharp on a Retina display.
        // A 120pt cell at 2× scale needs 240 source pixels in at least one dimension;
        // below that the image would be upscaled and appear blurry.
        // Thumbnails are never upscaled, so the thumbnail's size reflects the original here.
        guard max(image.size.width, image.size.height) >= 240 else { fail(); return }

        loadedImage = image
        isLoading   = false
    }

    private func fail() {
        isLoading = false
        guard !hasFailed else { return }
        hasFailed = true
        onFail()
    }
}

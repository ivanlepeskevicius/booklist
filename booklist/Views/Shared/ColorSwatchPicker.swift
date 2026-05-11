import SwiftUI

/// A swatch grid of curated colors plus a native ColorPicker row for any custom color.
/// Used in both the tag settings row (as popover content) and the folder form (inline).
/// Binding is a hex string so it works directly with Tag.color and Folder.color.
struct ColorSwatchPicker: View {
    @Binding var colorHex: String

    private let columns = Array(repeating: GridItem(.fixed(28), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Tag.palette, id: \.self) { hex in
                    swatchButton(hex: hex)
                }
            }

            Divider()

            // Full-width row that opens the macOS color panel for any custom color.
            HStack(spacing: 8) {
                Label("Custom color…", systemImage: "eyedropper")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { Color(hex: colorHex) },
                        set: { newColor in colorHex = newColor.toHex() ?? "#8B8B8B" }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 28, height: 28)
            }
            .padding(8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func swatchButton(hex: String) -> some View {
        let isSelected = colorHex.lowercased() == hex.lowercased()
        return Button {
            colorHex = hex
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 28, height: 28)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

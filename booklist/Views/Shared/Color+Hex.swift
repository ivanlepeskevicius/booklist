import SwiftUI
import AppKit

// MARK: - Focus ring modifier

extension View {
    /// Overlays a 1.5 pt accent-coloured border when `isFocused` is true.
    /// Apply this to the container wrapping a `.textFieldStyle(.plain)` field.
    func focusRing(when isFocused: Bool, cornerRadius: CGFloat = 8) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    isFocused ? Color.accentColor.opacity(0.75) : Color.clear,
                    lineWidth: 1.5
                )
        }
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

extension Color {
    /// Initialise a Color from a hex string such as "#FF6B6B" or "FF6B6B".
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  // #RGB
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  // #RRGGBB
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // #AARRGGBB
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 128, 128, 128)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Converts this Color to a "#RRGGBB" hex string. Returns nil if the color space conversion fails.
    func toHex() -> String? {
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

import Foundation
import SwiftData

@Model
final class Tag {
    var id: UUID
    var name: String
    var color: String   // hex string, e.g. "#FF6B6B"

    @Relationship(inverse: \Bookmark.tags)
    var bookmarks: [Bookmark]

    init(name: String, color: String = "#8B8B8B") {
        self.id = UUID()
        self.name = name
        self.color = color
        self.bookmarks = []
    }

    /// Curated palette of 28 colors — 4 rows × 7 columns.
    /// Arranged warm → cool → deep → soft/neutral so the grid reads naturally.
    static let palette: [String] = [
        // Row 1 — warm: reds, oranges, yellows, lime
        "#E63946", "#FF6B6B", "#FF8E53", "#FB5607", "#FFCA3A", "#8AC926", "#6BCB77",
        // Row 2 — cool: greens, teals, cyans, blues
        "#52B788", "#06D6A0", "#2EC4B6", "#00BBF9", "#4D96FF", "#3A86FF", "#457B9D",
        // Row 3 — deep: navy, violets, purples, pinks
        "#1D3557", "#9B5DE5", "#8338EC", "#7209B7", "#F72585", "#F15BB5", "#FF8FAB",
        // Row 4 — soft/neutral: pastels, mid-gray, charcoal
        "#FFB4A2", "#FFE5D9", "#B5E4F5", "#C5E8B0", "#E2C4F0", "#8B8B8B", "#2B2D42",
    ]

    /// Returns a random color from the curated palette.
    static func randomColor() -> String {
        palette.randomElement() ?? "#8B8B8B"
    }
}

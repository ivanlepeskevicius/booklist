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
}

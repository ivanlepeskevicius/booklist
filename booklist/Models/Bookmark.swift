import Foundation
import SwiftData

/// Whether a saved item is a regular bookmark or a wishlist/shopping item.
enum ItemType: String, Codable {
    case bookmark
    case wishlistItem
}

@Model
final class Bookmark {
    var id: UUID
    var title: String
    var url: String

    /// Auto-fetched meta description from the page (site-provided summary).
    var pageDescription: String?

    /// User's personal note explaining why they saved this.
    var note: String?

    var faviconURL: String?

    /// All candidate image URLs fetched from the page (OG image, etc.).
    var imageURLs: [String]

    /// The image the user chose to represent this bookmark.
    var selectedImageURL: String?

    var itemType: ItemType
    var price: String?      // only used for .wishlistItem

    var dateAdded: Date
    /// Set to the current date each time the user opens this link in a browser.
    /// nil means the link has never been opened after saving.
    var lastOpenedDate: Date?

    /// Sort proxy — returns lastOpenedDate or .distantPast so TableColumn can use a key path comparator.
    var lastOpenedDateForSorting: Date { lastOpenedDate ?? .distantPast }

    /// Sort proxy for the Tags column — first tag name alphabetically, empty string for untagged items.
    var tagSortKey: String { tags.min { $0.name < $1.name }?.name ?? "" }
    var isPinned: Bool
    var isRead: Bool

    /// The folder this bookmark belongs to. nil = lives in Inbox.
    var collection: Folder?

    var tags: [Tag]

    init(
        title: String,
        url: String,
        pageDescription: String? = nil,
        note: String? = nil,
        faviconURL: String? = nil,
        imageURLs: [String] = [],
        selectedImageURL: String? = nil,
        itemType: ItemType = .bookmark,
        price: String? = nil,
        collection: Folder? = nil,
        tags: [Tag] = []
    ) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.pageDescription = pageDescription
        self.note = note
        self.faviconURL = faviconURL
        self.imageURLs = imageURLs
        self.selectedImageURL = selectedImageURL
        self.itemType = itemType
        self.price = price
        self.collection = collection
        self.tags = tags
        self.dateAdded = Date()
        self.isPinned = false
        self.isRead = false
    }
}

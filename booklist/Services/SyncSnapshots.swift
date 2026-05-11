import Foundation

// Plain Codable structs used by SyncService for JSON snapshot serialisation.
// Explicit nonisolated encode/init(from:) implementations ensure the Codable
// conformances are usable from any concurrency context, preventing Swift 6
// main-actor-isolation warnings that arise from synthesised conformances when
// the surrounding module contains @MainActor @Model types.

struct SyncData: Codable {
    let version:    Int
    let exportedAt: Date
    let folders:    [FolderSnap]
    let tags:       [TagSnap]
    let bookmarks:  [BookmarkSnap]

    static let currentVersion = 1

    private enum CodingKeys: String, CodingKey {
        case version, exportedAt, folders, tags, bookmarks
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version,    forKey: .version)
        try c.encode(exportedAt, forKey: .exportedAt)
        try c.encode(folders,    forKey: .folders)
        try c.encode(tags,       forKey: .tags)
        try c.encode(bookmarks,  forKey: .bookmarks)
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c    = try decoder.container(keyedBy: CodingKeys.self)
        version    = try c.decode(Int.self,            forKey: .version)
        exportedAt = try c.decode(Date.self,           forKey: .exportedAt)
        folders    = try c.decode([FolderSnap].self,   forKey: .folders)
        tags       = try c.decode([TagSnap].self,      forKey: .tags)
        bookmarks  = try c.decode([BookmarkSnap].self, forKey: .bookmarks)
    }
}

struct FolderSnap: Codable {
    let id:        UUID
    let name:      String
    let icon:      String
    let color:     String
    let sortOrder: Int
    let parentID:  UUID?

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, color, sortOrder, parentID
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,        forKey: .id)
        try c.encode(name,      forKey: .name)
        try c.encode(icon,      forKey: .icon)
        try c.encode(color,     forKey: .color)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encodeIfPresent(parentID, forKey: .parentID)
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,   forKey: .id)
        name      = try c.decode(String.self, forKey: .name)
        icon      = try c.decode(String.self, forKey: .icon)
        color     = try c.decode(String.self, forKey: .color)
        sortOrder = try c.decode(Int.self,    forKey: .sortOrder)
        parentID  = try c.decodeIfPresent(UUID.self, forKey: .parentID)
    }
}

struct TagSnap: Codable {
    let id:    UUID
    let name:  String
    let color: String

    private enum CodingKeys: String, CodingKey {
        case id, name, color
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,    forKey: .id)
        try c.encode(name,  forKey: .name)
        try c.encode(color, forKey: .color)
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = try c.decode(UUID.self,   forKey: .id)
        name  = try c.decode(String.self, forKey: .name)
        color = try c.decode(String.self, forKey: .color)
    }
}

struct BookmarkSnap: Codable {
    let id:              UUID
    let title:           String
    let url:             String
    let pageDescription: String?
    let note:            String?
    let faviconURL:      String?
    let imageURLs:       [String]
    let selectedImageURL: String?
    let itemType:        String
    let price:           String?
    let dateAdded:       Date
    let lastOpenedDate:  Date?
    let isPinned:        Bool
    let isRead:          Bool
    let collectionID:    UUID?
    let tagIDs:          [UUID]

    private enum CodingKeys: String, CodingKey {
        case id, title, url, pageDescription, note, faviconURL
        case imageURLs, selectedImageURL, itemType, price
        case dateAdded, lastOpenedDate, isPinned, isRead
        case collectionID, tagIDs
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,              forKey: .id)
        try c.encode(title,           forKey: .title)
        try c.encode(url,             forKey: .url)
        try c.encodeIfPresent(pageDescription,  forKey: .pageDescription)
        try c.encodeIfPresent(note,             forKey: .note)
        try c.encodeIfPresent(faviconURL,       forKey: .faviconURL)
        try c.encode(imageURLs,       forKey: .imageURLs)
        try c.encodeIfPresent(selectedImageURL, forKey: .selectedImageURL)
        try c.encode(itemType,        forKey: .itemType)
        try c.encodeIfPresent(price,            forKey: .price)
        try c.encode(dateAdded,       forKey: .dateAdded)
        try c.encodeIfPresent(lastOpenedDate,   forKey: .lastOpenedDate)
        try c.encode(isPinned,        forKey: .isPinned)
        try c.encode(isRead,          forKey: .isRead)
        try c.encodeIfPresent(collectionID,     forKey: .collectionID)
        try c.encode(tagIDs,          forKey: .tagIDs)
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self,     forKey: .id)
        title           = try c.decode(String.self,   forKey: .title)
        url             = try c.decode(String.self,   forKey: .url)
        pageDescription = try c.decodeIfPresent(String.self, forKey: .pageDescription)
        note            = try c.decodeIfPresent(String.self, forKey: .note)
        faviconURL      = try c.decodeIfPresent(String.self, forKey: .faviconURL)
        imageURLs       = try c.decode([String].self, forKey: .imageURLs)
        selectedImageURL = try c.decodeIfPresent(String.self, forKey: .selectedImageURL)
        itemType        = try c.decode(String.self,   forKey: .itemType)
        price           = try c.decodeIfPresent(String.self, forKey: .price)
        dateAdded       = try c.decode(Date.self,     forKey: .dateAdded)
        lastOpenedDate  = try c.decodeIfPresent(Date.self, forKey: .lastOpenedDate)
        isPinned        = try c.decode(Bool.self,     forKey: .isPinned)
        isRead          = try c.decode(Bool.self,     forKey: .isRead)
        collectionID    = try c.decodeIfPresent(UUID.self, forKey: .collectionID)
        tagIDs          = try c.decode([UUID].self,   forKey: .tagIDs)
    }
}

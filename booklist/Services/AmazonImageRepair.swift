import Foundation
import SwiftData

/// One-time fix for Amazon bookmarks saved before captures used only the product gallery
/// (2026-10-23). Their image candidates are the whole page — navigation sprites, Prime and
/// Amazon Fresh banners, manufacturer banners, ad pixels, other products — and many show one of
/// those as their card image (it was the first candidate).
///
/// Works offline from what each bookmark already saved: the old candidates include the product's
/// main photo (marked `_ML2_`, or `_SX300_SY300_`) and its gallery thumbnails (`_US40_`, `_US100_`,
/// `_SR38,50_` depending on the page layout), and dropping an Amazon image's size suffix gives
/// the full-size photo. Already-repaired bookmarks only have full-size photos, so running again
/// leaves them alone.
enum AmazonImageRepair {

    nonisolated static let versionKey = "amazonImageRepairVersion"
    /// Bump when the repair learns a new page layout, so it runs once more.
    nonisolated static let version = 2

    /// Repairs every Amazon bookmark once per repair version. Returns the number changed.
    @discardableResult
    static func runIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) -> Int {
        guard !LaunchMode.isUITesting, !LaunchMode.isHostingTests,
              defaults.integer(forKey: versionKey) < version else { return 0 }
        let changed = run(context: context)
        defaults.set(version, forKey: versionKey)
        return changed
    }

    static func run(context: ModelContext) -> Int {
        let bookmarks = (try? context.fetch(FetchDescriptor<Bookmark>())) ?? []
        let repairs = bookmarks.compactMap { bookmark -> (Bookmark, Repaired)? in
            guard let url = URL(string: bookmark.url), MetadataFetcher.isAmazonURL(url),
                  let fixed = repaired(imageURLs: bookmark.imageURLs, selected: bookmark.selectedImageURL)
            else { return nil }
            return (bookmark, fixed)
        }
        guard !repairs.isEmpty else { return 0 }
        BackupService.backUp(context: context)
        for (bookmark, fixed) in repairs {
            bookmark.imageURLs = fixed.imageURLs
            bookmark.selectedImageURL = fixed.selected
        }
        try? context.save()
        return repairs.count
    }

    nonisolated struct Repaired: Equatable {
        let imageURLs: [String]
        let selected: String?
    }

    /// The product's photos at full size, main photo first. The selection is kept when it is a
    /// local file or any Amazon product photo (it may be the user's own pick); otherwise it becomes
    /// the main photo. Nil when there is nothing to change or no product photo to change to.
    nonisolated static func repaired(imageURLs: [String], selected: String?) -> Repaired? {
        let main = imageURLs.filter { $0.contains("_ML2_") || $0.contains("_SX300_") || $0.contains("_SY300_") }
        let gallery = imageURLs.filter { $0.contains("_US40_") || $0.contains("_US100_") || $0.contains("_SR38,50_") }
        var photos: [String] = []
        for url in (main + gallery).compactMap(fullSize) where !photos.contains(url) {
            photos.append(url)
        }
        guard let first = photos.first else { return nil }

        var newSelected = first
        if let selected {
            if selected.hasPrefix("file://") {
                newSelected = selected
            } else if let full = fullSize(selected) {
                newSelected = photos.contains(full) ? full : selected
            }
        }
        if !photos.contains(newSelected) && !newSelected.hasPrefix("file://") {
            photos.insert(newSelected, at: 0)
        }
        let result = Repaired(imageURLs: photos, selected: newSelected)
        return result == Repaired(imageURLs: imageURLs, selected: selected) ? nil : result
    }

    /// `…/images/I/51+BcEn5j8L._AC_SY300_SX300_QL70_ML2_.jpg` → `…/images/I/51+BcEn5j8L.jpg`
    nonisolated static func fullSize(_ url: String) -> String? {
        guard isProductPhoto(url) else { return nil }
        return url.replacingOccurrences(of: #"(/images/I/[^./]+)\.[^/]*(\.[a-zA-Z]+)$"#,
                                        with: "$1$2", options: .regularExpression)
    }

    /// Amazon serves product photos from `/images/I/`; UI graphics and banners live under
    /// `/images/G/` and `/images/S/`.
    nonisolated private static func isProductPhoto(_ url: String) -> Bool {
        url.contains("/images/I/")
    }
}

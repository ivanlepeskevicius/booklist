import Foundation
import Testing
@testable import booklist

/// Capture's wishlist default for a site follows the newest item the user saved from it.
@Suite("Wishlist sites learned from the library")
struct WishlistSitesTests {

    private typealias Saved = (url: String, isWishlist: Bool, dateAdded: Date)

    private let day: TimeInterval = 86_400
    private let shoe = "https://www.zalando.de/nike-sportswear-air-force-1-07-sneaker-low-white-ni112n022-a11.html"
    private let blog = "https://www.zalando.de/campaigns/style-guide/"

    private func suggests(_ url: String, _ saved: [Saved]) -> Bool {
        WishlistSites.lastChoiceWasWishlist(for: url, savedItems: saved)
    }

    @Test("After a wishlist item, the next link from the same shop defaults to wishlist")
    func learnsShop() {
        let saved: [Saved] = [(shoe, true, Date())]
        #expect(suggests("https://www.zalando.de/adidas-samba-og-ad115o1ln-a11.html", saved))
    }

    @Test("Saving a blog post from that shop as a bookmark switches the default back off")
    func latestBookmarkWins() {
        let saved: [Saved] = [(shoe, true, Date(timeIntervalSinceNow: -day)), (blog, false, Date())]
        #expect(!suggests("https://www.zalando.de/campaigns/another-post/", saved))
    }

    @Test("A newer wishlist item from the shop switches it back on")
    func latestWishlistWins() {
        let saved: [Saved] = [(blog, false, Date(timeIntervalSinceNow: -day)), (shoe, true, Date())]
        #expect(suggests("https://www.zalando.de/another-shoe.html", saved))
    }

    @Test("www. and m. prefixes and letter case don't matter")
    func prefixesIgnored() {
        let saved: [Saved] = [(shoe, true, Date())]
        #expect(suggests("https://zalando.de/some-shoe.html", saved))
        #expect(suggests("https://m.zalando.de/some-shoe.html", saved))
        #expect(suggests("https://WWW.ZALANDO.DE/some-shoe.html", saved))
    }

    @Test("Other subdomains are different sites (the Apple Store isn't Apple's docs)")
    func subdomainsStaySeparate() {
        let saved: [Saved] = [("https://www.apple.com/shop/product/mkr74zm/a/iphone-duo-folio", true, Date())]
        #expect(!suggests("https://developer.apple.com/documentation/swiftui", saved))
    }

    @Test("Unrelated sites, invalid URLs and an empty library suggest a bookmark")
    func unrelated() {
        let saved: [Saved] = [(shoe, true, Date())]
        #expect(!suggests("https://en.wikipedia.org/wiki/Sneakers", saved))
        #expect(!suggests("not a url", saved))
        #expect(!suggests(shoe, []))
    }
}

import Foundation
import Testing
@testable import booklist

/// Amazon product pages have no og:image or structured price data, so they get their own
/// extraction. Fixtures are trimmed copies of real amazon.es markup.
@Suite("Amazon product pages")
struct AmazonParsingTests {

    private let productURL = URL(string: "https://www.amazon.es/gp/product/B0GT9F92N2?psc=1")!

    private let productHTML = """
    <html><head><title>Outsunny Folding Garden Stool | Portable Garden Seat</title></head><body>
    <img src="https://m.media-amazon.com/images/G/30/gno/sprites/nav-sprite-global-1x._CB546381700_.png" width="400" height="400">
    <img alt="Outsunny Folding Garden Stool" src="https://m.media-amazon.com/images/I/81xI3eIdOLL._AC_SY300_SX300_QL70_ML2_.jpg" data-old-hires="https://m.media-amazon.com/images/I/81xI3eIdOLL._AC_SL1500_.jpg" class="a-dynamic-image" id="landingImage">
    <div class="a-section aok-hidden twister-plus-buying-options-price-data">{"desktop_buybox_group_1":[{"displayPrice":"€28.89","priceAmount":28.89}]}</div>
    <span class="a-price aok-align-center apex-pricetopay-value" data-a-size="xl" data-a-color="base"><span class="a-offscreen">€28.89</span><span aria-hidden="true"><span class="a-price-symbol">€</span><span class="a-price-whole">28</span></span></span>
    </body></html>
    """

    // MARK: - Detection

    @Test("Amazon storefronts are recognised", arguments: [
        "https://www.amazon.es/dp/B0GT9F92N2",
        "https://amazon.com/dp/B0GT9F92N2",
        "https://www.amazon.co.uk/dp/B0GT9F92N2",
        "https://www.amazon.com.mx/dp/B0GT9F92N2",
        "https://smile.amazon.de/dp/B0GT9F92N2",
    ])
    func recognised(_ link: String) throws {
        #expect(MetadataFetcher.isAmazonURL(try #require(URL(string: link))))
    }

    @Test("Other sites aren't mistaken for Amazon", arguments: [
        "https://www.notamazon.com/item",
        "https://example.com/amazon.es",
        "https://www.amazonia.org/",
        "https://www.reddit.com/r/amazon/",
    ])
    func notRecognised(_ link: String) throws {
        #expect(!MetadataFetcher.isAmazonURL(try #require(URL(string: link))))
    }

    // MARK: - Extraction

    @Test("Price to pay is extracted from the buy box")
    func price() {
        let meta = MetadataFetcher.parse(html: productHTML, baseURL: productURL)
        #expect(meta.price == "€28.89")
        #expect(meta.isProductPage)
    }

    @Test("Buy-box JSON is the fallback when the price span is missing")
    func priceFromJSON() {
        let html = #"<div>{"desktop_buybox_group_1":[{"displayPrice":"28,89 €","priceAmount":28.89}]}</div>"#
        #expect(MetadataFetcher.parse(html: html, baseURL: productURL).price == "28,89 €")
    }

    @Test("Main product photo comes first, high-res; nav sprites are dropped")
    func mainImage() {
        let images = MetadataFetcher.parse(html: productHTML, baseURL: productURL).imageURLs
        #expect(images.first == "https://m.media-amazon.com/images/I/81xI3eIdOLL._AC_SL1500_.jpg")
        #expect(!images.contains { $0.contains("/images/G/") })
    }

    @Test("Only the product's gallery photos, in Amazon's order — no thumbnails, banners or logos")
    func galleryOnly() {
        let html = """
        <img src="https://m.media-amazon.com/images/G/30/gno/sprites/nav-sprite-global-1x._CB546381700_.png" width="400" height="400">
        <img alt="Product" src="https://m.media-amazon.com/images/I/81xI3eIdOLL._AC_SY300_SX300_.jpg" data-old-hires="https://m.media-amazon.com/images/I/81xI3eIdOLL._AC_SL1500_.jpg" id="landingImage">
        <script>var data = { 'colorImages': { 'initial': A.$.parseJSON('[{"hiRes":"https://m.media-amazon.com/images/I/81xI3eIdOLL._AC_SL1500_.jpg","thumb":"https://m.media-amazon.com/images/I/51DrRbtiCgL._AC_US100_.jpg","large":"https://m.media-amazon.com/images/I/51DrRbtiCgL._AC_.jpg","variant":"MAIN"},{"hiRes":null,"thumb":"https://m.media-amazon.com/images/I/41x._AC_US100_.jpg","large":"https://m.media-amazon.com/images/I/41xLargeOnly._AC_.jpg","variant":"PT01"},{"hiRes":"https://m.media-amazon.com/images/I/81HN9qXjz-L._AC_SL1500_.jpg","large":"https://m.media-amazon.com/images/I/51y._AC_.jpg","variant":"PT02"}]')}, 'colorToAsin': {} };</script>
        <img src="https://m.media-amazon.com/images/I/51xDXJHYROL._AC_US100_.jpg">
        <img src="https://m.media-amazon.com/images/S/aplus-media-library-service-media/28822567-38ba.__CR0,0,970,600_PT0_SX970_V1___.jpg">
        <img src="https://m.media-amazon.com/images/S/al-eu-726f4d26-7fdb/55d569b5._CR0,0,1200,628_SX1200_.jpg">
        """
        #expect(MetadataFetcher.parse(html: html, baseURL: productURL).imageURLs == [
            "https://m.media-amazon.com/images/I/81xI3eIdOLL._AC_SL1500_.jpg",
            "https://m.media-amazon.com/images/I/41xLargeOnly._AC_.jpg",      // no hi-res → large
            "https://m.media-amazon.com/images/I/81HN9qXjz-L._AC_SL1500_.jpg",
        ])
    }

    @Test("Gallery entries with an escaped quote in their data still parse")
    func galleryWithEscapedQuote() {
        let html = #"'colorImages': { 'initial': A.$.parseJSON('[{"hiRes":"https://m.media-amazon.com/images/I/A._AC_SL1500_.jpg","variant":"MAIN","altText":"Kid's stool"}]')}"#
        #expect(MetadataFetcher.amazonGalleryImages(in: html) == ["https://m.media-amazon.com/images/I/A._AC_SL1500_.jpg"])
    }

    @Test("Non-Amazon pages are not product pages and keep generic image rules")
    func otherSite() throws {
        let url = try #require(URL(string: "https://example.com/post"))
        let meta = MetadataFetcher.parse(html: productHTML, baseURL: url)
        #expect(!meta.isProductPage)
        #expect(meta.imageURLs.first?.contains("/images/G/") == true)
    }
}

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

    @Test("Non-Amazon pages are not product pages and keep generic image rules")
    func otherSite() throws {
        let url = try #require(URL(string: "https://example.com/post"))
        let meta = MetadataFetcher.parse(html: productHTML, baseURL: url)
        #expect(!meta.isProductPage)
        #expect(meta.imageURLs.first?.contains("/images/G/") == true)
    }
}

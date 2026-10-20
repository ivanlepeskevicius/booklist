import Foundation
import Testing
@testable import booklist

/// Price extraction cases found by running real product pages from common US/EU shops
/// through the fetcher. Fixtures are trimmed copies of each shop's markup.
@Suite("Shop price extraction")
struct ShopPriceTests {

    private func price(_ html: String) -> String? {
        MetadataFetcher.parse(html: html, baseURL: URL(string: "https://shop.example/item")!).price
    }

    @Test("Zalando: price nested in ProductGroup.hasVariant")
    func productGroupVariants() {
        let html = """
        <script type="application/ld+json">[{"@context":"https://schema.org/","@type":"ProductGroup","name":"AIR FORCE 1 07","hasVariant":[{"@type":"Product","size":"38.5","offers":{"@type":"Offer","priceCurrency":"EUR","price":"95.95"}}]}]</script>
        """
        #expect(price(html) == "€95.95")
    }

    @Test("MediaMarkt: product nested in BuyAction.object, numeric price")
    func buyActionObject() {
        let html = """
        <script data-rh="true" type="application/ld+json">{"@context":"https://schema.org/","@type":"BuyAction","object":{"@type":"Product","name":"SONY WH 1000 XM 5","offers":[{"@type":"Offer","price":259,"priceCurrency":"EUR"}]}}</script>
        """
        #expect(price(html) == "€259.00")
    }

    @Test("PcComponentes: AggregateOffer lowPrice beats a recommended product's data-product-price")
    func aggregateOfferLowPrice() {
        let html = """
        <script type="application/ld+json">{"@context":"https://schema.org","@type":"product","offers":{"@type":"AggregateOffer","highPrice":"84.17","lowPrice":"66.99","priceCurrency":"EUR"}}</script>
        <div data-product-id="317616" data-product-price="89.99">Other headphones</div>
        """
        #expect(price(html) == "€66.99")
    }

    @Test("Fnac: warranty add-ons and their monthly rate are not the product price")
    func skipsAddOnsAndMonthlyRates() {
        let html = """
        <p><span class="CrossSellServices-module__price"><span>31,99 €</span></span> <span class="CrossSellServices-module__priceMonthly">0,89 €/mois</span></p>
        <p class="ShippingInfo-module__currentPrice">7,99 €</p>
        <span class="OtherOffersPreview-module__moreOffersTriggerPrice">269,99 €</span>
        """
        #expect(price(html) == "269,99 €")
    }

    @Test("A per-month rate alone yields no price rather than a wrong one")
    func monthlyRateOnly() {
        #expect(price(#"<span class="price-monthly-rate">0,89 €/mois</span>"#) == nil)
    }

    // MARK: - Product page detection (capture defaults these to wishlist)

    private func isProductPage(_ html: String) -> Bool {
        MetadataFetcher.parse(html: html, baseURL: URL(string: "https://shop.example/item")!).isProductPage
    }

    @Test("A page with a price is a product page")
    func priceMeansProduct() {
        #expect(isProductPage(#"<meta property="product:price:amount" content="19.99">"#))
    }

    @Test("Product pages without a readable price are detected from their markup", arguments: [
        #"<meta property="og:type" content="product">"#,
        #"<meta property="og:type" content="og:product">"#,
        #"<script type="application/ld+json">{"@type":"ProductGroup","name":"Sneaker"}</script>"#,
        #"<script type="application/ld+json">{"@type": "product", "name":"Headphones"}</script>"#,
    ])
    func declaredProduct(_ html: String) {
        #expect(isProductPage(html))
    }

    @Test("Articles and other pages are not product pages")
    func articleIsNotProduct() {
        let html = """
        <meta property="og:type" content="article">
        <script type="application/ld+json">{"@type":"BlogPosting","headline":"Best headphones of 2026"}</script>
        <p>The Sony WH-1000XM5 is our top pick.</p>
        """
        #expect(!isProductPage(html))
    }
}

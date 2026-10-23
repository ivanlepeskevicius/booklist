import Testing
@testable import booklist

/// The one-time repair of Amazon bookmarks saved before captures used only the product gallery.
/// URL shapes taken from real saved bookmarks (two Amazon page layouts).
@Suite("Amazon image repair")
struct AmazonImageRepairTests {

    private let sprite = "https://m.media-amazon.com/images/G/30/gno/sprites/nav-sprite-global-1x-reorg-privacy._CB546381700_.png"
    private let prime = "https://images-eu.ssl-images-amazon.com/images/G/02/prime/yourprime/yourprime-widget-piv-fallback._V310089192_.jpg"
    private let aplus = "https://m.media-amazon.com/images/S/aplus-media-library-service-media/ad3576cd-6fb8-4ca8-accf-f4ff6c618c50.__CR0,0,368_PT0_SX300_V1___.jpg"
    private let adPixel = "https://aax-eu-zaz.amazon.es/e/is/D8A8F2B64B75DAA625F6833085AA5FF3/impb?b=JJtKH1"
    private let otherProduct = "https://m.media-amazon.com/images/I/61wo37JZJnS._AC_SR139,139_CB1169409_QL70_.jpg"
    private let photo = "https://m.media-amazon.com/images/I/"

    @Test func fullSizeDropsTheSizeSuffix() {
        #expect(AmazonImageRepair.fullSize(photo + "51+BcEn5j8L._AC_SY300_SX300_QL70_ML2_.jpg") == photo + "51+BcEn5j8L.jpg")
        #expect(AmazonImageRepair.fullSize(photo + "41tc3K-pqSL._AC_SR38,50_.jpg") == photo + "41tc3K-pqSL.jpg")
        #expect(AmazonImageRepair.fullSize(photo + "51+BcEn5j8L.jpg") == photo + "51+BcEn5j8L.jpg")
        #expect(AmazonImageRepair.fullSize(sprite) == nil)
    }

    @Test func junkSelectionBecomesTheMainPhoto() throws {
        let saved = [sprite, prime, photo + "51+BcEn5j8L._AC_SY300_SX300_QL70_ML2_.jpg",
                     photo + "31VD-1-HgxL._AC_US100_.jpg", photo + "417qDAenf2L._AC_US100_.jpg",
                     aplus, adPixel, otherProduct]
        let fixed = try #require(AmazonImageRepair.repaired(imageURLs: saved, selected: sprite))
        #expect(fixed.selected == photo + "51+BcEn5j8L.jpg")
        #expect(fixed.imageURLs == [photo + "51+BcEn5j8L.jpg", photo + "31VD-1-HgxL.jpg", photo + "417qDAenf2L.jpg"])
    }

    @Test func secondLayout() throws {
        let saved = [sprite, prime, photo + "41tc3K-pqSL._AC_SR38,50_.jpg", photo + "41271uUq-nL._AC_SR38,50_.jpg",
                     photo + "41+3ADlMKYL._SX342_SY445_QL70_ML2_.jpg", photo + "71Dj27TD8QL._AC_SX367_SY500_.jpg"]
        let fixed = try #require(AmazonImageRepair.repaired(imageURLs: saved, selected: nil))
        #expect(fixed.selected == photo + "41+3ADlMKYL.jpg")
        #expect(fixed.imageURLs == [photo + "41+3ADlMKYL.jpg", photo + "41tc3K-pqSL.jpg", photo + "41271uUq-nL.jpg"])
    }

    @Test func galleryThumbnailSelectionIsUpgradedNotReplaced() throws {
        let saved = [sprite, photo + "51+BcEn5j8L._AC_SY300_SX300_QL70_ML2_.jpg", photo + "31VD-1-HgxL._AC_US40_.jpg"]
        let fixed = try #require(AmazonImageRepair.repaired(imageURLs: saved, selected: photo + "31VD-1-HgxL._AC_US40_.jpg"))
        #expect(fixed.selected == photo + "31VD-1-HgxL.jpg")
    }

    @Test func userPickedProductPhotoIsKept() throws {
        let picked = photo + "71Dj27TD8QL._SY500_.jpg"
        let saved = [sprite, photo + "51+BcEn5j8L._AC_SY300_SX300_QL70_ML2_.jpg", picked]
        let fixed = try #require(AmazonImageRepair.repaired(imageURLs: saved, selected: picked))
        #expect(fixed.selected == picked)
        #expect(fixed.imageURLs == [picked, photo + "51+BcEn5j8L.jpg"])
    }

    @Test func localImageIsKept() throws {
        let local = "file:///Users/x/Library/Application%20Support/Images/ABC.jpg"
        let saved = [sprite, photo + "51+BcEn5j8L._AC_SY300_SX300_QL70_ML2_.jpg"]
        let fixed = try #require(AmazonImageRepair.repaired(imageURLs: saved, selected: local))
        #expect(fixed.selected == local)
        #expect(fixed.imageURLs == [photo + "51+BcEn5j8L.jpg"])
    }

    @Test func noProductPhotoLeavesTheBookmarkAlone() {
        let banner = "https://m.media-amazon.com/images/G/01/T/TC05316420/A07531864/brand/landing-meta-image._CB403759455_.png"
        #expect(AmazonImageRepair.repaired(imageURLs: [banner], selected: banner) == nil)
    }

    /// Bookmarks repaired before, and new captures (gallery `hiRes` URLs), have nothing to fix.
    @Test func runningAgainChangesNothing() throws {
        let saved = [sprite, photo + "51+BcEn5j8L._AC_SY300_SX300_QL70_ML2_.jpg", photo + "31VD-1-HgxL._AC_US100_.jpg"]
        let fixed = try #require(AmazonImageRepair.repaired(imageURLs: saved, selected: sprite))
        #expect(AmazonImageRepair.repaired(imageURLs: fixed.imageURLs, selected: fixed.selected) == nil)
        let newCapture = [photo + "71abcDEF12L._AC_SL1500_.jpg", photo + "81xyz+987L._AC_SL1500_.jpg"]
        #expect(AmazonImageRepair.repaired(imageURLs: newCapture, selected: newCapture[0]) == nil)
    }
}

import Foundation
import Testing
@testable import booklist

/// Reddit's HTML page and JSON API are bot-blocked; oEmbed is the fallback that still
/// returns the real post title.
@Suite("Reddit oEmbed parsing")
struct RedditOEmbedTests {

    private let postURL = URL(string: "https://www.reddit.com/r/TheLastAirbender/comments/1xajsuk/just_watched_this_movie/")!

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    @Test("Title, author and subreddit (from the URL) are extracted")
    func fullResponse() throws {
        let data = try json([
            "title": "Just watched this movie, and my god, the GAANG were insanely nerfed.",
            "author_name": "Round_Interview2373",
            "provider_name": "reddit",
        ])
        let meta = try #require(MetadataFetcher.parseRedditOEmbed(data, postURL: postURL))
        #expect(meta.title == "Just watched this movie, and my god, the GAANG were insanely nerfed.")
        #expect(meta.redditAuthor == "Round_Interview2373")
        #expect(meta.redditSubreddit == "TheLastAirbender")
        #expect(meta.imageURLs.isEmpty)
    }

    @Test("HTML entities in the title are decoded")
    func entitiesDecoded() throws {
        let data = try json(["title": "Tom &amp; Jerry &#8212; best episode?"])
        let meta = try #require(MetadataFetcher.parseRedditOEmbed(data, postURL: postURL))
        #expect(meta.title == "Tom & Jerry — best episode?")
        #expect(meta.redditAuthor == nil)
    }

    @Test("Missing or empty title returns nil so the next fallback is tried")
    func noTitle() throws {
        #expect(MetadataFetcher.parseRedditOEmbed(try json(["author_name": "someone"]), postURL: postURL) == nil)
        #expect(MetadataFetcher.parseRedditOEmbed(try json(["title": "   "]), postURL: postURL) == nil)
        #expect(MetadataFetcher.parseRedditOEmbed(Data("not json".utf8), postURL: postURL) == nil)
    }

    // MARK: - Embed page images

    @Test("Post images are extracted in page order with &amp; decoded; subreddit icon skipped")
    func embedImages() {
        let html = """
        <img alt="icon" src="https://styles.redditmedia.com/t5_2rybx/styles/communityIcon.jpeg?s=1">
        <img alt="post" class="w-full" src="https://preview.redd.it/a-v0-first.jpeg?width=640&amp;crop=smart&amp;s=abc" srcset="x 320w">
        <img alt="post" src="https://preview.redd.it/a-v0-second.jpeg?width=640&amp;s=def">
        <img alt="post again" src="https://preview.redd.it/a-v0-first.jpeg?width=640&amp;crop=smart&amp;s=abc">
        """
        #expect(MetadataFetcher.redditEmbedImages(in: html) == [
            "https://preview.redd.it/a-v0-first.jpeg?width=640&crop=smart&s=abc",
            "https://preview.redd.it/a-v0-second.jpeg?width=640&s=def",
        ])
    }

    @Test("Text posts (no redd.it images) return no images")
    func embedNoImages() {
        let html = #"<img src="https://styles.redditmedia.com/icon.png"><p>Just text</p>"#
        #expect(MetadataFetcher.redditEmbedImages(in: html).isEmpty)
    }
}

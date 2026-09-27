import XCTest
@testable import NewsCore

final class DeduplicatorTests: XCTestCase {
    func testURLNormalization() {
        func n(_ s: String) -> String { URLNormalizer.normalize(URL(string: s)!) }
        XCTAssertEqual(
            n("http://www.Example.com/news/story/?utm_source=rss&utm_campaign=x&id=5#comments"),
            n("https://example.com/news/story?id=5")
        )
        XCTAssertEqual(n("https://m.example.com/a/amp"), n("https://example.com/a"))
        XCTAssertEqual(n("https://example.com/a?b=2&a=1"), n("https://example.com/a?a=1&b=2"))
        XCTAssertNotEqual(n("https://example.com/a?id=1"), n("https://example.com/a?id=2"))
        XCTAssertNotEqual(n("https://example.com/a"), n("https://example.com/b"))
    }

    func testStableIDsIgnoreTrackingParameters() {
        XCTAssertEqual(
            Article.makeID(for: URL(string: "https://example.com/x?utm_medium=rss")!),
            Article.makeID(for: URL(string: "http://www.example.com/x/")!)
        )
    }

    func testDeduplicatesByURL() {
        let articles = [
            Article.make(title: "First headline version here", link: "https://example.com/story?utm_source=a", source: "a"),
            Article.make(title: "Completely different title text", link: "http://www.example.com/story/", source: "b"),
        ]
        let result = Deduplicator().deduplicate(articles)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].sourceID, "a")
        XCTAssertEqual(result[0].additionalSourceNames, ["B"])
    }

    func testDeduplicatesByNormalizedTitle() {
        let articles = [
            Article.make(title: "Fed raises rates by 25 basis points", summary: "short", link: "https://a.com/1", source: "a", topics: [.finance]),
            Article.make(title: "FED raises rates — by 25 basis points!", summary: "a much longer summary", link: "https://b.com/2", source: "b", topics: [.economy]),
            Article.make(title: "Something else entirely different", link: "https://c.com/3", source: "c"),
        ]
        let result = Deduplicator().deduplicate(articles)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].topics, [.finance, .economy])
        XCTAssertEqual(result[0].summary, "a much longer summary")
        XCTAssertEqual(result[0].additionalSourceNames, ["B"])
    }

    func testShortTitlesAreNotMerged() {
        let articles = [
            Article.make(title: "Live updates", link: "https://a.com/1"),
            Article.make(title: "Live updates", link: "https://b.com/2"),
        ]
        XCTAssertEqual(Deduplicator().deduplicate(articles).count, 2)
    }

    func testMergeKeepsEarliestDate() {
        let articles = [
            Article.make(link: "https://a.com/1", published: date("2024-05-02T10:00:00Z")),
            Article.make(link: "https://a.com/1", published: date("2024-05-01T10:00:00Z")),
        ]
        XCTAssertEqual(Deduplicator().deduplicate(articles).first?.publishedAt, date("2024-05-01T10:00:00Z"))
    }
}

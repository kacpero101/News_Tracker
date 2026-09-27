import XCTest
@testable import NewsCore

final class FeedDiscoveryTests: XCTestCase {
    let page = """
    <!DOCTYPE html><html><head>
    <LINK REL="alternate" TYPE="application/rss+xml" title="Wiadomości" HREF="/rss/news.xml">
    <link rel='alternate stylesheet' type='text/css' href='/style.css'>
    <link type="application/atom+xml" rel="alternate" href="https://example.com/atom.xml?a=1&amp;b=2"/>
    </head><body>
    <abbr title="rss">RSS</abbr>
    <a href="/rss">RSS</a>
    <a class="x" href="https://example.com/rss/news.xml">duplicate</a>
    <a href="/kontakt">Kontakt</a>
    <a href="mailto:rss@example.com">mail</a>
    <a href=/feed/ >feed</a>
    </body></html>
    """

    func testCandidateURLsFromHTML() {
        let urls = FeedDiscovery.candidateURLs(inHTML: page, baseURL: URL(string: "https://example.com/page")!)
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://example.com/rss/news.xml",
            "https://example.com/atom.xml?a=1&b=2",
            "https://example.com/rss",
            "https://example.com/feed/",
        ])
    }

    func testURLHelpers() {
        XCTAssertEqual(FeedDiscovery.normalizedURL(from: " pb.pl ")?.absoluteString, "https://pb.pl")
        XCTAssertEqual(FeedDiscovery.normalizedURL(from: "https://www.money.pl/rss/")?.absoluteString, "https://www.money.pl/rss/")
        XCTAssertNil(FeedDiscovery.normalizedURL(from: "not a url"))
        XCTAssertNil(FeedDiscovery.normalizedURL(from: "localhost"))
        XCTAssertEqual(FeedDiscovery.commonFeedURLs(for: URL(string: "https://www.pb.pl/x/y")!).first?.absoluteString, "https://www.pb.pl/feed")
        XCTAssertTrue(FeedDiscovery.looksLikeHTML(Data(page.utf8)))
        XCTAssertFalse(FeedDiscovery.looksLikeHTML(Data("<?xml version=\"1.0\"?><rss></rss>".utf8)))
    }

    /// site.example: page with an alternate feed link and a link to an "RSS" page listing two more feeds.
    private func siteClient() throws -> MockHTTPClient {
        let home = """
        <html><head><link rel="alternate" type="application/rss+xml" href="/main.xml"></head>
        <body><a href="/rss-lista">Kanały RSS</a></body></html>
        """
        let hub = """
        <html><body><a href="/kanal/a.xml">A</a> <a href="https://site.example/kanal/b.xml">B</a></body></html>
        """
        return MockHTTPClient([
            URL(string: "https://site.example")!: .ok(Data(home.utf8)),
            URL(string: "https://site.example/main.xml")!: .ok(try Fixtures.data("rss2_sample.xml")),
            URL(string: "https://site.example/rss-lista")!: .ok(Data(hub.utf8)),
            URL(string: "https://site.example/kanal/a.xml")!: .ok(try Fixtures.data("atom_sample.xml")),
            URL(string: "https://site.example/kanal/b.xml")!: .ok(try Fixtures.data("rss1_sample.xml")),
        ])
    }

    func testDiscoverFeedAddressDirectly() async throws {
        let client = MockHTTPClient([URL(string: "https://feed.example/rss")!: .ok(try Fixtures.data("rss2_sample.xml"))])
        let feeds = await FeedDiscoverer(client: client).discover("feed.example/rss")
        XCTAssertEqual(feeds.count, 1)
        XCTAssertEqual(feeds.first?.title, "Sample Business News")
        XCTAssertEqual(feeds.first?.itemCount, 3)
        XCTAssertEqual(feeds.first?.sampleTitles.first, "Central bank raises interest rates to fight inflation")
    }

    func testDiscoverFeedsLinkedFromPageAndRSSListPage() async throws {
        let feeds = await FeedDiscoverer(client: try siteClient()).discover("site.example")
        XCTAssertEqual(feeds.map(\.url.absoluteString), [
            "https://site.example/main.xml",
            "https://site.example/kanal/a.xml",
            "https://site.example/kanal/b.xml",
        ])
        XCTAssertEqual(feeds.map(\.format), [.rss2, .atom, .rss1])
        let nothing = await FeedDiscoverer(client: MockHTTPClient()).discover("empty.example")
        XCTAssertEqual(nothing, [])
    }

    func testRefreshUsesFeedLinkedFromWebPageAndRemembersIt() async throws {
        let client = try siteClient()
        let source = FeedSource(id: "site", name: "Site", url: URL(string: "https://site.example")!, language: .english, defaultCategory: .finance)
        let aggregator = FeedAggregator(client: client, classifier: TopicClassifier(keywords: KeywordList(topics: [:])))

        let result = await aggregator.fetchAll([source])
        XCTAssertEqual(result.failures, [])
        XCTAssertEqual(result.articles.count, 3)
        XCTAssertEqual(result.resolvedFeedURLs, ["site": URL(string: "https://site.example/main.xml")!])
        XCTAssertTrue(result.articles.allSatisfy { $0.sourceID == "site" && $0.topics.contains(.finance) })

        // The repository reuses the found feed URL instead of loading the page again.
        let repository = NewsRepository(aggregator: aggregator, cache: nil)
        _ = await repository.refresh(sources: [source])
        let pageRequestsBefore = client.requests.filter { $0.url?.absoluteString == "https://site.example" }.count
        let outcome = await repository.refresh(sources: [source])
        let pageRequestsAfter = client.requests.filter { $0.url?.absoluteString == "https://site.example" }.count
        XCTAssertEqual(pageRequestsAfter, pageRequestsBefore)
        XCTAssertEqual(client.requests.last?.url?.absoluteString, "https://site.example/main.xml")
        XCTAssertEqual(outcome.resolvedFeedURLs["site"]?.absoluteString, "https://site.example/main.xml")
        XCTAssertEqual(outcome.failures, [])
    }

    func testWebPageWithoutFeedReportsClearError() async throws {
        let client = MockHTTPClient([URL(string: "https://nofeed.example")!: .ok(Data("<html><body>Hello</body></html>".utf8))])
        let source = FeedSource(id: "x", name: "X", url: URL(string: "https://nofeed.example")!, language: .polish, defaultCategory: nil)
        let result = await FeedAggregator(client: client, classifier: TopicClassifier(keywords: KeywordList(topics: [:]))).fetchAll([source])
        XCTAssertEqual(result.failures.map(\.message), [FeedDiscoveryError.noFeedFound.errorDescription!])
    }
}

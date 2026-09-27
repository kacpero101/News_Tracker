import XCTest
@testable import NewsCore

final class FeedAggregatorTests: XCTestCase {
    let english = FeedSource(id: "en", name: "English", url: URL(string: "https://en.example/rss")!, language: .english, defaultCategory: .economy)
    let atom = FeedSource(id: "de", name: "Deutsch", url: URL(string: "https://de.example/atom")!, language: .german, defaultCategory: nil)
    let broken = FeedSource(id: "broken", name: "Broken", url: URL(string: "https://broken.example/rss")!, language: .english, defaultCategory: nil)
    let notFound = FeedSource(id: "404", name: "Missing", url: URL(string: "https://missing.example/rss")!, language: .polish, defaultCategory: nil)
    let garbage = FeedSource(id: "garbage", name: "Garbage", url: URL(string: "https://garbage.example/rss")!, language: .english, defaultCategory: nil)

    private func makeAggregator(_ client: HTTPClient) throws -> FeedAggregator {
        FeedAggregator(
            client: client,
            classifier: TopicClassifier(keywords: try NewsConfiguration.defaultKeywords()),
            now: { date("2024-05-05T00:00:00Z") }
        )
    }

    func testFailingSourcesDoNotBreakTheList() async throws {
        let client = MockHTTPClient([
            english.url: .ok(try Fixtures.data("rss2_sample.xml")),
            atom.url: .ok(try Fixtures.data("atom_sample.xml")),
            notFound.url: .status(404),
            garbage.url: .ok(try Fixtures.data("invalid.xml")),
            // `broken` has no response -> network error
        ])
        let result = await try makeAggregator(client).fetchAll([english, broken, atom, notFound, garbage])

        XCTAssertEqual(result.articles.count, 5)
        XCTAssertEqual(result.succeededSourceIDs, ["en", "de"])
        XCTAssertEqual(result.failures.map(\.sourceID), ["broken", "404", "garbage"])
        XCTAssertEqual(result.failures[1].message, "HTTP status 404")
        XCTAssertEqual(client.requests.count, 5)
    }

    func testArticlesAreClassifiedAndSortedNewestFirst() async throws {
        let client = MockHTTPClient([
            english.url: .ok(try Fixtures.data("rss2_sample.xml")),
            atom.url: .ok(try Fixtures.data("atom_sample.xml")),
        ])
        let result = await try makeAggregator(client).fetchAll([english, atom])
        let dates = result.articles.map(\.sortDate)
        XCTAssertEqual(dates, dates.sorted(by: >))

        let bitcoin = try XCTUnwrap(result.articles.first { $0.title.hasPrefix("Bitcoin") })
        XCTAssertTrue(bitcoin.topics.isSuperset(of: [.economy, .crypto]))
        XCTAssertEqual(bitcoin.language, .english)
        XCTAssertEqual(bitcoin.sourceName, "English")

        let battery = try XCTUnwrap(result.articles.first { $0.title.contains("Batterie") })
        XCTAssertEqual(battery.language, .german)
        XCTAssertTrue(battery.topics.contains(.breakthroughs))

        let law = try XCTUnwrap(result.articles.first { $0.title.contains("Bundestag") })
        XCTAssertTrue(law.topics.contains(.politics))
    }

    func testSameArticleFromTwoFeedsIsShownOnce() async throws {
        let copy = FeedSource(id: "copy", name: "Copy", url: URL(string: "https://copy.example/rss")!, language: .english, defaultCategory: .finance)
        let data = try Fixtures.data("rss2_sample.xml")
        let client = MockHTTPClient([english.url: .ok(data), copy.url: .ok(data)])
        let result = await try makeAggregator(client).fetchAll([english, copy])
        XCTAssertEqual(result.articles.count, 3)
        XCTAssertTrue(result.articles.allSatisfy { $0.additionalSourceNames == ["Copy"] })
        XCTAssertTrue(result.articles.allSatisfy { $0.topics.isSuperset(of: [.economy, .finance]) })
    }

    func testRequestHeaders() async throws {
        let client = MockHTTPClient([english.url: .ok(try Fixtures.data("rss2_sample.xml"))])
        _ = try await makeAggregator(client).fetch(english)
        XCTAssertEqual(client.requests.first?.value(forHTTPHeaderField: "User-Agent"), "NewsTracker/1.0 (RSS reader)")
    }
}

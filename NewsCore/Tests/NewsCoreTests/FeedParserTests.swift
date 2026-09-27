import XCTest
@testable import NewsCore

final class FeedParserTests: XCTestCase {
    let parser = FeedParser()

    func testParsesRSS2() throws {
        let feed = try parser.parse(Fixtures.data("rss2_sample.xml"))
        XCTAssertEqual(feed.format, .rss2)
        XCTAssertEqual(feed.title, "Sample Business News")
        XCTAssertEqual(feed.items.count, 3)

        let first = feed.items[0]
        XCTAssertEqual(first.title, "Central bank raises interest rates to fight inflation")
        XCTAssertEqual(first.link?.absoluteString, "https://news.example.com/business/rates-2024?utm_source=rss&utm_medium=feed")
        XCTAssertEqual(first.summary, "The central bank raised rates by 0.25 points & signalled more to come.")
        XCTAssertEqual(first.publishedAt, date("2024-05-01T10:30:00Z"))
        XCTAssertEqual(first.guid, "rates-2024")

        XCTAssertEqual(feed.items[1].publishedAt, date("2024-04-30T06:00:00Z"))
    }

    func testRSS2FallsBackToGuidLinkAndContentEncoded() throws {
        let item = try parser.parse(Fixtures.data("rss2_sample.xml")).items[2]
        XCTAssertEqual(item.title, "Guid-only item with \"quoted\" title")
        XCTAssertEqual(item.link?.absoluteString, "https://news.example.com/guid-only")
        XCTAssertEqual(item.summary, "Only content encoded here.")
        XCTAssertEqual(item.publishedAt, date("2024-04-29T12:00:00Z"))
    }

    func testParsesAtom() throws {
        let feed = try parser.parse(Fixtures.data("atom_sample.xml"))
        XCTAssertEqual(feed.format, .atom)
        XCTAssertEqual(feed.title, "Beispiel Wissenschaft")
        XCTAssertEqual(feed.items.count, 2)

        let first = feed.items[0]
        XCTAssertEqual(first.title, "Forscher entdecken neue Batterie-Technologie")
        XCTAssertEqual(first.link?.absoluteString, "https://wissen.example.de/batterie")
        XCTAssertEqual(first.summary, "Ein Durchbruch für Elektroautos.")
        XCTAssertEqual(first.publishedAt, date("2024-05-02T06:15:30Z"))

        let second = feed.items[1]
        XCTAssertEqual(second.link?.absoluteString, "https://wissen.example.de/gesetz")
        XCTAssertEqual(second.summary, "Die Regierung hat sich geeinigt.")
        // Falls back to <updated> (with fractional seconds) when <published> is missing.
        XCTAssertEqual(second.publishedAt?.timeIntervalSince1970 ?? 0, date("2024-05-01T18:45:00Z").timeIntervalSince1970 + 0.123, accuracy: 0.001)
    }

    func testParsesRSS1() throws {
        let feed = try parser.parse(Fixtures.data("rss1_sample.xml"))
        XCTAssertEqual(feed.format, .rss1)
        XCTAssertEqual(feed.title, "RDF Example")
        XCTAssertEqual(feed.items.count, 1)
        XCTAssertEqual(feed.items[0].title, "Sejm uchwalił budżet na przyszły rok")
        XCTAssertEqual(feed.items[0].publishedAt, date("2024-05-03T05:00:00Z"))
    }

    func testInvalidXMLThrows() throws {
        XCTAssertThrowsError(try parser.parse(Fixtures.data("invalid.xml")))
        XCTAssertThrowsError(try parser.parse(Data()))
    }

    func testNonFeedDocumentThrowsUnsupportedFormat() throws {
        XCTAssertThrowsError(try parser.parse(Fixtures.data("html_page.xml"))) { error in
            XCTAssertEqual(error as? FeedParserError, .unsupportedFormat(rootElement: "html"))
        }
    }

    func testSummaryIsTruncated() throws {
        let long = String(repeating: "word ", count: 200)
        let xml = "<rss><channel><item><title>T</title><link>https://x.org/1</link><description>\(long)</description></item></channel></rss>"
        let item = try FeedParser(summaryMaxLength: 50).parse(Data(xml.utf8)).items[0]
        XCTAssertLessThanOrEqual(item.summary.count, 51)
        XCTAssertTrue(item.summary.hasSuffix("…"))
    }
}

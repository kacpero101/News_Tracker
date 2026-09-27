import XCTest
@testable import NewsCore

final class ArticleQueryTests: XCTestCase {
    let articles: [Article] = [
        .make(title: "Bitcoin hits record", summary: "Crypto rally", link: "https://a.com/1",
              published: date("2024-05-01T10:00:00Z"), source: "coindesk", language: .english, topics: [.crypto, .finance]),
        .make(title: "Sejm przyjął budżet", summary: "Posłowie głosowali w nocy", link: "https://a.com/2",
              published: date("2024-05-03T10:00:00Z"), source: "bankier", language: .polish, topics: [.politics, .economy]),
        .make(title: "Neue Batterie entdeckt", summary: "Durchbruch", link: "https://a.com/3",
              published: date("2024-05-02T10:00:00Z"), source: "spiegel", language: .german, topics: [.breakthroughs]),
        .make(title: "Unclassified story", link: "https://a.com/4", published: nil, source: "x", language: .english),
    ]

    func testEmptyQueryReturnsAllNewestFirst() {
        let result = ArticleQuery().apply(to: articles)
        XCTAssertEqual(result.map(\.link.absoluteString), ["https://a.com/2", "https://a.com/3", "https://a.com/1", "https://a.com/4"])
    }

    func testFilterByTopicsIsUnion() {
        let result = ArticleQuery(topics: [.crypto, .breakthroughs]).apply(to: articles)
        XCTAssertEqual(Set(result.map(\.link.absoluteString)), ["https://a.com/1", "https://a.com/3"])
    }

    func testFilterByLanguage() {
        let result = ArticleQuery(languages: [.polish, .german]).apply(to: articles)
        XCTAssertEqual(result.map(\.language), [.polish, .german])
    }

    func testCombinedFilters() {
        XCTAssertEqual(ArticleQuery(topics: [.economy], languages: [.english]).apply(to: articles), [])
        XCTAssertEqual(ArticleQuery(topics: [.economy], languages: [.polish]).apply(to: articles).count, 1)
    }

    func testSearchIsCaseAndDiacriticInsensitive() {
        XCTAssertEqual(ArticleQuery(searchText: "PRZYJAL").apply(to: articles).first?.title, "Sejm przyjął budżet")
        XCTAssertEqual(ArticleQuery(searchText: "poslowie").apply(to: articles).count, 1)
    }

    func testSearchRequiresAllTermsAndMatchesWordPrefixes() {
        XCTAssertEqual(ArticleQuery(searchText: "bitco rec").apply(to: articles).count, 1)
        XCTAssertEqual(ArticleQuery(searchText: "bitcoin budżet").apply(to: articles).count, 0)
        // Prefix of a word, not an arbitrary substring.
        XCTAssertEqual(ArticleQuery(searchText: "itcoin").apply(to: articles).count, 0)
    }

    func testSearchIncludesSourceName() {
        XCTAssertEqual(ArticleQuery(searchText: "spiegel").apply(to: articles).count, 1)
    }

    func testSearchCombinedWithFilters() {
        XCTAssertEqual(ArticleQuery(topics: [.crypto], searchText: "sejm").apply(to: articles).count, 0)
        XCTAssertTrue(ArticleQuery().isEmpty)
        XCTAssertFalse(ArticleQuery(searchText: "x").isEmpty)
    }
}

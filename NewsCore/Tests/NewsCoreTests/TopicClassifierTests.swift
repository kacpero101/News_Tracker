import XCTest
@testable import NewsCore

final class TopicClassifierTests: XCTestCase {
    let keywords = KeywordList(topics: [
        .crypto: .init(common: ["bitcoin*"], pl: ["kryptowalut*"], de: ["kryptowahrung*"]),
        .economy: .init(pl: ["inflacj*"], en: ["inflation"], de: ["inflation*"]),
        .finance: .init(pl: ["stop* procentow*"], en: ["central bank"]),
        .politics: .init(pl: ["sejm*"], de: ["bundestag"]),
    ])

    private func source(_ language: Language, category: Topic? = nil) -> FeedSource {
        FeedSource(id: "s", name: "S", url: URL(string: "https://s.example")!, language: language, defaultCategory: category)
    }

    func testMatchesWholeWordsPhrasesAndPrefixes() {
        let classifier = TopicClassifier(keywords: keywords)
        XCTAssertEqual(
            classifier.classify(title: "Central Bank fights inflation", summary: "", source: source(.english)),
            [.finance, .economy]
        )
        // "inflationary" is not the whole word "inflation".
        XCTAssertEqual(classifier.classify(title: "Inflationary pressure", summary: "", source: source(.english)), [])
        // Prefix match, case and diacritics ignored.
        XCTAssertEqual(classifier.classify(title: "BITCOINY tanieją", summary: "", source: source(.polish)), [.crypto])
    }

    func testPolishAndGermanInflectionsAndDiacritics() {
        let classifier = TopicClassifier(keywords: keywords)
        XCTAssertEqual(
            classifier.classify(title: "Inflacja spada", summary: "RPP obniża stopy procentowe", source: source(.polish)),
            [.economy, .finance]
        )
        XCTAssertEqual(
            classifier.classify(title: "Kryptowährungen im Aufwind", summary: "Der Bundestag debattiert", source: source(.german)),
            [.crypto, .politics]
        )
        XCTAssertEqual(classifier.classify(title: "Posiedzenie Sejmu", summary: "", source: source(.polish)), [.politics])
    }

    func testLanguageSpecificListsDoNotLeak() {
        let classifier = TopicClassifier(keywords: keywords)
        // "inflacja" is only in the Polish list.
        XCTAssertEqual(classifier.classify(title: "inflacja", summary: "", source: source(.english)), [])
    }

    func testSourceCategoryIsAlwaysIncludedAndArticleCanHaveMultipleTopics() {
        let classifier = TopicClassifier(keywords: keywords)
        let topics = classifier.classify(
            title: "Bitcoin reacts to central bank",
            summary: "",
            source: source(.english, category: .politics)
        )
        XCTAssertEqual(topics, [.politics, .crypto, .finance])
    }

    func testMinimumMatches() {
        var strict = keywords
        strict.minimumMatches = 2
        strict.topics[.economy] = .init(en: ["inflation", "wages"])
        let classifier = TopicClassifier(keywords: strict)
        XCTAssertEqual(classifier.classify(title: "Inflation", summary: "", source: source(.english)), [])
        XCTAssertEqual(classifier.classify(title: "Inflation and wages", summary: "", source: source(.english)), [.economy])
    }

    func testBundledKeywordsClassifyRealisticHeadlines() throws {
        let classifier = TopicClassifier(keywords: try NewsConfiguration.defaultKeywords())
        func topics(_ title: String, _ language: Language) -> Set<Topic> {
            classifier.classify(title: title, summary: "", source: source(language))
        }
        XCTAssertTrue(topics("Ethereum ETF approved by SEC", .english).contains(.crypto))
        XCTAssertTrue(topics("Kurs złotego słabnie, inwestorzy uciekają z GPW", .polish).contains(.finance))
        XCTAssertTrue(topics("Inflacja w Polsce spadła do 2,5 proc.", .polish).contains(.economy))
        XCTAssertTrue(topics("Sejm przyjął ustawę o KRS", .polish).contains(.politics))
        XCTAssertTrue(topics("Forscher entdecken neuen Exoplaneten", .german).contains(.breakthroughs))
        XCTAssertTrue(topics("Die Konjunktur in Deutschland schwächelt", .german).contains(.economy))
        XCTAssertTrue(topics("Scientists discover a new antibiotic", .english).contains(.breakthroughs))
        XCTAssertEqual(topics("Local football club wins cup", .english), [])
    }

    func testPatternCompilation() {
        XCTAssertEqual(TopicClassifier.compile("Stóp* procentow*")?.terms.map(\.word), ["stop", "procentow"])
        XCTAssertEqual(TopicClassifier.compile("s&p 500")?.terms.map(\.word), ["s", "p", "500"])
        XCTAssertNil(TopicClassifier.compile("  * "))
        let pattern = TopicClassifier.compile("stop* procentow*")!
        XCTAssertTrue(pattern.matches(TextNormalizer.tokens("Podwyżka stóp procentowych")))
        XCTAssertFalse(pattern.matches(TextNormalizer.tokens("procentowe stopy")))
    }
}

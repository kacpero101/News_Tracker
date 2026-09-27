import XCTest
@testable import NewsCore

final class MuteListTests: XCTestCase {
    let crash = Article.make(title: "Zderzenie na przejeździe, dwie osoby w szpitalu", summary: "Samochód wjechał pod pociąg",
                             link: "https://a.example/1", language: .polish)
    let drone = Article.make(title: "Nowoczesny dron USA w rękach Iranu", summary: "Irańczycy przejęli drona",
                             link: "https://a.example/2", language: .polish)
    let markets = Article.make(title: "Kurs złotego rośnie", link: "https://a.example/3", language: .polish)

    func testAddSkipsDuplicatesAndInvalidKeywords() {
        var list = MuteList()
        list.add(keywords: ["przejeźdz*", "Przejeźdz*", "  ", "*", "pociąg*"])
        XCTAssertEqual(list.keywords, ["przejeźdz*", "pociąg*"])
        list.remove(keyword: "pociąg*")
        XCTAssertEqual(list.keywords, ["przejeźdz*"])
        XCTAssertFalse(list.isEmpty)
    }

    func testMatcherHidesByKeywordAndByID() {
        var list = MuteList(keywords: ["przejeźdz*"])
        XCTAssertEqual(list.matcher().visible([crash, drone, markets]).map(\.id), [drone.id, markets.id])
        XCTAssertEqual(list.matcher().matchingKeywords(crash), ["przejeźdz*"])

        // Inflected forms and diacritics: "Iranu" is caught by "iran*" written without diacritics.
        list.add(keywords: ["iran*"])
        list.hiddenArticleIDs.insert(markets.id)
        XCTAssertEqual(list.matcher().visible([crash, drone, markets]), [])
        XCTAssertTrue(MuteList().matcher().visible([crash]).count == 1)
    }

    func testSuggestionsFromHeadline() {
        XCTAssertEqual(SimilarNewsSuggester.suggestions(for: crash), ["zderzenie", "przejeździe", "dwie", "osoby", "szpitalu"])
        XCTAssertEqual(SimilarNewsSuggester.suggestions(for: drone), ["nowoczesny", "dron", "USA", "rękach", "iranu"])
        let english = Article.make(title: "The Fed says rates will stay high in 2026", link: "https://a.example/4")
        XCTAssertEqual(SimilarNewsSuggester.suggestions(for: english, limit: 3), ["rates", "stay", "high"])
    }

    func testStemMatchesInflections() {
        XCTAssertEqual(SimilarNewsSuggester.stem("Iranu"), "iran*")
        XCTAssertEqual(SimilarNewsSuggester.stem("przejeździe"), "przejeźdz*")
        XCTAssertEqual(SimilarNewsSuggester.stem("USA"), "USA")
        XCTAssertEqual(SimilarNewsSuggester.stem("dron"), "dron")
        let matcher = MuteList(keywords: [SimilarNewsSuggester.stem("Iranu")]).matcher()
        XCTAssertTrue(matcher.isMuted(Article.make(title: "Sankcje wobec Iranu", link: "https://a.example/5")))
        XCTAssertTrue(matcher.isMuted(Article.make(title: "Iran threatens", link: "https://a.example/6")))
    }
}

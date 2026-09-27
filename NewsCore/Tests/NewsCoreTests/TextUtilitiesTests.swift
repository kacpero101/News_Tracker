import XCTest
@testable import NewsCore

final class TextUtilitiesTests: XCTestCase {
    func testHTMLPlainText() {
        XCTAssertEqual(HTMLText.plainText(from: "<p>Hello&nbsp;<b>world</b></p><p>Next</p>"), "Hello world Next")
        XCTAssertEqual(HTMLText.plainText(from: "A &#8211; B &#x2014; C &amp; D"), "A – B — C & D")
        XCTAssertEqual(HTMLText.plainText(from: "<script>alert(1)</script>Text<style>p{}</style>"), "Text")
        XCTAssertEqual(HTMLText.plainText(from: "Fish & chips; &unknown; stays"), "Fish & chips; &unknown; stays")
    }

    func testFoldingRemovesDiacritics() {
        XCTAssertEqual(TextNormalizer.fold("Złoty ŚWIAT Żółć"), "zloty swiat zolc")
        XCTAssertEqual(TextNormalizer.fold("Börse Straße"), "borse strasse")
        XCTAssertEqual(TextNormalizer.tokens("Hello, world! 2024"), ["hello", "world", "2024"])
    }

    func testDateParserFormats() {
        let parser = FeedDateParser()
        XCTAssertEqual(parser.parse("Wed, 01 May 2024 10:30:00 GMT"), date("2024-05-01T10:30:00Z"))
        XCTAssertEqual(parser.parse("Wed, 01 May 2024 10:30:00 +0200"), date("2024-05-01T08:30:00Z"))
        XCTAssertEqual(parser.parse("Wed, 1 May 2024 10:30:00 UT"), date("2024-05-01T10:30:00Z"))
        XCTAssertEqual(parser.parse("Wed, 01 May 2024 10:30:00 UTC"), date("2024-05-01T10:30:00Z"))
        XCTAssertEqual(parser.parse("2024-05-01T10:30:00Z"), date("2024-05-01T10:30:00Z"))
        XCTAssertEqual(parser.parse("2024-05-01T12:30:00+02:00"), date("2024-05-01T10:30:00Z"))
        XCTAssertEqual(parser.parse("2024-05-01"), date("2024-05-01T00:00:00Z"))
        XCTAssertNil(parser.parse("not a date"))
        XCTAssertNil(parser.parse(""))
    }
}

import XCTest
@testable import NewsCore

final class ConfigurationTests: XCTestCase {
    func testBundledSourcesAreValid() throws {
        let sources = try NewsConfiguration.defaultSources()
        XCTAssertGreaterThanOrEqual(sources.count, 15)
        XCTAssertEqual(Set(sources.map(\.id)).count, sources.count, "Source IDs must be unique")
        for language in Language.allCases {
            XCTAssertTrue(sources.contains { $0.language == language }, "No source for \(language)")
        }
        for topic in Topic.builtIn {
            XCTAssertTrue(sources.contains { $0.defaultCategory == topic }, "No source for \(topic)")
        }
        for source in sources {
            XCTAssertEqual(source.url.scheme, "https", "\(source.id) should use HTTPS")
        }
    }

    func testBundledKeywordsCoverAllTopicsAndLanguages() throws {
        let keywords = try NewsConfiguration.defaultKeywords()
        for topic in Topic.builtIn {
            let list = try XCTUnwrap(keywords.topics[topic], "Missing keywords for \(topic)")
            for language in Language.allCases {
                XCTAssertFalse(list.keywords(for: language).isEmpty, "\(topic) has no \(language) keywords")
            }
        }
    }

    func testSourcesDecodingDefaultsAndDuplicates() throws {
        let json = """
        {"sources": [
          {"id": "a", "name": "A", "url": "https://a.example/rss", "language": "pl"},
          {"id": "a", "name": "A2", "url": "https://a2.example/rss", "language": "en", "defaultCategory": "crypto", "verified": true}
        ]}
        """
        let sources = try NewsConfiguration.decodeSources(from: Data(json.utf8))
        XCTAssertEqual(sources.count, 1)
        XCTAssertNil(sources[0].defaultCategory)
        XCTAssertFalse(sources[0].verified)
    }

    func testKeywordListAcceptsAdditionalTopicsButNotEmptyNames() throws {
        let json = #"{"topics": {"sports": {"en": ["goal"]}}}"#
        XCTAssertEqual(try NewsConfiguration.decodeKeywords(from: Data(json.utf8)).topics.keys.map(\.rawValue), ["sports"])
        XCTAssertThrowsError(try NewsConfiguration.decodeKeywords(from: Data(#"{"topics": {" ": {}}}"#.utf8)))
    }
}

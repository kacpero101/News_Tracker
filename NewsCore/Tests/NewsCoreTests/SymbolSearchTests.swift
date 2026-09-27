import XCTest
@testable import NewsCore

final class SymbolSearchTests: XCTestCase {
    func testParsesSupportedInstruments() throws {
        let results = try YahooSymbolSearch.parse(Fixtures.data("yahoo_search.json"))
        XCTAssertEqual(results.map(\.symbol), ["URNU.L", "URNU.DE", "UEC", "BTC-USD"])
        XCTAssertEqual(results[0], SymbolSearchResult(symbol: "URNU.L", name: "Global X Uranium UCITS ETF", exchange: "London", kind: .etf))
        XCTAssertEqual(results[1].name, "Global X Uranium UCITS ETF")
        XCTAssertEqual(results[2].kind, .stock)
        XCTAssertEqual(results[3].kind, .crypto)
        XCTAssertEqual(try YahooSymbolSearch.parse(Data("{}".utf8)), [])
        XCTAssertThrowsError(try YahooSymbolSearch.parse(Data("oops".utf8)))
    }

    func testRequest() throws {
        let request = try YahooSymbolSearch.request(query: " uranium etf ")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://query1.finance.yahoo.com/v1/finance/search?q=uranium%20etf&quotesCount=15&newsCount=0&listsCount=0")
        XCTAssertThrowsError(try YahooSymbolSearch.request(query: "  "))
    }

    func testSearchUsesClient() async throws {
        let url = try YahooSymbolSearch.request(query: "URNU").url!
        let client = MockHTTPClient([url: .ok(try Fixtures.data("yahoo_search.json"))])
        let results = try await YahooSymbolSearch(client: client).search("URNU")
        XCTAssertEqual(results.count, 4)
    }

    func testUnknownYahooSymbolGivesHelpfulError() async throws {
        let asset = WatchedAsset(name: "Uranium", symbol: "URNX", kind: .etf, provider: .yahoo,
                                 rules: [AlertRule(windowHours: 24, thresholdPercent: 5)])
        let url = try YahooFinanceProvider.request(symbol: "URNX", window: 3600).url!
        let provider = YahooFinanceProvider(client: MockHTTPClient([url: .status(404)]))
        do {
            _ = try await provider.history(for: asset, covering: 3600)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? PriceProviderError, .symbolNotFound("URNX", provider: .yahoo))
            XCTAssertTrue(error.localizedDescription.contains(".DE (Xetra)"))
        }
    }
}

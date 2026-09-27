import XCTest
@testable import NewsCore

final class PriceProviderTests: XCTestCase {
    func testYahooParsesChartSkippingNullsAndAddsMarketPrice() throws {
        let series = try YahooFinanceProvider.parse(Fixtures.data("yahoo_chart.json"), assetID: "aapl")
        XCTAssertEqual(series.currency, "USD")
        XCTAssertEqual(series.points.map(\.price), [100, 101.5, 99, 95.5, 96.2, 97])
        XCTAssertEqual(series.points.first?.date, date("2024-05-01T08:00:00Z"))
        XCTAssertEqual(series.latest?.date, date("2024-05-01T13:10:00Z"))
    }

    func testYahooErrorResponse() throws {
        XCTAssertThrowsError(try YahooFinanceProvider.parse(Fixtures.data("yahoo_error.json"), assetID: "x")) {
            XCTAssertEqual($0 as? PriceProviderError, .noData("No data found, symbol may be delisted"))
        }
        XCTAssertThrowsError(try YahooFinanceProvider.parse(Data("oops".utf8), assetID: "x"))
    }

    func testYahooRequest() throws {
        let request = try YahooFinanceProvider.request(symbol: "PKN.WA", window: 54 * 3600)
        XCTAssertEqual(request.url?.absoluteString,
                       "https://query1.finance.yahoo.com/v8/finance/chart/PKN.WA?range=5d&interval=15m&includePrePost=false")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))
        XCTAssertEqual(YahooFinanceProvider.rangeAndInterval(for: 7 * 86_400).range, "1mo")
        XCTAssertThrowsError(try YahooFinanceProvider.request(symbol: "", window: 3600))
    }

    func testCoinGeckoParsesAndBuildsRequest() throws {
        let series = try CoinGeckoProvider.parse(Fixtures.data("coingecko_market_chart.json"), assetID: "btc", currency: "usd")
        XCTAssertEqual(series.currency, "USD")
        XCTAssertEqual(series.points.count, 5)
        XCTAssertEqual(series.latest?.price, 66100)
        XCTAssertEqual(series.latest?.date, date("2024-05-01T12:00:00Z"))

        let request = try CoinGeckoProvider.request(coinID: "Bitcoin", currency: "PLN", window: 54 * 3600)
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.coingecko.com/api/v3/coins/bitcoin/market_chart?vs_currency=pln&days=3")
        XCTAssertThrowsError(try CoinGeckoProvider.request(coinID: "../etc", currency: "usd", window: 3600))
    }

    func testRunnerFetchesDetectsAndIsolatesFailures() async throws {
        let btc = WatchedAsset(id: "btc", name: "Bitcoin", symbol: "bitcoin", kind: .crypto, provider: .coingecko, currency: "usd",
                               rules: [AlertRule(windowHours: 48, thresholdPercent: 8)])
        let aapl = WatchedAsset(id: "aapl", name: "Apple", symbol: "AAPL", kind: .stock, provider: .yahoo,
                                rules: [AlertRule(windowHours: 24, thresholdPercent: 5)])
        let broken = WatchedAsset(id: "broken", name: "Broken", symbol: "NOPE", kind: .stock, provider: .yahoo,
                                  rules: [AlertRule(windowHours: 24, thresholdPercent: 5)])
        let noRules = WatchedAsset(id: "idle", name: "Idle", symbol: "IDLE", kind: .stock, provider: .yahoo, rules: [])

        let client = MockHTTPClient([
            try CoinGeckoProvider.request(coinID: "bitcoin", currency: "usd", window: 54 * 3600).url!: .ok(try Fixtures.data("coingecko_market_chart.json")),
            try YahooFinanceProvider.request(symbol: "AAPL", window: 30 * 3600).url!: .ok(try Fixtures.data("yahoo_chart.json")),
            try YahooFinanceProvider.request(symbol: "NOPE", window: 30 * 3600).url!: .status(404),
        ])
        let runner = PriceWatchRunner(prices: PriceService(client: client))
        let report = await runner.run(assets: [btc, aapl, broken, noRules], now: date("2024-05-01T14:00:00Z"), previousCheck: nil)

        // BTC: 60 000 → 66 100 = +10.2 % (≥ 8 %). AAPL: high 101.5 → 97 = -4.4 % (< 5 %).
        XCTAssertEqual(report.alerts.map(\.asset.id), ["btc"])
        XCTAssertEqual(report.alerts.first?.move.changePercent ?? 0, 10.1667, accuracy: 0.001)
        XCTAssertEqual(Set(report.series.keys), ["btc", "aapl"])
        XCTAssertEqual(report.failures, ["broken": "HTTP status 404"])
        XCTAssertEqual(client.requests.count, 3)
    }

    func testNtfyRequest() throws {
        let asset = WatchedAsset(name: "Bitcoin", symbol: "bitcoin", kind: .crypto, provider: .coingecko,
                                 rules: [AlertRule(windowHours: 48, thresholdPercent: 8)])
        let move = PriceMove(isRise: false, changePercent: -12.5,
                             from: PricePoint(date: Date(), price: 80), to: PricePoint(date: Date(), price: 70))
        let alert = PriceAlert(asset: asset, rule: asset.rules[0], move: move, currency: "USD")
        let notifier = NtfyNotifier(topic: "my-secret-topic", client: MockHTTPClient())
        let request = try notifier.request(for: alert)

        XCTAssertEqual(request.url?.absoluteString, "https://ntfy.sh")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["topic"] as? String, "my-secret-topic")
        XCTAssertEqual(body["title"] as? String, "Bitcoin ▼ -12,5% w 48 h")
        // -12.5 % is at least 1.5× the 8 % threshold → max priority.
        XCTAssertEqual(body["priority"] as? Int, 5)
        XCTAssertEqual(body["click"] as? String, "https://www.coingecko.com/en/coins/bitcoin")
    }

    func testNtfyDeliverSendsOneRequestPerAlert() async throws {
        let server = URL(string: "https://ntfy.example.org")!
        let client = MockHTTPClient([server: .ok(Data("{}".utf8))])
        let asset = WatchedAsset(name: "A", symbol: "A", kind: .stock, provider: .yahoo, rules: [AlertRule(windowHours: 1, thresholdPercent: 1)])
        let move = PriceMove(isRise: true, changePercent: 2, from: PricePoint(date: Date(), price: 1), to: PricePoint(date: Date(), price: 1.02))
        let alert = PriceAlert(asset: asset, rule: asset.rules[0], move: move, currency: nil)
        try await NtfyNotifier(topic: "t", server: server, client: client).deliver([alert, alert])
        XCTAssertEqual(client.requests.count, 2)
    }

    func testWatchlistConfiguration() throws {
        let config = try PriceWatchConfiguration.defaultWatchlist()
        XCTAssertFalse(config.assets.isEmpty)
        XCTAssertTrue(config.assets.allSatisfy { !$0.rules.isEmpty })
        let btc = try XCTUnwrap(config.assets.first { $0.id == "btc" })
        XCTAssertEqual(btc.rules.first, AlertRule(windowHours: 48, thresholdPercent: 8, direction: .both))
        XCTAssertEqual(btc.rules.first?.id, "48h-8pct-both")

        // Round trip through the export format.
        let reloaded = try PriceWatchConfiguration.decode(from: config.encodedJSON())
        XCTAssertEqual(reloaded, config)

        let invalid = #"{"assets":[{"symbol":"X","rules":[{"windowHours":0,"thresholdPercent":5}]}]}"#
        XCTAssertThrowsError(try PriceWatchConfiguration.decode(from: Data(invalid.utf8)))
        let minimal = try PriceWatchConfiguration.decode(from: Data(#"{"assets":[{"symbol":"MSFT"}]}"#.utf8))
        XCTAssertEqual(minimal.assets.first?.id, "yahoo:msft")
        XCTAssertEqual(minimal.assets.first?.provider, .yahoo)
    }
}

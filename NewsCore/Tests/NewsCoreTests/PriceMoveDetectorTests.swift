import XCTest
@testable import NewsCore

final class PriceMoveDetectorTests: XCTestCase {
    let t0 = date("2024-05-01T00:00:00Z")

    /// Hourly points with the given prices, starting at `t0`.
    private func hourly(_ prices: [Double]) -> [PricePoint] {
        prices.enumerated().map { PricePoint(date: t0.addingTimeInterval(Double($0.offset) * 3600), price: $0.element) }
    }

    private func hour(_ h: Double) -> Date { t0.addingTimeInterval(h * 3600) }

    func testDetectsRiseFromWindowLow() {
        // Low of 90 at hour 2, now 99 → +10 %.
        let points = hourly([100, 95, 90, 94, 99])
        let rule = AlertRule(windowHours: 48, thresholdPercent: 8)
        let move = PriceMoveDetector.evaluate(points, rule: rule, at: hour(4))
        XCTAssertEqual(move?.isRise, true)
        XCTAssertEqual(move?.changePercent ?? 0, 10, accuracy: 0.0001)
        XCTAssertEqual(move?.from.price, 90)
        XCTAssertEqual(move?.to.price, 99)
    }

    func testDetectsDropFromWindowHigh() {
        let points = hourly([100, 110, 104, 98])
        let move = PriceMoveDetector.evaluate(points, rule: AlertRule(windowHours: 24, thresholdPercent: 10), at: hour(3))
        XCTAssertEqual(move?.isRise, false)
        XCTAssertEqual(move?.changePercent ?? 0, -10.909, accuracy: 0.001)
    }

    func testBelowThresholdReturnsNil() {
        let points = hourly([100, 103, 105])
        XCTAssertNil(PriceMoveDetector.evaluate(points, rule: AlertRule(windowHours: 24, thresholdPercent: 8), at: hour(2)))
    }

    func testWindowExcludesOlderPricesButKeepsStartReference() {
        // The last point before the window start is used as the price at the window start.
        let points = hourly([50, 100, 101, 102])
        let rule = AlertRule(windowHours: 2, thresholdPercent: 8)
        // Window [1h, 3h]: first point inside is hour 1, reference is hour 0 (50) → +104 %.
        XCTAssertEqual(PriceMoveDetector.evaluate(points, rule: rule, at: hour(3))?.from.price, 50)
        // Window [1.5h, 3.5h]: reference is hour 1 (100) → +2 %, below threshold.
        XCTAssertNil(PriceMoveDetector.evaluate(points, rule: rule, at: hour(3.5)))
    }

    func testIgnoresFuturePointsAndDirectionFilter() {
        let points = hourly([100, 80, 120])
        let upOnly = AlertRule(windowHours: 24, thresholdPercent: 5, direction: .up)
        let downOnly = AlertRule(windowHours: 24, thresholdPercent: 5, direction: .down)
        // At hour 1 only the drop to 80 exists; the future 120 is ignored.
        XCTAssertNil(PriceMoveDetector.evaluate(points, rule: upOnly, at: hour(1)))
        XCTAssertEqual(PriceMoveDetector.evaluate(points, rule: downOnly, at: hour(1))?.changePercent ?? 0, -20, accuracy: 0.001)
        // At hour 2: rise from 80 is +50 %, drop from 100... latest 120 is above, so only rise.
        XCTAssertEqual(PriceMoveDetector.evaluate(points, rule: upOnly, at: hour(2))?.changePercent ?? 0, 50, accuracy: 0.001)
        XCTAssertNil(PriceMoveDetector.evaluate(points, rule: downOnly, at: hour(2)))
    }

    func testDisabledRuleAndTooFewPoints() {
        var rule = AlertRule(windowHours: 24, thresholdPercent: 1)
        XCTAssertNil(PriceMoveDetector.evaluate(hourly([100]), rule: rule, at: hour(0)))
        rule.isEnabled = false
        XCTAssertNil(PriceMoveDetector.evaluate(hourly([100, 150]), rule: rule, at: hour(1)))
    }

    func testWindowChange() {
        let points = hourly([100, 90, 105])
        XCTAssertEqual(PriceMoveDetector.windowChange(points, window: 3 * 3600, at: hour(2)) ?? 0, 5, accuracy: 0.001)
    }

    func testEngineReportsOnlyNewMoves() {
        let asset = WatchedAsset(name: "Bitcoin", symbol: "bitcoin", kind: .crypto, provider: .coingecko,
                                 rules: [AlertRule(windowHours: 48, thresholdPercent: 8)])
        let series = PriceSeries(assetID: asset.id, currency: "USD", points: hourly([100, 104, 109, 111]))

        // First check ever: the move is reported.
        XCTAssertEqual(PriceAlertEngine.newAlerts(for: asset, series: series, now: hour(3), previousCheck: nil).count, 1)
        // Previous check at hour 1 (+4 %, below threshold) → new move, reported.
        XCTAssertEqual(PriceAlertEngine.newAlerts(for: asset, series: series, now: hour(3), previousCheck: hour(1)).count, 1)
        // Previous check at hour 2 (+9 %, already above threshold) → not reported again.
        XCTAssertEqual(PriceAlertEngine.newAlerts(for: asset, series: series, now: hour(3), previousCheck: hour(2)).count, 0)
    }

    func testEngineReportsReversal() {
        let asset = WatchedAsset(name: "X", symbol: "X", kind: .stock, provider: .yahoo,
                                 rules: [AlertRule(windowHours: 3, thresholdPercent: 8)])
        // Rise to 110 at hour 1, then crash to 95 at hour 3 (drop from high 110 = -13.6 %).
        let series = PriceSeries(assetID: asset.id, currency: nil, points: hourly([100, 110, 108, 95]))
        let alerts = PriceAlertEngine.newAlerts(for: asset, series: series, now: hour(3), previousCheck: hour(1))
        XCTAssertEqual(alerts.map(\.move.isRise), [false])
    }

    func testSeriesDropsInvalidPricesAndSorts() {
        let series = PriceSeries(assetID: "a", currency: nil, points: [
            PricePoint(date: hour(2), price: 3), PricePoint(date: hour(0), price: 1),
            PricePoint(date: hour(1), price: .nan), PricePoint(date: hour(3), price: 0),
        ])
        XCTAssertEqual(series.points.map(\.price), [1, 3])
    }

    func testFormatter() {
        let asset = WatchedAsset(name: "Bitcoin", symbol: "bitcoin", kind: .crypto, provider: .coingecko, currency: "usd",
                                 rules: [AlertRule(windowHours: 48, thresholdPercent: 8)])
        let move = PriceMove(isRise: true, changePercent: 9.24,
                             from: PricePoint(date: hour(0), price: 60000), to: PricePoint(date: hour(5), price: 65544.5))
        let alert = PriceAlert(asset: asset, rule: asset.rules[0], move: move, currency: "USD")
        XCTAssertEqual(PriceAlertFormatter.title(for: alert), "Bitcoin ▲ +9,2% w 48 h")
        XCTAssertEqual(PriceAlertFormatter.body(for: alert),
                       "Cena 65 544,50 USD (minimum w oknie: 60 000,00 USD). Próg reguły: 8,0% / 48 h.")
        XCTAssertEqual(PriceAlertFormatter.percent(-10), "-10,0%")
        XCTAssertEqual(PriceAlertFormatter.window(168), "7 dni")
        XCTAssertEqual(PriceAlertFormatter.window(1.5), "1,5 h")
        XCTAssertEqual(PriceAlertFormatter.price(1234567.891), "1 234 567,89")
        XCTAssertEqual(PriceAlertFormatter.price(0.12345), "0,123450")
    }
}

import XCTest
@testable import NewsCore

final class PriceChartDataTests: XCTestCase {
    let t0 = date("2024-05-01T00:00:00Z")

    private func series(_ prices: [Double], stepHours: Double = 1) -> PriceSeries {
        PriceSeries(assetID: "a", currency: "USD", points: prices.enumerated().map {
            PricePoint(date: t0.addingTimeInterval(Double($0.offset) * stepHours * 3600), price: $0.element)
        })
    }

    func testPointsInLastWindowCountBackFromLatestPoint() {
        let s = series([10, 11, 12, 13, 14]) // hours 0...4
        XCTAssertEqual(s.points(inLast: 2 * 3600).map(\.price), [12, 13, 14])
        // Explicit end (e.g. "now" two hours after the last point).
        XCTAssertEqual(s.points(inLast: 2 * 3600, endingAt: t0.addingTimeInterval(6 * 3600)).map(\.price), [14])
        XCTAssertEqual(PriceSeries(assetID: "a", currency: nil, points: []).points(inLast: 3600), [])
    }

    func testDownsampleKeepsEndsAndLimit() {
        let points = series((0..<1000).map(Double.init)).points
        let reduced = PriceSeries.downsample(points, maxPoints: 100)
        XCTAssertEqual(reduced.count, 100)
        XCTAssertEqual(reduced.first, points.first)
        XCTAssertEqual(reduced.last, points.last)
        XCTAssertEqual(PriceSeries.downsample(Array(points.prefix(10)), maxPoints: 100).count, 10)
    }

    func testSummary() throws {
        let summary = try XCTUnwrap(PriceSeries.summary(of: series([100, 90, 120, 110]).points))
        XCTAssertEqual(summary.first.price, 100)
        XCTAssertEqual(summary.last.price, 110)
        XCTAssertEqual(summary.low.price, 90)
        XCTAssertEqual(summary.high.price, 120)
        XCTAssertEqual(summary.changePercent, 10, accuracy: 0.0001)
        XCTAssertNil(PriceSeries.summary(of: []))
    }
}

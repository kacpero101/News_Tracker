import Foundation

public struct PricePoint: Codable, Hashable, Sendable {
    public var date: Date
    public var price: Double

    public init(date: Date, price: Double) {
        self.date = date
        self.price = price
    }
}

/// Price history of one asset, sorted by date (oldest first).
public struct PriceSeries: Codable, Equatable, Sendable {
    public var assetID: String
    public var currency: String?
    public private(set) var points: [PricePoint]

    public init(assetID: String, currency: String?, points: [PricePoint]) {
        self.assetID = assetID
        self.currency = currency
        self.points = points
            .filter { $0.price.isFinite && $0.price > 0 }
            .sorted { $0.date < $1.date }
    }

    public var latest: PricePoint? { points.last }
}

/// First/last/min/max of a price range (for charts).
public struct PriceRangeSummary: Equatable, Sendable {
    public var first: PricePoint
    public var last: PricePoint
    public var low: PricePoint
    public var high: PricePoint
    /// Change from the first to the last point, in percent.
    public var changePercent: Double
}

public extension PriceSeries {
    /// Points of the last `window` seconds, counted back from `end`
    /// (default: the latest point, so a weekend does not empty a stock chart).
    func points(inLast window: TimeInterval, endingAt end: Date? = nil) -> [PricePoint] {
        guard let end = end ?? latest?.date else { return [] }
        let start = end.addingTimeInterval(-window)
        return points.filter { $0.date >= start && $0.date <= end }
    }

    /// At most `maxPoints` evenly spaced points, always keeping the first and the last one.
    static func downsample(_ points: [PricePoint], maxPoints: Int) -> [PricePoint] {
        guard maxPoints >= 2, points.count > maxPoints else { return points }
        let step = Double(points.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { points[Int((Double($0) * step).rounded())] }
    }

    static func summary(of points: [PricePoint]) -> PriceRangeSummary? {
        guard let first = points.first, let last = points.last,
              let low = points.min(by: { $0.price < $1.price }),
              let high = points.max(by: { $0.price < $1.price })
        else { return nil }
        return PriceRangeSummary(
            first: first, last: last, low: low, high: high,
            changePercent: (last.price - first.price) / first.price * 100
        )
    }
}

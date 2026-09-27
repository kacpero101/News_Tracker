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

import Foundation

/// A detected price move inside a rule's time window.
public struct PriceMove: Equatable, Sendable {
    public var isRise: Bool
    /// Signed change in percent (negative for drops).
    public var changePercent: Double
    /// Reference point (window low for rises, window high for drops).
    public var from: PricePoint
    /// Latest price.
    public var to: PricePoint
}

/// Detects sudden price moves.
///
/// For a window `[now - windowHours, now]` the latest price is compared with the
/// **lowest** (rise) and **highest** (drop) earlier price in the window. The price at
/// the window start (last point before the window) is included as a reference.
/// This catches a fast move even when it started in the middle of the window.
public enum PriceMoveDetector {
    /// Points relevant for a window ending at `now`: the last point before the window
    /// start (price at the window start) plus all points inside the window.
    static func windowPoints(_ points: [PricePoint], window: TimeInterval, at now: Date) -> [PricePoint] {
        let start = now.addingTimeInterval(-window)
        let upToNow = points.filter { $0.date <= now }
        guard let firstInside = upToNow.firstIndex(where: { $0.date >= start }) else { return [] }
        let from = firstInside > 0 ? firstInside - 1 : firstInside
        return Array(upToNow[from...])
    }

    /// Largest move in the window (rise or drop), regardless of any threshold.
    public static func largestMove(in points: [PricePoint], window: TimeInterval, at now: Date, direction: MoveDirection = .both) -> PriceMove? {
        let relevant = windowPoints(points, window: window, at: now)
        guard relevant.count >= 2, let latest = relevant.last else { return nil }
        let earlier = relevant.dropLast()

        var candidates: [PriceMove] = []
        if direction.allows(isRise: true), let low = earlier.min(by: { $0.price < $1.price }) {
            let change = (latest.price - low.price) / low.price * 100
            if change > 0 { candidates.append(PriceMove(isRise: true, changePercent: change, from: low, to: latest)) }
        }
        if direction.allows(isRise: false), let high = earlier.max(by: { $0.price < $1.price }) {
            let change = (latest.price - high.price) / high.price * 100
            if change < 0 { candidates.append(PriceMove(isRise: false, changePercent: change, from: high, to: latest)) }
        }
        return candidates.max { abs($0.changePercent) < abs($1.changePercent) }
    }

    /// The move that satisfies the rule at `now`, or `nil`.
    public static func evaluate(_ points: [PricePoint], rule: AlertRule, at now: Date) -> PriceMove? {
        guard rule.isEnabled,
              let move = largestMove(in: points, window: rule.window, at: now, direction: rule.direction),
              abs(move.changePercent) >= rule.thresholdPercent
        else { return nil }
        return move
    }

    /// Simple change from the price at the window start to the latest price (for display).
    public static func windowChange(_ points: [PricePoint], window: TimeInterval, at now: Date) -> Double? {
        let relevant = windowPoints(points, window: window, at: now)
        guard relevant.count >= 2, let first = relevant.first, let last = relevant.last else { return nil }
        return (last.price - first.price) / first.price * 100
    }
}

/// A rule that fired for an asset.
public struct PriceAlert: Equatable, Sendable, Identifiable {
    public var id: String { "\(asset.id)|\(rule.id)|\(move.to.date.timeIntervalSince1970)" }
    public var asset: WatchedAsset
    public var rule: AlertRule
    public var move: PriceMove
    public var currency: String?
}

public enum PriceAlertEngine {
    /// Alerts that are **new** since `previousCheck`: a rule fires when its condition holds
    /// now but did not hold (in the same direction) at the previous check. This way one
    /// move produces one notification, without storing per-rule state.
    public static func newAlerts(for asset: WatchedAsset, series: PriceSeries, now: Date, previousCheck: Date?) -> [PriceAlert] {
        asset.rules.compactMap { rule in
            guard let move = PriceMoveDetector.evaluate(series.points, rule: rule, at: now) else { return nil }
            if let previousCheck, previousCheck < now,
               let before = PriceMoveDetector.evaluate(series.points, rule: rule, at: previousCheck),
               before.isRise == move.isRise {
                return nil
            }
            return PriceAlert(asset: asset, rule: rule, move: move, currency: series.currency)
        }
    }
}

import Foundation

/// One watcher pass: download prices for all assets, detect new moves, notify.
/// Shared by the iOS app (local notifications) and the `price-watch` CLI (ntfy).
public struct PriceWatchRunner: Sendable {
    public struct Report: Sendable {
        public var alerts: [PriceAlert]
        public var series: [String: PriceSeries]
        /// Asset ID → error message; one failing asset never stops the others.
        public var failures: [String: String]
    }

    private let prices: PriceHistoryProvider
    /// Extra history fetched on top of the longest window (reference price before the window).
    private let historyMargin: TimeInterval

    public init(prices: PriceHistoryProvider = PriceService(), historyMargin: TimeInterval = 6 * 3600) {
        self.prices = prices
        self.historyMargin = historyMargin
    }

    public func run(assets: [WatchedAsset], now: Date = Date(), previousCheck: Date?) async -> Report {
        let results = await withTaskGroup(of: (String, Result<PriceSeries, Error>).self) { group in
            for asset in assets where asset.longestWindow > 0 {
                group.addTask {
                    do {
                        return (asset.id, .success(try await prices.history(for: asset, covering: asset.longestWindow + historyMargin)))
                    } catch {
                        return (asset.id, .failure(error))
                    }
                }
            }
            var collected: [String: Result<PriceSeries, Error>] = [:]
            for await (id, result) in group {
                collected[id] = result
            }
            return collected
        }

        var report = Report(alerts: [], series: [:], failures: [:])
        for asset in assets {
            switch results[asset.id] {
            case let .success(series)?:
                report.series[asset.id] = series
                report.alerts += PriceAlertEngine.newAlerts(for: asset, series: series, now: now, previousCheck: previousCheck)
            case let .failure(error)?:
                report.failures[asset.id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            case nil:
                break
            }
        }
        return report
    }
}

/// Persisted state of the watcher (time of the previous successful check).
public struct PriceWatchState: Codable, Equatable, Sendable {
    public var lastCheck: Date?

    public init(lastCheck: Date?) {
        self.lastCheck = lastCheck
    }
}

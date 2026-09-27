import Foundation
import NewsCore
import Observation

/// A detected price alert kept in the alerts archive.
struct AlertRecord: Codable, Identifiable, Hashable {
    var id: String
    var assetID: String
    var title: String
    var body: String
    var date: Date
    var isRise: Bool
    // Added later – optional so older archives still decode.
    var assetName: String?
    var changePercent: Double?
    var quoteURL: URL?
}

/// An instrument that appears in the alerts archive (for filtering).
struct AlertAssetOption: Identifiable, Hashable {
    var id: String
    var name: String
}

/// Watchlist, latest prices and price alerts.
/// Detection logic lives in `NewsCore` (`PriceWatchRunner`); this class only keeps UI state.
@MainActor
@Observable
final class MarketStore {
    private(set) var assets: [WatchedAsset] = []
    private(set) var series: [String: PriceSeries] = [:]
    private(set) var failures: [String: String] = [:]
    /// Alerts archive, newest first (up to `alertsLimit`).
    private(set) var recentAlerts: [AlertRecord] = []
    private(set) var isChecking = false
    private(set) var lastCheck: Date?
    /// Last 7 days of prices per asset, for the charts in the Markets list.
    private(set) var chartSeries: [String: PriceSeries] = [:]
    private var chartFetchedAt: [String: Date] = [:]

    nonisolated static let chartWindow: TimeInterval = 7 * 86_400
    /// Charts are downloaded again at most this often (fewer requests to free APIs).
    private let chartMaxAge: TimeInterval = 30 * 60

    /// Local notifications (off until the user enables them and grants permission).
    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    private let watchlistStore: JSONFileStore<PriceWatchConfiguration>?
    private let alertsStore: JSONFileStore<[AlertRecord]>?
    private let defaults: UserDefaults
    private let runner = PriceWatchRunner()
    private let notifier = LocalNotifier()
    private let alertsLimit = 1000

    private enum Keys {
        static let notificationsEnabled = "priceNotificationsEnabled"
        static let lastCheck = "priceLastCheck"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ))?.appendingPathComponent("NewsTracker", isDirectory: true)
        watchlistStore = directory.map { JSONFileStore(fileURL: $0.appendingPathComponent("watchlist.json")) }
        alertsStore = directory.map { JSONFileStore(fileURL: $0.appendingPathComponent("price-alerts.json")) }

        notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        lastCheck = defaults.object(forKey: Keys.lastCheck) as? Date

        if let saved = (try? watchlistStore?.load()) ?? nil {
            assets = saved.assets
        } else {
            assets = (try? PriceWatchConfiguration.defaultWatchlist().assets) ?? []
        }
        recentAlerts = ((try? alertsStore?.load()) ?? nil) ?? []
    }

    // MARK: Checking

    /// Downloads prices and posts local notifications for new moves.
    /// Used by pull-to-refresh, app start and the background refresh task.
    @discardableResult
    func check() async -> Int {
        guard !isChecking else { return 0 }
        isChecking = true
        defer { isChecking = false }

        let now = Date()
        let report = await runner.run(assets: assets, now: now, previousCheck: lastCheck)
        series.merge(report.series) { _, new in new }
        failures = report.failures
        lastCheck = now
        defaults.set(now, forKey: Keys.lastCheck)

        guard !report.alerts.isEmpty else { return 0 }
        record(report.alerts)
        if notificationsEnabled {
            try? await notifier.deliver(report.alerts)
        }
        return report.alerts.count
    }

    private func record(_ alerts: [PriceAlert]) {
        let records = alerts.map {
            AlertRecord(
                id: $0.id,
                assetID: $0.asset.id,
                title: PriceAlertFormatter.title(for: $0),
                body: PriceAlertFormatter.body(for: $0),
                date: $0.move.to.date,
                isRise: $0.move.isRise,
                assetName: $0.asset.name,
                changePercent: $0.move.changePercent,
                quoteURL: $0.asset.quoteURL
            )
        }
        let existing = Set(recentAlerts.map(\.id))
        recentAlerts = Array((records.filter { !existing.contains($0.id) } + recentAlerts).prefix(alertsLimit))
        try? alertsStore?.save(recentAlerts)
    }

    func clearAlerts() {
        recentAlerts = []
        try? alertsStore?.delete()
    }

    func deleteAlerts(ids: Set<String>) {
        recentAlerts.removeAll { ids.contains($0.id) }
        try? alertsStore?.save(recentAlerts)
    }

    /// Instruments present in the archive, in order of their latest alert.
    var alertAssets: [AlertAssetOption] {
        var seen = Set<String>()
        return recentAlerts.compactMap { record in
            guard seen.insert(record.assetID).inserted else { return nil }
            let name = record.assetName ?? asset(withID: record.assetID)?.name ?? record.assetID
            return AlertAssetOption(id: record.assetID, name: name)
        }
    }

    /// Link to the quote page (also for alerts saved before links were stored).
    func quoteURL(for record: AlertRecord) -> URL? {
        record.quoteURL ?? asset(withID: record.assetID)?.quoteURL
    }

    // MARK: Charts

    /// Downloads 7-day histories for assets without a fresh chart (all of them when `force`).
    func loadCharts(force: Bool = false) async {
        let now = Date()
        let stale = assets.filter { asset in
            force || chartFetchedAt[asset.id].map { now.timeIntervalSince($0) > chartMaxAge } ?? true
        }
        guard !stale.isEmpty else { return }
        let window = Self.chartWindow
        let prices = PriceService()
        await withTaskGroup(of: (String, PriceSeries?).self) { group in
            for asset in stale {
                group.addTask {
                    (asset.id, try? await prices.history(for: asset, covering: window))
                }
            }
            for await (id, series) in group {
                if let series {
                    chartSeries[id] = series
                    chartFetchedAt[id] = now
                }
            }
        }
    }

    /// Price history of any length (asset detail chart).
    func history(for asset: WatchedAsset, window: TimeInterval) async throws -> PriceSeries {
        try await PriceService().history(for: asset, covering: window)
    }

    // MARK: Notifications

    /// Turns notifications on (asking for permission) or off.
    func setNotificationsEnabled(_ enabled: Bool) async {
        if enabled {
            notificationsEnabled = await LocalNotifier.requestAuthorization()
        } else {
            notificationsEnabled = false
        }
    }

    func sendTestNotification() async {
        try? await notifier.sendTest()
    }

    // MARK: Watchlist editing

    func asset(withID id: String) -> WatchedAsset? {
        assets.first { $0.id == id }
    }

    func upsert(_ asset: WatchedAsset) {
        if let index = assets.firstIndex(where: { $0.id == asset.id }) {
            assets[index] = asset
        } else {
            assets.append(asset)
        }
        series[asset.id] = nil
        chartSeries[asset.id] = nil
        chartFetchedAt[asset.id] = nil
        saveWatchlist()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            series[assets[index].id] = nil
            chartSeries[assets[index].id] = nil
            chartFetchedAt[assets[index].id] = nil
        }
        assets.remove(atOffsets: offsets)
        saveWatchlist()
    }

    func move(from source: IndexSet, to destination: Int) {
        assets.move(fromOffsets: source, toOffset: destination)
        saveWatchlist()
    }

    func resetToDefaults() {
        assets = (try? PriceWatchConfiguration.defaultWatchlist().assets) ?? []
        series = [:]
        saveWatchlist()
    }

    private func saveWatchlist() {
        try? watchlistStore?.save(PriceWatchConfiguration(assets: assets))
    }

    /// Watchlist as `alerts.json` for the GitHub Actions watcher.
    func exportedConfiguration() -> String {
        guard let data = try? PriceWatchConfiguration(assets: assets).encodedJSON() else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Checks that a symbol can be fetched; returns the latest price or an error message.
    func validate(_ asset: WatchedAsset) async -> Result<PricePoint, Error> {
        do {
            let series = try await PriceService().history(for: asset, covering: max(asset.longestWindow, 3600))
            guard let latest = series.latest else { throw PriceProviderError.noData(asset.symbol) }
            return .success(latest)
        } catch {
            return .failure(error)
        }
    }
}

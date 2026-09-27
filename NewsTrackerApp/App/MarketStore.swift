import Foundation
import NewsCore
import Observation

/// A delivered alert kept for the "Recent alerts" list.
struct AlertRecord: Codable, Identifiable, Hashable {
    var id: String
    var assetID: String
    var title: String
    var body: String
    var date: Date
    var isRise: Bool
}

/// Watchlist, latest prices and price alerts.
/// Detection logic lives in `NewsCore` (`PriceWatchRunner`); this class only keeps UI state.
@MainActor
@Observable
final class MarketStore {
    private(set) var assets: [WatchedAsset] = []
    private(set) var series: [String: PriceSeries] = [:]
    private(set) var failures: [String: String] = [:]
    private(set) var recentAlerts: [AlertRecord] = []
    private(set) var isChecking = false
    private(set) var lastCheck: Date?

    /// Local notifications (off until the user enables them and grants permission).
    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    private let watchlistStore: JSONFileStore<PriceWatchConfiguration>?
    private let alertsStore: JSONFileStore<[AlertRecord]>?
    private let defaults: UserDefaults
    private let runner = PriceWatchRunner()
    private let notifier = LocalNotifier()

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
                isRise: $0.move.isRise
            )
        }
        recentAlerts = Array((records + recentAlerts).prefix(50))
        try? alertsStore?.save(recentAlerts)
    }

    func clearAlerts() {
        recentAlerts = []
        try? alertsStore?.delete()
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
        saveWatchlist()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            series[assets[index].id] = nil
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

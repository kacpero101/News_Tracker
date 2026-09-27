import Foundation

/// Kind of a watched instrument (informational; used for UI and defaults).
public enum AssetKind: String, Codable, CaseIterable, Sendable {
    case stock, etf, crypto, index
}

/// Free, key-less price data sources.
public enum PriceProviderID: String, Codable, CaseIterable, Sendable {
    /// Yahoo Finance chart endpoint: stocks, ETFs, indices and crypto (e.g. `AAPL`, `SPY`, `PKN.WA`, `BTC-USD`).
    case yahoo
    /// CoinGecko public API: cryptocurrencies by coin id (e.g. `bitcoin`, `ethereum`).
    case coingecko
}

/// Which price moves a rule reacts to.
public enum MoveDirection: String, Codable, CaseIterable, Sendable {
    case up, down, both

    func allows(isRise: Bool) -> Bool {
        switch self {
        case .up: return isRise
        case .down: return !isRise
        case .both: return true
        }
    }
}

/// "Notify me when the price moves by at least `thresholdPercent` within `windowHours`".
public struct AlertRule: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var windowHours: Double
    public var thresholdPercent: Double
    public var direction: MoveDirection
    public var isEnabled: Bool

    public init(id: String? = nil, windowHours: Double, thresholdPercent: Double, direction: MoveDirection = .both, isEnabled: Bool = true) {
        self.windowHours = windowHours
        self.thresholdPercent = thresholdPercent
        self.direction = direction
        self.isEnabled = isEnabled
        self.id = id ?? AlertRule.defaultID(windowHours: windowHours, thresholdPercent: thresholdPercent, direction: direction)
    }

    public var window: TimeInterval { windowHours * 3600 }

    static func defaultID(windowHours: Double, thresholdPercent: Double, direction: MoveDirection) -> String {
        "\(formatNumber(windowHours))h-\(formatNumber(thresholdPercent))pct-\(direction.rawValue)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, windowHours, thresholdPercent, direction, isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let windowHours = try container.decode(Double.self, forKey: .windowHours)
        let threshold = try container.decode(Double.self, forKey: .thresholdPercent)
        guard windowHours > 0, threshold > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .windowHours, in: container, debugDescription: "windowHours and thresholdPercent must be positive")
        }
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            windowHours: windowHours,
            thresholdPercent: threshold,
            direction: try container.decodeIfPresent(MoveDirection.self, forKey: .direction) ?? .both,
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        )
    }
}

/// An instrument on the watchlist together with its alert rules.
public struct WatchedAsset: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Provider-specific symbol: Yahoo ticker (`AAPL`, `PKN.WA`, `BTC-USD`) or CoinGecko coin id (`bitcoin`).
    public var symbol: String
    public var kind: AssetKind
    public var provider: PriceProviderID
    /// Quote currency for CoinGecko (`usd`, `eur`, `pln`); Yahoo reports its own currency.
    public var currency: String?
    public var rules: [AlertRule]

    public init(
        id: String? = nil,
        name: String,
        symbol: String,
        kind: AssetKind,
        provider: PriceProviderID,
        currency: String? = nil,
        rules: [AlertRule]
    ) {
        self.id = id ?? "\(provider.rawValue):\(symbol.lowercased())"
        self.name = name
        self.symbol = symbol
        self.kind = kind
        self.provider = provider
        self.currency = currency
        self.rules = rules
    }

    /// Longest enabled rule window – how much history has to be downloaded.
    public var longestWindow: TimeInterval {
        rules.filter(\.isEnabled).map(\.window).max() ?? 0
    }

    /// Public web page with the quote (used as notification click target).
    public var quoteURL: URL? {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        switch provider {
        case .yahoo: return URL(string: "https://finance.yahoo.com/quote/\(encoded)")
        case .coingecko: return URL(string: "https://www.coingecko.com/en/coins/\(encoded)")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, kind, provider, currency, rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let symbol = try container.decode(String.self, forKey: .symbol).trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .symbol, in: container, debugDescription: "Empty symbol")
        }
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? symbol,
            symbol: symbol,
            kind: try container.decodeIfPresent(AssetKind.self, forKey: .kind) ?? .stock,
            provider: try container.decodeIfPresent(PriceProviderID.self, forKey: .provider) ?? .yahoo,
            currency: try container.decodeIfPresent(String.self, forKey: .currency),
            rules: try container.decodeIfPresent([AlertRule].self, forKey: .rules) ?? []
        )
    }
}

/// Content of `alerts.json` (GitHub Actions watcher) and the app's watchlist file.
public struct PriceWatchConfiguration: Codable, Equatable, Sendable {
    public var assets: [WatchedAsset]

    public init(assets: [WatchedAsset]) {
        self.assets = assets
    }

    public static func decode(from data: Data) throws -> PriceWatchConfiguration {
        let config = try JSONDecoder().decode(PriceWatchConfiguration.self, from: data)
        var seen = Set<String>()
        return PriceWatchConfiguration(assets: config.assets.filter { seen.insert($0.id).inserted })
    }

    /// Pretty-printed JSON, e.g. for exporting the app watchlist to `alerts.json`.
    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Bundled default watchlist (`Resources/watchlist.json`).
    public static func defaultWatchlist() throws -> PriceWatchConfiguration {
        guard let url = Bundle.module.url(forResource: "watchlist", withExtension: "json") else {
            throw NewsConfiguration.ConfigError.missingResource("watchlist.json")
        }
        return try decode(from: Data(contentsOf: url))
    }
}

/// "8", "2.5" – compact number formatting for identifiers.
func formatNumber(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(value)
}

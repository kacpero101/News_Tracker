import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PriceProviderError: Error, Equatable, LocalizedError {
    case invalidSymbol(String)
    case noData(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidSymbol(symbol): return "Nieprawidłowy symbol: \(symbol)"
        case let .noData(details): return "Brak danych: \(details)"
        case let .invalidResponse(details): return "Nieprawidłowa odpowiedź: \(details)"
        }
    }
}

/// Downloads price history for an asset.
public protocol PriceHistoryProvider: Sendable {
    func history(for asset: WatchedAsset, covering window: TimeInterval) async throws -> PriceSeries
}

extension HTTPClient {
    func fetchJSON(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw HTTPClientError.badStatus(response.statusCode)
        }
        return data
    }
}

// MARK: - Yahoo Finance

/// Unofficial but key-less Yahoo Finance chart endpoint (stocks, ETFs, indices, crypto).
public struct YahooFinanceProvider: PriceHistoryProvider {
    private let client: HTTPClient

    public init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    /// Smallest Yahoo range covering the window, with an interval Yahoo allows for it.
    static func rangeAndInterval(for window: TimeInterval) -> (range: String, interval: String) {
        let days = window / 86_400
        switch days {
        case ...0.9: return ("1d", "5m")
        case ...4.5: return ("5d", "15m")
        case ...28: return ("1mo", "1h")
        case ...85: return ("3mo", "1d")
        default: return ("1y", "1d")
        }
    }

    public static func request(symbol: String, window: TimeInterval) throws -> URLRequest {
        let (range, interval) = rangeAndInterval(for: window)
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              !symbol.isEmpty,
              var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)")
        else { throw PriceProviderError.invalidSymbol(symbol) }
        components.queryItems = [
            URLQueryItem(name: "range", value: range),
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "includePrePost", value: "false"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        // Yahoo rejects requests without a browser-like user agent.
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) NewsTracker/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private struct ChartResponse: Decodable {
        struct Chart: Decodable {
            let result: [Result]?
            let error: ChartError?
        }
        struct ChartError: Decodable {
            let code: String?
            let description: String?
        }
        struct Result: Decodable {
            struct Meta: Decodable {
                let currency: String?
                let regularMarketPrice: Double?
                let regularMarketTime: Double?
            }
            struct Indicators: Decodable {
                struct Quote: Decodable { let close: [Double?]? }
                let quote: [Quote]?
            }
            let meta: Meta?
            let timestamp: [Double]?
            let indicators: Indicators?
        }
        let chart: Chart
    }

    public static func parse(_ data: Data, assetID: String) throws -> PriceSeries {
        let response: ChartResponse
        do {
            response = try JSONDecoder().decode(ChartResponse.self, from: data)
        } catch {
            throw PriceProviderError.invalidResponse("Yahoo: \(error.localizedDescription)")
        }
        if let error = response.chart.error {
            throw PriceProviderError.noData(error.description ?? error.code ?? "Yahoo error")
        }
        guard let result = response.chart.result?.first else {
            throw PriceProviderError.noData("Yahoo: pusty wynik")
        }
        let timestamps = result.timestamp ?? []
        let closes = result.indicators?.quote?.first?.close ?? []
        var points = zip(timestamps, closes).compactMap { timestamp, close -> PricePoint? in
            close.map { PricePoint(date: Date(timeIntervalSince1970: timestamp), price: $0) }
        }
        // The latest regular market price may be newer than the last bar.
        if let price = result.meta?.regularMarketPrice, let time = result.meta?.regularMarketTime,
           time > (points.last?.date.timeIntervalSince1970 ?? 0) {
            points.append(PricePoint(date: Date(timeIntervalSince1970: time), price: price))
        }
        let series = PriceSeries(assetID: assetID, currency: result.meta?.currency, points: points)
        guard !series.points.isEmpty else { throw PriceProviderError.noData("Yahoo: brak notowań") }
        return series
    }

    public func history(for asset: WatchedAsset, covering window: TimeInterval) async throws -> PriceSeries {
        let data = try await client.fetchJSON(Self.request(symbol: asset.symbol, window: window))
        return try Self.parse(data, assetID: asset.id)
    }
}

// MARK: - CoinGecko

/// CoinGecko public API (free, no key; rate-limited to a few requests per minute).
public struct CoinGeckoProvider: PriceHistoryProvider {
    private let client: HTTPClient

    public init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    public static func request(coinID: String, currency: String, window: TimeInterval) throws -> URLRequest {
        let id = coinID.trimmingCharacters(in: .whitespaces).lowercased()
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
              var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/\(id)/market_chart")
        else { throw PriceProviderError.invalidSymbol(coinID) }
        // Up to 1 day → 5-minute data, 2–90 days → hourly data.
        let days = max(1, Int((window / 86_400).rounded(.up)))
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: currency.lowercased()),
            URLQueryItem(name: "days", value: String(days)),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("NewsTracker/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private struct MarketChart: Decodable {
        let prices: [[Double]]
    }

    public static func parse(_ data: Data, assetID: String, currency: String) throws -> PriceSeries {
        let chart: MarketChart
        do {
            chart = try JSONDecoder().decode(MarketChart.self, from: data)
        } catch {
            throw PriceProviderError.invalidResponse("CoinGecko: \(error.localizedDescription)")
        }
        let points = chart.prices.compactMap { pair -> PricePoint? in
            guard pair.count >= 2 else { return nil }
            return PricePoint(date: Date(timeIntervalSince1970: pair[0] / 1000), price: pair[1])
        }
        let series = PriceSeries(assetID: assetID, currency: currency.uppercased(), points: points)
        guard !series.points.isEmpty else { throw PriceProviderError.noData("CoinGecko: brak notowań") }
        return series
    }

    public func history(for asset: WatchedAsset, covering window: TimeInterval) async throws -> PriceSeries {
        let currency = asset.currency ?? "usd"
        let data = try await client.fetchJSON(Self.request(coinID: asset.symbol, currency: currency, window: window))
        return try Self.parse(data, assetID: asset.id, currency: currency)
    }
}

// MARK: - Routing

/// Picks the provider configured for each asset.
public struct PriceService: PriceHistoryProvider {
    private let yahoo: PriceHistoryProvider
    private let coinGecko: PriceHistoryProvider

    public init(client: HTTPClient = URLSessionHTTPClient()) {
        self.init(yahoo: YahooFinanceProvider(client: client), coinGecko: CoinGeckoProvider(client: client))
    }

    public init(yahoo: PriceHistoryProvider, coinGecko: PriceHistoryProvider) {
        self.yahoo = yahoo
        self.coinGecko = coinGecko
    }

    public func history(for asset: WatchedAsset, covering window: TimeInterval) async throws -> PriceSeries {
        switch asset.provider {
        case .yahoo: return try await yahoo.history(for: asset, covering: window)
        case .coingecko: return try await coinGecko.history(for: asset, covering: window)
        }
    }
}

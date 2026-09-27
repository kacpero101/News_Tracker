import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One instrument found by symbol search.
public struct SymbolSearchResult: Equatable, Identifiable, Sendable {
    public var id: String { symbol }
    public var symbol: String
    public var name: String
    /// Human readable exchange, e.g. "London", "XETRA", "NasdaqGS".
    public var exchange: String?
    public var kind: AssetKind

    public init(symbol: String, name: String, exchange: String?, kind: AssetKind) {
        self.symbol = symbol
        self.name = name
        self.exchange = exchange
        self.kind = kind
    }
}

/// Finds Yahoo Finance symbols by ticker or name (key-less, unofficial endpoint),
/// e.g. "uranium" or "URNU" → `URNU.L` (London), `URNU.DE` (XETRA)…
public struct YahooSymbolSearch: Sendable {
    private let client: HTTPClient

    public init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    public static func request(query: String) throws -> URLRequest {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search") else {
            throw PriceProviderError.invalidSymbol(query)
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "quotesCount", value: "15"),
            URLQueryItem(name: "newsCount", value: "0"),
            URLQueryItem(name: "listsCount", value: "0"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) NewsTracker/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private struct Response: Decodable {
        struct Quote: Decodable {
            let symbol: String?
            let shortname: String?
            let longname: String?
            let exchDisp: String?
            let exchange: String?
            let quoteType: String?
        }
        let quotes: [Quote]?
    }

    /// Supported instruments only (stocks, ETFs, funds, indices, crypto).
    public static func parse(_ data: Data) throws -> [SymbolSearchResult] {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw PriceProviderError.invalidResponse("Yahoo search: \(error.localizedDescription)")
        }
        return (response.quotes ?? []).compactMap { quote in
            guard let symbol = quote.symbol, !symbol.isEmpty, let kind = kind(for: quote.quoteType) else { return nil }
            return SymbolSearchResult(
                symbol: symbol,
                name: quote.longname ?? quote.shortname ?? symbol,
                exchange: quote.exchDisp ?? quote.exchange,
                kind: kind
            )
        }
    }

    static func kind(for quoteType: String?) -> AssetKind? {
        switch quoteType?.uppercased() {
        case "EQUITY": return .stock
        case "ETF", "MUTUALFUND": return .etf
        case "INDEX": return .index
        case "CRYPTOCURRENCY": return .crypto
        default: return nil
        }
    }

    public func search(_ query: String) async throws -> [SymbolSearchResult] {
        let data = try await client.fetchJSON(Self.request(query: query))
        return try Self.parse(data)
    }
}

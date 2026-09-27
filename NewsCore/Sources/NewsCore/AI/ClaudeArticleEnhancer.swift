import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Result of AI enrichment for one article.
public struct AIEnhancement: Equatable, Sendable {
    public var topics: Set<Topic>
    public var summary: String

    public init(topics: Set<Topic>, summary: String) {
        self.topics = topics
        self.summary = summary
    }
}

public enum ClaudeError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String)
    case refused
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Claude API key is not configured"
        case let .http(status, message): return "Claude API error \(status): \(message)"
        case .refused: return "Claude declined the request"
        case let .invalidResponse(details): return "Unexpected Claude API response: \(details)"
        }
    }
}

/// Optional, opt-in integration with the Claude Messages API (raw HTTP).
///
/// Sends only the headline, the short feed description and the language of an article
/// (never the full article) and asks for topics plus a 1–2 sentence summary.
/// The API key is passed in by the caller (the app keeps it in the Keychain); it is
/// never stored by this type.
public struct ClaudeArticleEnhancer: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let defaultModel = "claude-opus-5"
    /// Models offered in the app settings.
    public static let availableModels = ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"]

    private let client: HTTPClient
    public var model: String
    public var maxTokens: Int

    public init(client: HTTPClient = URLSessionHTTPClient(), model: String = ClaudeArticleEnhancer.defaultModel, maxTokens: Int = 1024) {
        self.client = client
        self.model = model
        self.maxTokens = maxTokens
    }

    // MARK: Request

    public func makeRequest(for article: Article, apiKey: String) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ClaudeError.missingAPIKey }

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": Self.systemPrompt,
            "messages": [["role": "user", "content": Self.userPrompt(for: article)]],
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": Self.responseSchema],
            ],
        ]
        // Opus 5 may decline a request via safety classifiers; let the API retry it on
        // a recommended fallback model instead of returning a refusal.
        if model.hasPrefix("claude-opus-5") {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    static let systemPrompt = """
    You classify news items for a personal news reader. You only see the headline and the \
    short description published in the RSS feed. Assign zero or more of these topics: \
    finance (markets, banks, interest rates, currencies), politics, breakthroughs \
    (scientific or technological discoveries), crypto (cryptocurrencies, blockchain), \
    economy (macroeconomics, inflation, trade, labour market). Write a neutral summary of \
    at most two sentences in the same language as the item, using only the given text.
    """

    static func userPrompt(for article: Article) -> String {
        """
        Language: \(article.language.rawValue)
        Source: \(article.sourceName)
        Headline: \(article.title)
        Description: \(article.summary)
        """
    }

    static let responseSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "topics": [
                "type": "array",
                "items": ["type": "string", "enum": Topic.allCases.map(\.rawValue)],
            ],
            "summary": ["type": "string"],
        ],
        "required": ["topics", "summary"],
        "additionalProperties": false,
    ]

    // MARK: Response

    public static func parseResponse(_ data: Data) throws -> AIEnhancement {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.invalidResponse("not a JSON object")
        }
        if json["stop_reason"] as? String == "refusal" {
            throw ClaudeError.refused
        }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard let payloadData = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            throw ClaudeError.invalidResponse("missing JSON text block")
        }
        let topics = (payload["topics"] as? [String] ?? []).compactMap(Topic.init(rawValue:))
        let summary = (payload["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return AIEnhancement(topics: Set(topics), summary: summary)
    }

    static func errorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(data: data.prefix(200), encoding: .utf8) ?? ""
    }

    // MARK: Calls

    public func enhance(_ article: Article, apiKey: String) async throws -> AIEnhancement {
        let request = try makeRequest(for: article, apiKey: apiKey)
        let (data, response) = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw ClaudeError.http(status: response.statusCode, message: Self.errorMessage(from: data))
        }
        return try Self.parseResponse(data)
    }

    /// Enhances up to `limit` articles that have no AI summary yet (sequentially, to keep
    /// usage predictable). AI topics are added to the keyword topics. Failures for
    /// individual articles are skipped; an authentication error (401/403) stops the batch.
    public func enhance(
        _ articles: [Article],
        apiKey: String,
        limit: Int = 10
    ) async throws -> [Article] {
        var updated: [Article] = []
        for article in articles.filter({ $0.aiSummary == nil }).prefix(limit) {
            try Task.checkCancellation()
            do {
                let enhancement = try await enhance(article, apiKey: apiKey)
                var copy = article
                copy.topics.formUnion(enhancement.topics)
                copy.aiSummary = enhancement.summary.isEmpty ? nil : enhancement.summary
                updated.append(copy)
            } catch let error as ClaudeError {
                switch error {
                case .missingAPIKey, .http(status: 401, _), .http(status: 403, _):
                    throw error
                default:
                    continue
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return updated
    }
}

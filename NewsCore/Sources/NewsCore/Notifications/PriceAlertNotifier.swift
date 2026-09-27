import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Delivers price alerts to the user (local notifications in the app, ntfy on the server).
public protocol PriceAlertNotifier: Sendable {
    func deliver(_ alerts: [PriceAlert]) async throws
}

/// Free push notifications via [ntfy](https://ntfy.sh): the phone subscribes to a topic in
/// the ntfy app, the watcher publishes to it. No account or API key is needed; the topic
/// name acts as a password, so it should be long and random.
public struct NtfyNotifier: PriceAlertNotifier {
    public let server: URL
    public let topic: String
    private let client: HTTPClient

    public init(topic: String, server: URL = URL(string: "https://ntfy.sh")!, client: HTTPClient = URLSessionHTTPClient()) {
        self.topic = topic
        self.server = server
        self.client = client
    }

    /// JSON publishing (supports UTF-8 titles, unlike HTTP headers).
    public func request(for alert: PriceAlert) throws -> URLRequest {
        var payload: [String: Any] = [
            "topic": topic,
            "title": PriceAlertFormatter.title(for: alert),
            "message": PriceAlertFormatter.body(for: alert),
            "tags": [alert.move.isRise ? "chart_with_upwards_trend" : "chart_with_downwards_trend"],
            "priority": abs(alert.move.changePercent) >= alert.rule.thresholdPercent * 1.5 ? 5 : 4,
        ]
        if let url = alert.asset.quoteURL {
            payload["click"] = url.absoluteString
        }
        return try jsonRequest(payload)
    }

    public func testRequest() throws -> URLRequest {
        try jsonRequest([
            "topic": topic,
            "title": "News Tracker – test",
            "message": "Powiadomienia o zmianach cen działają.",
            "tags": ["white_check_mark"],
        ])
    }

    private func jsonRequest(_ payload: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: server, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return request
    }

    public func deliver(_ alerts: [PriceAlert]) async throws {
        for alert in alerts {
            _ = try await client.fetchJSON(request(for: alert))
        }
    }

    public func sendTest() async throws {
        _ = try await client.fetchJSON(testRequest())
    }
}

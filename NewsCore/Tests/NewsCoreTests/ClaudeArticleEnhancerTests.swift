import XCTest
@testable import NewsCore

/// All tests use a mock HTTP client – no real (paid) API calls are made.
final class ClaudeArticleEnhancerTests: XCTestCase {
    let article = Article.make(title: "Bitcoin rallies after Fed decision", summary: "Markets react.", topics: [.crypto])

    private func response(text: String, stopReason: String = "end_turn") -> Data {
        let object: [String: Any] = [
            "id": "msg_1", "type": "message", "role": "assistant", "stop_reason": stopReason,
            "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": text]],
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    func testRequestShape() throws {
        let request = try ClaudeArticleEnhancer(client: MockHTTPClient()).makeRequest(for: article, apiKey: " sk-test ")
        XCTAssertEqual(request.url, ClaudeArticleEnhancer.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "claude-opus-5")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertTrue((messages[0]["content"] as? String ?? "").contains("Bitcoin rallies after Fed decision"))
        let outputConfig = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual((outputConfig["format"] as? [String: Any])?["type"] as? String, "json_schema")
    }

    func testNonOpusModelHasNoFallbackParameter() throws {
        let request = try ClaudeArticleEnhancer(client: MockHTTPClient(), model: "claude-haiku-4-5").makeRequest(for: article, apiKey: "k")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertNil(body["fallbacks"])
        XCTAssertNil(request.value(forHTTPHeaderField: "anthropic-beta"))
    }

    func testMissingKeyThrows() {
        XCTAssertThrowsError(try ClaudeArticleEnhancer(client: MockHTTPClient()).makeRequest(for: article, apiKey: "  ")) {
            XCTAssertEqual($0 as? ClaudeError, .missingAPIKey)
        }
    }

    func testParsesStructuredResponse() throws {
        let result = try ClaudeArticleEnhancer.parseResponse(response(text: #"{"topics":["crypto","finance","sports"],"summary":" Bitcoin rose. "}"#))
        XCTAssertEqual(result, AIEnhancement(topics: [.crypto, .finance], summary: "Bitcoin rose."))
    }

    func testRefusalAndGarbage() {
        XCTAssertThrowsError(try ClaudeArticleEnhancer.parseResponse(response(text: "", stopReason: "refusal"))) {
            XCTAssertEqual($0 as? ClaudeError, .refused)
        }
        XCTAssertThrowsError(try ClaudeArticleEnhancer.parseResponse(response(text: "not json")))
        XCTAssertThrowsError(try ClaudeArticleEnhancer.parseResponse(Data("[]".utf8)))
    }

    func testBatchEnhancementMergesTopicsAndRespectsLimit() async throws {
        let client = MockHTTPClient([
            ClaudeArticleEnhancer.endpoint: .ok(response(text: #"{"topics":["finance"],"summary":"Short summary."}"#)),
        ])
        let enhancer = ClaudeArticleEnhancer(client: client)
        var alreadyDone = Article.make(link: "https://a.com/done")
        alreadyDone.aiSummary = "done"
        let input = [article, Article.make(link: "https://a.com/2"), Article.make(link: "https://a.com/3"), alreadyDone]

        let updated = try await enhancer.enhance(input, apiKey: "k", limit: 2)
        XCTAssertEqual(updated.count, 2)
        XCTAssertEqual(updated[0].topics, [.crypto, .finance])
        XCTAssertEqual(updated[0].aiSummary, "Short summary.")
        XCTAssertEqual(client.requests.count, 2)
    }

    func testBatchStopsOnAuthenticationError() async {
        let client = MockHTTPClient([ClaudeArticleEnhancer.endpoint: .status(401)])
        do {
            _ = try await ClaudeArticleEnhancer(client: client).enhance([article, Article.make(link: "https://a.com/2")], apiKey: "bad")
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? ClaudeError, .http(status: 401, message: ""))
        }
        XCTAssertEqual(client.requests.count, 1)
    }

    func testBatchSkipsTransientFailures() async throws {
        let client = MockHTTPClient([ClaudeArticleEnhancer.endpoint: .status(529)])
        let updated = try await ClaudeArticleEnhancer(client: client).enhance([article, Article.make(link: "https://a.com/2")], apiKey: "k")
        XCTAssertEqual(updated, [])
        XCTAssertEqual(client.requests.count, 2)
    }
}

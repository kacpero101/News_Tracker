import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import NewsCore

enum Fixtures {
    static func data(_ name: String) throws -> Data {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures"),
            "Missing fixture \(name)"
        )
        return try Data(contentsOf: url)
    }
}

/// HTTP client returning canned responses per URL; unknown URLs fail.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    enum Response {
        case ok(Data)
        case status(Int)
        case failure(Error)
    }

    struct Offline: Error {}

    private let lock = NSLock()
    private var responses: [URL: Response]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [URL: Response] = [:]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let response: Response? = lock.withLock {
            requests.append(request)
            return responses[url]
        }
        switch response {
        case let .ok(data):
            return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        case let .status(code):
            return (Data(), HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!)
        case let .failure(error):
            throw error
        case nil:
            throw Offline()
        }
    }
}

extension Article {
    static func make(
        title: String = "Some title long enough for dedup",
        summary: String = "",
        link: String = "https://example.com/a",
        published: Date? = Date(timeIntervalSince1970: 1_700_000_000),
        source: String = "src",
        language: Language = .english,
        topics: Set<Topic> = []
    ) -> Article {
        Article(
            title: title,
            summary: summary,
            link: URL(string: link)!,
            publishedAt: published,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceID: source,
            sourceName: source.uppercased(),
            language: language,
            topics: topics
        )
    }
}

func date(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: iso)!
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal HTTP abstraction so that networking can be replaced with mocks in tests.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public enum HTTPClientError: Error, Equatable, LocalizedError {
    case nonHTTPResponse
    case badStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .nonHTTPResponse: return "The server returned a non-HTTP response"
        case let .badStatus(code): return "HTTP status \(code)"
        }
    }
}

/// `URLSession`-backed client (works on Apple platforms and Linux).
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: HTTPClientError.nonHTTPResponse)
                    return
                }
                continuation.resume(returning: (data ?? Data(), http))
            }
            task.resume()
        }
    }
}

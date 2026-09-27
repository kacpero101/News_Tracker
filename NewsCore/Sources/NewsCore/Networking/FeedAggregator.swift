import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A source that could not be fetched or parsed during a refresh.
public struct SourceFailure: Identifiable, Equatable, Sendable {
    public var id: String { sourceID }
    public let sourceID: String
    public let sourceName: String
    public let message: String

    public init(sourceID: String, sourceName: String, message: String) {
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.message = message
    }
}

/// Outcome of fetching all sources. Failures of individual sources never
/// prevent the remaining articles from being returned.
public struct AggregationResult: Sendable {
    /// Classified, deduplicated articles sorted newest first.
    public var articles: [Article]
    public var failures: [SourceFailure]
    /// IDs of sources fetched successfully.
    public var succeededSourceIDs: [String]

    public init(articles: [Article], failures: [SourceFailure], succeededSourceIDs: [String]) {
        self.articles = articles
        self.failures = failures
        self.succeededSourceIDs = succeededSourceIDs
    }
}

/// Downloads feeds concurrently, parses, classifies and deduplicates them.
public struct FeedAggregator: Sendable {
    private let client: HTTPClient
    private let parser: FeedParser
    private let classifier: TopicClassifier
    private let deduplicator: Deduplicator
    private let timeout: TimeInterval
    private let maxItemsPerSource: Int
    private let now: @Sendable () -> Date

    public init(
        client: HTTPClient = URLSessionHTTPClient(),
        parser: FeedParser = FeedParser(),
        classifier: TopicClassifier,
        deduplicator: Deduplicator = Deduplicator(),
        timeout: TimeInterval = 15,
        maxItemsPerSource: Int = 50,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.parser = parser
        self.classifier = classifier
        self.deduplicator = deduplicator
        self.timeout = timeout
        self.maxItemsPerSource = maxItemsPerSource
        self.now = now
    }

    /// Fetches all given sources in parallel.
    public func fetchAll(_ sources: [FeedSource]) async -> AggregationResult {
        let fetchDate = now()
        let outcomes = await withTaskGroup(of: (Int, Result<[Article], Error>).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    do {
                        return (index, .success(try await fetch(source, fetchedAt: fetchDate)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<[Article], Error>)] = []
            for await outcome in group {
                collected.append(outcome)
            }
            // Keep configuration order so that deduplication is deterministic.
            return collected.sorted { $0.0 < $1.0 }
        }

        var articles: [Article] = []
        var failures: [SourceFailure] = []
        var succeeded: [String] = []
        for (index, outcome) in outcomes {
            let source = sources[index]
            switch outcome {
            case let .success(sourceArticles):
                articles.append(contentsOf: sourceArticles)
                succeeded.append(source.id)
            case let .failure(error):
                failures.append(SourceFailure(
                    sourceID: source.id,
                    sourceName: source.name,
                    message: (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                ))
            }
        }

        return AggregationResult(
            articles: deduplicator.deduplicate(articles).sortedNewestFirst(),
            failures: failures,
            succeededSourceIDs: succeeded
        )
    }

    /// Fetches and converts a single source. Throws on network, HTTP or parsing errors.
    public func fetch(_ source: FeedSource, fetchedAt: Date? = nil) async throws -> [Article] {
        var request = URLRequest(url: source.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.5", forHTTPHeaderField: "Accept")
        request.setValue("NewsTracker/1.0 (RSS reader)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw HTTPClientError.badStatus(response.statusCode)
        }
        let feed = try parser.parse(data)
        return articles(from: feed, source: source, fetchedAt: fetchedAt ?? now())
    }

    /// Converts parsed feed items into classified articles.
    public func articles(from feed: ParsedFeed, source: FeedSource, fetchedAt: Date) -> [Article] {
        feed.items.prefix(maxItemsPerSource).compactMap { item -> Article? in
            guard let link = item.link, link.scheme?.hasPrefix("http") == true else { return nil }
            let title = item.title.isEmpty ? item.summary : item.title
            return Article(
                title: title,
                summary: item.summary,
                link: link,
                publishedAt: item.publishedAt,
                fetchedAt: fetchedAt,
                sourceID: source.id,
                sourceName: source.name,
                language: source.language,
                topics: classifier.classify(title: title, summary: item.summary, source: source)
            )
        }
    }
}

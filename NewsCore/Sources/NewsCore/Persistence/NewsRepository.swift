import Foundation

/// Combines the feed aggregator with a local JSON cache.
/// The app shows cached articles immediately and merges fresh ones on refresh.
public actor NewsRepository {
    public struct RefreshOutcome: Sendable {
        public var articles: [Article]
        public var failures: [SourceFailure]
        public var newArticleCount: Int
        /// Source ID → feed URL found on the source's web page (see `FeedAggregator`).
        public var resolvedFeedURLs: [String: URL]
    }

    private var aggregator: FeedAggregator
    private let cache: JSONFileStore<[Article]>?
    private let deduplicator: Deduplicator
    private let maxAge: TimeInterval
    private let maxArticles: Int
    private let now: @Sendable () -> Date
    private var articles: [Article] = []
    private var loaded = false
    /// Feed URLs found on web pages during this session, reused on the next refresh.
    private var resolvedFeedURLs: [String: URL] = [:]

    /// - Parameters:
    ///   - maxAge: articles older than this are dropped from the cache (default 7 days).
    ///   - maxArticles: upper bound of cached articles.
    public init(
        aggregator: FeedAggregator,
        cache: JSONFileStore<[Article]>?,
        deduplicator: Deduplicator = Deduplicator(),
        maxAge: TimeInterval = 7 * 24 * 3600,
        maxArticles: Int = 1500,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.aggregator = aggregator
        self.cache = cache
        self.deduplicator = deduplicator
        self.maxAge = maxAge
        self.maxArticles = maxArticles
        self.now = now
    }

    /// Cached articles (newest first). A corrupted cache is treated as empty.
    public func cachedArticles() -> [Article] {
        if !loaded {
            articles = ((try? cache?.load()) ?? nil) ?? []
            loaded = true
        }
        return articles
    }

    /// Fetches the given sources and merges the results into the cache.
    public func refresh(sources: [FeedSource]) async -> RefreshOutcome {
        let previous = cachedArticles()
        let previousIDs = Set(previous.map(\.id))
        // Sources configured with a web page address use the feed found on it last time.
        let effectiveSources = sources.map { source -> FeedSource in
            guard let url = resolvedFeedURLs[source.id] else { return source }
            return FeedSource(id: source.id, name: source.name, url: url, language: source.language,
                              defaultCategory: source.defaultCategory, verified: source.verified)
        }
        let result = await aggregator.fetchAll(effectiveSources)
        resolvedFeedURLs.merge(result.resolvedFeedURLs) { _, new in new }
        for failure in result.failures {
            // Look for the feed on the page again next time.
            resolvedFeedURLs[failure.sourceID] = nil
        }

        let merged = merge(fresh: result.articles, cached: previous)
        articles = merged
        try? cache?.save(merged)

        let newCount = merged.filter { !previousIDs.contains($0.id) }.count
        return RefreshOutcome(articles: merged, failures: result.failures, newArticleCount: newCount,
                              resolvedFeedURLs: resolvedFeedURLs)
    }

    /// Replaces stored articles (e.g. after AI enrichment) and persists them.
    public func update(_ updated: [Article]) {
        let byID = Dictionary(updated.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        articles = articles.map { byID[$0.id] ?? $0 }
        try? cache?.save(articles)
    }

    /// Switches to a new classifier and re-evaluates the `managed` topics (custom categories)
    /// of all cached articles. Returns the updated articles.
    @discardableResult
    public func applyClassifier(_ classifier: TopicClassifier, managing managed: Set<Topic>) -> [Article] {
        aggregator = aggregator.replacingClassifier(classifier)
        articles = cachedArticles().map { $0.reclassified(with: classifier, managing: managed) }
        try? cache?.save(articles)
        return articles
    }

    public func clearCache() {
        articles = []
        try? cache?.delete()
    }

    func merge(fresh: [Article], cached: [Article]) -> [Article] {
        let cutoff = now().addingTimeInterval(-maxAge)
        let combined = deduplicator.deduplicate(fresh + cached)
            .filter { $0.sortDate >= cutoff }
            .sortedNewestFirst()
        return Array(combined.prefix(maxArticles))
    }
}

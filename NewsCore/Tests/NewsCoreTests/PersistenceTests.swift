import XCTest
@testable import NewsCore

final class PersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("NewsCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testJSONFileStoreRoundTrip() throws {
        let store = JSONFileStore<[Article]>(fileURL: directory.appendingPathComponent("a/b/articles.json"))
        XCTAssertNil(try store.load())
        let articles = [Article.make(topics: [.crypto])]
        try store.save(articles)
        XCTAssertEqual(try store.load(), articles)
        try store.delete()
        XCTAssertNil(try store.load())
    }

    func testReadingListPersistsAndToggles() async throws {
        let store = JSONFileStore<[Article]>(fileURL: directory.appendingPathComponent("reading.json"))
        let list = ReadingList(store: store)
        let first = Article.make(link: "https://a.com/1")
        let second = Article.make(link: "https://a.com/2")

        let saved = try await list.toggle(first)
        XCTAssertTrue(saved)
        try await list.add(second)
        try await list.add(second)
        let all = await list.all
        XCTAssertEqual(all.map(\.id), [second.id, first.id])

        let reloaded = ReadingList(store: store)
        let reloadedIDs = await reloaded.ids
        XCTAssertEqual(reloadedIDs, [first.id, second.id])

        let removed = try await reloaded.toggle(first)
        XCTAssertFalse(removed)
        let containsFirst = await reloaded.contains(first.id)
        XCTAssertFalse(containsFirst)
    }

    func testRepositoryMergesWithCacheAndDropsOldArticles() async throws {
        let source = FeedSource(id: "en", name: "English", url: URL(string: "https://en.example/rss")!, language: .english, defaultCategory: nil)
        let cacheStore = JSONFileStore<[Article]>(fileURL: directory.appendingPathComponent("cache.json"))
        let cachedOld = Article.make(title: "Very old cached article title", link: "https://old.example/1", published: date("2024-01-01T00:00:00Z"))
        let cachedRecent = Article.make(title: "Recent cached article title", link: "https://recent.example/1", published: date("2024-05-04T00:00:00Z"))
        try cacheStore.save([cachedRecent, cachedOld])

        let client = MockHTTPClient([source.url: .ok(try Fixtures.data("rss2_sample.xml"))])
        let now: @Sendable () -> Date = { date("2024-05-05T00:00:00Z") }
        let aggregator = FeedAggregator(client: client, classifier: TopicClassifier(keywords: KeywordList(topics: [:])), now: now)
        let repository = NewsRepository(aggregator: aggregator, cache: cacheStore, now: now)

        let cached = await repository.cachedArticles()
        XCTAssertEqual(cached.count, 2)

        let outcome = await repository.refresh(sources: [source])
        XCTAssertEqual(outcome.failures, [])
        XCTAssertEqual(outcome.newArticleCount, 3)
        // 3 fresh + 1 recent cached; the old one is older than 7 days.
        XCTAssertEqual(outcome.articles.count, 4)
        XCTAssertFalse(outcome.articles.contains { $0.id == cachedOld.id })
        XCTAssertEqual(try cacheStore.load()?.count, 4)

        // A second refresh with a failing source keeps the cached articles.
        let failing = FeedAggregator(client: MockHTTPClient(), classifier: TopicClassifier(keywords: KeywordList(topics: [:])), now: now)
        let second = NewsRepository(aggregator: failing, cache: cacheStore, now: now)
        let secondOutcome = await second.refresh(sources: [source])
        XCTAssertEqual(secondOutcome.failures.count, 1)
        XCTAssertEqual(secondOutcome.articles.count, 4)
        XCTAssertEqual(secondOutcome.newArticleCount, 0)
    }

    func testCorruptedCacheIsTreatedAsEmpty() async throws {
        let url = directory.appendingPathComponent("cache.json")
        try Data("{not json".utf8).write(to: url)
        let aggregator = FeedAggregator(client: MockHTTPClient(), classifier: TopicClassifier(keywords: KeywordList(topics: [:])))
        let repository = NewsRepository(aggregator: aggregator, cache: JSONFileStore(fileURL: url))
        let cached = await repository.cachedArticles()
        XCTAssertEqual(cached, [])
    }
}

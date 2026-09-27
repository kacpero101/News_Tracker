import XCTest
@testable import NewsCore

final class CustomCategoryTests: XCTestCase {
    let drones = CustomCategory(id: "custom-drones", name: "Drony", keywords: ["dron*", "drone*", "unmanned aerial"], symbol: "airplane", color: "teal")
    let base = KeywordList(topics: [.politics: .init(pl: ["sejm*"], en: ["parliament"])])

    private func source(_ language: Language, category: Topic? = nil) -> FeedSource {
        FeedSource(id: "s", name: "S", url: URL(string: "https://s.example")!, language: language, defaultCategory: category)
    }

    func testTopicIsOpenAndOrdered() throws {
        let custom = Topic(rawValue: "custom-a")
        XCTAssertTrue(Topic.finance.isBuiltIn)
        XCTAssertFalse(custom.isBuiltIn)
        XCTAssertEqual([custom, .economy, Topic(rawValue: "custom-0"), .finance].sorted(),
                       [.finance, .economy, Topic(rawValue: "custom-0"), custom])
        // Encoded as a plain string, so existing caches stay compatible.
        XCTAssertEqual(String(decoding: try JSONEncoder().encode([Topic.crypto]), as: UTF8.self), #"["crypto"]"#)
        XCTAssertEqual(try JSONDecoder().decode([Topic].self, from: Data(#"["politics","custom-x"]"#.utf8)),
                       [.politics, Topic(rawValue: "custom-x")])
    }

    func testParseKeywords() {
        XCTAssertEqual(
            CustomCategory.parseKeywords("dron*, Drony;\nsztuczna inteligencja\n\n DRON* , *"),
            ["dron*", "Drony", "sztuczna inteligencja"]
        )
        XCTAssertTrue(CustomCategory(name: "X", keywords: []).id.hasPrefix("custom-"))
    }

    func testCustomCategoryMatchesInEveryLanguage() {
        let classifier = TopicClassifier(keywords: base.merging([drones]))
        XCTAssertEqual(classifier.classify(title: "Nowoczesny dron USA w rękach Iranu", summary: "", source: source(.polish)), [drones.topic])
        XCTAssertEqual(classifier.classify(title: "Drones attack the parliament", summary: "", source: source(.english)), [drones.topic, .politics])
        XCTAssertEqual(classifier.classify(title: "Neue Drohnen", summary: "unmanned aerial vehicles", source: source(.german)), [drones.topic])
    }

    func testReclassificationOnlyTouchesManagedTopics() {
        let removed = Topic(rawValue: "custom-removed")
        let article = Article.make(title: "Sejm o dronach", summary: "", language: .polish, topics: [.finance, removed])
        let classifier = TopicClassifier(keywords: base.merging([drones]))
        let updated = article.reclassified(with: classifier, managing: [drones.topic, removed])
        // finance (e.g. from the source category) stays, the removed custom topic is dropped,
        // the new custom category is added; built-in keyword topics are not recomputed.
        XCTAssertEqual(updated.topics, [.finance, drones.topic])
    }

    func testRepositoryAndReadingListApplyNewClassifier() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NewsCoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheStore = JSONFileStore<[Article]>(fileURL: directory.appendingPathComponent("cache.json"))
        let article = Article.make(title: "Drone strike reported near the border", link: "https://a.example/1",
                                   published: Date(), language: .english, topics: [.politics])
        try cacheStore.save([article])

        let repository = NewsRepository(
            aggregator: FeedAggregator(client: MockHTTPClient(), classifier: TopicClassifier(keywords: base)),
            cache: cacheStore
        )
        let classifier = TopicClassifier(keywords: base.merging([drones]))
        let updated = await repository.applyClassifier(classifier, managing: [drones.topic])
        XCTAssertEqual(updated.first?.topics, [.politics, drones.topic])
        XCTAssertEqual(try cacheStore.load()?.first?.topics, [.politics, drones.topic])

        let readingList = ReadingList(store: nil)
        try await readingList.add(article)
        try await readingList.reclassify(with: classifier, managing: [drones.topic])
        let saved = await readingList.all
        XCTAssertEqual(saved.first?.topics, [.politics, drones.topic])

        // New articles fetched after the change are classified with the custom category too.
        let source = FeedSource(id: "en", name: "EN", url: URL(string: "https://en.example/rss")!, language: .english, defaultCategory: nil)
        let xml = "<rss><channel><item><title>New drone rules</title><link>https://en.example/2</link></item></channel></rss>"
        let fetching = NewsRepository(
            aggregator: FeedAggregator(client: MockHTTPClient([source.url: .ok(Data(xml.utf8))]), classifier: TopicClassifier(keywords: base)),
            cache: nil
        )
        await fetching.applyClassifier(classifier, managing: [drones.topic])
        let outcome = await fetching.refresh(sources: [source])
        XCTAssertEqual(outcome.articles.first?.topics, [drones.topic])
    }
}

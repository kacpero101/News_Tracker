import XCTest
@testable import NewsCore

final class ReadArchiveTests: XCTestCase {
    func testMarkReadPersistsMovesToTopAndRespectsLimit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NewsCoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileStore<[ReadArticle]>(fileURL: directory.appendingPathComponent("read.json"))
        let archive = ReadArchive(store: store, limit: 2)
        let a = Article.make(link: "https://a.example/1")
        let b = Article.make(link: "https://a.example/2")
        let c = Article.make(link: "https://a.example/3")

        try await archive.markRead(a, at: date("2024-05-01T10:00:00Z"))
        try await archive.markRead(b, at: date("2024-05-01T11:00:00Z"))
        try await archive.markRead(a, at: date("2024-05-01T12:00:00Z"))
        var all = await archive.all
        XCTAssertEqual(all.map(\.id), [a.id, b.id])
        XCTAssertEqual(all.first?.readAt, date("2024-05-01T12:00:00Z"))

        // Limit 2: the oldest entry (b) is dropped.
        try await archive.markRead(c, at: date("2024-05-01T13:00:00Z"))
        all = await archive.all
        XCTAssertEqual(all.map(\.id), [c.id, a.id])

        // Persisted.
        let reloaded = ReadArchive(store: store)
        let reloadedIDs = await reloaded.ids
        XCTAssertEqual(reloadedIDs, [a.id, c.id])

        try await reloaded.remove(ids: [c.id])
        let containsC = await reloaded.contains(c.id)
        XCTAssertFalse(containsC)
        try await reloaded.clear()
        let remaining = await reloaded.all
        XCTAssertEqual(remaining, [])
        XCTAssertEqual(try store.load(), [])
    }

    func testReclassifyUpdatesCustomTopics() async throws {
        let archive = ReadArchive(store: nil)
        try await archive.markRead(Article.make(title: "Drone footage from the border region", topics: [.politics]))
        let drones = CustomCategory(id: "custom-drones", name: "Drony", keywords: ["drone*"])
        try await archive.reclassify(with: TopicClassifier(keywords: KeywordList(topics: [:]).merging([drones])), managing: [drones.topic])
        let topics = await archive.all.first?.article.topics
        XCTAssertEqual(topics, [.politics, drones.topic])
    }

    func testDayGrouping() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let dates = [
            date("2024-05-02T21:30:00Z"), // 23:30 in Warsaw → May 2
            date("2024-05-02T22:30:00Z"), // 00:30 in Warsaw → May 3
            date("2024-05-01T08:00:00Z"),
            date("2024-05-02T06:00:00Z"),
        ]
        let groups = DayGrouping.group(dates, calendar: calendar) { $0 }
        XCTAssertEqual(groups.map { calendar.component(.day, from: $0.day) }, [3, 2, 1])
        XCTAssertEqual(groups[1].items, [dates[0], dates[3]])
        XCTAssertEqual(DayGrouping.group([Date](), by: { $0 }).count, 0)
    }
}

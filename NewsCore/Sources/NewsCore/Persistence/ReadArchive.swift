import Foundation

/// An article the user marked as read.
public struct ReadArticle: Codable, Hashable, Identifiable, Sendable {
    public var article: Article
    public var readAt: Date
    public var id: String { article.id }

    public init(article: Article, readAt: Date) {
        self.article = article
        self.readAt = readAt
    }
}

/// Archive of read news (newest first). Marking a saved article as read moves it here,
/// so it no longer counts towards the "read later" list.
public actor ReadArchive {
    private let store: JSONFileStore<[ReadArticle]>?
    private let limit: Int
    private var entries: [ReadArticle]

    /// - Parameters:
    ///   - store: persistence; `nil` keeps the archive in memory only.
    ///   - limit: maximum number of kept entries (oldest are dropped).
    public init(store: JSONFileStore<[ReadArticle]>?, limit: Int = 2000) {
        self.store = store
        self.limit = limit
        self.entries = ((try? store?.load()) ?? nil) ?? []
    }

    /// Read articles, most recently read first.
    public var all: [ReadArticle] { entries }

    public var ids: Set<String> { Set(entries.map(\.id)) }

    public func contains(_ id: String) -> Bool {
        entries.contains { $0.id == id }
    }

    /// Adds the article (or moves it to the top with a new date if already archived).
    public func markRead(_ article: Article, at date: Date = Date()) throws {
        entries.removeAll { $0.id == article.id }
        entries.insert(ReadArticle(article: article, readAt: date), at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        try persist()
    }

    public func remove(ids: Set<String>) throws {
        entries.removeAll { ids.contains($0.id) }
        try persist()
    }

    public func clear() throws {
        entries = []
        try persist()
    }

    /// Re-evaluates custom-category topics (see `Article.reclassified`).
    public func reclassify(with classifier: TopicClassifier, managing managed: Set<Topic>) throws {
        entries = entries.map {
            ReadArticle(article: $0.article.reclassified(with: classifier, managing: managed), readAt: $0.readAt)
        }
        try persist()
    }

    private func persist() throws {
        try store?.save(entries)
    }
}

/// Groups items by calendar day (e.g. archive sections "Dziś", "Wczoraj", …).
public enum DayGrouping {
    public struct Group<Item> {
        /// Start of the day.
        public let day: Date
        public let items: [Item]
    }

    /// Groups sorted with the newest day first; items keep their relative order.
    public static func group<Item>(_ items: [Item], calendar: Calendar = .current, by date: (Item) -> Date) -> [Group<Item>] {
        var order: [Date] = []
        var buckets: [Date: [Item]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: date(item))
            if buckets[day] == nil {
                order.append(day)
            }
            buckets[day, default: []].append(item)
        }
        return order.sorted(by: >).map { Group(day: $0, items: buckets[$0] ?? []) }
    }
}

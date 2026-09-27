import Foundation

/// "Read later" list. Stores full article snapshots so saved items survive
/// even after they drop out of the feeds / cache.
public actor ReadingList {
    private let store: JSONFileStore<[Article]>?
    private var articles: [Article]

    /// - Parameter store: persistence; `nil` keeps the list in memory only.
    public init(store: JSONFileStore<[Article]>?) {
        self.store = store
        self.articles = ((try? store?.load()) ?? nil) ?? []
    }

    /// Saved articles, most recently saved first.
    public var all: [Article] { articles }

    public var ids: Set<String> { Set(articles.map(\.id)) }

    public func contains(_ id: String) -> Bool {
        articles.contains { $0.id == id }
    }

    public func add(_ article: Article) throws {
        guard !contains(article.id) else { return }
        articles.insert(article, at: 0)
        try persist()
    }

    public func remove(id: String) throws {
        articles.removeAll { $0.id == id }
        try persist()
    }

    /// Adds the article if missing, removes it otherwise. Returns `true` when now saved.
    @discardableResult
    public func toggle(_ article: Article) throws -> Bool {
        if contains(article.id) {
            try remove(id: article.id)
            return false
        }
        try add(article)
        return true
    }

    private func persist() throws {
        try store?.save(articles)
    }
}

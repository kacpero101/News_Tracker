import Foundation

/// Filter + search criteria applied to the article list.
public struct ArticleQuery: Equatable, Sendable {
    /// Selected topics; empty means "all topics" (including unclassified articles).
    public var topics: Set<Topic>
    /// Selected languages; empty means "all languages".
    public var languages: Set<Language>
    /// Free-text search over title, summary and source name.
    public var searchText: String

    public init(topics: Set<Topic> = [], languages: Set<Language> = [], searchText: String = "") {
        self.topics = topics
        self.languages = languages
        self.searchText = searchText
    }

    public var isEmpty: Bool {
        topics.isEmpty && languages.isEmpty && searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Whether a single article satisfies the query. Selecting `Topic.uncategorized`
    /// matches news without any topic.
    public func matches(_ article: Article) -> Bool {
        if !topics.isEmpty {
            let wantsUncategorized = topics.contains(.uncategorized) && article.topics.isEmpty
            if article.topics.isDisjoint(with: topics) && !wantsUncategorized { return false }
        }
        if !languages.isEmpty && !languages.contains(article.language) { return false }
        return matchesSearch(article)
    }

    /// Applies the query and returns matching articles sorted newest first.
    public func apply(to articles: [Article]) -> [Article] {
        articles.filter(matches).sortedNewestFirst()
    }

    /// Every search term (whitespace separated) must occur as a prefix of some word
    /// in the title, summary, AI summary or source name. Case and diacritics are ignored.
    private func matchesSearch(_ article: Article) -> Bool {
        let terms = TextNormalizer.tokens(searchText)
        guard !terms.isEmpty else { return true }
        let haystack = TextNormalizer.searchableText(
            [article.title, article.summary, article.aiSummary ?? "", article.sourceName]
                .joined(separator: " ")
        )
        return terms.allSatisfy { haystack.contains(" " + $0) }
    }
}

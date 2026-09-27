import Foundation

/// Collapses the same article published by several feeds into one entry.
///
/// Two articles are duplicates when their normalized URLs are equal, or when their
/// normalized titles are equal (titles shorter than `minimumTitleLength` characters
/// are ignored to avoid merging generic headlines like "Live updates").
public struct Deduplicator: Sendable {
    public var minimumTitleLength: Int

    public init(minimumTitleLength: Int = 20) {
        self.minimumTitleLength = minimumTitleLength
    }

    /// Normalized title key: folded, punctuation removed, whitespace collapsed.
    public static func titleKey(_ title: String) -> String {
        TextNormalizer.tokens(title).joined(separator: " ")
    }

    /// Returns unique articles, preserving the order of first occurrence.
    /// Merged entries keep the earliest publication date, the longest summary,
    /// the union of topics and the names of the other sources.
    public func deduplicate(_ articles: [Article]) -> [Article] {
        var result: [Article] = []
        var indexByURL: [String: Int] = [:]
        var indexByTitle: [String: Int] = [:]

        for article in articles {
            let urlKey = URLNormalizer.normalize(article.link)
            let titleKey = Self.titleKey(article.title)
            let useTitle = titleKey.count >= minimumTitleLength

            if let index = indexByURL[urlKey] ?? (useTitle ? indexByTitle[titleKey] : nil) {
                result[index] = merge(result[index], with: article)
                indexByURL[urlKey] = index
                if useTitle { indexByTitle[titleKey] = index }
            } else {
                result.append(article)
                indexByURL[urlKey] = result.count - 1
                if useTitle { indexByTitle[titleKey] = result.count - 1 }
            }
        }
        return result
    }

    private func merge(_ primary: Article, with duplicate: Article) -> Article {
        var merged = primary
        merged.topics.formUnion(duplicate.topics)
        if duplicate.summary.count > merged.summary.count {
            merged.summary = duplicate.summary
        }
        switch (merged.publishedAt, duplicate.publishedAt) {
        case let (lhs?, rhs?): merged.publishedAt = min(lhs, rhs)
        case (nil, let rhs?): merged.publishedAt = rhs
        default: break
        }
        merged.fetchedAt = min(merged.fetchedAt, duplicate.fetchedAt)
        if merged.aiSummary == nil { merged.aiSummary = duplicate.aiSummary }

        let otherNames = [duplicate.sourceName] + duplicate.additionalSourceNames
        for name in otherNames where name != merged.sourceName && !merged.additionalSourceNames.contains(name) {
            merged.additionalSourceNames.append(name)
        }
        return merged
    }
}

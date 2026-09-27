import Foundation

/// A news item presented to the user. Contains only metadata from the feed:
/// headline, short description, source, date and a link to the original article.
public struct Article: Identifiable, Codable, Hashable, Sendable {
    /// Stable identifier derived from the normalized article URL.
    public let id: String
    public var title: String
    /// Short plain-text description taken from the feed (HTML stripped, truncated).
    public var summary: String
    /// Link to the original article.
    public var link: URL
    public var publishedAt: Date?
    /// When the article was first fetched; used for ordering when `publishedAt` is missing.
    public var fetchedAt: Date
    public var sourceID: String
    public var sourceName: String
    public var language: Language
    public var topics: Set<Topic>
    /// Names of other sources that published the same article (filled by deduplication).
    public var additionalSourceNames: [String]
    /// Optional summary produced by the (opt-in) AI enhancer.
    public var aiSummary: String?

    public init(
        id: String? = nil,
        title: String,
        summary: String,
        link: URL,
        publishedAt: Date?,
        fetchedAt: Date = Date(),
        sourceID: String,
        sourceName: String,
        language: Language,
        topics: Set<Topic> = [],
        additionalSourceNames: [String] = [],
        aiSummary: String? = nil
    ) {
        self.id = id ?? Article.makeID(for: link)
        self.title = title
        self.summary = summary
        self.link = link
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.language = language
        self.topics = topics
        self.additionalSourceNames = additionalSourceNames
        self.aiSummary = aiSummary
    }

    /// Date used for sorting (newest first).
    public var sortDate: Date { publishedAt ?? fetchedAt }

    /// Deterministic identifier (FNV-1a 64-bit hash of the normalized URL).
    public static func makeID(for url: URL) -> String {
        let normalized = URLNormalizer.normalize(url)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

public extension Array where Element == Article {
    /// Sorted with the newest article first.
    func sortedNewestFirst() -> [Article] {
        sorted { lhs, rhs in
            if lhs.sortDate != rhs.sortDate { return lhs.sortDate > rhs.sortDate }
            return lhs.id < rhs.id
        }
    }
}

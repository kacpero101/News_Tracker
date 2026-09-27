import Foundation

/// A single RSS/Atom feed configured in `sources.json`.
public struct FeedSource: Identifiable, Codable, Hashable, Sendable {
    /// Stable identifier, e.g. `"bbc-business"`.
    public let id: String
    /// Human readable name shown in the UI.
    public let name: String
    /// Feed URL (RSS or Atom).
    public let url: URL
    /// Language of the feed content.
    public let language: Language
    /// Topic assigned to every article of this feed (optional for general feeds).
    public let defaultCategory: Topic?
    /// Whether the URL was verified to return a valid feed.
    public let verified: Bool

    public init(
        id: String,
        name: String,
        url: URL,
        language: Language,
        defaultCategory: Topic?,
        verified: Bool = false
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.language = language
        self.defaultCategory = defaultCategory
        self.verified = verified
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, url, language, defaultCategory, verified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(URL.self, forKey: .url)
        language = try container.decode(Language.self, forKey: .language)
        defaultCategory = try container.decodeIfPresent(Topic.self, forKey: .defaultCategory)
        verified = try container.decodeIfPresent(Bool.self, forKey: .verified) ?? false
    }
}

import Foundation

/// Keyword lists per topic and language, loaded from `keywords.json`.
///
/// File format:
/// ```json
/// {
///   "minimumMatches": 1,
///   "topics": {
///     "crypto": { "common": ["bitcoin", "blockchain"], "pl": ["kryptowalut*"], "en": [...], "de": [...] }
///   }
/// }
/// ```
/// Matching rules (case- and diacritic-insensitive, on word boundaries):
/// - `"inflation"` matches the whole word only,
/// - `"inflat*"` matches any word starting with `inflat`,
/// - `"central bank"` matches the phrase (words in order).
public struct KeywordList: Codable, Equatable, Sendable {
    public struct TopicKeywords: Codable, Equatable, Sendable {
        /// Keywords applied to articles in every language (names, tickers, brands).
        public var common: [String]
        public var pl: [String]
        public var en: [String]
        public var de: [String]

        public init(common: [String] = [], pl: [String] = [], en: [String] = [], de: [String] = []) {
            self.common = common
            self.pl = pl
            self.en = en
            self.de = de
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            common = try container.decodeIfPresent([String].self, forKey: .common) ?? []
            pl = try container.decodeIfPresent([String].self, forKey: .pl) ?? []
            en = try container.decodeIfPresent([String].self, forKey: .en) ?? []
            de = try container.decodeIfPresent([String].self, forKey: .de) ?? []
        }

        public func keywords(for language: Language) -> [String] {
            switch language {
            case .polish: return common + pl
            case .english: return common + en
            case .german: return common + de
            }
        }
    }

    /// Minimum number of distinct keyword hits needed to assign a topic.
    public var minimumMatches: Int
    public var topics: [Topic: TopicKeywords]

    public init(minimumMatches: Int = 1, topics: [Topic: TopicKeywords]) {
        self.minimumMatches = minimumMatches
        self.topics = topics
    }

    private enum CodingKeys: String, CodingKey {
        case minimumMatches, topics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minimumMatches = try container.decodeIfPresent(Int.self, forKey: .minimumMatches) ?? 1
        let raw = try container.decode([String: TopicKeywords].self, forKey: .topics)
        var topics: [Topic: TopicKeywords] = [:]
        for (key, value) in raw {
            guard let topic = Topic(rawValue: key) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .topics, in: container,
                    debugDescription: "Unknown topic '\(key)' in keyword list"
                )
            }
            topics[topic] = value
        }
        self.topics = topics
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(minimumMatches, forKey: .minimumMatches)
        let raw = Dictionary(uniqueKeysWithValues: topics.map { ($0.key.rawValue, $0.value) })
        try container.encode(raw, forKey: .topics)
    }
}

import Foundation

/// Free, offline topic classification: the source's default category plus keyword matching.
public struct TopicClassifier: Sendable {
    /// A compiled keyword pattern (folded, padded for word-boundary matching).
    private struct Pattern: Sendable {
        let needle: String
    }

    private let minimumMatches: Int
    private let patterns: [Language: [Topic: [Pattern]]]

    public init(keywords: KeywordList) {
        minimumMatches = max(1, keywords.minimumMatches)
        var patterns: [Language: [Topic: [Pattern]]] = [:]
        for language in Language.allCases {
            var perTopic: [Topic: [Pattern]] = [:]
            for (topic, list) in keywords.topics {
                perTopic[topic] = list.keywords(for: language).compactMap(Self.compile)
            }
            patterns[language] = perTopic
        }
        self.patterns = patterns
    }

    private static func compile(_ keyword: String) -> Pattern? {
        let isPrefix = keyword.hasSuffix("*")
        let words = TextNormalizer.tokens(isPrefix ? String(keyword.dropLast()) : keyword)
        guard !words.isEmpty else { return nil }
        // " word " for exact words, " word" for prefixes.
        return Pattern(needle: " " + words.joined(separator: " ") + (isPrefix ? "" : " "))
    }

    /// Topics detected from keywords only.
    public func keywordTopics(title: String, summary: String, language: Language) -> Set<Topic> {
        let haystack = TextNormalizer.searchableText(title + " " + summary)
        var result: Set<Topic> = []
        for (topic, topicPatterns) in patterns[language] ?? [:] {
            var hits = 0
            for pattern in topicPatterns where haystack.contains(pattern.needle) {
                hits += 1
                if hits >= minimumMatches {
                    result.insert(topic)
                    break
                }
            }
        }
        return result
    }

    /// Source default category ∪ keyword topics.
    public func classify(title: String, summary: String, source: FeedSource) -> Set<Topic> {
        var topics = keywordTopics(title: title, summary: summary, language: source.language)
        if let category = source.defaultCategory {
            topics.insert(category)
        }
        return topics
    }
}

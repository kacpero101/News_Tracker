import Foundation

/// Free, offline topic classification: the source's default category plus keyword matching.
public struct TopicClassifier: Sendable {
    /// A compiled keyword: a sequence of words, each matched exactly or as a prefix.
    struct Pattern: Sendable, Equatable {
        struct Term: Sendable, Equatable {
            let word: String
            let isPrefix: Bool

            func matches(_ token: String) -> Bool {
                isPrefix ? token.hasPrefix(word) : token == word
            }
        }

        let terms: [Term]

        /// Whether the terms occur consecutively somewhere in `tokens`.
        func matches(_ tokens: [String]) -> Bool {
            guard !terms.isEmpty, tokens.count >= terms.count else { return false }
            for start in 0...(tokens.count - terms.count) {
                var matched = true
                for (offset, term) in terms.enumerated() where !term.matches(tokens[start + offset]) {
                    matched = false
                    break
                }
                if matched { return true }
            }
            return false
        }
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

    /// `"stop* procentow*"` → [("stop", prefix), ("procentow", prefix)].
    static func compile(_ keyword: String) -> Pattern? {
        var terms: [Pattern.Term] = []
        for rawWord in keyword.split(whereSeparator: { $0.isWhitespace }) {
            let isPrefix = rawWord.hasSuffix("*")
            let words = TextNormalizer.tokens(String(isPrefix ? rawWord.dropLast() : rawWord))
            // Punctuation inside a word ("s&p", "us-notenbank") splits it into several tokens;
            // only the last one keeps the prefix flag.
            for (index, word) in words.enumerated() {
                terms.append(.init(word: word, isPrefix: isPrefix && index == words.count - 1))
            }
        }
        return terms.isEmpty ? nil : Pattern(terms: terms)
    }

    /// Topics detected from keywords only.
    public func keywordTopics(title: String, summary: String, language: Language) -> Set<Topic> {
        let tokens = TextNormalizer.tokens(title + " " + summary)
        var result: Set<Topic> = []
        for (topic, topicPatterns) in patterns[language] ?? [:] {
            var hits = 0
            for pattern in topicPatterns where pattern.matches(tokens) {
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

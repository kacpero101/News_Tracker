import Foundation

/// A user-defined news category, classified by keywords only (matched in all languages).
public struct CustomCategory: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Same syntax as `keywords.json`: `word`, `prefix*`, `two words`.
    public var keywords: [String]
    /// SF Symbol name used in the UI.
    public var symbol: String
    /// Color name used in the UI (e.g. `"teal"`).
    public var color: String

    public init(id: String? = nil, name: String, keywords: [String], symbol: String = "tag", color: String = "teal") {
        self.id = id ?? "custom-" + UUID().uuidString.prefix(8).lowercased()
        self.name = name
        self.keywords = keywords
        self.symbol = symbol
        self.color = color
    }

    public var topic: Topic { Topic(rawValue: id) }

    /// Splits user input ("dron*, sztuczna inteligencja\nNATO") into keywords.
    public static func parseKeywords(_ text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && TopicClassifier.compile($0) != nil }
            .filter { seen.insert(TextNormalizer.fold($0)).inserted }
    }
}

public extension KeywordList {
    /// Adds custom categories; their keywords apply to every language.
    func merging(_ categories: [CustomCategory]) -> KeywordList {
        var merged = self
        for category in categories {
            merged.topics[category.topic] = TopicKeywords(common: category.keywords)
        }
        return merged
    }
}

public extension Article {
    /// Recomputes only the `managed` topics (e.g. all custom categories, including removed
    /// ones) from keywords; other topics (source category, built-in keywords, AI) stay.
    func reclassified(with classifier: TopicClassifier, managing managed: Set<Topic>) -> Article {
        var copy = self
        let detected = classifier.keywordTopics(title: title, summary: summary, language: language)
        copy.topics = topics.subtracting(managed).union(detected.intersection(managed))
        return copy
    }
}

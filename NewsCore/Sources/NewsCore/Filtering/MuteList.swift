import Foundation

/// "Ignore similar news": muted keywords (same syntax as `keywords.json`) and
/// individually hidden articles.
public struct MuteList: Codable, Equatable, Sendable {
    public var keywords: [String]
    public var hiddenArticleIDs: Set<String>

    public init(keywords: [String] = [], hiddenArticleIDs: Set<String> = []) {
        self.keywords = keywords
        self.hiddenArticleIDs = hiddenArticleIDs
    }

    public var isEmpty: Bool { keywords.isEmpty && hiddenArticleIDs.isEmpty }

    /// Adds keywords, skipping duplicates (case and diacritics insensitive) and invalid entries.
    public mutating func add(keywords newKeywords: [String]) {
        var seen = Set(keywords.map(TextNormalizer.fold))
        for keyword in newKeywords.map({ $0.trimmingCharacters(in: .whitespaces) })
        where TopicClassifier.compile(keyword) != nil && seen.insert(TextNormalizer.fold(keyword)).inserted {
            keywords.append(keyword)
        }
    }

    public mutating func remove(keyword: String) {
        keywords.removeAll { $0 == keyword }
    }

    public func matcher() -> MuteMatcher {
        MuteMatcher(self)
    }
}

/// Compiled `MuteList` for fast filtering.
public struct MuteMatcher: Sendable {
    private let patterns: [(keyword: String, pattern: TopicClassifier.Pattern)]
    private let hiddenIDs: Set<String>

    public init(_ list: MuteList) {
        patterns = list.keywords.compactMap { keyword in
            TopicClassifier.compile(keyword).map { (keyword, $0) }
        }
        hiddenIDs = list.hiddenArticleIDs
    }

    /// Muted keywords found in the article's title or summary.
    public func matchingKeywords(_ article: Article) -> [String] {
        guard !patterns.isEmpty else { return [] }
        let tokens = TextNormalizer.tokens(article.title + " " + article.summary)
        return patterns.filter { $0.pattern.matches(tokens) }.map(\.keyword)
    }

    public func isMuted(_ article: Article) -> Bool {
        hiddenIDs.contains(article.id) || !matchingKeywords(article).isEmpty
    }

    /// Articles that are not muted.
    public func visible(_ articles: [Article]) -> [Article] {
        guard !patterns.isEmpty || !hiddenIDs.isEmpty else { return articles }
        return articles.filter { !isMuted($0) }
    }
}

/// Suggests keywords for "ignore similar news" from an article's headline.
public enum SimilarNewsSuggester {
    /// Frequent words that say nothing about the story (PL/EN/DE).
    static let stopwords: Set<String> = [
        // Polish
        "oraz", "jest", "jako", "przez", "przed", "podczas", "tylko", "bardzo", "jego", "jej", "ich",
        "sie", "nie", "tak", "czy", "juz", "jeszcze", "kiedy", "gdzie", "ktory", "ktora", "ktore",
        "ktorzy", "tego", "tej", "tym", "temu", "tych", "moze", "mozna", "beda", "bedzie", "byl", "byla",
        "bylo", "byly", "sa", "ten", "ta", "to", "po", "na", "za", "od", "do", "dla", "pod", "nad", "we",
        "wiec", "jednak", "takze", "rowniez", "teraz", "dzis", "dzisiaj", "wczoraj", "jutro", "nowy",
        "nowa", "nowe", "roku", "lata", "lat", "latach", "proc", "mln", "mld", "tys", "wiadomo", "zobacz",
        "wideo", "relacja", "najnowsze", "nagle", "ktorej", "ktorym", "swoje", "swoj", "swoja", "wszystko",
        "wszyscy", "sposob", "chca", "chce", "mowi", "powiedzial", "powiedziala",
        // English
        "the", "and", "for", "with", "from", "that", "this", "these", "those", "have", "has", "had",
        "will", "would", "could", "should", "been", "were", "was", "are", "about", "after", "before",
        "over", "into", "than", "then", "they", "their", "there", "what", "when", "where", "which",
        "while", "your", "says", "said", "just", "more", "most", "new", "news", "live", "latest",
        "update", "updates", "video", "watch", "year", "years", "first", "last", "how", "why", "who",
        // German
        "und", "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer",
        "mit", "von", "fur", "auf", "aus", "bei", "nach", "uber", "unter", "nicht", "sich", "auch",
        "noch", "wird", "werden", "wurde", "sind", "ist", "war", "hat", "haben", "sein", "seine",
        "ihre", "wie", "was", "wer", "wenn", "dass", "oder", "aber", "neue", "neuer", "neues", "jahr",
        "jahre", "heute", "jetzt", "mehr", "sagt",
    ]

    /// Distinct meaningful words of the headline (lowercased, original diacritics kept),
    /// in headline order. Short words are kept only when written in capitals (`USA`, `ONZ`, `AI`).
    public static func suggestions(for article: Article, limit: Int = 8) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let words = article.title.split { !($0.isLetter || $0.isNumber || $0 == "-") }
        for raw in words {
            let word = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let folded = TextNormalizer.fold(word)
            let isAcronym = word.count >= 2 && word == word.uppercased() && word.contains(where: \.isLetter)
            guard (word.count >= 4 || isAcronym),
                  !word.allSatisfy({ $0.isNumber || $0 == "-" }),
                  !stopwords.contains(folded),
                  seen.insert(folded).inserted
            else { continue }
            result.append(isAcronym ? word : word.lowercased())
            if result.count == limit { break }
        }
        return result
    }

    /// Prefix pattern that also matches inflected forms: `Iranu` → `iran*`, `przejeździe` → `przejeźdz*`.
    /// Acronyms and short words stay exact.
    public static func stem(_ word: String) -> String {
        let characters = Array(word.lowercased())
        guard characters.count >= 5, word != word.uppercased() else { return word }
        let keep = max(4, characters.count - 2)
        return String(characters.prefix(keep)) + "*"
    }
}

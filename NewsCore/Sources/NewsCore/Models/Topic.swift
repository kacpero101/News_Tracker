import Foundation

/// A thematic category an article can belong to. An article may have several topics.
///
/// Five topics are built in; users can add their own (see `CustomCategory`), so this is an
/// open set identified by a string (`"finance"`, `"custom-1a2b3c4d"`).
public struct Topic: RawRepresentable, Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let finance = Topic(rawValue: "finance")
    public static let politics = Topic(rawValue: "politics")
    public static let breakthroughs = Topic(rawValue: "breakthroughs")
    public static let crypto = Topic(rawValue: "crypto")
    public static let economy = Topic(rawValue: "economy")
    public static let defense = Topic(rawValue: "defense")
    public static let cybersecurity = Topic(rawValue: "cybersecurity")

    /// Filter-only pseudo-topic selecting news without any topic. Never assigned to articles.
    public static let uncategorized = Topic(rawValue: "uncategorized")

    /// Built-in topics in display order.
    public static let builtIn: [Topic] = [.finance, .politics, .breakthroughs, .crypto, .economy, .defense, .cybersecurity]

    public var isBuiltIn: Bool { Topic.builtIn.contains(self) }

    public var description: String { rawValue }

    /// Built-in topics first (in display order), then custom topics by identifier.
    public static func < (lhs: Topic, rhs: Topic) -> Bool {
        switch (builtIn.firstIndex(of: lhs), builtIn.firstIndex(of: rhs)) {
        case let (l?, r?): return l < r
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return lhs.rawValue < rhs.rawValue
        }
    }
}

import Foundation

/// A thematic category an article can belong to. An article may have several topics.
public enum Topic: String, CaseIterable, Codable, Hashable, Sendable, Comparable {
    case finance
    case politics
    case breakthroughs
    case crypto
    case economy

    public static func < (lhs: Topic, rhs: Topic) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

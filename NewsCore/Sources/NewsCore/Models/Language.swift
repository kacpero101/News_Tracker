import Foundation

/// Supported content languages (ISO 639-1 codes as raw values).
public enum Language: String, CaseIterable, Codable, Hashable, Sendable, Comparable {
    case polish = "pl"
    case english = "en"
    case german = "de"

    public static func < (lhs: Language, rhs: Language) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

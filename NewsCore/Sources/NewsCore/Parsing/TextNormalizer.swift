import Foundation

/// Text helpers used by classification, deduplication and search.
public enum TextNormalizer {
    /// Characters that `folding(options:)` does not decompose into a base letter.
    private static let extraFolding: [Character: String] = [
        "ł": "l", "Ł": "l", "ß": "ss", "ø": "o", "Ø": "o", "æ": "ae", "Æ": "ae", "đ": "d", "Đ": "d",
    ]

    /// Lowercases and removes diacritics (`"Złoty Świat"` → `"zloty swiat"`).
    public static func fold(_ text: String) -> String {
        var mapped = ""
        mapped.reserveCapacity(text.count)
        for character in text {
            if let replacement = extraFolding[character] {
                mapped += replacement
            } else {
                mapped.append(character)
            }
        }
        return mapped
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
    }

    /// Splits folded text into alphanumeric word tokens.
    public static func tokens(_ text: String) -> [String] {
        fold(text)
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }

    /// Folded tokens joined by single spaces and padded with a leading and trailing
    /// space, so that phrase and prefix matching can rely on word boundaries.
    public static func searchableText(_ text: String) -> String {
        " " + tokens(text).joined(separator: " ") + " "
    }
}

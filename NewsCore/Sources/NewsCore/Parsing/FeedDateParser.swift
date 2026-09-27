import Foundation

/// Parses the date formats found in RSS (RFC 822) and Atom (RFC 3339 / ISO 8601) feeds.
/// Not thread-safe; create one instance per parse.
final class FeedDateParser {
    private static let rfc822Formats = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, d MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm Z",
        "EEE, dd MMM yyyy HH:mm zzz",
        "dd MMM yyyy HH:mm:ss Z",
        "d MMM yyyy HH:mm:ss Z",
        "dd MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss",
    ]

    private static let isoFormats = [
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mmXXXXX",
        "yyyy-MM-dd HH:mm:ssXXXXX",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd",
    ]

    private lazy var rfc822Formatters: [DateFormatter] = Self.rfc822Formats.map(Self.makeFormatter)
    private lazy var isoFormatters: [DateFormatter] = Self.isoFormats.map(Self.makeFormatter)

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    func parse(_ raw: String) -> Date? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // ISO 8601: "2024-05-01T10:00:00Z" – normalize a trailing "Z" to "+00:00".
        if text.first?.isNumber == true, text.count >= 10, text[text.index(text.startIndex, offsetBy: 4)] == "-" {
            if text.hasSuffix("Z") || text.hasSuffix("z") {
                text = String(text.dropLast()) + "+00:00"
            }
            return firstMatch(text, in: isoFormatters)
        }

        // RFC 822: normalize common but non-standard zone names.
        for zone in [" UT", " Z", " UTC"] where text.hasSuffix(zone) {
            text = String(text.dropLast(zone.count)) + " GMT"
            break
        }
        return firstMatch(text, in: rfc822Formatters)
    }

    private func firstMatch(_ text: String, in formatters: [DateFormatter]) -> Date? {
        for formatter in formatters {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

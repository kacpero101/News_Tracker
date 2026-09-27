import Foundation

/// Converts HTML snippets from feed descriptions into plain text.
public enum HTMLText {
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "laquo": "«", "raquo": "»",
        "bdquo": "„", "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "sbquo": "‚",
        "euro": "€", "pound": "£", "copy": "©", "reg": "®", "trade": "™", "deg": "°",
        "auml": "ä", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß",
        "eacute": "é", "egrave": "è", "aacute": "á", "oacute": "ó", "Oacute": "Ó", "shy": "",
    ]

    /// Removes tags, decodes entities and collapses whitespace.
    public static func plainText(from html: String) -> String {
        collapseWhitespace(decodeEntities(stripTags(html)))
    }

    /// Plain text truncated to `maxLength` characters on a word boundary (with an ellipsis).
    public static func summary(from html: String, maxLength: Int = 300) -> String {
        let text = plainText(from: html)
        guard text.count > maxLength else { return text }
        let cut = text.prefix(maxLength)
        let trimmed: Substring
        if let lastSpace = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: lastSpace) > maxLength / 2 {
            trimmed = cut[..<lastSpace]
        } else {
            trimmed = cut
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) + "…"
    }

    static func stripTags(_ html: String) -> String {
        var result = ""
        result.reserveCapacity(html.count)
        var insideTag = false
        var skipContentUntil: String?
        var tagBuffer = ""

        for character in html {
            if insideTag {
                if character == ">" {
                    insideTag = false
                    let tagName = tagBuffer
                        .trimmingCharacters(in: .whitespaces)
                        .split(whereSeparator: { $0.isWhitespace })
                        .first
                        .map { $0.lowercased() } ?? ""
                    if let closing = skipContentUntil {
                        if tagName == closing { skipContentUntil = nil }
                    } else if tagName == "script" || tagName == "style" {
                        skipContentUntil = "/" + tagName
                    } else if ["br", "br/", "p", "/p", "div", "/div", "li", "/li"].contains(tagName) {
                        result.append(" ")
                    }
                    tagBuffer = ""
                } else {
                    tagBuffer.append(character)
                }
            } else if character == "<" {
                insideTag = true
            } else if skipContentUntil == nil {
                result.append(character)
            }
        }
        return result
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&",
                  let semicolon = text[index...].prefix(12).firstIndex(of: ";")
            else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            let entity = String(text[text.index(after: index)..<semicolon])
            if let decoded = decode(entity: entity) {
                result += decoded
                index = text.index(after: semicolon)
            } else {
                result.append(character)
                index = text.index(after: index)
            }
        }
        return result
    }

    private static func decode(entity: String) -> String? {
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            return UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        if entity.hasPrefix("#") {
            return UInt32(entity.dropFirst(), radix: 10).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return namedEntities[entity]
    }

    static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

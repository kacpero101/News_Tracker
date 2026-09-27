import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A raw entry extracted from a feed, before classification.
public struct FeedItem: Equatable, Sendable {
    public var title: String
    public var link: URL?
    /// Plain-text short description (HTML stripped, truncated).
    public var summary: String
    public var publishedAt: Date?
    public var guid: String?

    public init(title: String, link: URL?, summary: String, publishedAt: Date?, guid: String?) {
        self.title = title
        self.link = link
        self.summary = summary
        self.publishedAt = publishedAt
        self.guid = guid
    }
}

/// The result of parsing a feed document.
public struct ParsedFeed: Equatable, Sendable {
    public enum Format: String, Sendable {
        case rss2, rss1, atom
    }

    public var format: Format
    public var title: String
    public var items: [FeedItem]
}

public enum FeedParserError: Error, Equatable, LocalizedError {
    case invalidXML(String)
    case unsupportedFormat(rootElement: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidXML(message): return "Invalid XML: \(message)"
        case let .unsupportedFormat(root): return "Unsupported feed format (root element <\(root)>)"
        }
    }
}

/// Parses RSS 2.0, RSS 1.0 (RDF) and Atom 1.0 documents using `XMLParser`.
public struct FeedParser: Sendable {
    /// Maximum length of the plain-text summary kept for each item.
    public var summaryMaxLength: Int

    public init(summaryMaxLength: Int = 300) {
        self.summaryMaxLength = summaryMaxLength
    }

    public func parse(_ data: Data) throws -> ParsedFeed {
        let delegate = FeedParserDelegate(summaryMaxLength: summaryMaxLength)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        let success = parser.parse()

        guard let format = delegate.format else {
            if let root = delegate.rootElement {
                throw FeedParserError.unsupportedFormat(rootElement: root)
            }
            throw FeedParserError.invalidXML(parser.parserError?.localizedDescription ?? "empty document")
        }
        // Tolerate errors late in the document as long as some items were read.
        if !success && delegate.items.isEmpty {
            throw FeedParserError.invalidXML(parser.parserError?.localizedDescription ?? "unknown error")
        }
        return ParsedFeed(format: format, title: delegate.feedTitle, items: delegate.items)
    }
}

// MARK: - XMLParser delegate

private final class FeedParserDelegate: NSObject, XMLParserDelegate {
    let summaryMaxLength: Int
    private let dateParser = FeedDateParser()

    private(set) var rootElement: String?
    private(set) var format: ParsedFeed.Format?
    private(set) var feedTitle = ""
    private(set) var items: [FeedItem] = []

    private var elementStack: [String] = []
    private var text = ""
    private var current: ItemBuilder?

    private struct ItemBuilder {
        var title = ""
        var link: String?
        var alternateLink: String?
        var summary = ""
        var content = ""
        var published: String?
        var updated: String?
        var guid: String?
        var guidIsPermaLink = true
    }

    init(summaryMaxLength: Int) {
        self.summaryMaxLength = summaryMaxLength
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        if rootElement == nil {
            rootElement = elementName
            switch name {
            case "rss": format = .rss2
            case "rdf:rdf", "rdf": format = .rss1
            case "feed": format = .atom
            default: break
            }
        }
        elementStack.append(name)
        text = ""

        switch name {
        case "item", "entry":
            current = ItemBuilder()
        case "link" where format == .atom && current != nil:
            // Atom: <link rel="alternate" href="..."/>. A link without `rel` is alternate.
            let rel = attributeDict["rel"]?.lowercased() ?? "alternate"
            if let href = attributeDict["href"] {
                if rel == "alternate" && current?.alternateLink == nil {
                    current?.alternateLink = href
                } else if current?.link == nil && rel != "self" && rel != "enclosure" && rel != "replies" {
                    current?.link = href
                }
            }
        case "guid":
            current?.guidIsPermaLink = attributeDict["isPermaLink"]?.lowercased() != "false"
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            text += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            elementStack.removeLast()
            text = ""
        }

        guard current != nil else {
            // Channel / feed level: only the title is relevant.
            if name == "title", feedTitle.isEmpty, isDirectChildOfFeed {
                feedTitle = HTMLText.plainText(from: value)
            }
            return
        }

        // Only look at direct children of the item/entry (skip nested elements like <source><title>).
        guard elementStack.count >= 2, ["item", "entry"].contains(elementStack[elementStack.count - 2]) || name == "item" || name == "entry" else {
            return
        }

        switch name {
        case "title":
            current?.title = HTMLText.plainText(from: value)
        case "link":
            if format != .atom, !value.isEmpty { current?.link = value }
        case "description", "summary", "dc:description":
            if current?.summary.isEmpty == true { current?.summary = value }
        case "content", "content:encoded":
            if current?.content.isEmpty == true { current?.content = value }
        case "pubdate", "published", "dc:date", "issued":
            if current?.published == nil { current?.published = value }
        case "updated", "modified", "atom:updated":
            if current?.updated == nil { current?.updated = value }
        case "guid", "id":
            current?.guid = value
        case "item", "entry":
            if let builder = current { finish(builder) }
            current = nil
        default:
            break
        }
    }

    private var isDirectChildOfFeed: Bool {
        guard elementStack.count >= 2 else { return false }
        let parent = elementStack[elementStack.count - 2]
        return parent == "channel" || parent == "feed"
    }

    private func finish(_ builder: ItemBuilder) {
        var linkString = builder.alternateLink ?? builder.link
        if linkString == nil, builder.guidIsPermaLink, let guid = builder.guid, guid.hasPrefix("http") {
            linkString = guid
        }
        let link = linkString
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap(URL.init(string:))

        let rawSummary = builder.summary.isEmpty ? builder.content : builder.summary
        let dateString = builder.published ?? builder.updated

        let item = FeedItem(
            title: builder.title,
            link: link,
            summary: HTMLText.summary(from: rawSummary, maxLength: summaryMaxLength),
            publishedAt: dateString.flatMap(dateParser.parse),
            guid: builder.guid
        )
        // Skip entries that cannot be displayed meaningfully.
        guard !item.title.isEmpty || !item.summary.isEmpty else { return }
        items.append(item)
    }
}

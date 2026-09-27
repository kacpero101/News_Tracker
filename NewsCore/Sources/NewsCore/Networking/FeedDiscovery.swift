import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A feed found by `FeedDiscoverer`.
public struct DiscoveredFeed: Equatable, Identifiable, Sendable {
    public var id: URL { url }
    public var url: URL
    public var title: String
    public var format: ParsedFeed.Format
    public var itemCount: Int
    /// First few headlines, to help the user pick the right feed.
    public var sampleTitles: [String]

    init(url: URL, feed: ParsedFeed) {
        self.url = url
        self.title = feed.title.isEmpty ? (url.host ?? url.absoluteString) : feed.title
        self.format = feed.format
        self.itemCount = feed.items.count
        self.sampleTitles = feed.items.prefix(3).map(\.title)
    }
}

public enum FeedDiscoveryError: Error, Equatable, LocalizedError {
    case noFeedFound

    public var errorDescription: String? {
        "Pod tym adresem jest strona, a nie kanał RSS, i nie znaleziono na niej odnośnika do kanału"
    }
}

/// HTML helpers for finding RSS/Atom feeds linked from web pages.
public enum FeedDiscovery {
    /// Accepts what users type: `pb.pl`, `www.money.pl/rss/`, `https://…`.
    public static func normalizedURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), let host = url.host, host.contains(".") else { return nil }
        return url
    }

    public static func looksLikeHTML(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(4096), as: UTF8.self).lowercased()
        return head.contains("<html") || head.contains("<!doctype html")
    }

    /// Page text for link scanning (UTF-8, falling back to Latin-1).
    public static func decodeHTML(_ data: Data) -> String? {
        let slice = data.prefix(3_000_000)
        return String(data: slice, encoding: .utf8) ?? String(data: slice, encoding: .isoLatin1)
    }

    /// Feed links in a page: `<link rel="alternate" type="application/rss+xml">` first,
    /// then `<a href>` links that look like feeds (containing "rss", "feed", "atom" or ending in ".xml").
    public static func candidateURLs(inHTML html: String, baseURL: URL, limit: Int = 15) -> [URL] {
        var alternates: [URL] = []
        for tag in tags(named: "link", in: html) {
            let attributes = parseAttributes(tag)
            let rel = (attributes["rel"] ?? "").lowercased().split(separator: " ")
            let type = (attributes["type"] ?? "").lowercased()
            guard rel.contains("alternate"),
                  type.contains("rss") || type.contains("atom") || type.hasSuffix("/xml"),
                  let href = attributes["href"],
                  let url = resolve(href, against: baseURL)
            else { continue }
            alternates.append(url)
        }

        var anchors: [URL] = []
        for tag in tags(named: "a", in: html) {
            guard let href = parseAttributes(tag)["href"] else { continue }
            let lower = href.lowercased()
            let looksLikeFeed = lower.contains("rss") || lower.contains("feed") || lower.contains("atom") || lower.hasSuffix(".xml")
            guard looksLikeFeed, let url = resolve(href, against: baseURL) else { continue }
            anchors.append(url)
        }

        var seen = Set<String>()
        let unique = (alternates + anchors).filter { seen.insert($0.absoluteString).inserted }
        return Array(unique.prefix(limit))
    }

    /// Usual feed locations (WordPress, Ringier Axel Springer, GPW-style and generic).
    public static func commonFeedURLs(for url: URL) -> [URL] {
        guard let scheme = url.scheme, let host = url.host else { return [] }
        let root = "\(scheme)://\(host)"
        return ["/feed", "/rss", "/rss.xml", "/.feed", "/_rss", "/feed.xml", "/atom.xml", "/index.xml"]
            .compactMap { URL(string: root + $0) }
    }

    // MARK: Tolerant tag scanning (no regular expressions, works on Linux too)

    /// Raw start tags (`<link …>`) with the given name, case-insensitive.
    static func tags(named name: String, in html: String) -> [String] {
        var result: [String] = []
        var searchStart = html.startIndex
        while let open = html.range(of: "<" + name, options: .caseInsensitive, range: searchStart..<html.endIndex) {
            let after = open.upperBound
            guard after < html.endIndex else { break }
            // Tag name must end here, so "<a" does not match "<abbr".
            let next = html[after]
            guard next.isWhitespace || next == "/" || next == ">" else {
                searchStart = after
                continue
            }
            guard let close = html.range(of: ">", range: after..<html.endIndex) else { break }
            result.append(String(html[open.lowerBound..<close.upperBound]))
            searchStart = close.upperBound
        }
        return result
    }

    /// Attributes of a start tag (`name="v"`, `name='v'`, `name=v`), names lowercased.
    static func parseAttributes(_ tag: String) -> [String: String] {
        let chars = Array(tag)
        var attributes: [String: String] = [:]
        var i = 0
        // Skip "<name".
        while i < chars.count, !chars[i].isWhitespace, chars[i] != ">" { i += 1 }
        while i < chars.count {
            let start = i
            while i < chars.count, chars[i].isWhitespace || chars[i] == "/" { i += 1 }
            guard i < chars.count, chars[i] != ">" else { break }
            var name = ""
            while i < chars.count, !chars[i].isWhitespace, chars[i] != "=", chars[i] != ">", chars[i] != "/" {
                name.append(chars[i])
                i += 1
            }
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            var value = ""
            if i < chars.count, chars[i] == "=" {
                i += 1
                while i < chars.count, chars[i].isWhitespace { i += 1 }
                if i < chars.count, chars[i] == "\"" || chars[i] == "'" {
                    let quote = chars[i]
                    i += 1
                    while i < chars.count, chars[i] != quote {
                        value.append(chars[i])
                        i += 1
                    }
                    i += 1
                } else {
                    while i < chars.count, !chars[i].isWhitespace, chars[i] != ">" {
                        value.append(chars[i])
                        i += 1
                    }
                }
            }
            if !name.isEmpty {
                attributes[name.lowercased()] = HTMLText.decodeEntities(value)
            }
            if i == start { i += 1 } // always make progress
        }
        return attributes
    }

    static func resolve(_ href: String, against base: URL) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
              let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }
}

/// Finds RSS/Atom feeds for an address: the address itself, feeds linked from the page
/// (also through an "RSS" page listing several feeds) and usual feed locations.
public struct FeedDiscoverer: Sendable {
    private let client: HTTPClient
    private let parser: FeedParser
    private let timeout: TimeInterval

    public init(client: HTTPClient = URLSessionHTTPClient(), parser: FeedParser = FeedParser(), timeout: TimeInterval = 10) {
        self.client = client
        self.parser = parser
        self.timeout = timeout
    }

    /// All feeds found for a site or feed address typed by the user (for the "add source" screen).
    public func discover(_ input: String, maxProbes: Int = 15) async -> [DiscoveredFeed] {
        guard let url = FeedDiscovery.normalizedURL(from: input) else { return [] }
        guard let (data, finalURL) = try? await fetch(url) else {
            // The page itself failed; still try the usual feed locations.
            return await search(pageCandidates: [], pageURL: url, maxProbes: maxProbes, stopAtFirst: false)
                .map { DiscoveredFeed(url: $0.url, feed: $0.feed) }
        }
        if let feed = try? parser.parse(data) {
            return [DiscoveredFeed(url: url, feed: feed)]
        }
        let candidates = FeedDiscovery.decodeHTML(data).map { FeedDiscovery.candidateURLs(inHTML: $0, baseURL: finalURL) } ?? []
        return await search(pageCandidates: candidates, pageURL: finalURL, maxProbes: maxProbes, stopAtFirst: false)
            .map { DiscoveredFeed(url: $0.url, feed: $0.feed) }
    }

    /// First non-empty feed linked from an already downloaded HTML page (used while refreshing).
    public func firstFeed(linkedFrom html: String, pageURL: URL, maxProbes: Int = 6) async -> (url: URL, feed: ParsedFeed)? {
        let candidates = FeedDiscovery.candidateURLs(inHTML: html, baseURL: pageURL)
        return await search(pageCandidates: candidates, pageURL: pageURL, maxProbes: maxProbes, stopAtFirst: true).first
    }

    /// Breadth-first probing: page links first, then (one level deeper) links on pages that
    /// list feeds, then usual feed locations.
    private func search(pageCandidates: [URL], pageURL: URL, maxProbes: Int, stopAtFirst: Bool) async -> [(url: URL, feed: ParsedFeed)] {
        var queue: [(url: URL, depth: Int)] = pageCandidates.map { ($0, 1) }
        queue += FeedDiscovery.commonFeedURLs(for: pageURL).map { ($0, 1) }
        var visited: Set<String> = [pageURL.absoluteString]
        var found: [(url: URL, feed: ParsedFeed)] = []
        var probes = 0
        var index = 0
        while index < queue.count, probes < maxProbes {
            let (url, depth) = queue[index]
            index += 1
            guard visited.insert(url.absoluteString).inserted else { continue }
            probes += 1
            guard let (data, finalURL) = try? await fetch(url) else { continue }
            if let feed = try? parser.parse(data) {
                guard !feed.items.isEmpty || !stopAtFirst else { continue }
                found.append((url, feed))
                if stopAtFirst { break }
            } else if depth < 2, FeedDiscovery.looksLikeHTML(data), let html = FeedDiscovery.decodeHTML(data) {
                let nested = FeedDiscovery.candidateURLs(inHTML: html, baseURL: finalURL, limit: 10).map { ($0, depth + 1) }
                queue.insert(contentsOf: nested, at: index)
            }
        }
        return found
    }

    private func fetch(_ url: URL) async throws -> (Data, URL) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, text/html;q=0.7, */*;q=0.5", forHTTPHeaderField: "Accept")
        request.setValue("NewsTracker/1.0 (RSS reader)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw HTTPClientError.badStatus(response.statusCode)
        }
        return (data, response.url ?? url)
    }
}

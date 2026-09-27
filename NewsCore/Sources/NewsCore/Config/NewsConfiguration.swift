import Foundation

/// Loads `sources.json` and `keywords.json`.
public enum NewsConfiguration {
    public enum ConfigError: Error, LocalizedError {
        case missingResource(String)

        public var errorDescription: String? {
            switch self {
            case let .missingResource(name): return "Missing configuration resource \(name)"
            }
        }
    }

    private struct SourcesFile: Decodable {
        let sources: [FeedSource]
    }

    public static func decodeSources(from data: Data) throws -> [FeedSource] {
        let sources = try JSONDecoder().decode(SourcesFile.self, from: data).sources
        var seen = Set<String>()
        return sources.filter { seen.insert($0.id).inserted }
    }

    public static func decodeKeywords(from data: Data) throws -> KeywordList {
        try JSONDecoder().decode(KeywordList.self, from: data)
    }

    /// Bundled default sources (`Resources/sources.json`).
    public static func defaultSources() throws -> [FeedSource] {
        try decodeSources(from: resource("sources"))
    }

    /// Bundled default keywords (`Resources/keywords.json`).
    public static func defaultKeywords() throws -> KeywordList {
        try decodeKeywords(from: resource("keywords"))
    }

    private static func resource(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw ConfigError.missingResource("\(name).json")
        }
        return try Data(contentsOf: url)
    }
}

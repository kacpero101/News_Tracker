import Foundation

/// Normalizes article URLs so that the same article linked from several feeds
/// (with tracking parameters, `www.`, `http`, trailing slashes…) compares equal.
public enum URLNormalizer {
    /// Query parameters that never identify content.
    static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "dclid", "msclkid", "yclid", "mc_cid", "mc_eid", "igshid",
        "ref", "ref_src", "referrer", "source", "src", "cmpid", "cmp", "ito", "xtor",
        "ns_mchannel", "ns_source", "ns_campaign", "ns_linkname", "ns_fee", "at_medium", "at_campaign",
        "ocid", "smid", "partner", "feature", "rss", "from",
    ]

    public static func normalize(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        components.scheme = "https"
        components.fragment = nil
        components.user = nil
        components.password = nil
        if var host = components.host?.lowercased() {
            for prefix in ["www.", "m.", "amp.", "mobile."] where host.hasPrefix(prefix) {
                host.removeFirst(prefix.count)
                break
            }
            components.host = host
        }
        if components.port == 80 || components.port == 443 {
            components.port = nil
        }

        var path = components.percentEncodedPath
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        for suffix in ["/amp", "/index.html", "/index.htm"] where path.hasSuffix(suffix) {
            path.removeLast(suffix.count)
        }
        components.percentEncodedPath = path

        let keptItems = (components.queryItems ?? [])
            .filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && !trackingParameters.contains(name)
            }
            .sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        components.queryItems = keptItems.isEmpty ? nil : keptItems

        return components.string ?? url.absoluteString.lowercased()
    }
}

import Foundation

public enum SearchEngine: String, CaseIterable, Codable, Sendable, Identifiable {
    case google, duckDuckGo, kagi, bing, ecosia, startpage

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .kagi: "Kagi"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        case .startpage: "Startpage"
        }
    }

    private var endpoint: String {
        switch self {
        case .google: "https://www.google.com/search?q="
        case .duckDuckGo: "https://duckduckgo.com/?q="
        case .kagi: "https://kagi.com/search?q="
        case .bing: "https://www.bing.com/search?q="
        case .ecosia: "https://www.ecosia.org/search?q="
        case .startpage: "https://www.startpage.com/do/search?q="
        }
    }

    /// The engine's OpenSearch suggestions endpoint, if it has a public one.
    private var suggestionsEndpoint: String? {
        switch self {
        case .google: "https://suggestqueries.google.com/complete/search?client=firefox&q="
        case .duckDuckGo: "https://duckduckgo.com/ac/?type=list&q="
        case .kagi: "https://kagi.com/api/autosuggest?q="
        case .bing: "https://api.bing.com/osjson.aspx?query="
        case .ecosia, .startpage: nil
        }
    }

    public var offersSuggestions: Bool { suggestionsEndpoint != nil }

    public func searchURL(for query: String) -> URL? {
        Self.url(endpoint, query)
    }

    public func suggestionsURL(for query: String) -> URL? {
        suggestionsEndpoint.flatMap { Self.url($0, query) }
    }

    /// Reads an OpenSearch suggestions response: `["query", ["one", "two", …], …]`.
    public static func suggestions(from data: Data) -> [String] {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [Any],
              response.count > 1, let suggestions = response[1] as? [String]
        else { return [] }
        return suggestions
    }

    private static func url(_ endpoint: String, _ query: String) -> URL? {
        // URLComponents leaves `&`, `=` and `+` unescaped in query values,
        // which would split or mangle the search, so encode them ourselves.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: endpoint + encoded)
    }
}

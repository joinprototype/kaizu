import Foundation

/// Safari-style inline completion for the address field: "git" → "github.com"
/// when a site you know starts with what you typed.
public enum InlineCompletion {
    /// `typed` extended to the first matching site (best candidates first),
    /// keeping what was typed exactly as typed. Typing a slash completes paths
    /// too ("github.com/an" → "github.com/anthropics"). Nil when nothing
    /// extends it, or when `typed` already is a known address (so typing
    /// "google.com" in full never turns into "google.com.au").
    public static func complete(_ typed: String, from urls: [URL]) -> String? {
        guard typed.count >= 2, !typed.contains(where: \.isWhitespace), !typed.contains(":") else { return nil }
        let prefix = typed.lowercased()
        let exact = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        let wantsPath = prefix.contains("/")
        // Each known URL as the forms a typed prefix can match.
        let candidates = urls.lazy.compactMap { url -> [String]? in
            guard let host = url.host()?.lowercased() else { return nil }
            let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            let path = url.path().hasSuffix("/") ? String(url.path().dropLast()) : url.path()
            return wantsPath ? [site + path, host + path] : [site, host]
        }
        guard !candidates.contains(where: { forms in forms.contains(exact) }) else { return nil }
        for forms in candidates {
            if let match = forms.first(where: { $0.count > prefix.count && $0.hasPrefix(prefix) }) {
                return typed + match.dropFirst(typed.count)
            }
        }
        return nil
    }
}

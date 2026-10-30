import Foundation

/// Turns whatever the user typed into the command bar into a URL.
public enum URLInput {
    /// Returns a URL only when the text clearly is one (has a web scheme or looks like a domain).
    public static func explicitURL(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }

        let schemes: Set = ["http", "https", "file", "about", "data"]
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), schemes.contains(scheme) {
            return url
        }

        let lower = text.lowercased()
        let hostAndPort = lower.split(separator: "/", maxSplits: 1).first.map(String.init) ?? lower
        let host = hostAndPort.split(separator: ":").first.map(String.init) ?? hostAndPort

        if host == "localhost" || host.wholeMatch(of: /\d{1,3}(\.\d{1,3}){3}/) != nil {
            return URL(string: "http://" + text)
        }
        if let tld = host.split(separator: ".").last, host.contains("."), tld.count >= 2, tld.allSatisfy(\.isLetter) {
            return URL(string: "https://" + text)
        }
        return nil
    }
}

extension URL {
    /// Rough "same site" key: the last two labels of the host (`mail.google.com`
    /// → `google.com`), or the whole host for IP addresses. Good enough to tell
    /// "leaving this site" apart from moving within it; not a public-suffix lookup.
    public var siteKey: String? {
        guard let host = host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        if host.wholeMatch(of: /[\d.]+|\[.*\]/) != nil { return host }
        return host.split(separator: ".").suffix(2).joined(separator: ".")
    }

    /// "www.github.com" → "github.com"; falls back to the file name or full string.
    public var displayHost: String {
        if let host = host(percentEncoded: false) {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return isFileURL ? lastPathComponent : absoluteString
    }
}

import Foundation

/// Air Traffic Control: a rule sending links opened from other apps to a
/// specific space (and so its profile's logins).
public struct LinkRoute: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// `github.com` (the site and its subdomains) or `github.com/myorg` (a path prefix).
    public var pattern: String
    public var spaceID: UUID

    public init(id: UUID = UUID(), pattern: String, spaceID: UUID) {
        self.id = id
        self.pattern = pattern
        self.spaceID = spaceID
    }

    public func matches(_ url: URL) -> Bool {
        var rule = pattern.trimmingCharacters(in: .whitespaces).lowercased()
        if let scheme = rule.range(of: "://") {
            rule.removeSubrange(..<scheme.upperBound)
        }
        let parts = rule.split(separator: "/", maxSplits: 1)
        guard let ruleHost = parts.first.map({ Self.trimmingWWW(String($0)) }), !ruleHost.isEmpty,
              let host = url.host(percentEncoded: false).map({ Self.trimmingWWW($0.lowercased()) })
        else { return false }

        guard host == ruleHost || host.hasSuffix("." + ruleHost) else { return false }
        guard parts.count == 2 else { return true }
        let prefix = "/" + parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = url.path(percentEncoded: false).lowercased()
        return path == prefix || path.hasPrefix(prefix + "/")
    }

    private static func trimmingWWW(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

extension Array where Element == LinkRoute {
    /// The first matching rule, so the list order is the priority.
    public func first(matching url: URL) -> LinkRoute? {
        first { $0.matches(url) }
    }
}

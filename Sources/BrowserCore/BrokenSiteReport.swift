import Foundation

/// What Report a Broken Site sends: which site, what went wrong and the setup
/// that explains most breakage. The site's name only, unless the user adds the
/// full address: paths and queries can hold private details.
public struct BrokenSiteReport: Equatable, Sendable {
    public enum Problem: String, CaseIterable, Sendable {
        case wontLoad = "Page won't load"
        case looksWrong = "Page looks wrong"
        case controls = "Buttons or forms don't work"
        case media = "Video or sound won't play"
        case signIn = "Can't sign in"
        case blockerWall = "Says to turn off ad blocker"
        case unsupported = "Says browser isn't supported"
        case other = "Something else"
    }

    /// Whether turning blocking off fixed it: tells a filter rule gone wrong
    /// from a site that doesn't work on WebKit.
    public enum BlockingTest: String, CaseIterable, Sendable {
        case notTried = "Not tried"
        case fixed = "Yes"
        case notFixed = "No"
    }

    public var url: URL
    public var problem: Problem?
    public var note: String
    public var blockingTest: BlockingTest
    public var includesAddress: Bool
    /// Versions and settings, one per line.
    public var details: [String]

    public init(
        url: URL,
        problem: Problem? = nil,
        note: String = "",
        blockingTest: BlockingTest = .notTried,
        includesAddress: Bool = false,
        details: [String] = []
    ) {
        self.url = url
        self.problem = problem
        self.note = note
        self.blockingTest = blockingTest
        self.includesAddress = includesAddress
        self.details = details
    }

    /// The host of a website; nil for anything else (nothing to report on).
    public static func site(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(percentEncoded: false), !host.isEmpty
        else { return nil }
        return host.lowercased()
    }

    public var site: String {
        Self.site(of: url) ?? "?"
    }

    public var subject: String {
        "Kaizu broken site: \(site)"
    }

    public var text: String {
        var lines = ["Site: \(site)"]
        if includesAddress {
            lines.append("Address: \(address)")
        }
        lines += [
            "Problem: \(problem?.rawValue ?? "?")",
            "Fixed by turning blocking off: \(blockingTest.rawValue)",
        ]
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            lines += ["", note]
        }
        lines += ["", "---"] + details
        return lines.joined(separator: "\n") + "\n"
    }

    /// The full address, minus tracking parameters and any login in it.
    private var address: String {
        let url = TrackingParameters.stripped(url) ?? url
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return site }
        components.user = nil
        components.password = nil
        return components.string ?? site
    }
}

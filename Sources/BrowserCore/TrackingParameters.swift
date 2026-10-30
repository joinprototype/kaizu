import Foundation

/// Removes click-tracking query parameters (utm_*, fbclid, gclid…) from URLs.
/// Conservative on purpose: only parameters that exist purely for tracking.
public enum TrackingParameters {
    static let names: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid",
        "ttclid", "twclid", "igshid", "li_fat_id", "mc_cid", "mc_eid", "mkt_tok",
        "oly_anon_id", "oly_enc_id", "rb_clickid", "vero_id", "wickedid", "_openstat",
        "srsltid", "_gl", "ref_src", "__hsfp", "__hssc", "__hstc", "_hsenc", "_hsmi",
    ]
    static let prefixes = ["utm_", "hsa_"]
    /// Parameters that only mean "tracking" on specific sites (e.g. share links).
    static let perSite: [String: Set<String>] = [
        "youtube.com": ["si"],
        "youtu.be": ["si"],
        "open.spotify.com": ["si"],
        "instagram.com": ["igsh"],
        "x.com": ["s", "t"],
        "twitter.com": ["s", "t"],
    ]

    /// The URL without tracking parameters, or nil when there was nothing to remove.
    public static func stripped(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.percentEncodedQueryItems, !items.isEmpty
        else { return nil }

        let host = components.host?.lowercased() ?? ""
        let siteSpecific = perSite.first { host == $0.key || host.hasSuffix("." + $0.key) }?.value ?? []
        let kept = items.filter { item in
            let name = item.name.lowercased()
            return !names.contains(name) && !siteSpecific.contains(name) && !prefixes.contains { name.hasPrefix($0) }
        }
        guard kept.count != items.count else { return nil }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.url
    }
}

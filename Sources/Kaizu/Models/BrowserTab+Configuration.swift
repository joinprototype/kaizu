import WebKit

extension BrowserTab {
    static func makeConfiguration(for profile: Profile) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = profile.dataStore
        configuration.applicationNameForUserAgent = UserAgent.safariSuffix
        configuration.preferences.isElementFullscreenEnabled = true
        // HTTPS-first: upgrade every navigation, fall back to HTTP only if it fails.
        configuration.upgradeKnownHostsToHTTPS = true
        configuration.defaultWebpagePreferences.preferredHTTPSNavigationPolicy = .automaticFallbackToHTTP
        if #available(macOS 27.0, *) {
            // "Do not sell or share my data" signal (Sec-GPC header + navigator.globalPrivacyControl).
            configuration.defaultWebpagePreferences.globalPrivacyControlEnabled = true
        }
        return configuration
    }
}

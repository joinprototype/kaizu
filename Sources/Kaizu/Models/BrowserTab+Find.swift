import WebKit

extension BrowserTab {
    /// Selects the next (or previous) match, wrapping around. Returns whether there was one.
    func find(_ query: String, backwards: Bool) async -> Bool {
        guard let _webView else { return false }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        return (try? await _webView.find(query, configuration: configuration))?.matchFound ?? false
    }
}

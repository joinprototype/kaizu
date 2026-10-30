import SwiftUI

/// Find-in-page state. Nil `find` means the find bar is hidden.
struct FindState: Equatable {
    var query = ""
    /// Nil until the first search finishes.
    var matchFound: Bool?
}

extension BrowserStore {
    func showFindBar() {
        guard selectedTab != nil else { return }
        withAnimation(Motion.snap) {
            find = find ?? FindState()
        }
    }

    func hideFindBar() {
        withAnimation(Motion.snap) {
            find = nil
        }
        focusWebView()
    }

    func updateFind(_ query: String) {
        find?.query = query
        findNext()
    }

    func findNext(backwards: Bool = false) {
        guard let tab = selectedTab, let query = find?.query, !query.isEmpty else {
            withAnimation(Motion.snap) { find?.matchFound = nil }
            return
        }
        Task {
            let found = await tab.find(query, backwards: backwards)
            withAnimation(Motion.snap) { find?.matchFound = found }
        }
    }
}

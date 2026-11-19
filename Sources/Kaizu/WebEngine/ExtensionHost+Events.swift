import WebKit

extension ExtensionHost {
    // MARK: - Tab events

    // Private tabs are never mentioned to extensions (their URLs and titles
    // would leak through tabs.onUpdated and friends).

    func didOpen(_ tab: BrowserTab) {
        guard !tab.profile.isPrivate else { return }
        controller.didOpenTab(tab)
    }

    func didClose(_ tab: BrowserTab) {
        guard !tab.profile.isPrivate else { return }
        controller.didCloseTab(tab)
    }

    func didActivate(_ tab: BrowserTab, previous: BrowserTab?) {
        guard !tab.profile.isPrivate, tab !== previous else { return }
        controller.didActivateTab(tab, previousActiveTab: previous)
    }

    func didChange(_ properties: WKWebExtension.TabChangedProperties, for tab: BrowserTab) {
        guard !tab.profile.isPrivate else { return }
        controller.didChangeTabProperties(properties, for: tab)
    }

    // MARK: - Window events

    func didOpen(_ store: BrowserStore) {
        guard !store.isPrivate else { return }
        controller.didOpenWindow(store.extensionWindow)
    }

    func didClose(_ store: BrowserStore) {
        guard !store.isPrivate else { return }
        controller.didCloseWindow(store.extensionWindow)
    }

    func didFocus(_ store: BrowserStore) {
        guard !store.isPrivate else { return }
        controller.didFocusWindow(store.extensionWindow)
    }
}

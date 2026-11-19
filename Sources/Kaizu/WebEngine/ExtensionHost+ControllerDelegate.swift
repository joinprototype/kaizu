import AppKit
import WebKit

// MARK: - WKWebExtensionControllerDelegate

extension ExtensionHost: WKWebExtensionControllerDelegate {
    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        // Front window first, as the API asks.
        guard let app else { return [] }
        return ([app.regularFront] + app.stores.filter { $0 !== app.regularFront }).map(\.extensionWindow)
    }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        app?.regularFront.extensionWindow
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        let store = (configuration.window as? MainWindowAdapter)?.store ?? app?.regularFront
        completionHandler(store?.openTab(configuration.url, select: configuration.shouldBeActive), nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        let previous = app?.regularFront
        let store = app?.openWindow()
        for url in configuration.tabURLs.reversed() {
            store?.openTab(url)
        }
        if !configuration.shouldBeFocused {
            previous?.window?.makeKeyAndOrderFront(nil)
        }
        completionHandler(store?.extensionWindow, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        if let url = extensionContext.optionsPageURL {
            app?.regularFront.openTab(url)
        }
        completionHandler(nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        completionHandler(confirm("wants extra permissions: " + permissions.map(\.rawValue).sorted().joined(separator: ", "), for: extensionContext) ? permissions : [], nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        let hosts = urls.compactMap { $0.host() }.sorted().joined(separator: ", ")
        completionHandler(confirm("wants to access: \(hosts)", for: extensionContext) ? urls : [], nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        let patterns = matchPatterns.map(\.string).sorted().joined(separator: ", ")
        completionHandler(confirm("wants to access: \(patterns)", for: extensionContext) ? matchPatterns : [], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action, forExtensionContext context: WKWebExtensionContext) {
        actionRevision += 1
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for context: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let popover = action.popupPopover, let view = app?.regularFront.window?.contentView else {
            return completionHandler(CocoaError(.featureUnsupported))
        }
        popover.show(relativeTo: popupAnchor, of: view, preferredEdge: .maxY)
        completionHandler(nil)
    }

    private func confirm(_ request: String, for context: WKWebExtensionContext) -> Bool {
        let alert = NSAlert()
        alert.messageText = "“\(context.webExtension.displayName ?? "An extension")” \(request)"
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

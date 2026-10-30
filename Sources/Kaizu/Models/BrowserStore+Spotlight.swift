import AppKit
import CoreSpotlight
import UniformTypeIdentifiers

/// Pinned tabs and favorites in the system Spotlight: ⌘Space, "Gmail",
/// Return opens the pinned Gmail tab, where it already is. Only what you
/// chose to keep (never Today tabs or history), never private windows.
extension BrowserStore {
    private static let spotlightDomain = "com.joinprototype.kaizu.pinned"

    /// Re-indexes when the pinned set changed; called after every save.
    /// Titles are the site's name, never the live page title (a pinned mail
    /// tab's title can be a message subject).
    func updateSpotlight() {
        var seen = Set<UUID>()
        var entries: [(tab: BrowserTab, space: Space, title: String, url: URL?)] = []
        for space in spaces where !space.profile.isPrivate {
            for tab in space.profile.favorites + space.pinned.tabs where seen.insert(tab.id).inserted {
                let url = tab.pinnedURL ?? tab.url
                entries.append((tab, space, Self.siteName(of: tab, url: url), url))
            }
        }
        let signature = entries.map { "\($0.tab.id)\($0.title)\($0.url?.absoluteString ?? "")\($0.space.name)" }
        guard signature != spotlightSignature else { return }
        // Runs even with nothing pinned, to clear what earlier launches left.
        let isFirstUpdate = spotlightSignature == nil
        spotlightSignature = signature
        let items = entries.map { entry in
            let attributes = CSSearchableItemAttributeSet(contentType: .url)
            attributes.title = entry.title
            attributes.contentDescription = [entry.url?.displayHost, entry.space.name].compactMap(\.self).joined(separator: " · ")
            attributes.url = entry.url
            attributes.thumbnailData = entry.tab.favicon?.tiffRepresentation
            let item = CSSearchableItem(uniqueIdentifier: entry.tab.id.uuidString, domainIdentifier: Self.spotlightDomain, attributeSet: attributes)
            item.expirationDate = .distantFuture
            return item
        }
        let identifiers = Set(entries.map(\.tab.id.uuidString))
        let removed = spotlightIdentifiers.subtracting(identifiers)
        spotlightIdentifiers = identifiers
        // One update after another, in order.
        let previous = spotlightUpdate
        spotlightUpdate = Task {
            await previous?.value
            let index = CSSearchableIndex.default()
            if isFirstUpdate {
                // Whatever earlier launches left (unpinned just before
                // quitting, say) goes first.
                try? await index.deleteSearchableItems(withDomainIdentifiers: [Self.spotlightDomain])
            } else if !removed.isEmpty {
                // Indexing an identifier again replaces it; only unpinned ones need deleting.
                try? await index.deleteSearchableItems(withIdentifiers: Array(removed))
            }
            try? await index.indexSearchableItems(items)
        }
    }

    /// "Gmail" from "Inbox (3) – someone@example.com – Gmail": the last
    /// part of the title, which is the site's name by convention; else the host.
    private static func siteName(of tab: BrowserTab, url: URL?) -> String {
        let host = url?.displayHost ?? "Pinned tab"
        let separators = [" - ", " – ", " — ", " | ", " · "]
        guard let separator = separators.filter({ tab.title.contains($0) }).max(by: {
            tab.title.range(of: $0, options: .backwards)!.lowerBound < tab.title.range(of: $1, options: .backwards)!.lowerBound
        }) else { return host }
        let name = tab.title.components(separatedBy: separator).last?.trimmingCharacters(in: .whitespaces) ?? ""
        return (1...30).contains(name.count) ? name : host
    }

    /// A Spotlight result was opened: show that tab in its space.
    func openSpotlightItem(_ identifier: String) {
        guard let id = UUID(uuidString: identifier) else { return }
        let owner = spaces.first { $0.pinned.tabs.contains { $0.id == id } }
            ?? ([activeSpace] + spaces).first { $0.profile.favorites.contains { $0.id == id } }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // Gone since it was indexed: Kaizu still comes forward.
        guard let space = owner, let tab = space.allTabs.first(where: { $0.id == id }) else { return }
        switchTo(space)
        select(tab, in: space)
    }
}

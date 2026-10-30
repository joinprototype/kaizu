import AppKit
import BrowserCore
import OSLog
import WebKit

/// Web extensions (the cross-browser WebExtension format) on WebKit's
/// `WKWebExtensionController`. Installs from an unpacked folder, a `.zip`,
/// a Mac app that bundles a Safari web extension, or a Chrome Web Store /
/// Firefox Add-ons page; the list persists.
@MainActor @Observable
final class ExtensionHost: NSObject {
    @MainActor
    struct Installed: Identifiable {
        let id: UUID
        let context: WKWebExtensionContext
        var name: String { context.webExtension.displayName ?? "Extension" }
        var version: String { context.webExtension.displayVersion ?? "" }
        var icon: NSImage? { context.webExtension.icon(for: CGSize(width: 32, height: 32)) }
    }

    /// Where an installed extension's files live (persisted).
    private struct Record: Codable {
        enum Kind: String, Codable { case folder, safariApp }
        var id: UUID
        var kind: Kind
        var path: String
        /// The store listing it came from (`ExtensionGallery.Listing.source`).
        var source: String?

        /// Where it is now. Copied extensions are found by their folder's
        /// name, so moving the data folder (a rename of the app) keeps them.
        var location: URL {
            switch kind {
            case .folder: ExtensionHost.directory.appending(path: URL(fileURLWithPath: path).lastPathComponent, directoryHint: .isDirectory)
            case .safariApp: URL(fileURLWithPath: path)
            }
        }
    }

    @ObservationIgnored let controller = WKWebExtensionController(configuration: .default())
    @ObservationIgnored let mainWindow = MainWindowAdapter()
    @ObservationIgnored weak var store: BrowserStore? {
        didSet { mainWindow.store = store }
    }
    /// Where the next action popup should anchor (the clicked toolbar button), in window coordinates.
    @ObservationIgnored var popupAnchor: CGRect = .zero

    private(set) var installed: [Installed] = []
    /// The store listing being downloaded right now.
    private(set) var downloading: ExtensionGallery.Listing?
    /// Bumped when an extension updates its toolbar action (badge, icon), so views refresh.
    private(set) var actionRevision = 0

    @ObservationIgnored private var records: [Record] = []
    @ObservationIgnored private let log = Logger(subsystem: Log.subsystem, category: "Extensions")
    private static let recordsKey = "installedExtensions"
    nonisolated private static let safariExtensionPoint = "com.apple.Safari.web-extension"

    nonisolated static var directory: URL {
        AppPaths.support.appending(path: "Extensions", directoryHint: .isDirectory)
    }

    override init() {
        super.init()
        controller.delegate = self
    }

    // MARK: - Loading

    /// Re-loads extensions installed in earlier sessions.
    func loadInstalled() async {
        let data = UserDefaults.standard.data(forKey: Self.recordsKey)
        let saved = data.flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []
        for record in saved where !records.contains(where: { $0.id == record.id }) {
            guard let webExtension = try? await Self.makeExtension(record) else {
                log.error("Couldn't load extension at \(record.location.path, privacy: .public)")
                continue
            }
            activate(webExtension, record: record)
        }
    }

    func isInstalled(_ listing: ExtensionGallery.Listing) -> Bool {
        // Through `installed`, which views observe; records aren't.
        installed.contains { item in records.contains { $0.id == item.id && $0.source == listing.source } }
    }

    /// Downloads an extension from its store page, then installs it like a
    /// `.zip` (asking first).
    func install(_ listing: ExtensionGallery.Listing, askFirst: Bool = true) async {
        guard downloading == nil else { return }
        downloading = listing
        defer { downloading = nil }
        let archive = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: archive) }
        do {
            let (data, response) = try await Self.downloads.data(from: ExtensionGallery.downloadURL(for: listing))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            try ExtensionGallery.zipArchive(from: data).write(to: archive)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't download the extension"
            alert.informativeText = "The store didn't send an extension Kaizu can install. Try again later, or add it from a .zip in Settings → Extensions."
            alert.runModal()
            return
        }
        await install(from: archive, askFirst: askFirst, source: listing.source)
    }

    /// No cookies: the stores don't need to know who's downloading.
    private static let downloads = URLSession(configuration: .ephemeral)

    /// Asks the user, then installs: a folder or `.zip` is copied into
    /// Application Support; a Safari extension app is used in place.
    func install(from url: URL, askFirst: Bool = true, source: String? = nil) async {
        do {
            let id = UUID()
            let record: Record
            if url.pathExtension == "app" {
                record = Record(id: id, kind: .safariApp, path: url.path)
            } else {
                let directory = Self.directory
                let destination = directory.appending(path: id.uuidString, directoryHint: .isDirectory)
                // Off the main thread: a big extension takes a moment to unpack.
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    if url.pathExtension == "zip" {
                        try Self.unzip(url, to: destination)
                    } else {
                        try FileManager.default.copyItem(at: url, to: destination)
                    }
                }.value
                record = Record(id: id, kind: .folder, path: destination.path, source: source)
            }
            let webExtension = try await Self.makeExtension(record)
            guard !askFirst || confirmInstall(of: webExtension) else {
                if record.kind == .folder { try? FileManager.default.removeItem(at: record.location) }
                return
            }
            activate(webExtension, record: record)
            persist()
            store?.showToast("Added \(webExtension.displayName ?? "extension")", symbol: "puzzlepiece.extension")
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't add the extension"
            alert.runModal()
        }
    }

    func uninstall(_ item: Installed) {
        try? controller.unload(item.context)
        installed.removeAll { $0.id == item.id }
        if let record = records.first(where: { $0.id == item.id }), record.kind == .folder {
            try? FileManager.default.removeItem(at: record.location)
        }
        records.removeAll { $0.id == item.id }
        persist()
    }

    /// Safari web extensions bundled in apps under /Applications.
    nonisolated static func safariExtensionApps() -> [URL] {
        let apps = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil)) ?? []
        return apps.filter { $0.pathExtension == "app" && safariExtensionBundle(in: $0) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Actions

    func action(for item: Installed) -> WKWebExtension.Action? {
        _ = actionRevision  // observe action updates
        return item.context.action(for: store?.selectedTab)
    }

    func performAction(for item: Installed, anchor: CGRect) {
        popupAnchor = anchor
        item.context.performAction(for: store?.selectedTab)
    }

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
        guard !tab.profile.isPrivate else { return }
        controller.didActivateTab(tab, previousActiveTab: previous)
    }

    func didChange(_ properties: WKWebExtension.TabChangedProperties, for tab: BrowserTab) {
        guard !tab.profile.isPrivate else { return }
        controller.didChangeTabProperties(properties, for: tab)
    }

    // MARK: - Private

    private func activate(_ webExtension: WKWebExtension, record: Record) {
        let context = WKWebExtensionContext(for: webExtension)
        // A stable identifier keeps the extension's storage across launches.
        context.uniqueIdentifier = record.id.uuidString
        // Installing is the user's consent to what the extension asked for.
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        for pattern in webExtension.allRequestedMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        do {
            try controller.load(context)
            installed.append(Installed(id: record.id, context: context))
            if !records.contains(where: { $0.id == record.id }) {
                records.append(record)
            }
        } catch {
            log.error("Couldn't start \(webExtension.displayName ?? "?", privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func confirmInstall(of webExtension: WKWebExtension) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Add “\(webExtension.displayName ?? "this extension")”?"
        alert.informativeText = Self.describeAccess(of: webExtension)
        alert.icon = webExtension.icon(for: CGSize(width: 64, height: 64))
        alert.addButton(withTitle: "Add Extension")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Plain-language summary of what an extension asked for.
    static func describeAccess(of webExtension: WKWebExtension) -> String {
        let requested = webExtension.allRequestedMatchPatterns
        let patterns = requested.map(\.string)
        let sites: String
        if requested.contains(where: { $0.matchesAllURLs || $0.matchesAllHosts }) {
            sites = "It can read and change content on all websites."
        } else if patterns.isEmpty {
            sites = "It doesn't ask to access websites."
        } else {
            sites = "It can read and change content on: " + patterns.sorted().prefix(5).joined(separator: ", ")
        }
        let permissions = webExtension.requestedPermissions.map(\.rawValue).sorted()
        return permissions.isEmpty ? sites : sites + "\n\nPermissions: " + permissions.joined(separator: ", ")
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(records), forKey: Self.recordsKey)
    }

    private static func makeExtension(_ record: Record) async throws -> WKWebExtension {
        let url = record.location
        switch record.kind {
        case .folder:
            return try await WKWebExtension(resourceBaseURL: url)
        case .safariApp:
            guard let bundle = safariExtensionBundle(in: url) else { throw CocoaError(.fileNoSuchFile) }
            return try await WKWebExtension(appExtensionBundle: bundle)
        }
    }

    nonisolated private static func safariExtensionBundle(in app: URL) -> Bundle? {
        let plugins = app.appending(path: "Contents/PlugIns")
        let appexes = (try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)) ?? []
        return appexes.lazy.compactMap(Bundle.init(url:)).first { bundle in
            let point = (bundle.infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
            return point == safariExtensionPoint
        }
    }

    nonisolated private static func unzip(_ archive: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
        // Zips often wrap everything in one folder; use it if the manifest is inside.
        let contents = (try? FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)) ?? []
        if !FileManager.default.fileExists(atPath: destination.appending(path: "manifest.json").path),
           contents.count == 1, let inner = contents.first,
           FileManager.default.fileExists(atPath: inner.appending(path: "manifest.json").path) {
            let staging = destination.deletingLastPathComponent().appending(path: UUID().uuidString)
            try FileManager.default.moveItem(at: inner, to: staging)
            try FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: staging, to: destination)
        }
    }
}

// MARK: - WKWebExtensionControllerDelegate

extension ExtensionHost: WKWebExtensionControllerDelegate {
    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        [mainWindow]
    }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        mainWindow
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        let tab = store?.openTab(configuration.url, select: configuration.shouldBeActive)
        completionHandler(tab, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        // One window for now: open the requested pages as tabs in it.
        for url in configuration.tabURLs {
            store?.openTab(url, select: configuration.shouldBeFocused)
        }
        completionHandler(mainWindow, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        if let url = extensionContext.optionsPageURL {
            store?.openTab(url)
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
        guard let popover = action.popupPopover, let view = store?.window?.contentView else {
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

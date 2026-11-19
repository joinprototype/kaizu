import AppKit
import BrowserCore
import OSLog
import WebKit

/// Web extensions (the cross-browser WebExtension format) on WebKit's
/// `WKWebExtensionController`. Installs from an unpacked folder, a `.zip`,
/// a Mac app that bundles a Safari web extension, or a Chrome Web Store /
/// Firefox Add-ons page; the list persists.
@Observable
final class ExtensionHost: NSObject {
    struct Installed: Identifiable {
        let id: UUID
        let context: WKWebExtensionContext
        var name: String { context.webExtension.displayName ?? "Extension" }
        var version: String { context.webExtension.displayVersion ?? "" }
        var icon: NSImage? { context.webExtension.icon(for: CGSize(width: 32, height: 32)) }
    }

    struct Unavailable: Identifiable {
        let id: UUID
        let name: String
        let detail: String
    }

    /// Where an installed extension's files live (persisted).
    private struct Record: Codable {
        enum Kind: String, Codable { case folder, safariApp }
        var id: UUID
        var kind: Kind
        var path: String
        /// The store listing it came from (`ExtensionGallery.Listing.source`).
        var source: String?
        var displayName: String?
        /// Additional sites the user approved from the extension's toolbar menu.
        var additionalSites: [String]?

        /// Where it is now. Copied extensions are found by their folder's
        /// name, so moving the data folder (a rename of the app) keeps them.
        func location(in directory: URL) -> URL {
            switch kind {
            case .folder: directory.appending(path: URL(fileURLWithPath: path).lastPathComponent, directoryHint: .isDirectory)
            case .safariApp: URL(fileURLWithPath: path)
            }
        }
    }

    @ObservationIgnored let controller: WKWebExtensionController
    @ObservationIgnored weak var app: AppModel?
    /// Where the next action popup should anchor (the clicked toolbar button), in window coordinates.
    @ObservationIgnored var popupAnchor: CGRect = .zero

    private(set) var installed: [Installed] = []
    /// The store listing being downloaded right now.
    private(set) var downloading: ExtensionGallery.Listing?
    /// Bumped when an extension updates its toolbar action (badge, icon), so views refresh.
    var actionRevision = 0

    private var pendingSafariPaths: Set<String> = []
    private var records: [Record]
    private var failures: [UUID: String] = [:]
    private(set) var loading: Set<UUID> = []
    private let defaults: UserDefaults
    private let directory: URL

    var unavailable: [Unavailable] {
        records.compactMap { record in
            guard let detail = failures[record.id] else { return nil }
            let url = record.location(in: directory)
            let fallback = record.kind == .safariApp ? url.deletingPathExtension().lastPathComponent : "Extension"
            return Unavailable(id: record.id, name: record.displayName ?? fallback, detail: detail)
        }
    }

    var hasRegistrations: Bool { !records.isEmpty }

    @ObservationIgnored private let log = Logger(subsystem: Log.subsystem, category: "Extensions")
    private static let recordsKey = "installedExtensions"

    init(defaults: UserDefaults = AppDefaults.shared,
         directory: URL = AppPaths.support.appending(path: "Extensions", directoryHint: .isDirectory),
         configuration: WKWebExtensionController.Configuration = .default()) {
        self.defaults = defaults
        self.directory = directory
        let data = defaults.data(forKey: Self.recordsKey)
        records = data.flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []
        let webViewConfiguration = configuration.webViewConfiguration ?? WKWebViewConfiguration()
        webViewConfiguration.applicationNameForUserAgent = UserAgent.safariSuffix
        configuration.webViewConfiguration = webViewConfiguration
        controller = WKWebExtensionController(configuration: configuration)
        super.init()
        controller.delegate = self
    }

    // MARK: - Loading

    /// Re-loads extensions installed in earlier sessions.
    func loadInstalled() async {
        for id in records.map(\.id) {
            await load(id)
        }
    }

    func load(_ id: UUID) async {
        guard let record = records.first(where: { $0.id == id }),
              !installed.contains(where: { $0.id == id }),
              loading.insert(id).inserted else { return }
        defer { loading.remove(id) }
        let url = record.location(in: directory)
        do {
            let webExtension = try await Self.makeExtension(at: url, kind: record.kind)
            guard records.contains(where: { $0.id == id }) else { return }
            try activate(webExtension, record: record)
            failures[id] = nil
        } catch {
            guard records.contains(where: { $0.id == id }) else { return }
            failures[id] = error.localizedDescription
            log.error("Couldn't load extension at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func isInstalled(_ listing: ExtensionGallery.Listing) -> Bool {
        records.contains { $0.source == listing.source }
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
        let safariPath = url.pathExtension == "app" ? Self.safariPath(url) : nil
        if let safariPath {
            if let existing = registeredSafariApp(at: safariPath) {
                await load(existing.id)
                return
            }
            guard pendingSafariPaths.insert(safariPath).inserted else { return }
        }
        defer {
            if let safariPath { pendingSafariPaths.remove(safariPath) }
        }
        var stagedFolder: URL?
        defer {
            if let stagedFolder { try? FileManager.default.removeItem(at: stagedFolder) }
        }
        do {
            let id = UUID()
            var record: Record
            if safariPath != nil {
                record = Record(id: id, kind: .safariApp, path: url.path)
            } else {
                let directory = self.directory
                let destination = directory.appending(path: id.uuidString, directoryHint: .isDirectory)
                stagedFolder = destination
                try await Self.stage(url, in: directory, at: destination)
                record = Record(id: id, kind: .folder, path: destination.path, source: source)
            }
            let webExtension = try await Self.makeExtension(at: record.location(in: directory), kind: record.kind)
            guard !askFirst || confirmInstall(of: webExtension) else { return }
            try activate(webExtension, record: record)
            record.displayName = webExtension.displayName
            records.append(record)
            stagedFolder = nil
            persist()
            app?.regularFront.showToast("Added \(webExtension.displayName ?? "extension")", symbol: "puzzlepiece.extension")
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't add the extension"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func uninstall(_ id: UUID) {
        if let item = installed.first(where: { $0.id == id }) {
            try? controller.unload(item.context)
            installed.removeAll { $0.id == id }
        }
        if let record = records.first(where: { $0.id == id }), record.kind == .folder {
            try? FileManager.default.removeItem(at: record.location(in: directory))
        }
        failures[id] = nil
        records.removeAll { $0.id == id }
        persist()
    }

    private static func safariPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func registeredSafariApp(at path: String) -> Record? {
        records.first { $0.kind == .safariApp && Self.safariPath(URL(fileURLWithPath: $0.path)) == path }
    }

    func hasSafariApp(_ url: URL) -> Bool { registeredSafariApp(at: Self.safariPath(url)) != nil }

    func isAddingSafariApp(_ url: URL) -> Bool { pendingSafariPaths.contains(Self.safariPath(url)) }

    // MARK: - Actions

    func additionalSites(for item: Installed) -> [String] {
        records.first { $0.id == item.id }?.additionalSites ?? []
    }

    func availableSite(for item: Installed, on tab: BrowserTab?) -> WKWebExtension.MatchPattern? {
        guard let tab, !tab.profile.isPrivate, let url = tab.url,
              let scheme = url.scheme, ["https", "http"].contains(scheme),
              let host = url.host(), !host.isEmpty, !host.contains("*"),
              item.context.hasPermission(.tabs), !item.context.hasAccess(to: url) else { return nil }
        return try? WKWebExtension.MatchPattern(scheme: scheme, host: host, path: "/*")
    }

    func requestSite(for item: Installed, on tab: BrowserTab?) {
        guard let tab, let pattern = availableSite(for: item, on: tab) else { return }
        let alert = NSAlert()
        alert.messageText = "Allow “\(item.name)” on \(pattern.host ?? pattern.string)?"
        alert.informativeText = "This extension can read and change pages matching \(pattern.string) across regular profiles. You can remove this access in Settings → Extensions."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn,
              availableSite(for: item, on: tab)?.string == pattern.string,
              let index = records.firstIndex(where: { $0.id == item.id }) else { return }
        item.context.setPermissionStatus(.grantedExplicitly, for: pattern)
        records[index].additionalSites = Array(Set((records[index].additionalSites ?? []) + [pattern.string])).sorted()
        persist()
        didChange(.URL, for: tab)
    }

    func removeSite(_ site: String, for item: Installed) {
        guard let index = records.firstIndex(where: { $0.id == item.id }),
              records[index].additionalSites?.contains(site) == true,
              let pattern = try? WKWebExtension.MatchPattern(string: site) else { return }
        records[index].additionalSites?.removeAll { $0 == site }
        if !item.context.webExtension.allRequestedMatchPatterns.contains(pattern) {
            item.context.setPermissionStatus(.unknown, for: pattern)
        }
        persist()
    }

    func action(for item: Installed, on tab: BrowserTab?) -> WKWebExtension.Action? {
        _ = actionRevision  // observe action updates
        return item.context.action(for: tab)
    }

    func performAction(for item: Installed, on tab: BrowserTab?, anchor: CGRect) {
        popupAnchor = anchor
        item.context.performAction(for: tab)
    }

    // MARK: - Private

    private func activate(_ webExtension: WKWebExtension, record: Record) throws {
        let context = WKWebExtensionContext(for: webExtension)
        // WebKit generates the resource origin independently of the runtime ID.
        context.uniqueIdentifier = record.id.uuidString
        context.baseURL = URL(string: "webkit-extension://\(record.id.uuidString.lowercased())/")!
        // Installing is the user's consent to what the extension asked for.
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        for pattern in webExtension.allRequestedMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        for site in record.additionalSites ?? [] {
            if let pattern = try? WKWebExtension.MatchPattern(string: site) {
                context.setPermissionStatus(.grantedExplicitly, for: pattern)
            }
        }
        try controller.load(context)
        installed.append(Installed(id: record.id, context: context))
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
        defaults.set(try? JSONEncoder().encode(records), forKey: Self.recordsKey)
    }

    private static func makeExtension(at url: URL, kind: Record.Kind) async throws -> WKWebExtension {
        switch kind {
        case .folder:
            return try await WKWebExtension(resourceBaseURL: url)
        case .safariApp:
            guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
            guard let bundle = safariExtensionBundle(in: url) else {
                throw SafariInstallError.noWebExtension(url.lastPathComponent)
            }
            return try await WKWebExtension(appExtensionBundle: bundle)
        }
    }

    private enum SafariInstallError: LocalizedError {
        case noWebExtension(String)

        var errorDescription: String? {
            switch self {
            case .noWebExtension(let app):
                "\(app) contains no Safari web extension. Choose a Mac app with a web extension, or add a WebExtension ZIP. For ad and tracker blocking, Kaizu also has a built-in blocker."
            }
        }
    }
}

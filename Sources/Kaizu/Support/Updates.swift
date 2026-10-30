import AppKit
import BrowserCore
import OSLog

/// Keeps Kaizu current. It reads one small public file and sends nothing about
/// the person or the Mac. A newer build downloads quietly, is checked, and goes
/// in on restart or quit; when Kaizu can't replace itself, or anything about the
/// download is wrong, people get the Download notice instead.
@MainActor
enum Updates {
    private static let feed = URL(string: "https://kaizu.joinprototype.com/version.json")!
    /// The public half of ~/.config/kaizu/update-signing.key.
    private static let publicKey = "tW8o1qF3ETJjP1wAnTWIEFj+1eG46UNUNUGEDCKw4U8="
    private static let firstCheck: Duration = .seconds(10)
    private static let between: Duration = .seconds(6 * 60 * 60)
    private static let log = Logger(subsystem: "com.joinprototype.kaizu", category: "updates")
    private static var announced: Int?
    /// The update checked and waiting to go in on quit.
    private static var staged: StagedUpdate?
    private static var preparing: (build: Int, task: Task<StagedUpdate, Error>)?
    private static var relaunchAfterQuit = false

    private static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private static var feedOverride: URL? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["KAIZU_UPDATE_FEED"].flatMap(URL.init(string:))
        #else
        return nil
        #endif
    }

    /// Caches, so macOS may clear it; a staged update is fetched again if it does.
    private static var stagingRoot: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appending(path: "\(Bundle.main.bundleIdentifier ?? "Kaizu")/Updates", directoryHint: .isDirectory)
    }

    /// Checks shortly after launch, then a few times a day for Macs left running.
    static func start(store: BrowserStore) {
        // Anything here is left from an earlier run: an update that went in, or never did.
        try? FileManager.default.removeItem(at: stagingRoot)
        Task {
            try? await Task.sleep(for: firstCheck)
            while !Task.isCancelled {
                if let release = try? await latest(), release.build > currentBuild, staged?.build != release.build {
                    await offer(release, store: store)
                }
                try? await Task.sleep(for: between)
            }
        }
    }

    private static func offer(_ release: UpdateRelease, store: BrowserStore) async {
        do {
            let ready = try await prepare(release)
            guard announced != ready.build else { return }
            announced = ready.build
            store.showToast(
                "Kaizu \(ready.version) is ready",
                symbol: "arrow.down.circle",
                undo: { restart() },
                actionTitle: "Restart",
                lasts: .seconds(30)
            )
            #if DEBUG
            // QA: what the Restart button does, for a run nobody is watching.
            if ProcessInfo.processInfo.environment["KAIZU_DEBUG"] == "update-restart" { restart() }
            #endif
        } catch {
            log.error("Update \(release.build) not staged: \(String(describing: error), privacy: .public)")
            guard announced != release.build else { return }
            announced = release.build
            store.showToast(
                "Kaizu \(release.version) is available",
                symbol: "arrow.down.circle",
                undo: { store.openTab(release.url) },
                actionTitle: "Download",
                lasts: .seconds(15)
            )
        }
    }

    /// Downloads, verifies and stages a release once, however many callers ask.
    private static func prepare(_ release: UpdateRelease) async throws -> StagedUpdate {
        if let staged, staged.build == release.build { return staged }
        if let preparing, preparing.build == release.build { return try await preparing.task.value }
        guard UpdatePlace.canReplace(app: Bundle.main.bundleURL) else { throw UpdateFailure.cannotReplaceApp }
        guard let archive = release.archive, let signature = release.signature,
              archive.scheme == "https" || feedOverride != nil,
              let bundleID = Bundle.main.bundleIdentifier
        else { throw UpdateFailure.notOffered }

        let folder = stagingRoot.appending(path: String(release.build), directoryHint: .isDirectory)
        let stage = UpdateStage(folder: folder, bundleID: bundleID, publicKey: publicKey)
        let build = release.build
        let task = Task.detached(priority: .utility) {
            try await download(archive, into: folder, then: stage, build: build, signature: signature)
        }
        preparing = (build, task)
        defer { preparing = nil }
        let ready = try await task.value
        staged = ready
        log.notice("Update \(ready.build) staged")
        return ready
    }

    private nonisolated static func download(
        _ archive: URL, into folder: URL, then stage: UpdateStage, build: Int, signature: String
    ) async throws -> StagedUpdate {
        let manager = FileManager.default
        try? manager.removeItem(at: folder)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let (file, response) = try await URLSession(configuration: .ephemeral).download(for: URLRequest(url: archive))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateFailure.badDownload }
            let saved = folder.appending(path: "update.zip")
            try manager.moveItem(at: file, to: saved)
            return try stage.stage(archive: saved, build: build, signature: signature)
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
    }

    private static func restart() {
        relaunchAfterQuit = true
        NSApp.terminate(nil)
    }

    /// The last thing Kaizu does: leaves the swap running behind it.
    static func installIfReady() {
        guard let staged else { return }
        do {
            try UpdateSwap.launch(pid: getpid(), app: Bundle.main.bundleURL, staged: staged.app, relaunch: relaunchAfterQuit)
            log.notice("Installing update \(staged.build) on quit")
        } catch {
            log.error("Couldn't start the update: \(String(describing: error), privacy: .public)")
        }
    }

    /// Kaizu ▸ Check for Updates…: always answers, even when there's nothing new.
    static func checkNow(store: BrowserStore) {
        Task {
            do {
                let release = try await latest()
                guard release.build > currentBuild else {
                    let alert = NSAlert()
                    alert.messageText = "You’re up to date"
                    alert.informativeText = "Kaizu \(currentVersion) is the latest version."
                    alert.runModal()
                    return
                }
                if staged?.build != release.build {
                    store.showToast("Downloading Kaizu \(release.version)…", symbol: "arrow.down.circle")
                }
                await answer(release, store: store)
            } catch {
                log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
                let alert = NSAlert()
                alert.messageText = "Couldn’t check for updates"
                alert.informativeText = "Check your connection and try again."
                alert.runModal()
            }
        }
    }

    /// The menu's answer: Restart once it's staged, Download if it can't be.
    private static func answer(_ release: UpdateRelease, store: BrowserStore) async {
        let alert = NSAlert()
        alert.informativeText = "You have \(currentVersion). Your tabs and logins stay as they are."
        do {
            let ready = try await prepare(release)
            alert.messageText = "Kaizu \(ready.version) is ready"
            alert.addButton(withTitle: "Restart")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { restart() }
        } catch {
            log.error("Update \(release.build) not staged: \(String(describing: error), privacy: .public)")
            alert.messageText = "Kaizu \(release.version) is available"
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { store.openTab(release.url) }
        }
    }

    private static func latest() async throws -> UpdateRelease {
        var request = URLRequest(url: feedOverride ?? feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(UpdateRelease.self, from: data)
    }
}

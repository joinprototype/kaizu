import AppKit
import BrowserCore

@main
enum KaizuApp {
    static func main() {
        #if !DEBUG
        // A QA launch that requested an isolated session must never fall back to the normal profile.
        if ProcessInfo.processInfo.environment["KAIZU_SUPPORT"] != nil {
            FileHandle.standardError.write(Data("KAIZU_SUPPORT requires a debug build. Release launch stopped.\n".utf8))
            exit(EX_CONFIG)
        }
        #endif
        if let list = RuleListCompiler.requestedList {
            RuleListCompiler.runAndExit(list: list)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let session: SessionFiles.Opened?
        do {
            session = try SessionFiles(directory: AppPaths.support).open()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Kaizu couldn’t open your saved session"
            if case SessionError.unsupportedVersion(let version) = error {
                alert.informativeText = "This copy of Kaizu cannot read session version \(version). Open the session with a compatible version of Kaizu."
            } else {
                alert.informativeText = "Your tabs are stored in the Kaizu data folder. Check the session files and available disk space before trying again.\n\n\(error.localizedDescription)"
            }
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Show Data Folder")
            app.activate()
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.open(AppPaths.support)
            }
            return
        }
        let delegate = AppDelegate(session: session)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

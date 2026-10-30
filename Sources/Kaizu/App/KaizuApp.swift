import AppKit

@main
@MainActor
enum KaizuApp {
    // Held statically: NSApplication.delegate is weak.
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}

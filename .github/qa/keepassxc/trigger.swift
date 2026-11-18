import AppKit
import ApplicationServices

guard ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted", AXIsProcessTrusted() else { exit(2) }
let title = "Kaizu disposable login"
let command = CommandLine.arguments[1]
func attr(_ item: AXUIElement, _ key: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(item, key as CFString, &value) == .success else { return nil }
    return value
}
func descriptions(_ item: AXUIElement, depth: Int = 0) -> [String] {
    guard depth < 10 else { return [] }
    let strings = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { attr(item,$0) as? String }
    return strings + (attr(item,kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap { descriptions($0,depth:depth+1) }
}
func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
    for down in [true, false] {
        let ev = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        ev.flags = flags
        ev.post(tap: .cghidEventTap)
    }
}
if command == "trigger" {
    let kaizu = NSRunningApplication.runningApplications(withBundleIdentifier: "com.joinprototype.kaizu").first!
    kaizu.activate()
    Thread.sleep(forTimeInterval: 0.4)
    let app = AXUIElementCreateApplication(kaizu.processIdentifier)
    let windows = attr(app,kAXWindowsAttribute) as? [AXUIElement] ?? []
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == kaizu.processIdentifier,
          windows.contains(where: { attr($0,kAXTitleAttribute) as? String == title }) else {
        print("Kaizu’s fixture window was not focused with the expected title"); exit(3)
    }
    print("The native title matches the disposable vault entry. Triggering KeePassXC.")
    key(40,[.maskShift,.maskAlternate])
} else {
    guard let vendor = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "KeePassXC" }) else { exit(4) }
    let app = AXUIElementCreateApplication(vendor.processIdentifier)
    let windows = attr(app,kAXWindowsAttribute) as? [AXUIElement] ?? []
    let labels = windows.flatMap { descriptions($0) }.joined(separator:" ").lowercased()
    let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
    let windowTitles = windows.compactMap { attr($0, kAXTitleAttribute) as? String }
    let entryVisible = labels.contains(title.lowercased())
    print("Vendor windows:", windowTitles, "fixture entry visible:", entryVisible, "front app:", front)
    if command == "vault" {
        exit(entryVisible ? 0 : 6)
    }
    if labels.contains("permission required") || labels.contains("screen recording") || labels.contains("accessibility permission") {
        print("KeePassXC requested macOS permissions; automated trial stops at that prompt."); exit(5)
    }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier == vendor.processIdentifier,
       labels.contains("auto-type"), labels.contains(title.lowercased()) { key(36) }
}

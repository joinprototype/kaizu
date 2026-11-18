import AppKit
import ApplicationServices

func attribute(_ element: AXUIElement, _ key: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
}

func find(_ element: AXUIElement, role: String, title: String, depth: Int = 0) -> AXUIElement? {
    guard depth < 12 else { return nil }
    if attribute(element, kAXRoleAttribute) as? String == role,
       attribute(element, kAXTitleAttribute) as? String == title { return element }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let match = find(child, role: role, title: title, depth: depth + 1) { return match }
    }
    return nil
}

func press(_ element: AXUIElement?) -> Bool {
    guard let element else { return false }
    return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
}

let path = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath().standardizedFileURL
let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: "com.joinprototype.kaizu")
guard let running = candidates.first(where: { $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == path }) else { exit(2) }
if CommandLine.arguments[2] == "pid" {
    print(running.processIdentifier)
    exit(0)
}
guard AXIsProcessTrusted() else { print("Hosted process lacks Accessibility permission"); exit(3) }
let app = AXUIElementCreateApplication(running.processIdentifier)
guard let raw = attribute(app, kAXMenuBarAttribute) else { print("Missing application menu bar"); exit(4) }
let bar = raw as! AXUIElement
guard press(find(bar, role: kAXMenuBarItemRole, title: "Kaizu")) else { print("Missing Kaizu menu"); exit(5) }
guard press(find(bar, role: kAXMenuItemRole, title: "Check for Updates…")) else { print("Missing Check for Updates menu item"); exit(6) }
for _ in 0..<200 {
    for window in attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
        // Both buttons identify the updater's modal dialog, distinct from the announcement in the main window.
        if find(window, role: kAXButtonRole, title: "Later") != nil,
           press(find(window, role: kAXButtonRole, title: "Restart")) {
            print("Pressed Restart in the Check for Updates dialog.")
            exit(0)
        }
    }
    Thread.sleep(forTimeInterval: 0.1)
}
print("Update dialog failed to expose its Restart and Later buttons.")
exit(7)

import AppKit
import ApplicationServices

guard ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" else { exit(2) }
guard AXIsProcessTrusted() else {
    print("The disposable Mac runner does not grant accessibility to this test process.")
    exit(3)
}
guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first else { exit(4) }
let app = AXUIElementCreateApplication(safari.processIdentifier)
func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}
func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}
func dumpUI(_ el: AXUIElement, depth: Int = 0) {
    guard depth < 12 else { return }
    let role = attribute(el, kAXRoleAttribute) as? String ?? ""
    let title = attribute(el, kAXTitleAttribute) as? String ?? ""
    let description = attribute(el, kAXDescriptionAttribute) as? String ?? ""
    if !title.isEmpty || !description.isEmpty || role == "AXSheet" {
        print(String(repeating:" ",count:depth), role, title, description, attribute(el,kAXValueAttribute) as? NSNumber ?? -1)
    }
    if role != "AXWebArea" { for child in children(el) { dumpUI(child, depth:depth+1) } }
}
func windows() -> [AXUIElement] { attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] }
func elements(_ el: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    if depth > 14 || attribute(el,kAXRoleAttribute) as? String == "AXWebArea" { return [] }
    return [el] + children(el).flatMap { elements($0, depth:depth+1) }
}
func match(_ items: [AXUIElement], role: String, title: String) -> AXUIElement? {
    items.first { attribute($0,kAXRoleAttribute) as? String == role && attribute($0,kAXTitleAttribute) as? String == title }
}
func press(_ el: AXUIElement) {
    let result = AXUIElementPerformAction(el, kAXPressAction as CFString)
    guard result == .success else { print("Safari control press failed",result.rawValue); exit(5) }
    Thread.sleep(forTimeInterval: 0.8)
}
func key(_ code: CGKeyCode, modifiers: CGEventFlags = []) {
    for down in [true,false] {
        let event = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down)!
        event.flags=modifiers; event.postToPid(safari.processIdentifier)
    }
    Thread.sleep(forTimeInterval: 1)
}
func showWindows() { for window in windows() { dumpUI(window) } }
safari.activate()
key(2,modifiers:.maskCommand) // Add Bookmark
guard let add = match(windows().flatMap { elements($0) }, role:"AXButton", title:"Add") else {
    print("Missing bookmark confirmation"); showWindows(); exit(6)
}
press(add)
guard let bar = attribute(app,kAXMenuBarAttribute),
      let export = match(elements(bar as! AXUIElement),role:"AXMenuItem",title:"Export Browsing Data to File…") else { exit(7) }
press(export)
print("Safari export options:")
showWindows()

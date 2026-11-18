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
        print(String(repeating:" ",count:depth), role, title, description)
    }
    if role != "AXWebArea" { for child in children(el) { dumpUI(child, depth:depth+1) } }
}
for window in attribute(app,kAXWindowsAttribute) as? [AXUIElement] ?? [] { dumpUI(window) }
if let bar = attribute(app, kAXMenuBarAttribute) {
    let file = children(bar as! AXUIElement).first { attribute($0,kAXTitleAttribute) as? String == "File" }
    if let file { dumpUI(file) }
}

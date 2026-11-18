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
    if true {
        print(String(repeating:" ",count:depth), role, title, description, attribute(el,kAXValueAttribute) as? String ?? (attribute(el,kAXValueAttribute) as? NSNumber)?.stringValue ?? "")
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
Thread.sleep(forTimeInterval: 3)
let controls = windows().flatMap { elements($0) }
let types = ["Bookmarks","Reading List","History","Extensions","Credit Cards","Passwords"]
var selected = Set<String>()
var visited = Set<String>()
for row in controls where attribute(row,kAXRoleAttribute) as? String == "AXUnknown" {
    let contents = children(row)
    guard let label = contents.compactMap({ attribute($0,kAXValueAttribute) as? String }).first(where: types.contains),
          let flag = contents.first(where: { attribute($0,kAXRoleAttribute) as? String == "AXButton" })
    else { continue }
    visited.insert(label)
    let wanted = label == "Bookmarks" || label == "History"
    let state = (attribute(flag,kAXValueAttribute) as? NSNumber)?.boolValue == true
    let enabled = (attribute(flag,kAXEnabledAttribute) as? NSNumber)?.boolValue == true
    if wanted != state && enabled { press(flag) }
    if (attribute(flag,kAXValueAttribute) as? NSNumber)?.boolValue == true { selected.insert(label) }
}
guard visited == Set(types), selected == Set(["Bookmarks","History"]) else {
    print("Export selection:",selected, "available types:", visited); showWindows(); exit(9)
}
print("Only bookmarks and history selected")
guard let confirm = match(controls,role:"AXButton",title:"Export") else { exit(10) }
press(confirm)
showWindows()
let outputDir = ProcessInfo.processInfo.environment["RUNNER_TEMP"]! + "/fixture-export"
try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
key(5, modifiers:[.maskCommand,.maskShift]) // Go to Folder in the save panel
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(outputDir, forType:.string)
key(9,modifiers:.maskCommand) // Paste the runner's output path
key(36) // Choose the folder
guard let save = match(windows().flatMap { elements($0) },role:"AXButton",title:"Save") else {
    print("Missing Save button"); showWindows(); exit(11)
}
showWindows()
press(save)
for _ in 0..<40 {
    let outputs = try FileManager.default.contentsOfDirectory(atPath:outputDir)
    if outputs.contains(where: { $0.lowercased().hasSuffix(".zip") }) {
        print("Safari saved its export to the selected runner directory."); exit(0)
    }
    Thread.sleep(forTimeInterval:0.5)
}
print("No ZIP in selected folder",try FileManager.default.contentsOfDirectory(atPath:outputDir))
showWindows()
print("Frontmost app:",NSWorkspace.shared.frontmostApplication?.localizedName ?? "")
exit(12)

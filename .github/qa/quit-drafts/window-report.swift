import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else { exit(64) }
let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where window[kCGWindowOwnerPID as String] as? Int32 == pid {
    let layer = window[kCGWindowLayer as String] as? Int
    guard layer == 0 else { continue }
    print("Browser window", window[kCGWindowNumber as String] ?? "unknown",
          "onscreen", window[kCGWindowIsOnscreen as String] ?? false,
          "bounds", window[kCGWindowBounds as String] ?? "unknown")
}

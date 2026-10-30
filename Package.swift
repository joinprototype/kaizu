// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Embed Info.plist into the binary so `swift run` / Xcode runs get a bundle
// identifier (WebKit needs one for per-profile website data stores).
let infoPlist = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/Info.plist")
    .path

let package = Package(
    name: "Kaizu",
    platforms: [.macOS("15.4")],
    targets: [
        .executableTarget(
            name: "Kaizu",
            dependencies: ["BrowserCore"],
            path: "Sources/Kaizu",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlist,
                ]),
            ]
        ),
        // Pure Swift logic with no AppKit/WebKit dependency, so it's unit-testable.
        .target(
            name: "BrowserCore",
            path: "Sources/BrowserCore"
        ),
        .testTarget(
            name: "BrowserCoreTests",
            dependencies: ["BrowserCore"],
            path: "Tests/BrowserCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)

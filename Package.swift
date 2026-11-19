// swift-tools-version: 6.2
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
            dependencies: ["BrowserCore", "DesignSystem"],
            path: "Sources/Kaizu",
            // An AppKit app: everything is main-actor unless it says otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlist,
                ]),
            ]
        ),
        .testTarget(name: "KaizuTests", dependencies: ["Kaizu", "DesignSystem", "TestSupport"]),
        // Colours, type, motion, the chart drawings and the paper sounds.
        // SwiftUI and AppKit only: nothing here knows about tabs or pages.
        .target(
            name: "DesignSystem",
            path: "Sources/DesignSystem",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        // Pure Swift logic with no AppKit/WebKit dependency, so it's unit-testable.
        .target(
            name: "BrowserCore",
            path: "Sources/BrowserCore"
        ),
        .testTarget(
            name: "BrowserCoreTests",
            dependencies: ["BrowserCore", "TestSupport"],
            path: "Tests/BrowserCoreTests",
            resources: [.copy("Fixtures")]
        ),
        // Helpers shared by both test targets.
        .target(
            name: "TestSupport",
            path: "Tests/TestSupport"
        ),
    ]
)

import Foundation
import Testing
@testable import BrowserCore

/// Guards the real bundled lists against WebKit's limits as they get updated.
@Suite struct BundledFilterListTests {
    static let filtersDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../../Resources/Filters")
        .standardizedFileURL

    @Test(arguments: ["easylist", "easyprivacy", "cookies", "kaizu"])
    func convertsWithinWebKitLimits(list: String) throws {
        let text = try String(contentsOf: Self.filtersDirectory.appendingPathComponent("\(list).txt"), encoding: .utf8)
        let start = Date()
        let output = FilterListConverter.convert(text)
        let elapsed = Date().timeIntervalSince(start)

        let scoped = output.rules.filter { $0.trigger.urlFilter == ".*" && ($0.trigger.ifDomain != nil || $0.trigger.unlessDomain != nil) }
        let json = try output.rules.encodedJSON()
        print("""
            \(list): \(output.rules.count) rules (\(output.rules.filter { $0.action.type == .block }.count) block, \
            \(output.rules.filter { $0.action.type == .cssDisplayNone }.count) hide, \
            \(output.rules.filter { $0.action.type == .ignorePreviousRules }.count) exceptions), \
            \(output.skipped) skipped, \(json.utf8.count / 1024) KB JSON, \(String(format: "%.2f", elapsed)) s
            """)

        #expect(output.rules.count <= FilterListConverter.defaultMaxRules)
        #expect(scoped.count < 65_535)
        if list == "kaizu" {
            #expect(output.skipped == 0, "every rule in our own list must convert")
        } else {
            #expect(output.rules.count > 1_000)
        }
    }
}

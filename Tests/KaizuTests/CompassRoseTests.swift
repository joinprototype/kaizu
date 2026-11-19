import AppKit
import SwiftUI
import Testing
@testable import Kaizu

@MainActor
struct CompassRoseTests {
    /// The fleur-de-lis on the north point used to run past the top of the
    /// rose's plate and was cut off. Nothing drawn may reach the plate's edge,
    /// at any bearing the sidebar turns it to.
    @Test(arguments: [0.0, 67.5, 135.0], [ColorScheme.dark, .light])
    func nothingTouchesTheEdge(degrees: Double, scheme: ColorScheme) throws {
        _ = NSApplication.shared
        let size: CGFloat = 200
        let view = CompassRose(size: size)
            .rotationEffect(.degrees(degrees))
            .frame(width: size, height: size)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: image)
        var touching = 0
        func check(_ x: Int, _ y: Int) {
            if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { touching += 1 }
        }
        for x in 0..<rep.pixelsWide { check(x, 0); check(x, rep.pixelsHigh - 1) }
        for y in 0..<rep.pixelsHigh { check(0, y); check(rep.pixelsWide - 1, y) }
        #expect(touching == 0, "\(touching) drawn pixels on the edge at \(degrees)°")
    }
}

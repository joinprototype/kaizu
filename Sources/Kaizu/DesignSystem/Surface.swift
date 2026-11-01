import SwiftUI

/// Neutral, opaque surfaces for chrome that floats over web content.
/// Never use materials over pages: the page's colors bleed through.
enum Surface {
    /// Command bar, toasts, popovers.
    static func elevated(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x252428) : .white
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.1) : .black.opacity(0.08)
    }

    /// Dims the window behind modal chrome.
    static func scrim(_ scheme: ColorScheme) -> Color {
        .black.opacity(scheme == .dark ? 0.4 : 0.18)
    }

    /// Fresh paper: the command bar, toasts, slips.
    static func card(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? 0x22211F : 0xFBF7EC)
    }

    /// Paper's tooth: dark and light flecks, so it shows on any color. A
    /// tile made once, always the same.
    static let grain: NSImage = {
        let size = 192
        var seed: UInt64 = 0x4B41495A55
        func next() -> UInt64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return seed >> 33
        }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let roll = next() % 100
            guard roll < 40 else { continue }
            let alpha = UInt8(next() % 10 + 3)
            // Premultiplied: a light fleck has its alpha in every channel.
            let shade = roll < 22 ? 0 : alpha
            pixels[index] = shade
            pixels[index + 1] = shade
            pixels[index + 2] = shade
            pixels[index + 3] = alpha
        }
        let image = CGContext(
            data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
        return image.map { NSImage(cgImage: $0, size: NSSize(width: size / 2, height: size / 2)) } ?? NSImage()
    }()

    /// Vellum, where Kaizu draws its own pages (Reader's `--paper`).
    static func paper(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? 0x1C1A17 : 0xF4EFE3)
    }
}

/// The chart-maker's inks, from the icon's compass rose.
enum Ink {
    /// Iron gall: what headings are written in.
    static func iron(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? 0xEFE6CF : 0x1C2541)
    }

    static func gilt(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? 0xD2B063 : 0x9A7A2E)
    }

    static func claret(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? 0xD9A08B : 0x8C3A32)
    }

    static func verdigris(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? 0x8FB3A0 : 0x3F6B58)
    }
}

/// Translucent fills for controls that sit on a theme backdrop.
enum SidebarFill {
    static func subtle(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.07) : .white.opacity(0.5)
    }

    static func hover(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.06) : .white.opacity(0.35)
    }

    static func selected(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.13) : .white.opacity(0.9)
    }
}

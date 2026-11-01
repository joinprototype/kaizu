import AppKit
import CoreText
import SwiftUI

/// Kaizu's two voices, the same as its website's. IM Fell, cut in the 1670s,
/// for names and headings: what a chart-maker would have lettered. Everything
/// read small is New York, the system serif, set at the root of each window
/// with `fontDesign(.serif)`.
enum Typeface {
    private static let roman = "IM_FELL_Double_Pica_Roman"
    private static let italic = "IM_FELL_Double_Pica_Italic"

    /// Once, before the first window.
    static func register() {
        for name in ["IMFell-Roman", "IMFell-Italic"] {
            guard let url = BundledResource.url(named: name, extension: "ttf", in: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Land on a chart is lettered upright: names of things.
    static func display(_ size: CGFloat) -> Font {
        .custom(roman, fixedSize: size)
    }

    /// Water is lettered in italics: sections, and what's said in passing.
    static func water(_ size: CGFloat) -> Font {
        .custom(italic, fixedSize: size)
    }

    static func displayField(_ size: CGFloat) -> NSFont {
        NSFont(name: roman, size: size) ?? .systemFont(ofSize: size)
    }

    /// New York, for AppKit fields.
    static func textField(_ size: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: size)
        return system.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? system
    }
}

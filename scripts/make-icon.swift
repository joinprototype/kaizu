// Renders the Kaizu app icon: a compass rose on vellum in the manner of a
// 14th-century sea chart. Rhumb lines follow the chart-makers' colour
// code (black: the 8 winds, green: half-winds, red: quarter-winds); a gilded
// fleur-de-lis marks north.
// Usage: swift scripts/make-icon.swift <output.iconset> [preview.png]
// ICON_VARIANT=plain renders the rose without the fleur-de-lis.
import AppKit
import CoreText
import SwiftUI

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

enum Ink {
    static let navy = color(0x1C2541)
    static let navyLight = color(0x35466E)
    static let goldLight = color(0xE6CB86)
    static let goldDark = color(0xA37A33)
    static let oxblood = color(0x8C2C27)
    static let oxbloodLight = color(0xB9483F)
    static let sepia = color(0x4A3A2A)
    static let verdigris = color(0x4E7D6C)
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: locations)!
}

func makeContext(_ pixels: Int) -> CGContext {
    CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func continuousRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
}

/// Vector outline of a single character, scaled to `height` and centered on `center`.
func glyphPath(_ character: String, font name: String, height: CGFloat, center: CGPoint) -> CGPath? {
    let font = CTFontCreateWithName(name as CFString, 200, nil)
    var characters = Array(character.utf16)
    var glyphs = [CGGlyph](repeating: 0, count: characters.count)
    guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count), glyphs[0] != 0,
          let path = CTFontCreatePathForGlyph(font, glyphs[0], nil)
    else { return nil }
    let box = path.boundingBoxOfPath
    let scale = height / box.height
    var transform = CGAffineTransform(translationX: center.x, y: center.y)
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -box.midX, y: -box.midY)
    return path.copy(using: &transform)
}

/// One compass point: a kite split along its axis into a lit and a shaded half.
func drawPoint(_ ctx: CGContext, center: CGPoint, bearing: CGFloat, length: CGFloat, width: CGFloat, lit: CGColor, shade: CGColor) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: -bearing * .pi / 180)
    for (side, fill) in [(-1.0, lit), (1.0, shade)] as [(CGFloat, CGColor)] {
        ctx.move(to: .zero)
        ctx.addLine(to: CGPoint(x: side * width, y: width))
        ctx.addLine(to: CGPoint(x: 0, y: length))
        ctx.closePath()
        ctx.setFillColor(fill)
        ctx.setStrokeColor(color(0x161C30, 0.55))
        ctx.setLineWidth(1.4)
        ctx.setLineJoin(.miter)
        ctx.drawPath(using: .fillStroke)
    }
    ctx.restoreGState()
}

func renderMaster() -> CGImage {
    let ctx = makeContext(1024)
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = continuousRect(tile, radius: 185)
    let center = CGPoint(x: 512, y: 512)
    let hasFleur = ProcessInfo.processInfo.environment["ICON_VARIANT"] != "plain"
    // Shorter points when the fleur-de-lis needs headroom, so the rose stays centered.
    let scale: CGFloat = hasFleur ? 0.86 : 1

    // Tile + drop shadow (Big Sur icon grid).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 26, color: color(0x000000, 0.32))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0xEADCBB))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Vellum, slightly darker toward the edges like an old skin.
    ctx.drawLinearGradient(
        gradient([color(0xF4EAD3), color(0xE5D3AC)]),
        start: CGPoint(x: 140, y: 900), end: CGPoint(x: 880, y: 120), options: []
    )
    ctx.drawRadialGradient(
        gradient([color(0x9C7C4C, 0), color(0x9C7C4C, 0.26)]),
        startCenter: center, startRadius: 300, endCenter: center, endRadius: 640, options: [.drawsAfterEndLocation]
    )

    // Chart frame: a heavy and a hairline rule.
    let outerFrame = continuousRect(tile.insetBy(dx: 30, dy: 30), radius: 158)
    let innerFrame = continuousRect(tile.insetBy(dx: 42, dy: 42), radius: 147)
    ctx.addPath(outerFrame)
    ctx.setStrokeColor(color(0x1C2541, 0.85))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.addPath(innerFrame)
    ctx.setLineWidth(1.5)
    ctx.strokePath()

    // Rhumb lines in the chart-makers' colour code.
    ctx.saveGState()
    ctx.addPath(innerFrame)
    ctx.clip()
    for index in 0..<32 {
        let angle = CGFloat(index) * 11.25 * .pi / 180
        let (ink, alpha): (CGColor, CGFloat) = switch index % 4 {
        case 0: (Ink.sepia, 0.6)
        case 2: (Ink.verdigris, 0.6)
        default: (Ink.oxblood, 0.5)
        }
        ctx.move(to: center)
        ctx.addLine(to: CGPoint(x: center.x + sin(angle) * 900, y: center.y + cos(angle) * 900))
        ctx.setStrokeColor(ink.copy(alpha: alpha)!)
        ctx.setLineWidth(2.4)
        ctx.strokePath()
    }
    // The "hidden circle" secondary roses sit on in real sea charts.
    ctx.addEllipse(in: CGRect(x: center.x - 340, y: center.y - 340, width: 680, height: 680))
    ctx.setStrokeColor(Ink.sepia.copy(alpha: 0.3)!)
    ctx.setLineWidth(1.6)
    ctx.strokePath()
    ctx.restoreGState()

    // Degree ring.
    let ringOuter: CGFloat = 150
    let ringInner: CGFloat = 136
    ctx.addEllipse(in: CGRect(x: center.x - ringOuter, y: center.y - ringOuter, width: ringOuter * 2, height: ringOuter * 2))
    ctx.setFillColor(color(0xF6EEDA, 0.7))
    ctx.fillPath()
    for radius in [ringOuter, ringInner] {
        ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
    ctx.setStrokeColor(Ink.navy)
    ctx.setLineWidth(2.5)
    ctx.strokePath()
    for tick in 0..<72 {
        let angle = CGFloat(tick) * 5 * .pi / 180
        let inner = tick % 2 == 0 ? ringInner : ringInner + 6
        ctx.move(to: CGPoint(x: center.x + sin(angle) * inner, y: center.y + cos(angle) * inner))
        ctx.addLine(to: CGPoint(x: center.x + sin(angle) * ringOuter, y: center.y + cos(angle) * ringOuter))
    }
    ctx.setLineWidth(1.5)
    ctx.strokePath()

    // The rose, with a little relief.
    let cardinal: CGFloat = 268 * scale
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 8, color: color(0x3A2A14, 0.35))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    for k in 0..<8 {
        drawPoint(ctx, center: center, bearing: 22.5 + CGFloat(k) * 45, length: 128 * scale, width: 19 * scale, lit: Ink.oxbloodLight, shade: Ink.oxblood)
    }
    for k in 0..<4 {
        drawPoint(ctx, center: center, bearing: 45 + CGFloat(k) * 90, length: 198 * scale, width: 30 * scale, lit: Ink.goldLight, shade: Ink.goldDark)
    }
    for k in 0..<4 {
        drawPoint(ctx, center: center, bearing: CGFloat(k) * 90, length: cardinal, width: 40, lit: Ink.navyLight, shade: Ink.navy)
    }

    // Hub.
    let hub = CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44)
    ctx.saveGState()
    ctx.addEllipse(in: hub)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([Ink.goldLight, Ink.goldDark]),
        start: CGPoint(x: hub.minX, y: hub.maxY), end: CGPoint(x: hub.maxX, y: hub.minY), options: []
    )
    ctx.restoreGState()
    ctx.addEllipse(in: hub)
    ctx.setStrokeColor(Ink.navy)
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.setFillColor(Ink.navy)
    ctx.fillEllipse(in: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12))

    // Gilded fleur-de-lis at north.
    let fleurCenter = CGPoint(x: center.x, y: center.y + cardinal + 44)
    if hasFleur, let fleur = glyphPath("\u{269C}", font: "Apple Symbols", height: 80, center: fleurCenter) {
        ctx.saveGState()
        ctx.addPath(fleur)
        ctx.clip()
        ctx.drawLinearGradient(
            gradient([Ink.goldLight, color(0xC9A253), Ink.goldDark]),
            start: CGPoint(x: fleurCenter.x, y: fleurCenter.y + 40), end: CGPoint(x: fleurCenter.x, y: fleurCenter.y - 40), options: []
        )
        ctx.restoreGState()
        ctx.addPath(fleur)
        ctx.setStrokeColor(Ink.navy)
        ctx.setLineWidth(2)
        ctx.strokePath()
    }

    ctx.endTransparencyLayer()
    ctx.restoreGState()
    ctx.restoreGState()

    addGrain(ctx)
    return ctx.makeImage()!
}

/// Faint vellum texture. Deterministic so the icon is reproducible.
func addGrain(_ ctx: CGContext) {
    guard let data = ctx.data else { return }
    let pixels = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * ctx.height)
    var seed: UInt32 = 0x1375
    for y in 0..<ctx.height {
        for x in 0..<ctx.width {
            let i = y * ctx.bytesPerRow + x * 4
            let alpha = Int(pixels[i + 3])
            guard alpha > 0 else { continue }
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = (Int(seed >> 24) - 128) * 6 / 128 * alpha / 255
            for c in 0..<3 {
                pixels[i + c] = UInt8(clamping: min(alpha, max(0, Int(pixels[i + c]) + noise)))
            }
        }
    }
}

func writePNG(_ image: CGImage, pixels: Int, to url: URL) {
    let ctx = makeContext(pixels)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage: make-icon.swift <output.iconset> [preview.png]")
    exit(1)
}
let iconset = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let master = renderMaster()
for points in [16, 32, 128, 256, 512] {
    writePNG(master, pixels: points, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    writePNG(master, pixels: points * 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
if arguments.count >= 3 {
    writePNG(master, pixels: 1024, to: URL(fileURLWithPath: arguments[2]))
}
print("wrote \(iconset.path)")

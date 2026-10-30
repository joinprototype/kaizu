import SwiftUI

/// A space with no tab open: chart paper, the name, and a few keys.
struct EmptyState: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Surface.paper(scheme)
            ChartPaper()
            // A clearing in the lines for the name, like a chart's cartouche.
            RadialGradient(colors: [Surface.paper(scheme), Surface.paper(scheme).opacity(0)], center: .center, startRadius: 40, endRadius: 260)
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text("Kaizu")
                        .font(.system(size: 56, weight: .regular, design: .serif))
                        .tracking(1)
                    // 海図, "sea chart".
                    Text("海図")
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .tracking(6)
                }
                .foregroundStyle(.tertiary)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    hint("⌘T", "New tab")
                    hint("⌘L", "Open location")
                    hint("⌘S", "Toggle sidebar")
                    hint("⌘D", "Pin tab")
                    hint("⌃1–9", "Switch space")
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { store.showCommandBar(.newTab) }
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        GridRow {
            KeyCap(keys: keys, size: 12)
                .gridColumnAlignment(.trailing)
            Text(label)
        }
    }
}

/// The web of rhumb lines old sea charts were drawn on: a rose in the
/// middle and sixteen around it, each casting the 32 compass bearings, inked
/// as the chart-makers did (the eight winds dark, half winds green, quarter
/// winds red). Faint, and drawn outward once when it appears.
private struct ChartPaper: View {
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = Date.now
    @State private var isDrawn = Motion.isReduced
    private static let drawing = 1.6

    // Driven by the clock, not an animation transaction: a page opening
    // while the lines are still drawing (a link from another app at launch)
    // must replace the empty state at once.
    var body: some View {
        TimelineView(.animation(paused: isDrawn)) { context in
            let progress = isDrawn ? 1 : min(1, context.date.timeIntervalSince(appeared) / Self.drawing)
            let reach = 1 - pow(1 - progress, 3)  // ease out
            ZStack {
                RhumbLines(bearings: stride(from: 0, to: 32, by: 4), reach: reach)
                    .stroke(.primary.opacity(0.09), lineWidth: 0.75)
                RhumbLines(bearings: stride(from: 2, to: 32, by: 4), reach: reach)
                    .stroke(Ink.verdigris(scheme).opacity(0.10), lineWidth: 0.5)
                RhumbLines(bearings: stride(from: 1, to: 32, by: 2), reach: reach)
                    .stroke(Ink.claret(scheme).opacity(0.08), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
        .task {
            try? await Task.sleep(for: .seconds(Self.drawing))
            isDrawn = true
        }
    }
}

private struct RhumbLines: Shape {
    /// Of the 32 compass points, 0 being east, clockwise.
    let bearings: [Int]
    let reach: Double

    init(bearings: some Sequence<Int>, reach: Double) {
        self.bearings = Array(bearings)
        self.reach = reach
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.4
        let length = hypot(rect.width, rect.height) * reach
        // Sixteen roses on a circle: every bearing from one passes through
        // others, which is what makes the web.
        let roses = [center] + (0..<16).map { index in
            let angle = Double(index) * .pi / 8
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        var path = Path()
        for rose in roses {
            for bearing in bearings {
                let angle = Double(bearing) * .pi / 16
                path.move(to: rose)
                path.addLine(to: CGPoint(x: rose.x + length * cos(angle), y: rose.y + length * sin(angle)))
            }
        }
        return path
    }
}

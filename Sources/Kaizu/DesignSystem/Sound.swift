import Foundation

/// Kaizu's interface sounds, all paper, like the chart room itself: a sheet
/// unfolding, a card laid down and drawn away, a page turning, a crease.
/// Made here in code from filtered noise with a little crinkle, so there's
/// nothing to bundle and nothing borrowed. Each is short, quiet and soft,
/// swelling in rather than clicking. `SoundPlayer` decides when one plays;
/// it's off unless the user turns it on.
enum Sound: String, CaseIterable, Sendable {
    /// The command bar comes up: a small hand bell on the chart table.
    case commandBar
    /// A tab opens from the command bar, or comes back with ⇧⌘T: a card laid down.
    case openTab
    /// ⌘W or a row's close button: the card slid away.
    case closeTab
    /// Pinned or made a favorite: a brass pin pressed home.
    case pin
    /// Back to Today: the pin drawn out.
    case unpin
    /// Another space: a chart's page turning.
    case switchSpace
    /// A split made or a pane added: dividers set down, two light knocks.
    case split

    static let sampleRate = 44_100.0
    /// Nothing runs longer than this; they're feedback, not music.
    static let longest = 0.25

    /// The sound as mono samples at `sampleRate`, from silence to silence.
    func render(sampleRate rate: Double = Sound.sampleRate) -> [Float] {
        switch self {
        case .commandBar:
            // A folded sheet opened out.
            var tape = Tape(duration: 0.2, rate: rate)
            tape.rustle(from: 500, to: 1_600, q: 0.7, gain: 1, at: 0, length: 0.16, seed: 3, crinkle: 0.5)
            tape.rustle(from: 220, to: 220, q: 0.8, gain: 0.35, at: 0.11, length: 0.05, seed: 5)  // it settles
            return tape.finished(peak: -26)
        case .openTab:
            // A card slid onto the table.
            var tape = Tape(duration: 0.15, rate: rate)
            tape.rustle(from: 900, to: 1_300, q: 0.8, gain: 0.8, at: 0, length: 0.09, seed: 7, crinkle: 0.25)
            tape.rustle(from: 180, to: 160, q: 0.7, gain: 0.6, at: 0.07, length: 0.05, seed: 9)  // and lands
            return tape.finished(peak: -27)
        case .closeTab:
            // The card drawn away across the paper.
            var tape = Tape(duration: 0.16, rate: rate)
            tape.rustle(from: 1_400, to: 600, q: 0.8, gain: 1, at: 0, length: 0.14, seed: 11, crinkle: 0.25)
            return tape.finished(peak: -28)
        case .pin:
            // Paper pressed down under a thumb: dull, close.
            var tape = Tape(duration: 0.12, rate: rate)
            tape.rustle(from: 260, to: 200, q: 0.7, gain: 1, at: 0, length: 0.045, seed: 13)
            tape.rustle(from: 1_100, to: 900, q: 1, gain: 0.25, at: 0.005, length: 0.03, seed: 17, crinkle: 0.6)
            return tape.finished(peak: -26)
        case .unpin:
            // Lifted off again: lighter, a little higher.
            var tape = Tape(duration: 0.12, rate: rate)
            tape.rustle(from: 700, to: 1_200, q: 0.8, gain: 0.7, at: 0, length: 0.06, seed: 19, crinkle: 0.4)
            tape.rustle(from: 320, to: 320, q: 0.7, gain: 0.4, at: 0.01, length: 0.035, seed: 21)
            return tape.finished(peak: -28)
        case .switchSpace:
            // A chart's page turning.
            var tape = Tape(duration: 0.23, rate: rate)
            tape.rustle(from: 400, to: 1_500, q: 0.7, gain: 1, at: 0, length: 0.19, seed: 23, crinkle: 0.45)
            tape.rustle(from: 170, to: 170, q: 0.7, gain: 0.3, at: 0.15, length: 0.06, seed: 29)  // it lands
            return tape.finished(peak: -28)
        case .split:
            // A crease folded in, twice.
            var tape = Tape(duration: 0.15, rate: rate)
            for (start, center, seed) in [(0.0, 1_000.0, UInt32(31)), (0.06, 1_300.0, 37)] {
                tape.rustle(from: center, to: center * 0.8, q: 0.9, gain: 1, at: start, length: 0.05, seed: seed, crinkle: 0.7)
            }
            return tape.finished(peak: -27)
        }
    }
}

/// Where a sound is put together, one layer at a time.
private struct Tape {
    let rate: Double
    var samples: [Double]

    init(duration: Double, rate: Double) {
        self.rate = rate
        samples = Array(repeating: 0, count: Int(duration * rate))
    }

    /// Noise through a band-pass whose center sweeps from `from` to `to`:
    /// paper sliding, a page turning, felt. Seeded, so every render matches.
    /// `crinkle` from 0 to 1 breaks the noise into the uneven little grains
    /// that make it sound like paper rather than air.
    mutating func rustle(from: Double, to: Double, q: Double, gain: Double, at start: Double, length: Double, seed: UInt32, crinkle: Double = 0) {
        var state = seed
        var grain = 1.0, grainTarget = 1.0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        var b0 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
        let first = Int(start * rate), count = min(Int(length * rate), samples.count - first)
        for step in 0..<max(count, 0) {
            let progress = Double(step) / Double(count)
            if step % 32 == 0 {
                // RBJ band-pass, 0 dB at the center.
                let omega = 2 * .pi * from * pow(to / from, progress) / rate
                let alpha = sin(omega) / (2 * q), a0 = 1 + alpha
                b0 = alpha / a0
                b2 = -alpha / a0
                a1 = -2 * cos(omega) / a0
                a2 = (1 - alpha) / a0
            }
            state = state &* 1_664_525 &+ 1_013_904_223
            let noise = Double(state >> 8) / Double(1 << 23) - 1
            if crinkle > 0, step % 96 == 0 {
                // A new grain every ~2 ms, eased toward so the grains don't click.
                state = state &* 1_664_525 &+ 1_013_904_223
                grainTarget = 1 - crinkle * Double(state >> 8) / Double(1 << 24)
            }
            grain += (grainTarget - grain) * 0.02
            let filtered = b0 * noise + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = noise
            y2 = y1
            y1 = filtered
            // Swells over the first third, then fades away.
            let envelope = progress < 0.3 ? pow(sin(.pi / 2 * progress / 0.3), 2) : pow(cos(.pi / 2 * (progress - 0.3) / 0.7), 2)
            samples[first + step] += gain * envelope * grain * filtered
        }
    }

    /// Scaled so its loudest moment is `peak` dBFS, and eased out over the
    /// last 15 ms so it ends at silence.
    func finished(peak: Double) -> [Float] {
        // A gentle low-pass keeps the paper soft: no hiss above about 3 kHz.
        var samples = samples
        let smoothing = 1 - exp(-2 * .pi * 3_000 / rate)
        var level = 0.0
        for index in samples.indices {
            level += smoothing * (samples[index] - level)
            samples[index] = level
        }
        let loudest = samples.lazy.map(abs).max() ?? 0
        guard loudest > 0 else { return samples.map(Float.init) }
        let scale = pow(10, peak / 20) / loudest
        let fade = Int(0.015 * rate)
        return samples.enumerated().map { index, sample in
            let left = samples.count - 1 - index
            let ease = left < fade ? pow(sin(.pi / 2 * Double(left) / Double(fade)), 2) : 1
            return Float(sample * scale * ease)
        }
    }
}

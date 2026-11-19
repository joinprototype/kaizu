import Foundation

/// Kaizu's interface sounds, made here in code from a few rung tones and a
/// little filtered noise, so there's nothing to bundle and nothing borrowed.
/// The chart room's materials: paper, wood, brass, a small bell. Each is
/// short, quiet and low, swelling in over about ten milliseconds rather
/// than clicking, with its main note between 150 and 400 Hz on one G
/// pentatonic scale, so they sit together. `SoundPlayer` decides when
/// one plays; it's off unless the user turns it on.
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
        // An octave below the first set: low enough to sit under speech and
        // music instead of cutting through them.
        let g3 = 196.0, b3 = 246.94, d4 = 293.66, e4 = 329.63, g4 = 392.0
        switch self {
        case .commandBar:
            var tape = Tape(duration: 0.24, rate: rate)
            tape.ring(e4 / 2, gain: 0.15, decay: 0.1, attack: 0.015)  // the hum below
            tape.ring(e4, gain: 1, decay: 0.09, attack: 0.012)
            tape.ring(e4 * 2, gain: 0.12, decay: 0.05, attack: 0.012)
            return tape.finished(peak: -24)
        case .openTab:
            var tape = Tape(duration: 0.15, rate: rate)
            tape.rustle(from: 600, to: 1_000, q: 0.8, gain: 0.2, at: 0, length: 0.05, seed: 7)
            // Wood, rising into its note.
            tape.ring(d4, gain: 1, decay: 0.04, at: 0.015, attack: 0.01, bend: 0.97)
            return tape.finished(peak: -27)
        case .closeTab:
            var tape = Tape(duration: 0.16, rate: rate)
            tape.rustle(from: 900, to: 500, q: 0.8, gain: 0.2, at: 0, length: 0.06, seed: 11)
            // Lower, and settling down into its note.
            tape.ring(g3, gain: 1, decay: 0.045, at: 0.025, attack: 0.01, bend: 1.03)
            return tape.finished(peak: -28)
        case .pin:
            var tape = Tape(duration: 0.22, rate: rate)
            tape.ring(d4 / 2, gain: 0.35, decay: 0.025, attack: 0.006)  // the press
            tape.ring(g4, gain: 0.8, decay: 0.07, at: 0.004, attack: 0.01)  // and the brass
            tape.ring(g4 * 2, gain: 0.1, decay: 0.03, at: 0.004, attack: 0.01)
            return tape.finished(peak: -25)
        case .unpin:
            var tape = Tape(duration: 0.19, rate: rate)
            tape.ring(d4, gain: 0.7, decay: 0.05, attack: 0.01)
            tape.ring(g3, gain: 0.3, decay: 0.03, at: 0.03, attack: 0.008)
            return tape.finished(peak: -27)
        case .switchSpace:
            var tape = Tape(duration: 0.22, rate: rate)
            tape.rustle(from: 400, to: 1_400, q: 0.7, gain: 0.6, at: 0, length: 0.17, seed: 23)
            tape.ring(g3 * 0.75, gain: 0.25, decay: 0.06, at: 0.1, attack: 0.012)  // the page lands
            return tape.finished(peak: -29)
        case .split:
            var tape = Tape(duration: 0.17, rate: rate)
            for (start, note) in [(0.0, b3), (0.07, e4)] {
                tape.ring(note, gain: 1, decay: 0.03, at: start, attack: 0.008)
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

    /// A struck tone: a short rise (no click), then an exponential decay.
    /// `bend` starts it off pitch, gliding to `frequency` within ~20 ms.
    mutating func ring(_ frequency: Double, gain: Double, decay: Double, at start: Double = 0, attack: Double = 0.002, bend: Double = 1) {
        var phase = 0.0
        for index in Int(start * rate)..<samples.count {
            let time = Double(index) / rate - start
            let envelope = (time < attack ? pow(sin(.pi / 2 * time / attack), 2) : 1) * exp(-time / decay)
            if time > attack, envelope < 1e-5 { break }
            phase += 2 * .pi * frequency * (1 + (bend - 1) * exp(-time / 0.02)) / rate
            samples[index] += gain * envelope * sin(phase)
        }
    }

    /// Noise through a band-pass whose center sweeps from `from` to `to`:
    /// paper sliding, a page turning, felt. Seeded, so every render matches.
    mutating func rustle(from: Double, to: Double, q: Double, gain: Double, at start: Double, length: Double, seed: UInt32) {
        var state = seed
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
            let filtered = b0 * noise + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = noise
            y2 = y1
            y1 = filtered
            // Swells over the first third, then fades away.
            let envelope = progress < 0.3 ? pow(sin(.pi / 2 * progress / 0.3), 2) : pow(cos(.pi / 2 * (progress - 0.3) / 0.7), 2)
            samples[first + step] += gain * envelope * filtered
        }
    }

    /// Scaled so its loudest moment is `peak` dBFS, and eased out over the
    /// last 15 ms so it ends at silence.
    func finished(peak: Double) -> [Float] {
        // A gentle low-pass takes the edge off whatever is left above 2 kHz.
        var samples = samples
        let smoothing = 1 - exp(-2 * .pi * 2_000 / rate)
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

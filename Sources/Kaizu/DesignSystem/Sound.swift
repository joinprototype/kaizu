import Foundation

/// Kaizu's interface sounds, made here in code from a few rung tones and a
/// little filtered noise, so there's nothing to bundle and nothing borrowed.
/// The chart room's materials: paper, wood, brass, a small bell. Each is
/// short and quiet, with its main note between 200 and 800 Hz on one G
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
        let g4 = 392.0, b4 = 493.88, d5 = 587.33, e5 = 659.26, g5 = 783.99
        switch self {
        case .commandBar:
            var tape = Tape(duration: 0.23, rate: rate)
            tape.rustle(from: 2_400, to: 2_400, q: 1, gain: 0.05, at: 0, length: 0.012, seed: 3)  // the felt mallet
            tape.ring(e5 / 2, gain: 0.10, decay: 0.12)  // the hum below
            tape.ring(e5, gain: 1, decay: 0.075, attack: 0.003)
            tape.ring(e5 * 2, gain: 0.2, decay: 0.045, attack: 0.003)
            tape.ring(e5 * 2.76, gain: 0.06, decay: 0.022, attack: 0.003)
            return tape.finished(peak: -16)
        case .openTab:
            var tape = Tape(duration: 0.14, rate: rate)
            tape.rustle(from: 1_200, to: 2_200, q: 0.9, gain: 0.5, at: 0, length: 0.05, seed: 7)
            // Wood, rising into its note.
            tape.ring(d5, gain: 1, decay: 0.032, at: 0.018, bend: 0.94)
            tape.ring(d5 * 3.93, gain: 0.12, decay: 0.009, at: 0.018)
            return tape.finished(peak: -19)
        case .closeTab:
            var tape = Tape(duration: 0.15, rate: rate)
            tape.rustle(from: 1_800, to: 900, q: 0.9, gain: 0.5, at: 0, length: 0.06, seed: 11)
            // Lower, and settling down into its note.
            tape.ring(g4, gain: 1, decay: 0.035, at: 0.03, bend: 1.05)
            tape.ring(g4 * 3.93, gain: 0.1, decay: 0.01, at: 0.03)
            return tape.finished(peak: -20)
        case .pin:
            var tape = Tape(duration: 0.21, rate: rate)
            tape.rustle(from: 420, to: 300, q: 0.7, gain: 0.25, at: 0, length: 0.02, seed: 13)
            tape.ring(g4 / 2, gain: 0.55, decay: 0.022, attack: 0.001)  // the press
            tape.ring(g5, gain: 0.7, decay: 0.06, at: 0.006)  // and the brass
            tape.ring(g5 * 2.32, gain: 0.22, decay: 0.03, at: 0.006)
            tape.ring(g5 * 4.25, gain: 0.06, decay: 0.014, at: 0.006)
            return tape.finished(peak: -16)
        case .unpin:
            var tape = Tape(duration: 0.18, rate: rate)
            tape.ring(d5, gain: 0.7, decay: 0.045)
            tape.ring(d5 * 2.32, gain: 0.15, decay: 0.02)
            tape.ring(g4 / 2, gain: 0.35, decay: 0.02, at: 0.03, attack: 0.001)
            return tape.finished(peak: -19)
        case .switchSpace:
            var tape = Tape(duration: 0.22, rate: rate)
            tape.rustle(from: 700, to: 2_600, q: 0.8, gain: 1, at: 0, length: 0.17, seed: 23)
            tape.ring(g4 * 0.75, gain: 0.35, decay: 0.06, at: 0.1)  // the page lands
            return tape.finished(peak: -21)
        case .split:
            var tape = Tape(duration: 0.16, rate: rate)
            for (start, note) in [(0.0, b4), (0.06, e5)] {
                tape.rustle(from: 3_000, to: 3_000, q: 1.2, gain: 0.15, at: start, length: 0.006, seed: 31)
                tape.ring(note, gain: 1, decay: 0.026, at: start, attack: 0.0015)
                tape.ring(note * 3.93, gain: 0.1, decay: 0.007, at: start, attack: 0.0015)
            }
            return tape.finished(peak: -18)
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

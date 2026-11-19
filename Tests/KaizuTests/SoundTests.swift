import Foundation
import AVFoundation
import Testing
@testable import DesignSystem
@testable import Kaizu

@MainActor
struct SoundTests {
    /// A player wired to a fake clock, fake system settings and fake speakers.
    @MainActor private final class Rig {
        let suite = "dev.kaizu.tests.sounds." + UUID().uuidString
        let defaults: UserDefaults
        let settings: Settings
        var time: TimeInterval = 100
        var systemAllows = true
        var volume: Float = 0.5
        var isActive = true
        var isKeyRepeat = false
        var heard: [(Sound, Float)] = []
        private(set) lazy var player = SoundPlayer(
            settings: settings,
            system: SoundPlayer.System(
                allowsInterfaceSounds: { [unowned self] in systemAllows },
                alertVolume: { [unowned self] in volume },
                isActive: { [unowned self] in isActive },
                isKeyRepeat: { [unowned self] in isKeyRepeat }
            ),
            now: { [unowned self] in time },
            output: { [unowned self] in heard.append(($0, $1)) }
        )

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            settings = Settings(defaults: defaults)
        }

        deinit { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    }

    @Test func soundsAreOffByDefaultAndTheSettingPersists() throws {
        let rig = try Rig()
        #expect(!rig.settings.interfaceSounds)
        #expect(!rig.player.play(.openTab))
        #expect(rig.heard.isEmpty)

        rig.settings.interfaceSounds = true
        #expect(Settings(defaults: rig.defaults).interfaceSounds)
        rig.settings.interfaceSounds = false
        #expect(!Settings(defaults: rig.defaults).interfaceSounds)
    }

    @Test func settingsSavedBeforeSoundsExistKeepThemOff() throws {
        let rig = try Rig()
        rig.defaults.set(Data(#"{"autoPictureInPicture":false}"#.utf8), forKey: "settings")
        let settings = Settings(defaults: rig.defaults)
        #expect(!settings.interfaceSounds)
        #expect(!settings.autoPictureInPicture)
    }

    @Test func playsOnlyWhenOnAndMacOSPlaysInterfaceSounds() throws {
        let rig = try Rig()
        rig.settings.interfaceSounds = true
        rig.systemAllows = false
        #expect(!rig.player.isAudible)
        #expect(!rig.player.play(.pin))

        rig.systemAllows = true
        #expect(rig.player.play(.pin))
        #expect(rig.heard.map(\.0) == [.pin])
        #expect(rig.heard.map(\.1) == [0.5])
    }

    @Test func staysQuietInTheBackgroundOnHeldKeysAndAtZeroVolume() throws {
        let rig = try Rig()
        rig.settings.interfaceSounds = true
        rig.isActive = false
        #expect(!rig.player.play(.switchSpace))
        rig.isActive = true
        rig.isKeyRepeat = true
        rig.time += 1
        #expect(!rig.player.play(.closeTab))
        rig.isKeyRepeat = false
        rig.volume = 0
        rig.time += 1
        #expect(!rig.player.play(.closeTab))
        #expect(rig.heard.isEmpty)
    }

    @Test func aHeldRepeatPlaysOnceUntilItPauses() throws {
        let rig = try Rig()
        rig.settings.interfaceSounds = true
        // ⌘W held with a fast key repeat: one sound, however long it's held.
        var played = 0
        for _ in 0..<40 {
            if rig.player.play(.closeTab) { played += 1 }
            rig.time += 0.035
        }
        #expect(played == 1)
        rig.time += SoundThrottle.repeatWindow
        #expect(rig.player.play(.closeTab))
    }

    @Test func differentSoundsKeepApartAndBurstsAreCapped() throws {
        var throttle = SoundThrottle()
        let first = throttle.allows(.commandBar, at: 0)
        let tooClose = throttle.allows(.openTab, at: 0.03)
        let later = throttle.allows(.openTab, at: 0.3)
        #expect(first && !tooClose && later)
        // Swiping through spaces at a steady 250 ms: capped per burst window.
        var played = 0
        for step in 0..<12 {
            if throttle.allows(.switchSpace, at: 0.6 + Double(step) * 0.25) { played += 1 }
        }
        #expect(played <= SoundThrottle.burstLimit * 2)
        #expect(played >= 2)
    }

    @Test func soundsAreMadeOnlyOnceTurnedOnAndLetGoWhenTurnedOff() async throws {
        let rig = try Rig()
        // The real engine, never started: loading renders and wires up, silently.
        let real = SoundPlayer(settings: rig.settings)
        real.prepare()
        #expect(await real.engine.loadedCount == 0, "nothing is made while sounds are off")

        rig.settings.interfaceSounds = true
        real.prepare()
        #expect(await real.engine.loadedCount == Sound.allCases.count)
        real.unload()
        #expect(await real.engine.loadedCount == 0)
    }

    /// Switching to another app for a few seconds stopped the idle engine, and
    /// every sound after that was silent. Uses the real engine at zero volume;
    /// skipped on a Mac with no audio output.
    @Test(.enabled(if: SoundTests.hasAudioOutput))
    func playsAgainAfterTheEngineStopsWhenIdle() async throws {
        let engine = SoundEngine()
        // Waits for each sound to be heard through rather than a fixed time:
        // a busy audio device (a video playing) can start the engine late.
        func played(_ count: Int) async throws -> Bool {
            let deadline = ContinuousClock.now + .seconds(3)
            while engine.finishedCount < count, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            return engine.finishedCount >= count
        }
        engine.play(.pin, volume: 0)
        #expect(try await played(1))
        engine.stopForIdle()
        try await Task.sleep(for: .milliseconds(100))
        engine.play(.pin, volume: 0)
        #expect(try await played(2), "a sound after the engine idled out is heard")
        engine.unload()
    }

    nonisolated static var hasAudioOutput: Bool {
        // Kept alive for the call: a temporary engine is freed mid-read.
        let engine = AVAudioEngine()
        return withExtendedLifetime(engine) { engine.outputNode.outputFormat(forBus: 0).sampleRate > 0 }
    }

    /// Every sound is short, quiet and clean. Prints its levels; with
    /// `KAIZU_WRITE_SOUNDS=<folder>` it also writes each as a WAV to listen to.
    @Test(arguments: Sound.allCases)
    func soundsAreShortSoftAndClean(_ sound: Sound) throws {
        let samples = sound.render()
        let rate = Sound.sampleRate
        let duration = Double(samples.count) / rate
        let peak = samples.map { abs(Double($0)) }.max() ?? 0
        let rms = (samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
        // Loudness while it's actually sounding: RMS over the loudest 50 ms.
        let window = Int(0.05 * rate)
        var energy = samples.prefix(window).reduce(0) { $0 + Double($1) * Double($1) }
        var loudest = energy
        for index in window..<samples.count {
            energy += Double(samples[index]) * Double(samples[index]) - Double(samples[index - window]) * Double(samples[index - window])
            loudest = max(loudest, energy)
        }
        let body = (loudest / Double(window)).squareRoot()
        func dB(_ value: Double) -> Double { 20 * log10(value) }
        print(String(format: "sound %-12@ %3.0f ms  peak %6.1f dBFS  RMS %6.1f dBFS  loudest 50 ms %6.1f dBFS",
                     sound.rawValue as NSString, duration * 1000, dB(peak), dB(rms), dB(body)))

        #expect(samples.allSatisfy { $0.isFinite })
        #expect(duration <= Sound.longest)
        #expect(duration >= 0.1)
        #expect(dB(peak) <= -23.9, "soft: far below a system alert")
        #expect(dB(peak) >= -30)
        #expect((-46.0 ... -26).contains(dB(body)))
        #expect(abs(samples.first ?? 1) < 0.002 && abs(samples.last ?? 1) < 0.0001, "starts and ends without a click")
        #expect(sound.render() == samples, "renders the same every time")

        if let folder = ProcessInfo.processInfo.environment["KAIZU_WRITE_SOUNDS"] {
            try Self.wav(samples, sampleRate: rate)
                .write(to: URL(fileURLWithPath: folder).appending(path: "\(sound.rawValue).wav"))
        }
    }

    @Test func allSoundsRenderQuickly() {
        let start = ContinuousClock.now
        let rendered = Sound.allCases.map { $0.render() }
        let elapsed = ContinuousClock.now - start
        print("rendered \(rendered.count) sounds, \(rendered.map(\.count).reduce(0, +) * 4) bytes of samples, in \(elapsed)")
        #expect(elapsed < .milliseconds(250))
    }

    /// 16-bit mono PCM in a WAV file, to listen to with `afplay`.
    private static func wav(_ samples: [Float], sampleRate: Double) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let bytes = UInt32(samples.count * 2), rate = UInt32(sampleRate)
        data.append(contentsOf: Array("RIFF".utf8))
        append(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))  // PCM
        append(UInt16(1))  // mono
        append(rate)
        append(rate * 2)
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(bytes)
        for sample in samples {
            append(Int16((max(min(sample, 1), -1) * Float(Int16.max)).rounded()))
        }
        return data
    }
}

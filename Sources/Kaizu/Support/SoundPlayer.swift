import AVFoundation
import AppKit

/// Plays a `Sound` for something the user just did, if they've turned
/// sounds on (Settings → General; off by default) and macOS plays interface
/// sounds too. Call it from user actions only, never from what a page or an
/// extension can repeat on its own. Held keys and quick runs of the same
/// action stay quiet after the first (see `SoundThrottle`).
///
/// Nothing is made until sounds are on. The main thread only decides and
/// hands off; `SoundEngine` renders and plays on its own queue.
@MainActor
final class SoundPlayer {
    /// What macOS says, read on each play so changes apply at once.
    struct System {
        /// System Settings → Sound → "Play user interface sound effects".
        var allowsInterfaceSounds: @MainActor () -> Bool
        /// System Settings → Sound → Alert volume, 0 to 1. Kaizu has no
        /// volume of its own, like Herdr: interface sounds follow this one.
        var alertVolume: @MainActor () -> Float
        /// Sounds answer what you do in Kaizu, so none while it's in the background.
        var isActive: @MainActor () -> Bool
        /// The event being handled is a held key repeating.
        var isKeyRepeat: @MainActor () -> Bool

        static var live: System {
            System(
                allowsInterfaceSounds: { (UserDefaults.standard.object(forKey: "com.apple.sound.uiaudio.enabled") as? NSNumber)?.boolValue ?? true },
                alertVolume: { min(max((UserDefaults.standard.object(forKey: "com.apple.sound.beep.volume") as? NSNumber)?.floatValue ?? 1, 0), 1) },
                isActive: { NSApp.isActive },
                isKeyRepeat: { NSApp.currentEvent.map { $0.type == .keyDown && $0.isARepeat } ?? false }
            )
        }
    }

    private let settings: Settings
    private let system: System
    private let now: () -> TimeInterval
    /// Stands in for the speakers in tests.
    private let output: ((Sound, Float) -> Void)?
    private var throttle = SoundThrottle()
    let engine = SoundEngine()

    init(
        settings: Settings,
        system: System = .live,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        output: ((Sound, Float) -> Void)? = nil
    ) {
        self.settings = settings
        self.system = system
        self.now = now
        self.output = output
    }

    /// Whether `play` would make a sound now, before rate limits.
    var isAudible: Bool {
        settings.interfaceSounds && system.allowsInterfaceSounds()
    }

    /// Plays `sound` unless it's off, muted by macOS, or a repeat.
    @discardableResult
    func play(_ sound: Sound) -> Bool {
        guard isAudible, system.isActive(), !system.isKeyRepeat(),
              throttle.allows(sound, at: now())
        else { return false }
        let volume = system.alertVolume()
        guard volume > 0 else { return false }
        if let output {
            output(sound, volume)
        } else {
            engine.play(sound, volume: volume)
        }
        return true
    }

    /// Renders the sounds ahead of the first one. Called at launch and when
    /// the setting is turned on; does nothing while it's off.
    func prepare() {
        guard settings.interfaceSounds, output == nil else { return }
        engine.load()
    }

    /// Turned off: let the sounds and the engine go.
    func unload() {
        engine.unload()
    }
}

/// One `AVAudioEngine` with a player per sound, touched only on its own
/// queue, so the main thread never waits on audio (`NSSound.play()` held it
/// 10 to 140 ms). Scheduling a rendered buffer costs microseconds; the
/// engine stops after a few quiet seconds so an idle Kaizu has no audio
/// thread waking up, and starts again (about 10 ms, on this queue) when needed.
final class SoundEngine: @unchecked Sendable {
    private static let idleTimeout: TimeInterval = 4

    private let queue = DispatchQueue(label: "com.joinprototype.kaizu.sounds", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var players: [Sound: (node: AVAudioPlayerNode, buffer: AVAudioPCMBuffer)] = [:]
    private var idleStop: DispatchWorkItem?

    func load() {
        queue.async { Sound.allCases.forEach { _ = self.player(for: $0) } }
    }

    func play(_ sound: Sound, volume: Float) {
        queue.async {
            guard let (node, buffer) = self.player(for: sound), let engine = self.engine else { return }
            if !engine.isRunning {
                engine.prepare()
                guard (try? engine.start()) != nil else { return }
            }
            node.volume = volume
            // Interrupts the same sound if it's still ringing; others overlap.
            node.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !node.isPlaying { node.play() }
            self.idleStop?.cancel()
            let stop = DispatchWorkItem { [weak engine] in engine?.stop() }
            self.idleStop = stop
            self.queue.asyncAfter(deadline: .now() + Self.idleTimeout, execute: stop)
        }
    }

    func unload() {
        queue.async {
            self.idleStop?.cancel()
            self.engine?.stop()
            self.engine = nil
            self.players = [:]
        }
    }

    /// How many sounds are ready, for tests.
    var loadedCount: Int {
        get async { await withCheckedContinuation { done in queue.async { done.resume(returning: self.players.count) } } }
    }

    /// On `queue` only.
    private func player(for sound: Sound) -> (node: AVAudioPlayerNode, buffer: AVAudioPCMBuffer)? {
        if let player = players[sound] { return player }
        let samples = sound.render()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Sound.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        let engine = engine ?? AVAudioEngine()
        self.engine = engine
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        players[sound] = (node, buffer)
        return (node, buffer)
    }
}

/// Keeps sounds from piling up: a held ⌘W, a run of space swipes or a
/// burst of actions plays the first and then waits for a pause.
struct SoundThrottle {
    /// The same sound asked for again this soon is a repeat, and the quiet
    /// lasts until the repeats stop.
    static let repeatWindow: TimeInterval = 0.2
    /// Two different sounds this close would blur into one.
    static let spacing: TimeInterval = 0.07
    /// At most `burstLimit` sounds in any `burstWindow`.
    static let burstLimit = 4
    static let burstWindow: TimeInterval = 1.5

    private var lastAsked: [Sound: TimeInterval] = [:]
    private var played: [TimeInterval] = []

    mutating func allows(_ sound: Sound, at time: TimeInterval) -> Bool {
        let previous = lastAsked.updateValue(time, forKey: sound)
        if let previous, time - previous < Self.repeatWindow { return false }
        if let last = played.last, time - last < Self.spacing { return false }
        played.removeAll { time - $0 >= Self.burstWindow }
        guard played.count < Self.burstLimit else { return false }
        played.append(time)
        return true
    }
}

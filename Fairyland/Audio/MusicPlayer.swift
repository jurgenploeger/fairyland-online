import AVFoundation
import Observation

/// Plays the songs from content/music.json: one per map, plus battle and victory.
/// Uses the "ambient" audio session, so the phone's silent switch mutes it.
@Observable
final class MusicPlayer {
    static let shared = MusicPlayer()

    private(set) var isMuted: Bool

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var synth: ChiptuneSynth?
    @ObservationIgnored private var tunes: [String: Tune] = [:]
    @ObservationIgnored private var current: String?

    init() {
        isMuted = UserDefaults.standard.bool(forKey: "musicMuted")
        for song in Content.shared.songs {
            tunes[song.id] = Tune(song)
        }
    }

    func toggleMute() {
        isMuted.toggle()
        UserDefaults.standard.set(isMuted, forKey: "musicMuted")
        synth?.setMuted(isMuted)
    }

    /// Music volume from Settings (0...1).
    func setVolume(_ volume: Double) {
        engine.mainMixerNode.outputVolume = Self.mixerVolume(volume)
    }

    private static func mixerVolume(_ volume: Double) -> Float {
        Float(0.7 * min(1, max(0, volume)))
    }

    /// Switches to a song (nil = silence). Playing the current song again does nothing.
    func play(_ id: String?) {
        guard id != current else { return }
        current = id
        startIfNeeded()
        synth?.play(id.flatMap { tunes[$0] })
    }

    /// Restarts audio after the app returns to the foreground or the output changes.
    func resume() {
        guard synth != nil, !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
    }

    private func startIfNeeded() {
        guard synth == nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient)
            try session.setActive(true)

            let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate > 0 ? sampleRate : 44_100, channels: 1)!
            let synth = ChiptuneSynth(sampleRate: format.sampleRate)
            synth.setMuted(isMuted)
            let source = Self.makeSourceNode(synth: synth, format: format)
            engine.attach(source)
            engine.connect(source, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = Self.mixerVolume(GameSettings.musicVolume)
            engine.prepare()
            try engine.start()
            self.synth = synth
        } catch {
            print("⚠️ Music unavailable: \(error)")
        }
    }

    /// Built outside the main actor so the render block can run on the audio thread.
    private nonisolated static func makeSourceNode(synth: ChiptuneSynth, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            synth.render(frameCount: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(audioBufferList))
            return noErr
        }
    }
}

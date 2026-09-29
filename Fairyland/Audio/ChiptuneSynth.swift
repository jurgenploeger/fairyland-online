import AVFoundation
import Foundation

nonisolated enum Wave: Sendable {
    case square, triangle, noise
}

/// A song turned into playable note events.
nonisolated struct Tune: Sendable {
    nonisolated struct Note: Sendable {
        /// Hz; 0 is a rest, -1 is a noise hit.
        let frequency: Double
        let steps: Int
    }

    nonisolated struct Voice: Sendable {
        let wave: Wave
        let duty: Double
        let volume: Float
        let notes: [Note]
    }

    let secondsPerStep: Double
    let loops: Bool
    let voices: [Voice]

    /// Parses music.json notation: `C5:2 F#5:1 Bb4:4 -:2 N:1`, with `|` bar lines ignored.
    init(_ song: SongDef) {
        secondsPerStep = 30 / song.tempo   // a step is an eighth note
        loops = song.loops ?? true
        voices = song.tracks.map { track in
            let wave: Wave = switch track.wave {
            case "triangle": .triangle
            case "noise": .noise
            default: .square
            }
            let notes = track.notes.split(separator: " ").compactMap { token -> Note? in
                guard token != "|" else { return nil }
                let parts = token.split(separator: ":")
                guard parts.count == 2, let steps = Int(parts[1]) else { return nil }
                let name = String(parts[0])
                let frequency: Double = switch name {
                case "-": 0
                case "N": -1
                default: Self.frequency(of: name) ?? 0
                }
                return Note(frequency: frequency, steps: steps)
            }
            return Voice(wave: wave, duty: track.duty ?? 0.5, volume: Float(track.volume), notes: notes)
        }
    }

    static func frequency(of name: String) -> Double? {
        let semitones: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard let letter = name.first, var semitone = semitones[letter] else { return nil }
        var rest = name.dropFirst()
        if rest.first == "#" { semitone += 1; rest = rest.dropFirst() }
        else if rest.first == "b" { semitone -= 1; rest = rest.dropFirst() }
        guard let octave = Int(rest) else { return nil }
        let midi = 12 * (octave + 1) + semitone
        return 440 * pow(2, Double(midi - 69) / 12)
    }
}

/// A tiny four-channel chiptune synth: pulse, triangle and noise voices rendered
/// sample by sample on the audio thread. Everything here runs off the main actor.
nonisolated final class ChiptuneSynth: @unchecked Sendable {
    private struct VoiceState {
        var noteIndex = -1
        var samplesLeft = 0
        var samplesPlayed = 0
        var phase = 0.0
        var noise: UInt32 = 0xACE1
        var noiseLevel: Float = 0
        var noiseCountdown = 0
        var finished = false
    }

    private let lock = NSLock()
    private var queuedTune: Tune?
    private var hasQueuedTune = false
    private var queuedMuted = false

    // Audio-thread state.
    private var tune: Tune?
    private var voices: [VoiceState] = []
    private var muted = false
    private var fade: Float = 0
    let sampleRate: Double

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func play(_ tune: Tune?) {
        lock.lock()
        queuedTune = tune
        hasQueuedTune = true
        lock.unlock()
    }

    func setMuted(_ muted: Bool) {
        lock.lock()
        queuedMuted = muted
        lock.unlock()
    }

    func render(frameCount: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        // Pick up changes from the main thread without ever blocking the audio thread.
        if lock.try() {
            if hasQueuedTune {
                tune = queuedTune
                voices = Array(repeating: VoiceState(), count: tune?.voices.count ?? 0)
                hasQueuedTune = false
                fade = 0
            }
            muted = queuedMuted
            lock.unlock()
        }

        guard let tune, !muted else {
            for buffer in buffers {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            return
        }

        let stepSamples = max(1, Int(tune.secondsPerStep * sampleRate))
        let attack = sampleRate * 0.004
        let decay = sampleRate * 0.18
        let release = sampleRate * 0.02
        let noiseDecay = sampleRate * 0.035
        let fadeStep = Float(1 / (sampleRate * 0.4))

        for frame in 0..<frameCount {
            var mix: Float = 0
            for index in voices.indices {
                let voice = tune.voices[index]
                guard !voice.notes.isEmpty else { continue }
                var state = voices[index]
                if state.finished { continue }

                if state.samplesLeft <= 0 {
                    state.noteIndex += 1
                    if state.noteIndex >= voice.notes.count {
                        if tune.loops {
                            state.noteIndex = 0
                        } else {
                            state.finished = true
                            voices[index] = state
                            continue
                        }
                    }
                    state.samplesLeft = voice.notes[state.noteIndex].steps * stepSamples
                    state.samplesPlayed = 0
                }

                let note = voice.notes[state.noteIndex]
                let played = Double(state.samplesPlayed)
                if note.frequency > 0 {
                    state.phase += note.frequency / sampleRate
                    if state.phase >= 1 { state.phase -= 1 }
                    let raw: Float = switch voice.wave {
                    case .square: state.phase < voice.duty ? 1 : -1
                    case .triangle: Float(4 * abs(state.phase - 0.5) - 1)
                    case .noise: 0
                    }
                    let sustain = voice.wave == .triangle ? 0.9 : 0.55
                    var envelope = min(1, played / attack) * (sustain + (1 - sustain) * exp(-played / decay))
                    envelope *= min(1, Double(state.samplesLeft) / release)
                    mix += raw * Float(envelope) * voice.volume
                } else if note.frequency < 0 {
                    if state.noiseCountdown <= 0 {
                        // 15-bit LFSR, like the NES noise channel.
                        let bit = (state.noise ^ (state.noise >> 1)) & 1
                        state.noise = (state.noise >> 1) | (bit << 14)
                        state.noiseLevel = (state.noise & 1) == 0 ? 1 : -1
                        state.noiseCountdown = 3
                    }
                    state.noiseCountdown -= 1
                    mix += state.noiseLevel * Float(exp(-played / noiseDecay)) * voice.volume
                }
                state.samplesLeft -= 1
                state.samplesPlayed += 1
                voices[index] = state
            }

            fade = min(1, fade + fadeStep)
            let sample = max(-1, min(1, mix * fade * 0.8))
            for buffer in buffers {
                buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
            }
        }
    }
}

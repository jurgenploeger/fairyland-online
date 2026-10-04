import AVFoundation
import UIKit

/// The player's settings (the Settings tab), kept in UserDefaults. The Settings screen edits the
/// same keys with @AppStorage, so the defaults here and there must match.
nonisolated enum GameSettings {
    static let musicVolumeKey = "musicVolume"
    static let soundVolumeKey = "soundVolume"
    static let footstepsKey = "footsteps"
    static let hapticsKey = "haptics"
    /// The top-left HUD folds a party of three or more into one row (WorldHUD); the player can unfold it.
    static let partyFoldedKey = "partyFolded"
    /// Battles ask what your companion should do after the hero's choice; off, it fights on its own.
    static let commandCompanionKey = "commandCompanion"

    static var musicVolume: Double { value(musicVolumeKey, fallback: 1) }
    static var soundVolume: Double { value(soundVolumeKey, fallback: 1) }
    static var footsteps: Bool { value(footstepsKey, fallback: true) }
    static var haptics: Bool { value(hapticsKey, fallback: true) }
    static var commandCompanion: Bool { value(commandCompanionKey, fallback: true) }

    private static func value<T>(_ key: String, fallback: T) -> T {
        UserDefaults.standard.object(forKey: key) as? T ?? fallback
    }
}

/// Short sound effects from sound/*.wav (made by tools/make_sounds.py), played over the music.
/// Uses the same "ambient" audio session as the music, so the silent switch mutes them too.
final class SoundEffects {
    static let shared = SoundEffects()

    enum Sound: String, CaseIterable {
        case tap, close, talk, step
        case hit, crit, magic, heal, potion, shield = "guard", capture, breakFree = "break_free", run, poof, faint, lose
        case levelUp = "level_up", coins, questAccept = "quest_accept", questDone = "quest_done"
        case chest, hatch, equip, learn, whoosh, encounter
    }

    private var players: [Sound: [AVAudioPlayer]] = [:]
    private var turn: [Sound: Int] = [:]
    /// Unit tests don't need sound.
    private let isEnabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

    private init() {}

    func play(_ sound: Sound, volume: Float = 1) {
        let level = Float(GameSettings.soundVolume) * volume
        guard isEnabled, level > 0.001, let player = nextPlayer(for: sound) else { return }
        player.volume = min(1, level)
        player.currentTime = 0
        player.play()
    }

    /// Loads every sound ahead of time, so the first of each plays without a hitch.
    func preload() {
        guard isEnabled else { return }
        for sound in Sound.allCases where players[sound] == nil {
            players[sound] = load(sound)
        }
    }

    private func nextPlayer(for sound: Sound) -> AVAudioPlayer? {
        if players[sound] == nil { players[sound] = load(sound) }
        guard let pool = players[sound], !pool.isEmpty else { return nil }
        let index = (turn[sound] ?? 0) % pool.count
        turn[sound] = index + 1
        return pool[index]
    }

    private func load(_ sound: Sound) -> [AVAudioPlayer] {
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav", subdirectory: "sound") else { return [] }
        // A few copies, so quick repeats (footsteps, hits) overlap instead of cutting each other off.
        return (0..<3).compactMap { _ in
            let player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            return player
        }
    }
}

/// Little taps of the Taptic Engine on hits and rewards (off in Settings → Haptics).
enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard GameSettings.haptics else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        guard GameSettings.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

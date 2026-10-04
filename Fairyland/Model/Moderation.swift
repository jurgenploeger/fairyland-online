import CryptoKit
import Foundation

/// Moderator mode, for the game's own team: a MOD tag on your name (over your head, in the chat and
/// on your stats), and the World channel in the chat to message everyone in the game. Type
/// `/mod <code>` in the chat to switch it on for this device, and `/mod off` to switch it off. Only
/// the code's SHA-256 is in the source. Once there's online play, being a moderator will be a role
/// on your account, checked by the server, instead.
enum Moderation {
    /// UserDefaults: moderator mode is on, on this device.
    static let key = "moderator"
    /// SHA-256 of the moderator code (trimmed, in lower case).
    private static let codeHash = "b262ac692ae5f8acc7262e806fd6152522ae653fe7ff7d3c0beacd4e8d743067"

    static var isOn: Bool { DebugLaunch.isModerator || UserDefaults.standard.bool(forKey: key) }

    /// Switches moderator mode on if `code` is the moderator code. Returns whether it was.
    static func unlock(with code: String) -> Bool {
        let typed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hash = SHA256.hash(data: Data(typed.utf8)).map { String(format: "%02x", $0) }.joined()
        guard hash == codeHash else { return false }
        UserDefaults.standard.set(true, forKey: key)
        return true
    }

    static func switchOff() {
        UserDefaults.standard.set(false, forKey: key)
    }
}

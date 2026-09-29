import Foundation

/// Debug-only shortcuts for testing, via the FAIRYLAND_DEBUG environment variable
/// (Xcode: Product → Scheme → Edit Scheme → Run → Environment Variables), comma-separated:
///
///   newgame        skip the title screen with a fresh hero
///   level=5        start at a level
///   hp=0.2         start with this fraction of HP left
///   map=<id>       start on a map from content/maps.json
///   battle         start in a random battle on the current map
///   menu=<tab>     open character | companions | bag | quests
///   npc=<id>       open an NPC dialog
///   landscape      lock the app to landscape
enum DebugLaunch {
    private static var flags: [String: String] {
        #if DEBUG
        let raw = ProcessInfo.processInfo.environment["FAIRYLAND_DEBUG"] ?? ""
        var flags: [String: String] = [:]
        for part in raw.split(separator: ",") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            flags[pair[0]] = pair.count > 1 ? pair[1] : ""
        }
        return flags
        #else
        return [:]
        #endif
    }

    static var forcesLandscape: Bool { flags["landscape"] != nil }

    static func session() -> GameSession? {
        let flags = flags
        guard flags["newgame"] != nil else { return nil }
        SaveStore.fileName = "fairyland-debug-save.json"
        let session = GameSession.newGame(name: "Hero", raceID: "human")
        if let level = flags["level"].flatMap(Int.init), level > 1 {
            session.data.hero.level = level
            session.restoreHero()
        }
        if let fraction = flags["hp"].flatMap(Double.init) {
            session.data.hero.hp = max(1, Int(Double(session.heroStats.hp) * fraction))
        }
        if let map = flags["map"], Content.shared.map(map) != nil {
            session.data.mapID = map
        }
        return session
    }

    static func apply(to coordinator: GameCoordinator) {
        let flags = flags
        if flags["battle"] != nil {
            let encounters = Content.shared.map(coordinator.session.data.mapID)?.encounters
                ?? Content.shared.maps.compactMap(\.encounters).first
            if let encounters { coordinator.startBattle(encounters) }
        }
        if let tab = flags["menu"].flatMap({ MenuTab(rawValue: $0.capitalized) }) {
            coordinator.open(.menu(tab))
        }
        if let npc = flags["npc"] {
            coordinator.open(.npc(npc))
        }
    }
}

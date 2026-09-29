import Foundation

nonisolated struct Equipment: Codable, Equatable, Sendable {
    var weapon: String?
    var armor: String?
    var accessory: String?

    subscript(slot: ItemType) -> String? {
        get {
            switch slot {
            case .weapon: weapon
            case .armor: armor
            case .accessory: accessory
            case .consumable: nil
            }
        }
        set {
            switch slot {
            case .weapon: weapon = newValue
            case .armor: armor = newValue
            case .accessory: accessory = newValue
            case .consumable: break
            }
        }
    }
}

nonisolated struct Hero: Codable, Equatable, Sendable {
    var name: String
    var raceID: String
    var classID: String
    var level: Int
    var exp: Int
    var hp: Int
    var mp: Int
    var equipment: Equipment
    /// Skill id → level (1 when learned; raised with skill points).
    var skillLevels: [String: Int]?
}

/// A captured monster travelling with the hero.
nonisolated struct Pet: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var speciesID: String
    var name: String
    var level: Int
    var exp: Int
    var hp: Int
    var mp: Int
}

nonisolated struct QuestProgress: Codable, Equatable, Sendable {
    nonisolated enum State: String, Codable, Sendable {
        case active, completed
    }

    var state: State
    var count: Int
}

/// Everything that's written to disk.
nonisolated struct SaveData: Codable, Sendable {
    var version = 1
    var hero: Hero
    var pets: [Pet]
    var activePetID: UUID?
    var gold: Int
    var inventory: [String: Int]
    var quests: [String: QuestProgress]
    var mapID: String
    var position: [Double]?
    /// When this hero's story began; drives the in-game calendar.
    var startedAt: Date?
    /// Gift boxes already opened.
    var openedChests: [String]?
    /// What will hatch from the pet egg (from the elder's question).
    var eggSpecies: String?
}

enum SaveStore {
    /// Debug launches use their own file so testing never overwrites your real game.
    static var fileName = "fairyland-save.json"
    static var url: URL { URL.applicationSupportDirectory.appending(path: fileName) }

    static var exists: Bool { load() != nil }

    static func load() -> SaveData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SaveData.self, from: data)
    }

    static func save(_ data: SaveData) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(data).write(to: url, options: .atomic)
        } catch {
            print("⚠️ Couldn't save the game: \(error)")
        }
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

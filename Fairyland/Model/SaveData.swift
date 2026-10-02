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
            case .consumable, .material: nil
            }
        }
        set {
            switch slot {
            case .weapon: weapon = newValue
            case .armor: armor = newValue
            case .accessory: accessory = newValue
            case .consumable, .material: break
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
    var look: Look?
    /// Skills learned with skill points (nil in saves from before skills had to be learned).
    var learnedSkills: [String]?
    /// Extra points, e.g. for skills older saves got for free.
    var bonusSkillPoints: Int?
    /// Times reborn (Fairyland Online's 轉生): back to level 1, keeping skills and some strength.
    var rebirths: Int?
}

/// The hero's chosen colours (preset ids from content/appearance.json).
nonisolated struct Look: Codable, Equatable, Sendable {
    var hair: String
    var outfit: String
    var skin: String
    /// male | female | other (content/appearance.json `genders`); nil in older saves, which
    /// keep their race's original sheet.
    var gender: String? = nil

    static let standard = Look(hair: "ginger", outfit: "green", skin: "fair")

    var key: String { "\(hair)/\(outfit)/\(skin)" + (gender.map { "/" + $0 } ?? "") }
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
    /// 2: the elder hands out the starter gifts (1: they were gift boxes around Meadowbrook).
    var version = 2
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
    /// Where you wake up after fainting.
    var checkpoint: Checkpoint?
    /// Adventurers you've befriended, and which of them travel with you.
    var friends: [Adventurer]?
    var partyIDs: [UUID]?
    /// Bosses you've beaten (their NPC ids); they don't come back.
    var defeatedBosses: [String]?
    /// Maps you've set foot on, for the world map.
    var visitedMaps: [String]?
    /// Levels were stretched from 1–33 to 1–105 (Fairyland Online's long climb); older saves are
    /// scaled up once so the hero still matches the zones they were in.
    var levelsRescaled: Bool?
}

/// Another adventurer (Fairyland's other players): met on the map, befriended, and maybe
/// invited to travel and fight alongside you.
nonisolated struct Adventurer: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var raceID: String
    var classID: String
    var level: Int
    var look: Look
    var petSpecies: String?
    /// Red-named troublemakers in danger zones pick fights.
    var hostile = false
}

/// A town square, or the entrance you last walked into a map through.
nonisolated struct Checkpoint: Codable, Equatable, Sendable {
    var mapID: String
    /// nil: the map's centre (towns); otherwise just inside this edge.
    var entry: Edge?
}

enum SaveStore {
    /// Tests and debug launches use their own files so they never overwrite your real game.
    static var fileName = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        ? "fairyland-tests-save.json"
        : "fairyland-save.json"
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

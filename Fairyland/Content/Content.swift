import Foundation

// MARK: - Stats & elements

nonisolated struct Stats: Codable, Equatable, Sendable {
    var hp: Int
    var mp: Int
    var attack: Int
    var defense: Int
    var magic: Int
    var speed: Int

    enum CodingKeys: String, CodingKey {
        case hp, mp, attack, defense, magic, speed
    }

    static let zero = Stats()

    init(hp: Int = 0, mp: Int = 0, attack: Int = 0, defense: Int = 0, magic: Int = 0, speed: Int = 0) {
        self.hp = hp
        self.mp = mp
        self.attack = attack
        self.defense = defense
        self.magic = magic
        self.speed = speed
    }

    /// Fields missing from the JSON count as 0, so content only lists what matters.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hp = try container.decodeIfPresent(Int.self, forKey: .hp) ?? 0
        mp = try container.decodeIfPresent(Int.self, forKey: .mp) ?? 0
        attack = try container.decodeIfPresent(Int.self, forKey: .attack) ?? 0
        defense = try container.decodeIfPresent(Int.self, forKey: .defense) ?? 0
        magic = try container.decodeIfPresent(Int.self, forKey: .magic) ?? 0
        speed = try container.decodeIfPresent(Int.self, forKey: .speed) ?? 0
    }

    static func + (lhs: Stats, rhs: Stats) -> Stats {
        Stats(
            hp: lhs.hp + rhs.hp, mp: lhs.mp + rhs.mp, attack: lhs.attack + rhs.attack,
            defense: lhs.defense + rhs.defense, magic: lhs.magic + rhs.magic, speed: lhs.speed + rhs.speed
        )
    }

    static func * (lhs: Stats, factor: Int) -> Stats {
        Stats(
            hp: lhs.hp * factor, mp: lhs.mp * factor, attack: lhs.attack * factor,
            defense: lhs.defense * factor, magic: lhs.magic * factor, speed: lhs.speed * factor
        )
    }
}

/// Fairyland's seven elements. The classic five-element cycle — each element overcomes the
/// next — plus light and dark, which overcome each other. Strong hits deal 1.5×, resisted 0.75×.
nonisolated enum Element: String, Codable, CaseIterable, Sendable {
    case neutral, metal, wood, water, fire, earth, light, dark

    /// water → fire → metal → wood → earth → water
    private static let cycle: [Element] = [.water, .fire, .metal, .wood, .earth]

    func multiplier(against defender: Element) -> Double {
        if (self == .light && defender == .dark) || (self == .dark && defender == .light) { return 1.5 }
        guard let attacker = Self.cycle.firstIndex(of: self), let target = Self.cycle.firstIndex(of: defender) else { return 1 }
        if (attacker + 1) % Self.cycle.count == target { return 1.5 }
        if (target + 1) % Self.cycle.count == attacker { return 0.75 }
        return 1
    }

    var displayName: String { rawValue.capitalized }
}

// MARK: - Definitions (one per JSON file in content/)

nonisolated struct RaceDef: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let base: Stats
    /// This race's walk sheet in art/assets.json.
    let art: String?

    var sheet: String { art ?? "player_walk" }
}

nonisolated struct ClassDef: Decodable, Identifiable, Sendable {
    nonisolated struct SkillUnlock: Decodable, Sendable {
        let skill: String
        let level: Int
    }

    let id: String
    let name: String
    let guild: String?
    let description: String
    let growth: Stats
    let skills: [SkillUnlock]
    /// Multiplies capture chance (Beast Tamers are better at taming).
    let captureBonus: Double?
    /// Share of battle EXP the active companion receives (default 0.5).
    let petExpShare: Double?
}

nonisolated enum SkillKind: String, Decodable, Sendable {
    case physical, magic, heal
}

nonisolated enum SkillTarget: String, Decodable, Sendable {
    case enemy, allEnemies, ally, allAllies
}

nonisolated struct SkillDef: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let mp: Int
    let kind: SkillKind
    let element: Element?
    let power: Double
    let target: SkillTarget
    let description: String?
    /// Battle effect: slash | whirlwind | fire | stone | leaves | water | heal | holy | wild | needles | bounce | bite
    let animation: String?
    /// A GameIcon name for menus.
    let icon: String?
    /// Spells: the share of damage that also hits the target's neighbours at skill level 5
    /// (60% of that at level 3, 80% at level 4, none below).
    let splash: Double?
}

nonisolated struct MonsterDef: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let art: String
    let element: Element
    let base: Stats
    let growth: Stats
    let exp: Int
    let gold: Int
    let captureRate: Double
    let skills: [String]
    /// A rarer colour variant: tougher, worth more, harder to catch.
    let rare: Bool?
    /// The species this is a colour variant of.
    let variantOf: String?
    /// How it fidgets standing still: breathe | squish | hop | sway | bounce.
    let motion: String?
    /// Bosses can't be captured and never run away.
    let boss: Bool?

    func stats(at level: Int) -> Stats { base + growth * (level - 1) }
}

nonisolated enum ItemType: String, Decodable, Sendable {
    case consumable, weapon, armor, accessory

    static let equipmentSlots: [ItemType] = [.weapon, .armor, .accessory]

    var displayName: String { rawValue.capitalized }
}

nonisolated struct ItemDef: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let type: ItemType
    let price: Int
    let heal: Int?
    let mp: Int?
    let stats: Stats?
    let classes: [String]?
    let level: Int?
    let description: String?
    /// For eggs: the species that can hatch from it.
    let hatches: [String]?
    /// A GameIcon name for the bag and shops.
    let icon: String?
    /// Seal Stones: thrown in battle to befriend a weakened monster.
    let capture: Bool?
    /// Armour: how it recolours the hero's outfit while worn (same rules as looks).
    let recolor: [RecolorRule]?
}

nonisolated struct QuestDef: Decodable, Identifiable, Sendable {
    nonisolated enum ObjectiveType: String, Decodable, Sendable {
        case defeat, capture, reachLevel, chooseClass, collect
    }

    /// Asked when accepting; the answer decides which companion hatches from the egg.
    nonisolated struct Question: Decodable, Sendable {
        nonisolated struct Answer: Decodable, Sendable {
            let text: String
            let egg: String
        }

        let text: String
        let answers: [Answer]
    }

    nonisolated struct Objective: Decodable, Sendable {
        let type: ObjectiveType
        let target: String?
        let count: Int?
    }

    nonisolated struct Reward: Decodable, Sendable {
        let gold: Int?
        let exp: Int?
        let items: [String]?
    }

    let id: String
    let title: String
    let giver: String
    let description: String
    let requires: [String]?
    let minLevel: Int?
    let question: Question?
    let objective: Objective
    let reward: Reward
    /// Items handed over when you accept (e.g. Seal Stones for the capture quest).
    let starterItems: [String]?
}

nonisolated enum Edge: String, Codable, Sendable {
    case north, south, east, west

    var opposite: Edge {
        switch self {
        case .north: .south
        case .south: .north
        case .east: .west
        case .west: .east
        }
    }
}

nonisolated enum NPCRole: String, Decodable, Sendable {
    /// `boss`: a mighty monster waiting on the map; talk to it to fight.
    case healer, shop, quests, guild, chest, boss
}

nonisolated struct NPCDef: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let role: NPCRole
    let art: String
    let x: Int
    let y: Int
    let greeting: String
    let stock: [String]?
    let classId: String?
    /// Chests: the item inside, and the quest that unlocks them.
    let gives: String?
    let quest: String?
    /// Bosses: which monster, at what level.
    let monster: String?
    let level: Int?
}

nonisolated struct MapDef: Decodable, Identifiable, Sendable {
    nonisolated struct Theme: Decodable, Sendable {
        let ground: String
        let path: String
        let accent: String?
        /// Number of accent patches (flower meadows etc.); without it accents are scattered.
        let accentPatches: Int?
        /// Ground outside a fenced town.
        let border: String?
        /// Water tile for ponds.
        let water: String?
        let ponds: Int?
        let fairyRings: FairyRings?
        let props: [PropPlacement]
        /// The map's colour mood for ground, scenery and buildings.
        let palette: MapPalette?
    }

    nonisolated struct PropPlacement: Decodable, Sendable {
        let art: String
        let count: Int
        let blocking: Bool
        /// Grow in groups of about this many (groves, rock piles) instead of evenly.
        let cluster: Int?
        /// How far (in cells) a group spreads from its centre; smaller packs a grove tighter.
        let spread: Int?
        /// Each one is drawn at a random size in this range ([0.8, 1.25] = 80% to 125%).
        let size: [Double]?
        /// A soft glow around each one (crystals, glowing mushrooms, lanterns), e.g. "#9FE8FF".
        let glow: String?
        /// A soft shadow on the ground under each one (trees, big rocks).
        let shadow: Bool?
        /// Sways gently in the breeze.
        let sway: Bool?
        /// Plant only within this many cells of the map's centre, inside a town's fence too
        /// (flower beds around the square). Otherwise props go anywhere free (in towns: the border).
        let within: Int?
    }

    nonisolated struct FairyRings: Decodable, Sendable {
        let count: Int
        let art: String
    }

    nonisolated struct Decor: Decodable, Sendable {
        let art: String
        let x: Int
        let y: Int
        let blocking: Bool?
    }

    /// Whimsy: floating particles, butterflies, cloud shadows and a colour mood.
    nonisolated struct Ambience: Decodable, Sendable {
        /// petals | leaves | fireflies | sparkles
        let particles: String?
        let butterflies: Int?
        let clouds: Bool?
        /// Hex colour laid over the map, e.g. "#3A2A6B".
        let tint: String?
        let tintAlpha: Double?
        let vignette: Double?
        /// Soft pools of light on the ground (dappled sunlight, moonlight). See `Lighting`.
        let lightPatches: Lights?
        /// Long soft sunbeams slanting across the map.
        let sunbeams: Lights?
        /// A big soft glow in the top corner of the screen, as if the sun were just out of view.
        let sun: String?
        /// Distance haze: the top of the screen fades toward this colour, by `hazeAlpha`.
        let haze: String?
        let hazeAlpha: Double?
        /// Out-of-focus scenery drifting past in front of the camera.
        let foreground: Foreground?

        nonisolated struct Lights: Decodable, Sendable {
            let color: String
            let count: Int
            /// Width range in points.
            let size: [Double]?
            let alpha: Double?
        }

        nonisolated struct Foreground: Decodable, Sendable {
            /// Sprites to blur, picked at random.
            let art: [String]
            let count: Int
            let alpha: Double?
            /// Blur radius in texture pixels, and how many times bigger than the sprite.
            let blur: Double?
            let scale: Double?
        }
    }

    nonisolated struct Exit: Decodable, Sendable {
        let edge: Edge
        let to: String
        /// A quest you must finish before this road opens.
        let requires: String?
    }

    nonisolated struct Building: Decodable, Sendable {
        let art: String
        let x: Int
        let y: Int
    }

    nonisolated struct Encounters: Decodable, Sendable {
        let rate: Double
        let graceSteps: Int
        let levels: [Int]
        let groupSize: [Int]
        let monsters: [String: Int]
    }

    let id: String
    let name: String
    let width: Int
    let height: Int
    let music: String?
    /// Song for random battles here (content/music.json); "battle" when unset.
    let battleMusic: String?
    let theme: Theme
    let fence: Bool?
    let exits: [Exit]
    let buildings: [Building]?
    let decor: [Decor]?
    let npcs: [NPCDef]?
    let encounters: Encounters?
    let ambience: Ambience?
    /// Background characters wandering the map (see content/crowd.json).
    let crowd: Crowd?
    /// A danger zone: adventurers can duel here, and some will pick a fight.
    let danger: Bool?
    /// Town planning: streets, a plaza, shops along the streets and raised terraces.
    let town: Town?

    nonisolated struct Town: Decodable, Sendable {
        /// Straight streets as [x1, y1, x2, y2] offsets from the centre.
        let streets: [[Int]]?
        /// Radius of the cobbled plaza in the middle.
        let plaza: Int?
        /// Buildings placed along the streets, in order.
        let lots: [String]?
        /// Street furniture: art id → how many.
        let streetDecor: [String: Int]?
        /// Raised stone terraces (layered walls with balustrades and stairs).
        let terraces: [Terrace]?
    }

    nonisolated struct Terrace: Decodable, Sendable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    nonisolated struct Crowd: Decodable, Sendable {
        let adventurers: Int?
        let villagers: Int?
    }
}

nonisolated struct SongDef: Decodable, Identifiable, Sendable {
    nonisolated struct Track: Decodable, Sendable {
        let wave: String
        let duty: Double?
        let volume: Double
        let notes: String
    }

    let id: String
    let title: String
    let tempo: Double
    let loops: Bool?
    let tracks: [Track]
}

/// A colour choice in the look customiser (content/appearance.json).
nonisolated struct LookPreset: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let swatch: String
    let recolor: [RecolorRule]
    /// A quest that unlocks this look.
    let unlock: String?
}

/// Names and chatter for the background characters (content/crowd.json).
nonisolated struct CrowdOptions: Decodable, Sendable {
    let adventurerNames: [String]
    let adventurerLines: [String]
    let villagerNames: [String]
    let villagerLines: [String]
    /// Answers when you say something in chat.
    let replies: [String]
    let companions: [String]
}

nonisolated struct AppearanceOptions: Decodable, Sendable {
    let hair: [LookPreset]
    let outfits: [LookPreset]
    let skin: [LookPreset]
}

// MARK: - Loading

private nonisolated struct ClassesFile: Decodable {
    let classChoiceLevel: Int
    let races: [RaceDef]
    let classes: [ClassDef]
}

private nonisolated struct SkillsFile: Decodable { let skills: [SkillDef] }
private nonisolated struct MonstersFile: Decodable { let monsters: [MonsterDef] }
private nonisolated struct ItemsFile: Decodable { let items: [ItemDef] }
private nonisolated struct QuestsFile: Decodable { let quests: [QuestDef] }
private nonisolated struct MapsFile: Decodable { let start: String; let maps: [MapDef] }
private nonisolated struct MusicFile: Decodable { let songs: [SongDef] }

/// All game data from the bundled content/ folder. Edit the JSON, rebuild, done.
final class Content {
    static let shared = Content()

    let classChoiceLevel: Int
    let races: [RaceDef]
    let classes: [ClassDef]
    let skills: [SkillDef]
    let monsters: [MonsterDef]
    let items: [ItemDef]
    let quests: [QuestDef]
    let maps: [MapDef]
    let startMap: String
    let songs: [SongDef]
    let appearance: AppearanceOptions
    let crowd: CrowdOptions

    init(bundle: Bundle = .main) {
        let classFile: ClassesFile = Self.load("classes", from: bundle)
        classChoiceLevel = classFile.classChoiceLevel
        races = classFile.races
        classes = classFile.classes
        skills = (Self.load("skills", from: bundle) as SkillsFile).skills
        monsters = (Self.load("monsters", from: bundle) as MonstersFile).monsters
        items = (Self.load("items", from: bundle) as ItemsFile).items
        quests = (Self.load("quests", from: bundle) as QuestsFile).quests
        let mapFile: MapsFile = Self.load("maps", from: bundle)
        maps = mapFile.maps
        startMap = mapFile.start
        songs = (Self.load("music", from: bundle) as MusicFile).songs
        appearance = Self.load("appearance", from: bundle)
        crowd = Self.load("crowd", from: bundle)
    }

    private static func load<T: Decodable>(_ name: String, from bundle: Bundle) -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "content") else {
            fatalError("content/\(name).json is missing from the app bundle")
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            fatalError("content/\(name).json couldn't be read: \(error)")
        }
    }

    func race(_ id: String) -> RaceDef { races.first { $0.id == id } ?? races[0] }
    func classDef(_ id: String) -> ClassDef { classes.first { $0.id == id } ?? classes[0] }
    func skill(_ id: String) -> SkillDef? { skills.first { $0.id == id } }
    func monster(_ id: String) -> MonsterDef? { monsters.first { $0.id == id } }
    func item(_ id: String) -> ItemDef? { items.first { $0.id == id } }
    func quest(_ id: String) -> QuestDef? { quests.first { $0.id == id } }
    func map(_ id: String) -> MapDef? { maps.first { $0.id == id } }
    func song(_ id: String) -> SongDef? { songs.first { $0.id == id } }

    func npc(_ id: String) -> NPCDef? {
        maps.lazy.compactMap { $0.npcs?.first { $0.id == id } }.first
    }
}

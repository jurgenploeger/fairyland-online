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

    /// Elements this one hits harder (×1.5), and the ones that hit it harder.
    var strongAgainst: [Element] { Element.allCases.filter { multiplier(against: $0) > 1 } }
    var weakTo: [Element] { Element.allCases.filter { $0.multiplier(against: self) > 1 } }
}

// MARK: - Definitions (one per JSON file in content/)

nonisolated struct RaceDef: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let base: Stats
    /// This race's walk sheet in art/assets.json.
    let art: String?
    /// Gender id → its own walk sheet; genders without one use `art`.
    let sheets: [String: String]?
    /// The hairstyle a hero of this race starts with (an AppearanceOptions `styles` id).
    let hair: String?

    var sheet: String { art ?? "player_walk" }

    func sheet(for gender: String?) -> String {
        gender.flatMap { sheets?[$0] } ?? sheet
    }
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
    /// `revive` wakes a fainted ally, `buff` raises strength and defense for a few turns, `curse`
    /// lays its `inflicts` on foes without hurting them (Curse, Poison), and `field` spells are cast
    /// from the Character screen outside battle (Bridge of Light).
    case physical, magic, heal, revive, buff, curse, field

    /// Hurts the other side with a hit.
    var isAttack: Bool { self == .physical || self == .magic }
    /// Aimed at the other side: an attack or a curse (what monsters and companions pick to fight with).
    var isHostile: Bool { isAttack || self == .curse }
}

/// What a skill leaves on the fighters it reaches, for a few rounds (`inflicts` in skills.json).
nonisolated struct Affliction: Decodable, Sendable {
    let effect: Ailment
    /// Poison: how many times it bites, at the end of the round it lands in and the ones after.
    /// Curse: how many rounds it lasts after the one it lands in.
    let rounds: Int
    /// Poison: each round's bite, as a share of a hit from the caster (magic for spells, strength
    /// for bites). Curse: how much weaker the target's own hits get (0.2 = 20%). Both grow with
    /// the skill's level, like its damage would.
    let power: Double
    /// The odds it takes hold (always, unless set).
    let chance: Double?
}

/// Fairyland's dark arts (the Acolyte of Dark's Curse and Poison): lingering harm, not a hit.
nonisolated enum Ailment: String, Decodable, Sendable {
    /// Loses HP at the end of every round.
    case poison
    /// Hits for less.
    case curse
}

nonisolated enum SkillTarget: String, Decodable, Sendable {
    case enemy, allEnemies, ally, allAllies
    /// A fainted fighter on your own side (Revive).
    case fallenAlly
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
    /// Its pixel-art icon (art/sprites/skill_<id>.png, drawn by tools/skill_art.py).
    let art: String?
    /// Spells: the share of damage that also hits the target's neighbours once mastered (level 10);
    /// 60% of that from level 5, growing each step, none below.
    let splash: Double?
    /// A poison or curse it leaves on whoever it reaches (not the splash).
    let inflicts: Affliction?
}

nonisolated struct MonsterDef: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let art: String
    let element: Element
    /// The Monster Book's entry, unlocked by meeting it in battle.
    let lore: String?
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
    /// Rare spoils, rolled every time it's beaten (bosses come back for rematches).
    let drops: [Drop]?

    nonisolated struct Drop: Decodable, Sendable {
        let item: String
        /// 0...1, rolled on each win.
        let chance: Double
    }

    func stats(at level: Int) -> Stats { base + growth * (level - 1) }
}

nonisolated enum ItemType: String, Decodable, Sendable {
    /// `material`: wood, metal, gems and hides that monsters drop, for the blacksmith.
    case consumable, weapon, armor, accessory, material

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
    /// Its sprite in art/assets.json (item_<id>, drawn by tools/item_art.py).
    let art: String?
    /// A GameIcon name for the bag and shops when there's no sprite.
    let icon: String?
    /// Seal Stones: thrown in battle to befriend a weakened monster.
    let capture: Bool?
    /// Armour: how it recolours the hero's outfit while worn (same rules as looks).
    let recolor: [RecolorRule]?
    /// Materials: wood | metal | gem | hide. Monsters of at least `level` drop them.
    let material: String?
    /// What a blacksmith needs to forge it: material id → how many.
    let recipe: [String: Int]?
    /// How it changes the hero's sprite (see GearOverlay): armour's cut (vest | mail | plate | robe |
    /// cloak), or "boots" for footwear.
    let wear: String?
    /// Finer work drawn on stronger armour: engraved | scales | fur | runes | pockets.
    let pattern: String?
    /// Whole walk sheets (art/sprites) per race id, worn instead of the paper-doll layers.
    let sheets: [String: String]?
    /// A rare colour variant's recolour of those sheets.
    let tint: [RecolorRule]?
    /// Trim colour on the sprite (buttons, clasps, hems) and an accessory's sparkle, "#RRGGBB".
    let accent: String?
    /// Magic weapons: a soft light while held, "#RRGGBB", centred on `glowAt` ([x, y] in the 32×32 art).
    let glow: String?
    let glowAt: [Double]?
}

nonisolated struct QuestDef: Decodable, Identifiable, Sendable {
    nonisolated enum ObjectiveType: String, Decodable, Sendable {
        case defeat, capture, reachLevel, chooseClass, collect, hatch
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
    /// `smith`: forges weapons from materials (the item's `recipe`).
    case healer, shop, quests, guild, chest, boss, smith
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
    /// Bosses: which monster, at what level, and how many of the map's own monsters fight at its
    /// side (2 unless set; 0 for none).
    let monster: String?
    let level: Int?
    let minions: Int?
    /// Bosses: what beating it means, told the first time you win (and kept in the Monster Book).
    let victory: Victory?
    /// Offers rebirth once you're strong enough (Elder Oak).
    let rebirth: Bool?

    nonisolated struct Victory: Decodable, Sendable {
        let title: String
        /// A few short paragraphs, shown one after another.
        let story: [String]
    }
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
        /// Caves are solid rock with tunnels and chambers dug out of it.
        let cave: Cave?
    }

    /// Solid rock everywhere except galleries along the roads and trails, chambers off them and
    /// dead-end tunnels, drawn as raised walls you walk between (and behind).
    nonisolated struct Cave: Decodable, Sendable {
        /// Tile for the tops and faces of the walls.
        let rock: String
        /// How tall the walls stand, in points (40 by default).
        let height: Double?
        /// Half-width of the galleries around roads and trails, in cells (3 by default; 0.5 or more).
        let width: Double?
        /// Extra chambers dug off the galleries.
        let chambers: Int?
        /// Dead-end tunnels branching off, for a bit of a maze.
        let branches: Int?
        /// Narrow zigzag passages linking parts of the cave.
        let zigzags: Int?
        /// A maze of narrow passages over the whole cave, with junctions about this many cells apart.
        let maze: Int?
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
        /// Floats gently up and down (magic lanterns, floating crystals).
        let bob: Bool?
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
        /// petals | leaves | fireflies | sparkles | snow | dust | motes | bubbles | dandelions | sprinkles |
        /// lanterns | zzz | notes, or several joined with "+".
        let particles: String?
        let butterflies: Int?
        /// Little animals living on the map that hop off when you come close. See `Critters`.
        let critters: [Critter]?
        /// A flock crossing the sky now and then: songbirds | gulls | bats.
        let birds: String?
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
        /// Depth of field on the map's own scenery (on by default). See `DepthOfField`.
        let focus: Focus?
        /// A dark map (a cave): you see only as far as your light reaches, and the minimap shows only
        /// what you've seen. See `Lantern`.
        let darkness: Darkness?

        nonisolated struct Critter: Decodable, Sendable {
            /// bunny | frog | crab
            let kind: String
            let count: Int
        }

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

        nonisolated struct Darkness: Decodable, Sendable {
            /// How far your light reaches, in points (default 190).
            let radius: Double?
            /// How dark it is beyond, 0...1 (default 0.9).
            let alpha: Double?
            /// The dark's colour (default "#03040A").
            let color: String?
            /// Your light's soft glow on the ground around you (none if unset).
            let light: String?
        }

        nonisolated struct Focus: Decodable, Sendable {
            /// Strongest blur in points, at the top of the screen (default 1.5; 0 turns it off).
            let blur: Double?
            /// Half-height of the sharp band around the hero, as a fraction of half the screen (default 0.4).
            let band: Double?
            /// How soft the bottom of the screen gets compared with the top (default 0.5).
            let near: Double?
        }
    }

    nonisolated struct Exit: Decodable, Sendable {
        let edge: Edge
        let to: String
        /// A quest you must finish before this road opens.
        let requires: String?
        /// Where along its edge the road leaves, in cells from the middle of the edge (east/north positive).
        let at: Int?
        /// Waypoints the road winds through on its way out, as [x, y] cell offsets from the centre.
        let via: [[Int]]?
    }

    /// A narrower path off the roads, to somewhere worth visiting (a boss's lair, an oasis).
    nonisolated struct Trail: Decodable, Sendable {
        /// [x, y] cell offsets from the centre. Starts at the hub unless `from` is set.
        let to: [Int]
        let from: [Int]?
        let via: [[Int]]?
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
    /// Where this place sits on the world map, in steps [east, north] from the start town.
    let world: [Int]?
    /// Where the roads meet, as an [x, y] cell offset from the centre (the centre by default).
    let hub: [Int]?
    let trails: [Trail]?
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
        /// An instrument from music.json "instruments" (or "drums").
        let instrument: String?
        /// Old chiptune tracks: square, triangle or noise.
        let wave: String?
        let duty: Double?
        let volume: Double
        /// -1 left ... 1 right.
        let pan: Double?
        /// How much of this track goes to the reverb (0...1, default 1).
        let reverb: Double?
        let notes: String
    }

    let id: String
    let title: String
    let tempo: Double
    let loops: Bool?
    /// The hall reverb's level for the whole song.
    let reverb: Double?
    let tracks: [Track]
}

/// An additive instrument (content/music.json "instruments"): sine partials, each
/// [frequency ratio, level, decay per second], plus envelope and colour.
nonisolated struct InstrumentDef: Decodable, Sendable {
    let id: String
    let partials: [[Double]]?
    /// Held notes (winds, strings) don't decay; struck ones do.
    let held: Bool?
    let attack: Double?
    let release: Double?
    /// [depth in semitones, rate in Hz, delay in seconds]
    let vibrato: [Double]?
    let voices: Int?
    /// Cents between the chorus voices.
    let detune: Double?
    let breath: Double?
    let click: Double?
    let gain: Double?
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

/// One entry in content/changelog.json, shown under "What's new" on the title screen.
nonisolated struct ReleaseNote: Decodable, Identifiable, Sendable {
    let version: String
    let date: String
    let title: String
    let notes: [String]
    var id: String { version }
}

nonisolated struct GenderOption: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
}

/// A hairstyle: art/sprites/hair_<id>_<race>.png, drawn over the bald body_<race>.png.
nonisolated struct HairStyle: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    /// A walk sheet's own hair (a gender's: a ponytail, braids), worn only on that sheet and the
    /// hair it starts with; nil for the styles anyone can wear.
    let sheet: String?
}

nonisolated struct AppearanceOptions: Decodable, Sendable {
    let genders: [GenderOption]
    let styles: [HairStyle]
    /// The window a hair preset's rules widen to on the hero's hair and locks layers, which hold
    /// nothing but hair (only `hue`, the saturations and the values are read).
    let hairLayer: RecolorRule?
    let hair: [LookPreset]
    let outfits: [LookPreset]
    let skin: [LookPreset]

    /// The hairstyles a walk sheet can wear: its own hair first, then the ones anyone can.
    func styles(for sheet: String) -> [HairStyle] {
        styles.filter { $0.sheet == sheet } + styles.filter { $0.sheet == nil }
    }
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
private nonisolated struct MusicFile: Decodable { let songs: [SongDef]; let instruments: [InstrumentDef]? }
private nonisolated struct ChangelogFile: Decodable { let releases: [ReleaseNote] }

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
    let instruments: [InstrumentDef]
    let appearance: AppearanceOptions
    let crowd: CrowdOptions
    /// Newest first.
    let releases: [ReleaseNote]

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
        let musicFile: MusicFile = Self.load("music", from: bundle)
        songs = musicFile.songs
        instruments = musicFile.instruments ?? []
        appearance = Self.load("appearance", from: bundle)
        crowd = Self.load("crowd", from: bundle)
        releases = (Self.load("changelog", from: bundle) as ChangelogFile).releases
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

    /// The boss that fights as this monster, if it's one.
    func boss(fighting monsterID: String) -> NPCDef? {
        maps.lazy.compactMap { $0.npcs?.first { $0.role == .boss && $0.monster == monsterID } }.first
    }

    /// The map a character lives on.
    func home(ofNPC id: String) -> MapDef? {
        maps.first { $0.npcs?.contains { $0.id == id } == true }
    }
}

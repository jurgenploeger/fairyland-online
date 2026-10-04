import Foundation

/// Debug-only shortcuts for testing, via the FAIRYLAND_DEBUG environment variable
/// (Xcode: Product → Scheme → Edit Scheme → Run → Environment Variables), comma-separated:
///
///   newgame        skip the title screen with a fresh hero
///   level=5        start at a level
///   levelup        start one EXP short of the next level
///   hp=0.2         start with this fraction of HP left
///   map=<id>       start on a map from content/maps.json
///   at=x_y         start at this offset from the map's centre (e.g. at=0_14)
///   equip=a+b      start wearing these items (ids from content/items.json, joined with +)
///   bag=a+b        put these items in the bag
///   pet=<species>  a companion of that species (content/monsters.json), out with you
///   friends=n      that many friends (up to GameSession.maxAllies) travelling in your party
///   unfold         the top-left HUD shows a big party in full instead of folded into one row
///   change=<slot>  open the Character tab's list for weapon | armor | accessory (with menu=character)
///   customize      open the Character tab's look editor (with menu=character)
///   race=<id>      play this race (content/classes.json)
///   style=<id>     wear this hairstyle (content/appearance.json `styles`)
///   hair=<id>      dye the hair this colour (content/appearance.json `hair`)
///   gender=<id>    male | female | other (picks the race's matching sheet)
///   battle[=n]     start in a random battle on the current map (n: exactly that many monsters)
///   win            with battle, duel or boss: the foes fall at once and the victory plays out
///   duel           start in a duel with an adventurer of your level (with win: their dropped goods)
///   boss=<npc>     once the map is on screen, fight that boss (as if you'd pressed Fight)
///   wave=<n>       with boss: the fight opens at that wave (3: the boss's own)
///   orders         with battle: the hero picks Attack on the first monster, so your companion's turn shows
///   afflict        with battle: the first monster poisoned, the next one cursed, and the hero poisoned
///   cast=<skill>[:n]  with battle: once everyone is in, the hero casts that skill (at skill level n)
///   fxstop=<s>     with cast: the battle slows right down and freezes s seconds into the cast
///   turntimer=<s>  battles give you s seconds to choose before you attack (none otherwise in debug)
///   menu=<tab>     open character | companions | bag | quests
///   bottom         open the menu scrolled to the end
///   npc=<id>       open an NPC dialog
///   info=<item>    with npc=<a shop>: open that item's info card
///   worldmap       open the world map
///   book           open the Monster Book, with the first 24 monsters already met
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
    /// `turntimer=40`: battles give you that many seconds to choose (debug launches have no clock
    /// otherwise, so screenshots can wait in a battle).
    static var turnSeconds: TimeInterval? { flags["turntimer"].flatMap(Double.init) }
    /// `wave=3`: a boss fight opens at that wave, skipping the ones before.
    static var bossWave: Int? { flags["wave"].flatMap { Int($0) } }
    /// `arrange`: battles open with the buttons already wiggling, ready to rearrange.
    static var arrangesButtons: Bool { flags["arrange"] != nil }

    /// A debug game (tests, screenshots): the first-play tour stays hidden unless `coach` is set.
    static var isActive: Bool { flags["newgame"] != nil }

    /// Debug launches leave `Documents/debug-ready` once the map or battle is on screen, so
    /// tools/screenshots.sh knows when to shoot (the loading curtain alone can look "drawn").
    static func markReady() {
        guard isActive, let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? Data().write(to: folder.appending(path: "debug-ready"))
    }
    static var showsCoachMarks: Bool { flags["coach"] != nil }
    static var opensMonsterBook: Bool { flags["book"] != nil }
    /// `change=armor`: the Character tab opens with that slot's list of things to wear.
    static var changingSlot: ItemType? { flags["change"].flatMap(ItemType.init(rawValue:)) }
    static var opensMenuAtBottom: Bool { flags["bottom"] != nil }
    static var opensCustomize: Bool { flags["customize"] != nil }
    /// `info=iron_axe`: the shop's info card for that item opens with the dialog.
    static var itemInfo: ItemDef? { flags["info"].flatMap { Content.shared.item($0) } }
    /// `intro` or `intro=<page>` opens the title screen's story pages (1 = the story).
    static var introPage: Int? { flags["intro"].map { Int($0).map { $0 - 1 } ?? 0 } }

    static func session() -> GameSession? {
        let flags = flags
        guard flags["newgame"] != nil else { return nil }
        SaveStore.fileName = "fairyland-debug-save.json"
        let session = GameSession.newGame(name: "Hero", raceID: flags["race"] ?? "human")
        if let level = flags["level"].flatMap(Int.init), level > 1 {
            session.data.hero.level = level
            session.restoreHero()
        }
        if flags["levelup"] != nil {
            session.data.hero.exp = GameSession.expToNext(level: session.data.hero.level) - 1
        }
        if let fraction = flags["hp"].flatMap(Double.init) {
            session.data.hero.hp = max(1, Int(Double(session.heroStats.hp) * fraction))
        }
        if let map = flags["map"], Content.shared.map(map) != nil {
            session.data.mapID = map
        }
        if flags["book"] != nil {
            for (index, monster) in Content.shared.monsters.prefix(24).enumerated() {
                session.sawMonster(monster.id, level: 3 + index)
            }
        }
        for id in flags["equip"]?.split(separator: "+").map(String.init) ?? [] {
            if let item = Content.shared.item(id), ItemType.equipmentSlots.contains(item.type) {
                session.data.hero.equipment[item.type] = id
            }
        }
        for id in flags["bag"]?.split(separator: "+").map(String.init) ?? [] where Content.shared.item(id) != nil {
            session.addItem(id)
        }
        if let species = flags["pet"], let pet = session.makePet(species: species, level: max(1, session.data.hero.level - 15)) {
            session.addPet(pet, countsForQuests: false)
            session.data.activePetID = pet.id
        }
        if let count = flags["friends"].flatMap({ Int($0) }) {
            // Most bring a companion, as friends do.
            let people: [(name: String, race: String, classID: String, pet: String?)] = [
                ("Dumpling", "human", "fighter", "jelly"), ("Sprout", "elf", "mage", nil),
                ("Clover", "dwarf", "tamer", "bunny"), ("Maple", "human", "mage", "hedgehog"),
            ]
            let friends = people.prefix(min(count, GameSession.maxAllies)).map { person in
                Adventurer(name: person.name, raceID: person.race, classID: person.classID, level: session.data.hero.level,
                           look: .standard, petSpecies: person.pet)
            }
            session.data.friends = (session.data.friends ?? []) + friends
            session.data.partyIDs = (session.data.partyIDs ?? []) + friends.map(\.id)
        }
        if flags["unfold"] != nil {
            UserDefaults.standard.set(false, forKey: GameSettings.partyFoldedKey)
        }
        if let style = flags["style"] {
            var look = session.data.hero.look ?? .standard
            look.style = style
            session.data.hero.look = look
        }
        if let gender = flags["gender"] {
            var look = session.data.hero.look ?? .standard
            look.gender = gender
            session.data.hero.look = look
        }
        if let hair = flags["hair"] {
            var look = session.data.hero.look ?? .standard
            look.hair = hair
            session.data.hero.look = look
        }
        session.applyLook()
        // `class=fighter`, and `pin=bash+power_strike` learns those skills and pins them to the battle bar.
        if let classID = flags["class"] {
            session.data.hero.classID = classID
        }
        let pins = flags["pin"]?.split(separator: "+").map(String.init) ?? []
        if !pins.isEmpty {
            session.data.hero.learnedSkills = (session.data.hero.learnedSkills ?? []) + pins
            session.data.pinnedSkills = pins
        }
        if let at = flags["at"]?.split(separator: ";").first ?? flags["at"].map({ Substring($0) }),
           let def = Content.shared.map(session.data.mapID) {
            let parts = at.split(separator: "_").compactMap { Int($0) }
            if parts.count == 2 {
                let grid = WorldMap(def: def)
                session.playerPosition = grid.center(of: grid.offset(parts[0], parts[1]))
            }
        }
        return session
    }

    static func apply(to coordinator: GameCoordinator) {
        let flags = flags
        if flags["battle"] != nil {
            let encounters = Content.shared.map(coordinator.session.data.mapID)?.encounters
                ?? Content.shared.maps.compactMap(\.encounters).first
            // battle=8: exactly that many monsters (to check big formations).
            if let encounters, let count = flags["battle"].flatMap({ Int($0) }) {
                coordinator.startBattle(MapDef.Encounters(rate: encounters.rate, graceSteps: encounters.graceSteps,
                                                          levels: encounters.levels, groupSize: [count, count],
                                                          monsters: encounters.monsters))
            } else if let encounters {
                coordinator.startBattle(encounters)
            }
            #if DEBUG
            // `win`: once everyone has marched in, the monsters fall and the victory plays out.
            if flags["win"] != nil, let battle = coordinator.battle {
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    battle.winForDebug()
                }
            }
            // `orders`: the hero goes for the first monster, and it's your companion's turn.
            if flags["orders"] != nil, let battle = coordinator.battle {
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    battle.attack()
                    if let first = battle.enemies.first(where: \.isAlive) { battle.select(first.id) }
                }
            }
            // `afflict`: poison and a curse on the field, so their marks show.
            if flags["afflict"] != nil, let battle = coordinator.battle {
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    battle.afflictForDebug()
                }
            }
            // `cast=stone_spike:5`: once the battle is on screen and everyone is in, the hero casts.
            if let cast = flags["cast"], let skillID = cast.split(separator: ":").first.map(String.init),
               let battle = coordinator.battle {
                let level = cast.split(separator: ":").dropFirst().first.flatMap { Int($0) } ?? 1
                let stop = flags["fxstop"].flatMap(Double.init)
                Task {
                    for _ in 0..<240 {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard let scene = battle.scene, scene.view != nil else { continue }
                        try? await Task.sleep(for: .seconds(2))
                        scene.castForDebug(skillID, level: level, stopAt: stop)
                        return
                    }
                }
            }
            #endif
        }
        #if DEBUG
        if let id = flags["boss"], let npc = Content.shared.npc(id) {
            Task {
                for _ in 0..<240 {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard coordinator.isReady, coordinator.world.view != nil else { continue }
                    try? await Task.sleep(for: .seconds(1))
                    coordinator.fightBoss(npc)
                    // With `win`: the boss and its minions fall, and the first win's story is told.
                    if flags["win"] != nil, let battle = coordinator.battle {
                        try? await Task.sleep(for: .seconds(2))
                        battle.winForDebug()
                    }
                    return
                }
            }
        }
        if flags["duel"] != nil {
            let level = coordinator.session.data.hero.level
            coordinator.duelForDebug(Adventurer(name: "Hazel", raceID: "elf", classID: "tamer", level: level, look: .standard))
            if flags["win"] != nil, let battle = coordinator.battle {
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    battle.winForDebug()
                }
            }
        }
        #endif
        if let tab = flags["menu"].flatMap({ MenuTab(rawValue: $0.capitalized) }) {
            coordinator.open(.menu(tab))
        }
        if let npc = flags["npc"] {
            coordinator.open(.npc(npc))
        }
        if flags["book"] != nil {
            coordinator.open(.menu(.companions))
        }
        if flags["worldmap"] != nil {
            coordinator.open(.worldMap)
        }
    }
}

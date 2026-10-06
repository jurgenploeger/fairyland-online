import Foundation
import SpriteKit

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
///   away=n         with friends: the first n of them wait for you a few steps east of where you start
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
///   invite=n       once the map is on screen, the n nearest adventurers come over, become friends
///                  and join your party, through the same steps as their card's buttons
///   wave=<n>       with boss: the fight opens at that wave (3: the boss's own)
///   orders         with battle: the hero picks Attack on the first monster, so your companion's turn shows
///   afflict        with battle: the first monster poisoned, the next one cursed, and the hero poisoned
///   herodown       with battle: the hero faints at once, and any friends fight on without them
///   cast=<skill>[:n]  with battle: once everyone is in, the hero casts that skill (at skill level n)
///   fxstop=<s>     with cast: the battle slows right down and freezes s seconds into the cast
///   turntimer=<s>  battles give you s seconds to choose before you attack (none otherwise in debug)
///   auto           battles start on Auto where it's allowed (monsters well below you)
///   fast           battles play at 2×
///   mod            moderator mode (a MOD tag, and the chat's World channel) for this launch only
///   announce       once the map is on screen: a rare sighting, news of another adventurer and, with mod,
///                  a World message (with chat: then the chat opens)
///   chat           open the chat window
///   menu=<tab>     open character | companions | bag | quests
///   profile=<who>  open someone's stats: hero | pet (with pet=) | friend (with friends=)
///   bottom         open the menu scrolled to the end
///   npc=<id>       open an NPC dialog
///   info=<item>    with npc=<a shop>: open that item's info card
///   worldmap       open the world map
///   book           open the Monster Book, with the first 24 monsters already met
///   landscape      lock the app to landscape
///   clean          no frame counter in the corner (App Store screenshots; tools/screenshots.sh also
///                  leaves out the Dynamic Island's black mask)
///   nohud          the map without its HUD (App Store slides of the world)
///   hour=<h>       the calendar starts at that hour of the day (0-23: 21 for night, 18 for dusk)
///   weather=<kind> every map with a sky has this weather (clear | cloudy | rain | storm | fog | snow)
///   lang=<code>    play in this language (content/i18n/languages.json), without changing the saved choice
///   intro[=page]   open the title screen's story pages at that page (1 = the story, 4 = how to play)
///   clip=<n>       with intro=4: How to play's picture starts at that part (0 walk … 4 town), and
///                  marks debug-ready as it does
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
    /// `mod`: moderator mode for this launch, without touching the saved setting.
    static var isModerator: Bool { flags["mod"] != nil }

    /// A debug game (tests, screenshots): the first-play tour stays hidden unless `coach` is set.
    static var isActive: Bool { flags["newgame"] != nil }

    /// Debug launches leave `Documents/debug-ready` once the map or battle is on screen (or How to
    /// play's part, with `clip`), so tools/screenshots.sh knows when to shoot (the loading curtain
    /// alone can look "drawn").
    static func markReady() {
        guard isActive || introClip != nil, let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? Data().write(to: folder.appending(path: "debug-ready"))
    }
    static var showsCoachMarks: Bool { flags["coach"] != nil }
    /// `demo`: filmed for the App Store preview, so no frame counter in the corner.
    static var isFilming: Bool { flags["demo"] != nil }
    /// `clean`: no frame counter in the corner either, for App Store screenshots.
    static var hidesFrameCounter: Bool { isFilming || flags["clean"] != nil }
    /// `nohud`: the map on its own, without the HUD over it (App Store slides of the world).
    static var hidesHUD: Bool { flags["nohud"] != nil }
    static var opensMonsterBook: Bool { flags["book"] != nil }
    /// `change=armor`: the Character tab opens with that slot's list of things to wear.
    static var changingSlot: ItemType? { flags["change"].flatMap(ItemType.init(rawValue:)) }
    static var opensMenuAtBottom: Bool { flags["bottom"] != nil }
    static var opensCustomize: Bool { flags["customize"] != nil }
    /// `info=iron_axe`: the shop's info card for that item opens with the dialog.
    static var itemInfo: ItemDef? { flags["info"].flatMap { Content.shared.item($0) } }
    /// `intro` or `intro=<page>` opens the title screen's story pages (1 = the story).
    static var introPage: Int? { flags["intro"].map { Int($0).map { $0 - 1 } ?? 0 } }
    /// `clip=<n>`: How to play's picture starts at that part (0 walk, 1 battle, 2 seal, 3 victory, 4 town).
    static var introClip: Int? { flags["clip"].flatMap { Int($0) } }

    /// `battle[=n]` once the map is up: a fight on the current map (exactly n monsters), and the
    /// flags that act on it.
    private static func startBattle(on coordinator: GameCoordinator, flags: [String: String], backdrop: SKTexture?) {
        let encounters = Content.shared.map(coordinator.session.data.mapID)?.encounters
            ?? Content.shared.maps.compactMap(\.encounters).first
        // battle=8: exactly that many monsters (to check big formations).
        if let encounters, let count = flags["battle"].flatMap({ Int($0) }) {
            coordinator.startBattle(MapDef.Encounters(rate: encounters.rate, graceSteps: encounters.graceSteps,
                                                      levels: encounters.levels, groupSize: [count, count],
                                                      monsters: encounters.monsters), backdrop: backdrop)
        } else if let encounters {
            coordinator.startBattle(encounters, backdrop: backdrop)
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
        // `herodown`: once everyone has marched in, the hero faints and the friends fight on.
        if flags["herodown"] != nil, let battle = coordinator.battle {
            Task {
                try? await Task.sleep(for: .seconds(2))
                battle.knockOutHeroForDebug()
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
        // `seal=ok` or `seal=fail`: once everyone is in, the hero seals the first monster (just the
        // animation, frozen at `fxstop` like a cast).
        if let seal = flags["seal"], let battle = coordinator.battle {
            let stop = flags["fxstop"].flatMap(Double.init)
            Task {
                for _ in 0..<240 {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let scene = battle.scene, scene.view != nil else { continue }
                    try? await Task.sleep(for: .seconds(2))
                    scene.sealForDebug(success: seal != "fail", stopAt: stop)
                    return
                }
            }
        }
        #endif
    }

    #if DEBUG
    /// `demo`: a stretch of play as a player would play it, for the App Store video
    /// (tools/screenshots.sh records it with `record=`): a stroll with the stick, a monster
    /// encounter, a spell and some blows, a Seal Stone on the last monster when it's weak enough,
    /// the victory, and on along the road.
    private static func playDemo(on coordinator: GameCoordinator) {
        Task {
            func pause(_ seconds: Double) async { try? await Task.sleep(for: .milliseconds(Int(seconds * 1000))) }
            for _ in 0..<240 {
                if coordinator.isReady, coordinator.world.view != nil { break }
                await pause(0.25)
            }
            // tools/screenshots.sh starts filming a few seconds after the map is up, so wait for it.
            await pause(5)
            // A quest giver first, when one stands nearby (the scene starts you beside them): talk as
            // the talk button does, read their offer, and head off.
            // The demo picks its own moment for a fight, so no monster cuts in on the way.
            coordinator.world.holdsEncounters = true
            coordinator.input.move = CGVector(dx: 1, dy: 0)
            for _ in 0..<10 where coordinator.session.nearbyNPC == nil { await pause(0.2) }
            coordinator.input.move = .zero
            await pause(0.4)
            if coordinator.session.nearbyNPC != nil {
                for _ in 0..<6 where coordinator.overlay == nil {
                    coordinator.talkToNearby()
                    await pause(0.5)
                }
                await pause(4)
                coordinator.closeOverlay()
                await pause(0.8)
            }
            let stroll: [(CGVector, Double)] = [
                (CGVector(dx: 0.9, dy: 0.35), 1.6), (CGVector(dx: 0.25, dy: 1), 1.3),
                (CGVector(dx: -0.8, dy: 0.55), 1.2), (CGVector(dx: 0.7, dy: -0.4), 1.0),
            ]
            for (move, seconds) in stroll {
                coordinator.input.move = move
                await pause(seconds)
            }
            coordinator.input.move = .zero
            await pause(0.5)
            coordinator.world.encounterForDebug()
            for _ in 0..<40 where coordinator.battle == nil { await pause(0.25) }
            guard let battle = coordinator.battle else { return }
            // Everyone marches in.
            await pause(2.5)
            var turns = 0
            var casts = 0
            while battle.result == nil, turns < 40 {
                guard battle.phase == .command else {
                    await pause(0.3)
                    continue
                }
                turns += 1
                await pause(0.8)
                let foes = battle.enemies.filter(\.isAlive)
                guard let foe = foes.min(by: { $0.hp < $1.hp }) else { continue }
                if battle.choosingForCompanion {
                    battle.attack()
                } else if battle.canCapture {
                    battle.capture()
                } else if let hero = battle.combatants.first(where: \.isHero),
                          case let spells = battle.skills.filter({ [.enemy, .allEnemies].contains($0.target) && battle.cost(of: $0) <= hero.mp }),
                          !spells.isEmpty, foes.count > 1 || foe.hp > foe.stats.hp / 2 {
                    // Take turns with the spells you have, so the video shows more than one.
                    battle.openSkills()
                    await pause(0.7)
                    battle.useSkill(spells[casts % spells.count])
                    casts += 1
                } else {
                    battle.attack()
                }
                await pause(0.6)
                battle.select(foe.id)
            }
            // The rewards, then back to the map.
            await pause(4)
            battle.leave()
            for _ in 0..<40 where coordinator.battle != nil { await pause(0.25) }
            await pause(1)
            coordinator.input.move = CGVector(dx: 0.8, dy: 0.5)
            await pause(2.5)
            coordinator.input.move = .zero
        }
    }
    #endif

    /// `lang=de`: the game speaks that language for this launch (title screen included).
    static func applyLanguage() {
        if let code = flags["lang"] { Localizer.shared.choose(code, remember: false) }
    }

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
        if let hour = flags["hour"].flatMap({ Int($0) }), (0..<24).contains(hour) {
            // The calendar opens at 9hr (`GameClock.hours`), an in-game hour to the real minute.
            session.data.startedAt = Date().addingTimeInterval(-Double((hour - 9 + 24) % 24) * 60)
        }
        Weather.forced = flags["weather"].flatMap(Weather.init(rawValue:))
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
        if flags["auto"] != nil {
            UserDefaults.standard.set(true, forKey: GameSettings.autoBattleKey)
        }
        if flags["fast"] != nil {
            UserDefaults.standard.set(2.0, forKey: GameSettings.battleSpeedKey)
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
        // `away=1`: friends waiting for you to come back for them, a few steps east of you.
        if let count = flags["away"].flatMap({ Int($0) }), let def = Content.shared.map(session.data.mapID) {
            let grid = WorldMap(def: def)
            let start = session.playerPosition ?? grid.center(of: grid.center)
            for friend in session.partyMembers.prefix(count) {
                guard let index = session.data.friends?.firstIndex(where: { $0.id == friend.id }) else { continue }
                session.data.friends?[index].waitingAt = Spot(mapID: def.id, position: [Double(start.x) + 160, Double(start.y) + 20])
            }
        }
        return session
    }

    static func apply(to coordinator: GameCoordinator) {
        let flags = flags
        if flags["battle"] != nil {
            // Like a real encounter, the fight starts once the map is on screen, over the spot
            // you're standing on (WorldScene.battleBackdrop), not on plain grass.
            Task {
                for _ in 0..<240 {
                    if coordinator.isReady, coordinator.world.view != nil { break }
                    try? await Task.sleep(for: .milliseconds(250))
                }
                startBattle(on: coordinator, flags: flags, backdrop: coordinator.world.battleBackdrop())
            }
        }
        #if DEBUG
        if flags["demo"] != nil { playDemo(on: coordinator) }
        #endif
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
        // `invite=1`: like walking up to the nearest adventurers and pressing Befriend, then Invite.
        if let count = flags["invite"].flatMap({ Int($0) }) {
            Task {
                for _ in 0..<240 {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard coordinator.isReady, coordinator.world.view != nil else { continue }
                    try? await Task.sleep(for: .seconds(1))
                    let newcomers = coordinator.world.summonAdventurersForDebug(count)
                    // The map notes who's around every 0.4 s; inviting needs them counted.
                    try? await Task.sleep(for: .seconds(1))
                    for adventurer in newcomers {
                        coordinator.befriend(adventurer)
                        try? await Task.sleep(for: .seconds(1))
                        coordinator.invite(adventurer)
                        try? await Task.sleep(for: .seconds(1))
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
        // `announce`: once the map is on screen, a few notices (and the chat, with `chat`).
        if flags["announce"] != nil {
            Task {
                for _ in 0..<240 {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard coordinator.isReady else { continue }
                    coordinator.announcer.showOffForDebug()
                    // A moderator's World message, which adventurers about answer.
                    if coordinator.session.isModerator {
                        coordinator.broadcast("Welcome to Storyleaf! Be kind, and have fun out there.")
                    }
                    if flags["chat"] != nil { coordinator.open(.chat) }
                    return
                }
            }
        } else if flags["chat"] != nil {
            coordinator.open(.chat)
        }
        if let tab = flags["menu"].flatMap({ MenuTab(rawValue: $0.capitalized) }) {
            coordinator.open(.menu(tab))
        }
        if let npc = flags["npc"] {
            coordinator.open(.npc(npc))
        }
        if let who = flags["profile"] {
            let session = coordinator.session
            let profile: Profile? = switch who {
            case "pet": session.activePet.map { .pet($0.id) }
            case "friend": session.partyMembers.first.map { .adventurer($0) }
            default: .hero
            }
            if let profile { coordinator.open(.profile(profile)) }
        }
        if flags["book"] != nil {
            coordinator.open(.menu(.companions))
        }
        if flags["worldmap"] != nil {
            coordinator.open(.worldMap)
        }
    }
}

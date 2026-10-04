import Foundation
import Observation

struct BattleResult {
    let outcome: BattleOutcome
    let lines: [String]
    /// The hero's new level, if they levelled up (the result screen then offers skill choices).
    var newLevel: Int?
    /// The pay: EXP, gold, and what was found (item id and how many), shown as icons.
    var exp = 0
    var gold = 0
    var loot: [(id: String, count: Int)] = []
    /// How many levels the win was worth (the level-up banner adds up what they raised).
    var levelsGained = 0
    /// Friends and your companion who went up a level with the win.
    var others: [LevelUp] = []
    /// A boss beaten for the first time: what it means, told before the pay.
    var story: BossStory?
}

/// Someone else in the party who went up a level with a win: a friend or your companion.
struct LevelUp {
    let name: String
    let level: Int
    /// What the log says about it.
    let line: String
    /// Their fighter, to celebrate on the field (nil when they weren't standing at the end).
    let fighterID: Int?
}

/// A boss's `victory` story (content/maps.json), with the boss to draw above it.
struct BossStory {
    let art: String
    let title: String
    let paragraphs: [String]
}

/// Runs one battle: turns the player's menu choices into engine actions, feeds the
/// resulting events to the scene for animation, and pays out rewards at the end.
@Observable
final class BattleController {
    enum Phase: Equatable {
        case command, skills, items, target, animating, finished
    }

    private enum Pending {
        case attack, skill(SkillDef), item(ItemDef), capture
    }

    private(set) var phase: Phase = .command
    private(set) var message: String
    /// Display copy of the fighters; updates event by event as the scene animates.
    private(set) var combatants: [Combatant]
    private(set) var prompt = ""
    private(set) var validTargets: [Int] = []
    private(set) var result: BattleResult?
    /// A boss fight comes in waves: the one on the field, out of how many (1 of 1 otherwise).
    private(set) var wave = 1
    let waveCount: Int

    let session: GameSession
    /// What plays during the fight: the map's battle theme, or the boss theme.
    @ObservationIgnored var music: String
    @ObservationIgnored weak var scene: BattleScene?
    @ObservationIgnored var onFinish: (@MainActor (BattleOutcome) -> Void)?
    private let engine: BattleEngine
    @ObservationIgnored private var pending: Pending?
    /// The adventurer you're duelling: beaten, they drop what they carry.
    @ObservationIgnored private var rival: Adventurer?
    /// A boss you've never beaten: winning tells its story.
    @ObservationIgnored private var story: BossStory?

    init(engine: BattleEngine, session: GameSession, intro: String? = nil) {
        self.engine = engine
        self.session = session
        wave = engine.wave
        waveCount = engine.waveCount
        // Like Fairyland Online, a foe 5+ levels above you gets the tougher battle theme.
        let toughest = engine.alive(on: .enemies).map(\.level).max() ?? 0
        music = toughest >= session.data.hero.level + 5
            ? "battle_dark"
            : session.content.map(session.data.mapID)?.battleMusic ?? "battle"
        combatants = engine.combatants
        let names = engine.alive(on: .enemies).map(\.name)
        message = intro ?? (names.count == 1 ? "A wild \(names[0]) appears!" : "\(names.count) monsters appear!")
        if let rare = engine.alive(on: .enemies).first(where: \.isRare) {
            message += " ✦ A rare \(rare.name)!"
        }
        for foe in engine.alive(on: .enemies) {
            if let id = foe.speciesID { session.sawMonster(id, level: foe.level) }
        }
    }

    /// You, your companion and the friends in your party who are at your side.
    private static func party(for session: GameSession) -> [Combatant] {
        var hero = Combatant(
            id: 0, side: .party, source: .hero, name: session.data.hero.name, art: GameSession.heroArt,
            level: session.data.hero.level, element: .neutral, stats: session.heroStats,
            hp: max(1, session.data.hero.hp), mp: session.data.hero.mp,
            skills: session.heroSkills.map(\.id), captureRate: 0
        )
        hero.skillLevels = Dictionary(uniqueKeysWithValues: session.heroSkills.map { ($0.id, session.skillLevel($0.id)) })
        hero.classID = session.data.hero.classID
        hero.raceID = session.data.hero.raceID
        var party: [Combatant] = [hero]
        if let pet = session.activePet, pet.hp > 0, let species = session.species(of: pet) {
            var companion = Combatant(
                id: 1, side: .party, source: .pet(pet.id), name: pet.name, art: session.artID(for: pet),
                level: pet.level, element: species.element, stats: session.stats(of: pet),
                hp: pet.hp, mp: pet.mp, skills: species.skills, captureRate: 0
            )
            // It stands right behind you.
            companion.ownerID = hero.id
            party.append(companion)
        }
        for (index, friend) in session.friendsAtYourSide.enumerated() {
            party.append(adventurer(friend, id: 2 + index, side: .party, session: session))
            // A friend's companion fights behind them (a step below their level, like a rival's),
            // named for its owner so it's never mistaken for yours.
            if let speciesID = friend.petSpecies, let species = session.content.monster(speciesID) {
                let level = max(1, friend.level - 1)
                let stats = species.stats(at: level)
                var companion = Combatant(
                    id: 2 + GameSession.maxAllies + index, side: .party, source: .pet(UUID()), name: "\(friend.name)'s \(species.name)", art: species.art,
                    level: level, element: species.element, stats: stats, hp: stats.hp, mp: stats.mp, skills: species.skills, captureRate: 0
                )
                companion.ownerID = 2 + index
                party.append(companion)
            }
        }
        return party
    }

    /// An adventurer as a fighter, at full strength.
    private static func adventurer(_ person: Adventurer, id: Int, side: BattleSide, session: GameSession) -> Combatant {
        let stats = session.stats(of: person)
        let skills = session.skills(of: person)
        var fighter = Combatant(
            id: id, side: side, source: side == .party ? .ally(person.id) : .rival(person.id), name: person.name,
            art: session.artID(for: person), level: person.level, element: .neutral, stats: stats,
            hp: stats.hp, mp: stats.mp, skills: skills.map(\.id), captureRate: 0
        )
        fighter.skillLevels = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, Combatant.naturalSkillLevel(for: person.level)) })
        fighter.classID = person.classID
        fighter.raceID = person.raceID
        return fighter
    }

    /// The adventurer a fighter is: a friend at your side or the rival you're duelling (not their
    /// companions, who come from the same person).
    func person(behind fighter: Combatant) -> Adventurer? {
        guard fighter.art.hasPrefix("adv:") else { return nil }
        switch fighter.source {
        case .ally(let id): return session.friends.first { $0.id == id }
        case .rival(let id): return rival?.id == id ? rival : nil
        default: return nil
        }
    }

    /// A duel with another adventurer (and their companion) in a danger zone.
    static func duel(with rival: Adventurer, session: GameSession) -> BattleController {
        var enemies = [adventurer(rival, id: 10, side: .enemies, session: session)]
        if let speciesID = rival.petSpecies, let species = session.content.monster(speciesID) {
            let level = max(1, rival.level - 1)
            let stats = species.stats(at: level)
            var companion = Combatant(
                id: 11, side: .enemies, source: .rival(rival.id), name: "\(rival.name)'s \(species.name)", art: species.art,
                level: level, element: species.element, stats: stats, hp: stats.hp, mp: stats.mp, skills: species.skills, captureRate: 0
            )
            companion.ownerID = 10
            enemies.append(companion)
        }
        let engine = BattleEngine(party: party(for: session), enemies: enemies, content: session.content)
        let intro = rival.hostile ? "\(rival.name) picks a fight with you!" : "You challenge \(rival.name) to a duel!"
        let controller = BattleController(engine: engine, session: session, intro: intro)
        controller.rival = rival
        return controller
    }

    /// A boss waiting on the map. The fight comes in waves (`waves` on the NPC, 3 unless it says
    /// otherwise): first waves of `waveSize` of the map's own monsters, then the boss with its
    /// minions (`minions`, enough to make `waveSize` unless set), standing in front. Each wave is a little stronger than the
    /// one before, and the boss outranks them all. Your HP and MP carry from wave to wave.
    static func boss(_ npc: NPCDef, encounters: MapDef.Encounters? = nil, session: GameSession) -> BattleController? {
        guard let id = npc.monster, let species = session.content.monster(id),
              var waves = bossWaves(npc, encounters: encounters, session: session), !waves.isEmpty else { return nil }
        // Debug launches (`wave=n`, screenshots): the fight opens at that wave.
        if let start = DebugLaunch.bossWave, start > 1 { waves.removeFirst(min(start - 1, waves.count - 1)) }
        let engine = BattleEngine(party: party(for: session), enemies: waves[0], content: session.content,
                                  captureBonus: session.heroClass.captureBonus ?? 1, waves: Array(waves.dropFirst()))
        let intro = if engine.waveCount > 1 && engine.wave < engine.waveCount {
            "\(species.name) sends its followers! Wave \(engine.wave) of \(engine.waveCount)."
        } else if engine.waveCount > 1 {
            "Final wave: \(species.name) steps forward!"
        } else if waves[0].count > 1 {
            "\(species.name) and its followers block your way!"
        } else {
            "\(species.name) blocks your way!"
        }
        let controller = BattleController(engine: engine, session: session, intro: intro)
        controller.music = "boss"
        if !session.isDefeated(npc), let victory = npc.victory {
            controller.story = BossStory(art: species.art, title: victory.title, paragraphs: victory.story)
        }
        return controller
    }

    /// How many fighters each wave of a boss fight has, the boss's own included.
    static let waveSize = 10

    /// A boss fight's waves, in order: `waveSize` of the map's monsters in each wave before the
    /// boss's own, where it stands in the middle of the front row of its minions. Levels climb three
    /// a wave: the boss's minions are 1 to 8 levels below it, the wave before 4 to 11, and so on,
    /// within the map's range but never up to the boss's level. Wave n's fighters have ids from 100 × n.
    static func bossWaves(_ npc: NPCDef, encounters: MapDef.Encounters?, session: GameSession) -> [[Combatant]]? {
        guard let id = npc.monster, let species = session.content.monster(id) else { return nil }
        let level = npc.level ?? 10
        let followers = max(0, npc.minions ?? waveSize - 1)
        // Waves of monsters need the map's own; without them the boss stands alone.
        let count = (encounters?.monsters.isEmpty ?? true) ? 1 : max(1, npc.waves ?? 3)
        // The map's level range, kept below the boss's own.
        let mapTop = encounters.map { max($0.levels.first ?? 1, $0.levels.last ?? 1) } ?? level
        let highest = max(1, min(mapTop, level - 1))
        let lowest = min(encounters?.levels.first ?? 1, highest)

        func monsters(_ amount: Int, wave: Int) -> [Combatant] {
            guard let encounters, amount > 0 else { return [] }
            let back = 3 * (count - wave)
            let top = max(lowest, min(highest, level - 1 - back))
            let bottom = max(lowest, min(top, level - 8 - back))
            var group: [Combatant] = []
            for index in 0..<amount {
                guard let kindID = pick(from: encounters.monsters), let kind = session.content.monster(kindID) else { continue }
                let kindLevel = Int.random(in: bottom...top)
                let stats = kind.stats(at: kindLevel)
                var monster = Combatant(
                    id: 100 * wave + 1 + index, side: .enemies, source: .wild(kindID), name: kind.name, art: kind.art,
                    level: kindLevel, element: kind.element, stats: stats, hp: stats.hp, mp: stats.mp,
                    skills: kind.skills, captureRate: kind.captureRate
                )
                monster.isRare = kind.rare == true
                monster.wave = wave
                group.append(monster)
            }
            return group
        }

        var waves: [[Combatant]] = (1..<count).map { monsters(waveSize, wave: $0) }
        let stats = species.stats(at: level)
        var boss = Combatant(id: 100 * count, side: .enemies, source: .wild(id), name: species.name, art: species.art,
                             level: level, element: species.element, stats: stats, hp: stats.hp, mp: stats.mp,
                             skills: species.skills, captureRate: 0)
        boss.wave = count
        var lastWave = monsters(followers, wave: count)
        // The battle stands a side in rows of five, the last one nearest you: the boss takes the
        // middle of that row.
        let total = lastWave.count + 1
        let frontRow = (total - 1) / 5 * 5
        lastWave.insert(boss, at: frontRow + (total - frontRow) / 2)
        waves.append(lastWave)
        return waves
    }

    /// How often each monster turns up on the current map: its encounter table, with a rare one
    /// sighted here (an announcement, `GameSession.sighting`) `boost` times as often until it's over.
    static func encounterWeights(_ encounters: MapDef.Encounters, session: GameSession) -> [String: Int] {
        var weights = encounters.monsters
        if let sighting = session.sighting, sighting.mapID == session.data.mapID, sighting.until > Date(),
           let weight = weights[sighting.monsterID] {
            weights[sighting.monsterID] = weight * sighting.boost
        }
        return weights
    }

    /// Builds a random encounter for the current map.
    static func encounter(_ encounters: MapDef.Encounters, session: GameSession) -> BattleController {
        let content = session.content
        let party = party(for: session)
        let weights = encounterWeights(encounters, session: session)

        let low = encounters.groupSize.first ?? 1
        let high = max(low, encounters.groupSize.last ?? low)
        let minLevel = encounters.levels.first ?? 1
        let maxLevel = max(minLevel, encounters.levels.last ?? minLevel)
        // Small groups are common, the biggest rare (squaring the roll leans it low).
        let count = min(high, low + Int(pow(Double.random(in: 0..<1), 2) * Double(high - low + 1)))
        var enemies: [Combatant] = []
        for index in 0..<count {
            guard let id = pick(from: weights), let species = content.monster(id) else { continue }
            let level = Int.random(in: minLevel...maxLevel)
            let stats = species.stats(at: level)
            var enemy = Combatant(
                id: 10 + index, side: .enemies, source: .wild(id), name: species.name, art: species.art,
                level: level, element: species.element, stats: stats, hp: stats.hp, mp: stats.mp,
                skills: species.skills, captureRate: species.captureRate
            )
            enemy.isRare = species.rare == true
            enemies.append(enemy)
        }
        let engine = BattleEngine(party: party, enemies: enemies, content: content, captureBonus: session.heroClass.captureBonus ?? 1)
        let controller = BattleController(engine: engine, session: session)
        controller.isWild = true
        controller.isAuto = GameSettings.autoBattle && controller.canAuto
        return controller
    }

    private static func pick(from weights: [String: Int]) -> String? {
        let total = weights.values.reduce(0, +)
        guard total > 0 else { return nil }
        var roll = Int.random(in: 0..<total)
        for (id, weight) in weights.sorted(by: { $0.key < $1.key }) {
            if roll < weight { return id }
            roll -= weight
        }
        return nil
    }

    // MARK: - Reading

    /// Set when the hero levels up during the victory payout.
    private var newLevel: Int?
    private var levelsGained = 0
    /// Friends and your companion who went up a level with the win.
    private var othersLevelled: [LevelUp] = []
    private var rewardEXP = 0
    private var rewardGold = 0
    /// Item id → how many were found after a win.
    private var loot: [String: Int] = [:]

    var hero: Combatant? { combatants.first(where: \.isHero) }
    var party: [Combatant] { combatants.filter { $0.side == .party } }
    var enemies: [Combatant] { combatants.filter { $0.side == .enemies } }
    /// The wave on the field (a boss fight's beaten waves have left it).
    var enemiesOnField: [Combatant] { enemies.filter { $0.wave == wave } }
    /// Skills usable in battle (Bridge of Light and other field spells are cast from the menu).
    var skills: [SkillDef] { session.heroSkills.filter { $0.kind != .field } }
    var items: [ItemDef] { session.battleItems }

    /// True when a hurt party member could use a healing item, so Items moves out from under "More".
    var needsHealing: Bool {
        guard items.contains(where: { ($0.heal ?? 0) > 0 }) else { return false }
        return party.contains { $0.isAlive && Double($0.hp) <= Double($0.stats.hp) * 0.35 }
    }

    /// True when the last monster is weak enough to seal and you have a Seal Stone
    /// (the Capture button only shows then).
    var canCapture: Bool {
        guard session.sealStones > 0 else { return false }
        return enemies.contains { enemy in
            if case .ready = engine.captureStatus(of: enemy.id) { return true }
            return false
        }
    }

    func name(_ id: Int) -> String { combatants.first { $0.id == id }?.name ?? "?" }

    private var aliveEnemyIDs: [Int] { enemies.filter(\.isAlive).map(\.id) }
    private var aliveAllyIDs: [Int] { party.filter(\.isAlive).map(\.id) }

    // MARK: - Your companion's turn

    /// Your own companion while it's standing (friends' companions fight on their own).
    var companion: Combatant? {
        guard let id = session.activePet?.id else { return nil }
        return combatants.first { $0.petID == id && $0.isAlive }
    }

    /// True while you choose what your companion does, after the hero's choice. Like Fairyland,
    /// you command your pet every round (unless `GameSettings.commandCompanion` is off). The hero's
    /// choice stands: there's no taking it back on the companion's turn.
    private(set) var choosingForCompanion = false
    /// The hero's choice, waiting while you choose the companion's.
    @ObservationIgnored private var heroChoice: BattleAction?

    /// Its skills, for the Skills list on its turn.
    var companionSkills: [SkillDef] { companion?.skills.compactMap { session.content.skill($0) } ?? [] }
    func companionLevel(of skill: SkillDef) -> Int { companion?.skillLevel(skill.id) ?? 1 }
    func companionCost(of skill: SkillDef) -> Int { GameSession.mpCost(of: skill, level: companionLevel(of: skill)) }

    /// Auto: the companion decides for itself this round.
    func letCompanionDecide() {
        guard choosingForCompanion else { return }
        stopTurnClock()
        clearTargets()
        choosingForCompanion = false
        resolve(heroChoice ?? .defend, orders: [:])
    }

    // MARK: - Pace

    /// How fast the fight plays (the 2× button): its animations and the pauses between rounds that
    /// play by themselves, never your time to choose. Kept for the next fights.
    private(set) var speed = GameSettings.battleSpeed

    func toggleSpeed() {
        speed = speed > 1 ? 1 : 2
        UserDefaults.standard.set(speed, forKey: GameSettings.battleSpeedKey)
        scene?.setPace(speed)
    }

    /// Auto: the hero fights by themselves, as a friend in your party would
    /// (`BattleEngine.autoAction`), your companion decides for itself, and the rounds play on their
    /// own until you switch it off. Only in a wild fight against monsters well below you, never a
    /// boss or a duel; it hands back to you when you're badly hurt. Left on, it's on in the next
    /// fight it's allowed in.
    private(set) var isAuto = false
    /// A wild encounter (not a boss or a duel), where Auto may play.
    @ObservationIgnored private(set) var isWild = false
    /// How many levels below you every monster must be for Auto.
    static let autoLevelGap = 5
    /// Below this share of HP, Auto stops and you choose again.
    static let autoStopsBelow = 0.3

    /// Auto is allowed here: a wild fight where every monster standing is well below you.
    var canAuto: Bool {
        guard isWild, let hero, hero.isAlive else { return false }
        let standing = enemies.filter(\.isAlive)
        return !standing.isEmpty && standing.allSatisfy { $0.level <= hero.level - Self.autoLevelGap }
    }

    /// Auto plays the next round: it's on, allowed here, and you're not badly hurt.
    private var autoPlays: Bool {
        isAuto && canAuto && (hero?.hpFraction ?? 0) >= Self.autoStopsBelow
    }

    func toggleAuto() {
        guard phase != .finished else { return }
        if isAuto {
            isAuto = false
            UserDefaults.standard.set(false, forKey: GameSettings.autoBattleKey)
            return
        }
        guard canAuto else {
            message = isWild
                ? "Auto fights only monsters at least \(Self.autoLevelGap) levels below you."
                : "No Auto against a boss or in a duel."
            return
        }
        isAuto = true
        UserDefaults.standard.set(true, forKey: GameSettings.autoBattleKey)
        // Mid-choice, it plays on at once (with your choice, if you'd made it and were on your companion's).
        if isChoosing { autoRound() }
    }

    /// The fight is on screen: your first turn's clock starts, or on Auto the first round plays
    /// once everyone has marched in.
    func begin() {
        if autoPlays, phase == .command, !choosingForCompanion {
            playOnAuto(after: 1200)
        } else {
            if phase == .command { armAttack() }
            startTurnClock()
        }
    }

    /// Plays the next round on Auto after a short pause (or hands back to you if Auto was switched
    /// off meanwhile). The chat holds it, as it holds the turn clock.
    private func playOnAuto(after milliseconds: Int = 500) {
        phase = .animating
        message = "Auto: \(hero?.name ?? "you") fights on…"
        Task { [weak self] in
            await self?.breather(milliseconds)
            while self?.holds.isEmpty == false { try? await Task.sleep(for: .milliseconds(250)) }
            guard let self, self.phase == .animating, self.result == nil else { return }
            if self.autoPlays { self.autoRound() } else { self.awaitCommand() }
        }
    }

    /// One round on Auto: the hero acts as a friend would (or as you'd chosen, mid-choice), and your
    /// companion decides for itself.
    private func autoRound() {
        stopTurnClock()
        clearTargets()
        let action = heroChoice ?? hero.map { engine.autoAction(for: $0.id) } ?? .defend
        choosingForCompanion = false
        resolve(action, orders: [:])
    }

    /// Your turn to choose; the turn clock starts.
    private func awaitCommand(note: String? = nil) {
        phase = .command
        armAttack()
        let ask = "What will \(hero?.name ?? "you") do?"
        message = note.map { "\($0) \(ask)" } ?? ask
        startTurnClock()
    }

    /// Attack is already chosen when a turn starts, yours or your companion's, as in Fairyland: the
    /// monsters show as targets, and tapping one attacks it, without the Attack button first. A
    /// skill, an item or Capture takes over the targets when you pick it.
    private func armAttack() {
        pending = .attack
        validTargets = aliveEnemyIDs
        scene?.showTargets(validTargets)
    }

    /// A pause before something that plays by itself, shorter at 2×. None without a scene (tests).
    private func breather(_ milliseconds: Int) async {
        guard scene != nil else { return }
        try? await Task.sleep(for: .milliseconds(Int(Double(milliseconds) / speed)))
    }

    // MARK: - Commands

    func attack() {
        let prompt = choosingForCompanion ? "\(companion?.name ?? "It") attacks which monster?" : "Attack which monster?"
        beginTargeting(.attack, targets: aliveEnemyIDs, prompt: prompt)
    }

    func openSkills() {
        guard phase == .command else { return }
        clearTargets()
        phase = .skills
    }

    func openItems() {
        guard phase == .command else { return }
        clearTargets()
        phase = .items
    }

    func back() {
        // Out of time just as you backed out: the round is already playing.
        guard isChoosing else { return }
        clearTargets()
        phase = .command
        armAttack()
    }

    func level(of skill: SkillDef) -> Int { session.skillLevel(skill.id) }

    var pinnedSkills: [SkillDef] { session.pinnedSkills }

    func togglePin(_ skill: SkillDef) {
        if session.togglePin(skill.id) {
            session.save()
        } else {
            message = "The quick bar holds \(GameSession.maxPinnedSkills) skills. Unpin one first."
        }
    }

    /// Saves a new order for the battle buttons (from holding one down).
    func arrangeButtons(_ order: [String]) {
        session.data.battleButtons = order
        session.save()
    }

    func cost(of skill: SkillDef) -> Int { GameSession.mpCost(of: skill, level: level(of: skill)) }

    func useSkill(_ skill: SkillDef) {
        let user = choosingForCompanion ? companion : hero
        let price = choosingForCompanion ? companionCost(of: skill) : cost(of: skill)
        guard let user, user.mp >= price else {
            message = "Not enough MP for \(skill.name)."
            return
        }
        switch skill.target {
        case .enemy: beginTargeting(.skill(skill), targets: aliveEnemyIDs, prompt: "\(skill.name): choose a monster")
        case .ally: beginTargeting(.skill(skill), targets: aliveAllyIDs, prompt: "\(skill.name): choose who")
        case .fallenAlly:
            let fallen = party.filter { $0.isFallen && !$0.isHero }.map(\.id)
            guard !fallen.isEmpty else {
                message = "Nobody has fainted. \(skill.name) can wait."
                return
            }
            beginTargeting(.skill(skill), targets: fallen, prompt: "\(skill.name): wake who?")
        case .allEnemies, .allAllies: submit(.skill(skill.id, target: -1))
        }
    }

    func useItem(_ item: ItemDef) {
        beginTargeting(.item(item), targets: aliveAllyIDs, prompt: "Use \(item.name) on…")
    }

    func capture() {
        guard session.sealStones > 0 else {
            message = "You need a Seal Stone. Trader Bo in Meadowbrook sells them."
            return
        }
        beginTargeting(.capture, targets: aliveEnemyIDs, prompt: "Throw a Seal Stone at…")
    }

    func defend() { submit(.defend) }

    func escape() { submit(.escape) }

    /// A target was tapped in the scene or picked in the menu (on a turn's command menu, a monster
    /// tapped is attacked: `armAttack`, unless the chat or rearranging the buttons has your attention).
    func select(_ id: Int) {
        guard phase == .target || (phase == .command && holds.isEmpty), validTargets.contains(id), let pending else { return }
        switch pending {
        case .attack:
            submit(.attack(target: id))
        case .skill(let skill):
            submit(.skill(skill.id, target: id))
        case .item(let item):
            submit(.item(item.id, target: id))
        case .capture:
            switch engine.captureStatus(of: id) {
            case .ready: submit(.capture(target: id))
            case .notAlone: message = "Only the last monster standing can be sealed. Beat the others first!"
            case .tooHealthy: message = "\(name(id)) is too lively. Weaken it below 20% HP first!"
            case .impossible: message = "\(name(id)) can't be captured."
            }
        }
    }

    func leave() {
        onFinish?(engine.outcome)
    }

    private func beginTargeting(_ command: Pending, targets: [Int], prompt: String) {
        guard !targets.isEmpty else { return }
        pending = command
        validTargets = targets
        self.prompt = prompt
        phase = .target
        scene?.showTargets(targets)
    }

    /// The choice for whoever's turn it is. After the hero's, your companion gets its turn (unless
    /// it fights on its own, or you're running away); after the companion's, the round plays.
    private func submit(_ action: BattleAction, askCompanion: Bool = true) {
        stopTurnClock()
        clearTargets()
        if choosingForCompanion {
            choosingForCompanion = false
            resolve(heroChoice ?? .defend, orders: companion.map { [$0.id: action] } ?? [:])
            return
        }
        switch action {
        case .attack(let target): lastTarget = target
        case .skill(_, let target) where aliveEnemyIDs.contains(target): lastTarget = target
        default: break
        }
        if askCompanion, GameSettings.commandCompanion, let companion, !action.isEscape {
            heroChoice = action
            choosingForCompanion = true
            phase = .command
            armAttack()
            message = "What will \(companion.name) do?"
            startTurnClock()
            return
        }
        resolve(action, orders: [:])
    }

    private func clearTargets() {
        pending = nil
        validTargets = []
        scene?.showTargets([])
    }

    /// Plays the round with everyone's choices.
    private func resolve(_ heroAction: BattleAction, orders: [Int: BattleAction]) {
        heroChoice = nil
        phase = .animating
        let events = engine.resolveRound(heroAction: heroAction, orders: orders)
        Task {
            if let scene {
                await scene.play(events)
            } else {
                for event in events { apply(event) }
            }
            roundFinished()
        }
    }

    // MARK: - Turn clock

    /// Seconds you get to choose each turn before the hero just attacks. None in tests and debug
    /// launches (screenshots wait in battle for a while), unless `turntimer=` sets one.
    static var turnSeconds: TimeInterval? {
        if let seconds = DebugLaunch.turnSeconds { return seconds }
        if DebugLaunch.isActive || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return nil }
        return 10
    }

    /// When the time to choose runs out; nil while no clock is ticking.
    private(set) var turnDeadline: Date?
    @ObservationIgnored private var turnClock: Task<Void, Never>?
    /// Time left on a clock that's on hold, and what's holding it (the chat, moving the buttons).
    @ObservationIgnored private var heldTime: TimeInterval?
    @ObservationIgnored private var holds: Set<String> = []
    /// The monster you last went for: a timed-out attack goes for it again.
    @ObservationIgnored private var lastTarget: Int?

    private var isChoosing: Bool { [.command, .skills, .items, .target].contains(phase) }

    /// Starts the clock for a turn: each new one, and the first once the battle is on screen.
    func startTurnClock() {
        guard let seconds = Self.turnSeconds, isChoosing, turnClock == nil, heldTime == nil else { return }
        if holds.isEmpty {
            runTurnClock(seconds)
        } else {
            heldTime = seconds
        }
    }

    /// Holds the clock while something else has your attention, and starts it again where it was.
    func holdTurnClock(_ held: Bool, for reason: String) {
        if held {
            let running = holds.isEmpty
            holds.insert(reason)
            guard running, let deadline = turnDeadline else { return }
            heldTime = max(1, deadline.timeIntervalSinceNow)
            turnClock?.cancel()
            turnClock = nil
            turnDeadline = nil
        } else {
            holds.remove(reason)
            guard holds.isEmpty, let left = heldTime, isChoosing else { return }
            heldTime = nil
            runTurnClock(left)
        }
    }

    private func runTurnClock(_ seconds: TimeInterval) {
        turnClock?.cancel()
        turnDeadline = Date().addingTimeInterval(seconds)
        turnClock = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.timeIsUp()
        }
    }

    private func stopTurnClock() {
        turnClock?.cancel()
        turnClock = nil
        turnDeadline = nil
        heldTime = nil
    }

    /// Out of time: the hero attacks the monster they last went for, or the first one standing, and
    /// the companion fights on its own. On the companion's turn, it decides for itself.
    private func timeIsUp() {
        turnClock = nil
        guard isChoosing, holds.isEmpty else { return }
        if choosingForCompanion {
            message = "Time's up! \(companion?.name ?? "Your companion") fights on its own."
            letCompanionDecide()
            return
        }
        let standing = aliveEnemyIDs
        guard let target = lastTarget.flatMap({ standing.contains($0) ? $0 : nil }) ?? standing.first else { return }
        message = "Time's up! \(hero?.name ?? "You") attacks."
        submit(.attack(target: target), askCompanion: false)
    }

    // MARK: - Playback

    /// Updates the display state and battle log for one event (called by the scene mid-animation).
    func apply(_ event: BattleEvent) {
        switch event {
        case .attack(let actor, let hit):
            damage(hit)
            SoundEffects.shared.play(hit.critical ? .crit : .hit)
            Haptics.impact(hit.critical ? .medium : .light)
            message = "\(name(actor)) attacks \(name(hit.target))!" + (hit.critical ? " Critical hit!" : "")
        case .skill(let actor, let skill, let level, let hits):
            mutate(actor) { $0.mp = max(0, $0.mp - GameSession.mpCost(of: skill, level: level)) }
            SoundEffects.shared.play(skill.kind.isHostile ? .magic : .heal)
            for hit in hits {
                switch skill.kind {
                case .heal, .revive: mutate(hit.target) { $0.hp = min($0.stats.hp, $0.hp + hit.amount) }
                case .physical, .magic: damage(hit)
                case .buff, .curse, .field: break
                }
            }
            var text = "\(name(actor)) uses \(skill.name)!"
            if skill.kind == .revive, let hit = hits.first { text += " \(name(hit.target)) is back on their feet!" }
            if hits.contains(where: { $0.effectiveness > 1 }) { text += " A weak spot!" }
            if hits.contains(where: { $0.effectiveness < 1 }) { text += " It was resisted…" }
            message = text
        case .item(let actor, let item, let target, let hp, let mp):
            // Only used up once it actually reaches someone.
            session.removeItem(item.id)
            SoundEffects.shared.play(.potion)
            mutate(target) {
                $0.hp += hp
                $0.mp += mp
            }
            message = "\(name(actor)) uses a \(item.name) on \(name(target))."
        case .defend(let actor):
            SoundEffects.shared.play(.shield)
            message = "\(name(actor)) is on guard."
        case .capture(_, let target, let success, _):
            SoundEffects.shared.play(success ? .capture : .breakFree)
            if success { Haptics.success() }
            if success {
                mutate(target) { $0.isCaptured = true }
                // Like Fairyland's capsules, a stone is only used up when it works.
                if let stone = session.content.items.first(where: { $0.capture == true && session.count(of: $0.id) > 0 }) {
                    session.removeItem(stone.id)
                }
            }
            message = success ? "Sealed! \(name(target)) was captured!" : "Oh no! \(name(target)) broke free!"
        case .fled(let id):
            SoundEffects.shared.play(.run)
            mutate(id) { $0.hasFled = true }
            message = "\(name(id)) ran away!"
        case .escape(_, let success):
            SoundEffects.shared.play(success ? .run : .breakFree)
            message = success ? "Got away safely!" : "Couldn't get away!"
        case .defeated(let id):
            let fighter = combatants.first { $0.id == id }
            SoundEffects.shared.play(fighter?.side == .enemies ? .poof : .faint)
            message = fighter?.side == .enemies ? "\(name(id)) is defeated!" : "\(name(id)) fainted!"
        case .message(let text):
            message = text
        case .afflicted(let target, let effect, let rounds):
            // A curse's drops come in the event after this one (`statsChanged`).
            if effect == .poison {
                mutate(target) { $0.poisonRounds = max($0.poisonRounds, rounds) }
            }
            SoundEffects.shared.play(.faint, volume: 0.5)
            message = switch effect {
            case .poison: "\(name(target)) is poisoned!"
            case .curse: "\(name(target)) is cursed!"
            }
        case .statsChanged(let target, let changes, let rounds):
            mutate(target) { $0.change(changes, rounds: rounds + 1) }
            message = Self.statLine(name(target), changes, rounds: rounds)
        case .ailmentDamage(let target, _, let amount):
            mutate(target) {
                $0.hp = max(0, $0.hp - amount)
                $0.poisonRounds = max(0, $0.poisonRounds - 1)
            }
            SoundEffects.shared.play(.hit, volume: 0.6)
            Haptics.impact(.light)
            message = "\(name(target)) is hurt by the poison!"
        case .wave(let number, let total, let arrivals):
            combatants += arrivals
            wave = number
            for foe in arrivals {
                if let id = foe.speciesID { session.sawMonster(id, level: foe.level) }
            }
            SoundEffects.shared.play(.encounter)
            Haptics.impact(.medium)
            if number == total, let boss = arrivals.first(where: { $0.captureRate == 0 }) {
                message = "Final wave: \(boss.name) steps forward!"
            } else {
                message = "Wave \(number) of \(total): \(arrivals.count) more monster\(arrivals.count == 1 ? "" : "s")!"
            }
            if let rare = arrivals.first(where: \.isRare) { message += " ✦ A rare \(rare.name)!" }
        }
    }

    func announce(_ text: String) {
        message = text
    }

    /// Everyone one blow knocked out, at once: one sound and one line for them all.
    func applyDefeats(_ ids: [Int]) {
        guard ids.count > 1 else {
            if let id = ids.first { apply(.defeated(id)) }
            return
        }
        let foes = ids.filter { id in combatants.first { $0.id == id }?.side == .enemies }
        let friends = ids.filter { !foes.contains($0) }
        SoundEffects.shared.play(foes.isEmpty ? .faint : .poof)
        var lines: [String] = []
        if !foes.isEmpty { lines.append("\(Self.tally(foes.map { name($0) })) \(foes.count == 1 ? "is" : "are") defeated!") }
        if !friends.isEmpty { lines.append("\(Self.tally(friends.map { name($0) })) fainted!") }
        message = lines.joined(separator: " ")
    }

    /// "Maple's ATK +25% and DEF +25% for 3 rounds!"
    static func statLine(_ name: String, _ changes: [StatChange], rounds: Int) -> String {
        let parts = changes.map { "\($0.stat.short) \(percent($0.amount))" }
        return "\(name)'s \(GameSession.listed(parts)) for \(rounds) round\(rounds == 1 ? "" : "s")!"
    }

    /// A stat change as the battle shows it: "+25%", "−20%".
    static func percent(_ amount: Double) -> String {
        let value = Int((abs(amount) * 100).rounded())
        return amount >= 0 ? "+\(value)%" : "\u{2212}\(value)%"
    }

    /// Names in the order they fell, a repeated one counted: "Dark Beetle ×2 and Fire Rat".
    static func tally(_ names: [String]) -> String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for name in names {
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return GameSession.listed(order.map { name in
            let count = counts[name, default: 1]
            return count > 1 ? "\(name) ×\(count)" : name
        })
    }

    private func damage(_ hit: Hit) {
        mutate(hit.target) { $0.hp = max(0, $0.hp - hit.amount) }
    }

    private func mutate(_ id: Int, _ change: (inout Combatant) -> Void) {
        guard let index = combatants.firstIndex(where: { $0.id == id }) else { return }
        change(&combatants[index])
    }

    private func roundFinished() {
        combatants = engine.combatants
        // The marks count down at the start of a round (curses) as well as with each bite.
        scene?.refreshBars()
        switch engine.outcome {
        case .ongoing where heroIsDown:
            fightOnWithoutYou()
        case .ongoing where autoPlays:
            playOnAuto()
        case .ongoing where isAuto && canAuto:
            // Badly hurt: Auto hands back to you (and comes on again in the next fight).
            isAuto = false
            awaitCommand(note: "Auto stops: you're badly hurt!")
        case .ongoing:
            awaitCommand()
        case .victory:
            finish(.victory, lines: concludeVictory() + afterTheFight())
        case .fled:
            let runaway = engine.combatants.first { $0.hasFled }?.name ?? "The monster"
            finish(.fled, lines: ["\(runaway) ran away!"] + concludeVictory() + afterTheFight())
        case .defeat:
            finish(.defeat, lines: ["\(hero?.name ?? "You") fainted…"] + afterTheFight())
        case .escaped:
            syncParty()
            finish(.escaped, lines: ["You got away safely."] + afterTheFight())
        }
    }

    /// The hero has fainted: the fight goes on without them while a friend still stands.
    var heroIsDown: Bool { engine.hero?.isAlive == false }

    /// While you lie fainted, the friends still standing fight on. The rounds play by themselves
    /// (your companion decides for itself), a moment apart so you can follow, until the fight is won
    /// or lost or someone wakes you. The chat holds them, as it holds the turn clock.
    private func fightOnWithoutYou() {
        let standing = party.filter { $0.isAlly && $0.isAlive }.map(\.name)
        message = "\(hero?.name ?? "You") fainted! \(GameSession.listed(standing)) \(standing.count == 1 ? "fights" : "fight") on…"
        Task {
            await breather(900)
            while !holds.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            resolve(.defend, orders: [:])
        }
    }

    /// Whoever fainted wakes up at their own checkpoint, you included even when your friends won,
    /// and friends still standing when you fell stay where the fight was (`GameSession.partWays`).
    private func afterTheFight() -> [String] {
        let fainted = Set(engine.combatants.compactMap { fighter -> UUID? in
            guard case .ally(let id) = fighter.source, !fighter.isAlive else { return nil }
            return id
        })
        let lines = session.partWays(fainted: fainted, heroFainted: heroIsDown)
        session.save()
        return lines
    }

    private func finish(_ outcome: BattleOutcome, lines: [String]) {
        stopTurnClock()
        let found = loot.sorted { $0.key < $1.key }.map { (id: $0.key, count: $0.value) }
        // The card shows level-ups as banners of their own; their lines go to the log.
        let levelText = newLevel.map { levelLine($0) }
        let othersText = Set(othersLevelled.map(\.line))
        result = BattleResult(outcome: outcome, lines: lines.filter { $0 != levelText && !othersText.contains($0) }, newLevel: newLevel,
                              exp: rewardEXP, gold: rewardGold, loot: found, levelsGained: levelsGained,
                              others: othersLevelled, story: outcome == .victory ? story : nil)
        let won = outcome == .victory || outcome == .fled
        // The log gets it all in words; the result card shows the pay as icons.
        var logged = lines
        var pay: [String] = []
        if rewardEXP > 0 { pay.append("+\(rewardEXP) EXP") }
        if rewardGold > 0 { pay.append("+\(rewardGold) gold") }
        if !pay.isEmpty { logged.insert(pay.joined(separator: "    "), at: min(1, logged.count)) }
        for item in found {
            let name = session.content.item(item.id)?.name ?? item.id
            logged.append(item.count > 1 ? "Found \(name) ×\(item.count)!" : "Found \(name)!")
        }
        for line in logged { session.post(line, won ? .reward : .battle) }
        MusicPlayer.shared.play(won ? "victory" : nil)
        if outcome == .defeat { SoundEffects.shared.play(.lose) }
        guard newLevel != nil || !othersLevelled.isEmpty else {
            phase = .finished
            return
        }
        // A level-up gets its own moment on the field before the card: after the first notes of
        // the victory fanfare, light pours down on the hero with the level-up jingle, and on every
        // friend and companion who went up with them.
        message = ([newLevel.map { levelLine($0) }].compactMap { $0 } + othersLevelled.map(\.line)).joined(separator: " ")
        let others = othersLevelled
        Task {
            await breather(450)
            if let newLevel { scene?.celebrateLevelUp(to: newLevel) }
            for other in others {
                if let id = other.fighterID { scene?.celebrateLevelUp(of: id, to: other.level) }
            }
            SoundEffects.shared.play(.levelUp)
            Haptics.success()
            await breather(1500)
            phase = .finished
        }
    }

    private func levelLine(_ level: Int) -> String {
        "\(session.data.hero.name) reached level \(level)!"
    }

    #if DEBUG
    /// Debug launches (`win`): every monster falls at once (no falling animation: a CI simulator
    /// draws a frame every couple of seconds), and the win plays out as usual.
    func winForDebug() {
        guard phase == .command else { return }
        phase = .animating
        let events = engine.defeatEnemiesForDebug()
        // The later waves of a boss fight join the field all at once, so they have names in the log.
        combatants = engine.combatants
        for event in events { apply(event) }
        roundFinished()
    }

    /// Debug launches (`afflict`): poison and a curse on the field, so their marks show.
    func afflictForDebug() {
        engine.afflictForDebug()
        combatants = engine.combatants
        scene?.refreshBars()
    }

    /// Debug launches (`herodown`): the hero faints where they stand, and any friends fight on.
    func knockOutHeroForDebug() {
        guard phase == .command, !choosingForCompanion else { return }
        stopTurnClock()
        phase = .animating
        let events = engine.knockOutHeroForDebug()
        Task {
            if let scene {
                await scene.play(events)
            } else {
                for event in events { apply(event) }
            }
            roundFinished()
        }
    }
    #endif

    /// Writes battle damage back to the hero and companion.
    private func syncParty() {
        if let hero = engine.hero {
            session.data.hero.hp = max(1, hero.hp)
            session.data.hero.mp = hero.mp
        }
        for fighter in engine.combatants {
            guard let petID = fighter.petID, let index = session.data.pets.firstIndex(where: { $0.id == petID }) else { continue }
            // A companion that fainted stays down until a potion or a healer wakes it up.
            session.data.pets[index].hp = max(0, fighter.hp)
            session.data.pets[index].mp = fighter.mp
        }
    }

    private func concludeVictory() -> [String] {
        syncParty()
        let content = session.content
        var lines: [String] = []

        var exp = 0
        var gold = 0
        for foe in engine.combatants where foe.side == .enemies && !foe.isCaptured && !foe.hasFled {
            if case .rival = foe.source {
                // The adventurer pays out for the duel, and drops everything they carry; their
                // companion comes along for free.
                if foe.art.hasPrefix("adv:") {
                    exp += 14 * foe.level
                    gold += 10 * foe.level
                    lines.append("You won the duel against \(foe.name)!")
                    if let rival {
                        let spoils = session.takeSpoils(from: rival)
                        for item in spoils { loot[item.id, default: 0] += 1 }
                        if !spoils.isEmpty { lines.append("\(foe.name) dropped everything they carried!") }
                    }
                }
                continue
            }
            guard let id = foe.speciesID, let species = content.monster(id) else { continue }
            exp += Int((Double(species.exp) * (1 + 0.35 * Double(foe.level - 1))).rounded())
            gold += Int((Double(species.gold) * (1 + 0.25 * Double(foe.level - 1))).rounded())
            session.record(.defeat, target: id)
            session.beatMonster(id, level: foe.level)
        }
        session.data.gold += gold
        rewardGold = gold

        if heroIsDown {
            // Out cold, you learn nothing from it, like a fainted companion. The spoils are shared.
            lines.append("Your friends won while you were out cold: no EXP for you this time.")
        } else {
            rewardEXP = exp
            let learnableBefore = Set(session.learnableSkills.map(\.id))
            let levels = session.gainHeroEXP(exp)
            if levels > 0 {
                newLevel = session.data.hero.level
                levelsGained = levels
                lines.append(levelLine(session.data.hero.level))
                for skill in session.learnableSkills where !learnableBefore.contains(skill.id) {
                    lines.append("New skill to learn: \(skill.name)!")
                }
                if session.canChooseClass {
                    lines.append("You can choose a path now! Visit a guild master in town.")
                }
            }
        }

        // Your friends still standing keep up with you, a level behind: whoever went up celebrates
        // with you.
        let standing = Set(engine.combatants.compactMap { fighter -> UUID? in
            guard case .ally(let id) = fighter.source, fighter.isAlive else { return nil }
            return id
        })
        for friend in session.growParty(standing: standing) {
            let fighter = engine.combatants.first { $0.source == .ally(friend.id) }
            let line = "\(friend.name) reached level \(friend.level)!"
            othersLevelled.append(LevelUp(name: friend.name, level: friend.level, line: line, fighterID: fighter?.id))
            lines.append(line)
        }

        if let fighter = engine.combatants.first(where: { $0.petID != nil }), let petID = fighter.petID,
           let pet = session.data.pets.first(where: { $0.id == petID }) {
            if fighter.hp <= 0 {
                // Fainted companions earn nothing and sit out until they're healed.
                lines.append("\(pet.name) needs rest: use a potion or visit a healer.")
            } else {
                let share = Int((Double(exp) * (session.heroClass.petExpShare ?? 0.5)).rounded())
                if session.gainPetEXP(petID, share) > 0, let updated = session.data.pets.first(where: { $0.id == petID }) {
                    let line = "\(pet.name) grew to level \(updated.level)!"
                    othersLevelled.append(LevelUp(name: pet.name, level: updated.level, line: line, fighterID: fighter.id))
                    lines.append(line)
                }
            }
        }

        for captured in engine.combatants where captured.isCaptured {
            guard let id = captured.speciesID, var pet = session.makePet(species: id, level: captured.level) else { continue }
            pet.hp = max(1, captured.hp)
            if session.addPet(pet) {
                lines.append("\(pet.name) joined your party!")
            } else {
                // Full party: the result screen asks who stays behind.
                session.record(.capture, target: id)
                session.pendingPet = pet
                lines.append("\(pet.name) wants to join, but your party is full!")
            }
        }

        if Double.random(in: 0..<1) < 0.25 {
            session.addItem("potion")
            loot["potion", default: 0] += 1
        }

        // Materials for the blacksmith: about one wild monster in three drops something, bosses three.
        for foe in engine.combatants where foe.side == .enemies && !foe.isCaptured && !foe.hasFled {
            guard case .wild = foe.source, let id = foe.speciesID else { continue }
            let isBoss = content.monster(id)?.boss == true
            for _ in 0..<(isBoss ? 3 : 1) where isBoss || Double.random(in: 0..<1) < 0.35 {
                guard let material = session.materialDrop(level: foe.level) else { continue }
                session.addItem(material.id)
                loot[material.id, default: 0] += 1
            }
        }

        // Equipment: now and then a beaten monster drops gear from up to its own level, more often
        // the stronger it is next to you; a rare one often, a boss always. Two pieces at most a fight.
        var gearFound = 0
        for foe in engine.combatants where foe.side == .enemies && !foe.isCaptured && !foe.hasFled {
            guard gearFound < 2 else { break }
            guard case .wild = foe.source, let id = foe.speciesID else { continue }
            let isBoss = content.monster(id)?.boss == true
            let chance = GameSession.equipmentDropChance(level: foe.level, heroLevel: session.data.hero.level,
                                                         rare: foe.isRare, boss: isBoss)
            guard Double.random(in: 0..<1) < chance,
                  let gear = session.equipmentDrop(level: foe.level, best: foe.isRare || isBoss) else { continue }
            session.addItem(gear.id)
            loot[gear.id, default: 0] += 1
            gearFound += 1
            lines.append("\(foe.name) dropped \(gear.name)!")
        }
        session.save()
        return lines
    }
}

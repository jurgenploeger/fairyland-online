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

    let session: GameSession
    /// What plays during the fight: the map's battle theme, or the boss theme.
    @ObservationIgnored var music: String
    @ObservationIgnored weak var scene: BattleScene?
    @ObservationIgnored var onFinish: (@MainActor (BattleOutcome) -> Void)?
    private let engine: BattleEngine
    @ObservationIgnored private var pending: Pending?
    /// The adventurer you're duelling: beaten, they drop what they carry.
    @ObservationIgnored private var rival: Adventurer?

    init(engine: BattleEngine, session: GameSession, intro: String? = nil) {
        self.engine = engine
        self.session = session
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
        engine.canSeal = session.sealStones > 0
        for foe in engine.alive(on: .enemies) {
            if let id = foe.speciesID { session.sawMonster(id, level: foe.level) }
        }
    }

    /// You, your companion and the friends in your party.
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
            party.append(Combatant(
                id: 1, side: .party, source: .pet(pet.id), name: pet.name, art: session.artID(for: pet),
                level: pet.level, element: species.element, stats: session.stats(of: pet),
                hp: pet.hp, mp: pet.mp, skills: species.skills, captureRate: 0
            ))
        }
        for (index, friend) in session.partyMembers.enumerated() {
            party.append(adventurer(friend, id: 2 + index, side: .party, session: session))
            // A friend's companion fights beside them (a step below their level, like a rival's).
            if let speciesID = friend.petSpecies, let species = session.content.monster(speciesID) {
                let level = max(1, friend.level - 1)
                let stats = species.stats(at: level)
                party.append(Combatant(
                    id: 2 + GameSession.maxAllies + index, side: .party, source: .pet(UUID()), name: species.name, art: species.art,
                    level: level, element: species.element, stats: stats, hp: stats.hp, mp: stats.mp, skills: species.skills, captureRate: 0
                ))
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

    /// A duel with another adventurer (and their companion) in a danger zone.
    static func duel(with rival: Adventurer, session: GameSession) -> BattleController {
        var enemies = [adventurer(rival, id: 10, side: .enemies, session: session)]
        if let speciesID = rival.petSpecies, let species = session.content.monster(speciesID) {
            let level = max(1, rival.level - 1)
            let stats = species.stats(at: level)
            enemies.append(Combatant(
                id: 11, side: .enemies, source: .rival(rival.id), name: "\(rival.name)'s \(species.name)", art: species.art,
                level: level, element: species.element, stats: stats, hp: stats.hp, mp: stats.mp, skills: species.skills, captureRate: 0
            ))
        }
        let engine = BattleEngine(party: party(for: session), enemies: enemies, content: session.content)
        let intro = rival.hostile ? "\(rival.name) picks a fight with you!" : "You challenge \(rival.name) to a duel!"
        let controller = BattleController(engine: engine, session: session, intro: intro)
        controller.rival = rival
        return controller
    }

    /// A boss waiting on the map.
    static func boss(_ npc: NPCDef, session: GameSession) -> BattleController? {
        guard let id = npc.monster, let species = session.content.monster(id) else { return nil }
        let level = npc.level ?? 10
        let stats = species.stats(at: level)
        let boss = Combatant(id: 10, side: .enemies, source: .wild(id), name: species.name, art: species.art,
                             level: level, element: species.element, stats: stats, hp: stats.hp, mp: stats.mp,
                             skills: species.skills, captureRate: 0)
        let engine = BattleEngine(party: party(for: session), enemies: [boss], content: session.content)
        let controller = BattleController(engine: engine, session: session, intro: "\(species.name) blocks your way!")
        controller.music = "boss"
        return controller
    }

    /// Builds a random encounter for the current map.
    static func encounter(_ encounters: MapDef.Encounters, session: GameSession) -> BattleController {
        let content = session.content
        let party = party(for: session)

        let low = encounters.groupSize.first ?? 1
        let high = max(low, encounters.groupSize.last ?? low)
        let minLevel = encounters.levels.first ?? 1
        let maxLevel = max(minLevel, encounters.levels.last ?? minLevel)
        // Small groups are common, the biggest rare (squaring the roll leans it low).
        let count = min(high, low + Int(pow(Double.random(in: 0..<1), 2) * Double(high - low + 1)))
        var enemies: [Combatant] = []
        for index in 0..<count {
            guard let id = pick(from: encounters.monsters), let species = content.monster(id) else { continue }
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
        return BattleController(engine: engine, session: session)
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
    private var rewardEXP = 0
    private var rewardGold = 0
    /// Item id → how many were found after a win.
    private var loot: [String: Int] = [:]

    var hero: Combatant? { combatants.first(where: \.isHero) }
    var party: [Combatant] { combatants.filter { $0.side == .party } }
    var enemies: [Combatant] { combatants.filter { $0.side == .enemies } }
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

    // MARK: - Commands

    func attack() {
        beginTargeting(.attack, targets: aliveEnemyIDs, prompt: "Attack which monster?")
    }

    func openSkills() {
        guard phase == .command else { return }
        phase = .skills
    }

    func openItems() {
        guard phase == .command else { return }
        phase = .items
    }

    func back() {
        pending = nil
        validTargets = []
        scene?.showTargets([])
        phase = .command
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
        guard let hero, hero.mp >= cost(of: skill) else {
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

    /// A target was tapped in the scene or picked in the menu.
    func select(_ id: Int) {
        guard phase == .target, validTargets.contains(id), let pending else { return }
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

    private func submit(_ action: BattleAction) {
        pending = nil
        validTargets = []
        scene?.showTargets([])
        phase = .animating
        let events = engine.resolveRound(heroAction: action)
        Task {
            if let scene {
                await scene.play(events)
            } else {
                for event in events { apply(event) }
            }
            roundFinished()
        }
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
            SoundEffects.shared.play(skill.kind.isAttack ? .magic : .heal)
            for hit in hits {
                switch skill.kind {
                case .heal, .revive: mutate(hit.target) { $0.hp = min($0.stats.hp, $0.hp + hit.amount) }
                case .physical, .magic: damage(hit)
                case .buff, .field: break
                }
            }
            var text = "\(name(actor)) uses \(skill.name)!"
            if skill.kind == .revive, let hit = hits.first { text += " \(name(hit.target)) is back on their feet!" }
            if skill.kind == .buff, let hit = hits.first { text += " \(name(hit.target)) feels stronger." }
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
        }
    }

    func announce(_ text: String) {
        message = text
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
        engine.canSeal = session.sealStones > 0
        switch engine.outcome {
        case .ongoing:
            phase = .command
            message = "What will \(hero?.name ?? "you") do?"
        case .victory:
            finish(.victory, lines: concludeVictory())
        case .fled:
            let runaway = engine.combatants.first { $0.hasFled }?.name ?? "The monster"
            finish(.fled, lines: ["\(runaway) ran away!"] + concludeVictory())
        case .defeat:
            session.faint()
            session.save()
            finish(.defeat, lines: ["\(hero?.name ?? "You") fainted…", "You wake up at \(session.checkpointName(session.checkpoint)), a little bruised."])
        case .escaped:
            syncParty()
            session.save()
            finish(.escaped, lines: ["You got away safely."])
        }
    }

    private func finish(_ outcome: BattleOutcome, lines: [String]) {
        let found = loot.sorted { $0.key < $1.key }.map { (id: $0.key, count: $0.value) }
        // The card shows a level-up as a banner of its own; its line goes to the log.
        let levelText = newLevel.map { levelLine($0) }
        result = BattleResult(outcome: outcome, lines: lines.filter { $0 != levelText }, newLevel: newLevel,
                              exp: rewardEXP, gold: rewardGold, loot: found, levelsGained: levelsGained)
        let won = outcome == .victory || outcome == .fled
        // The log gets it all in words; the result card shows the pay as icons.
        var logged = lines
        if rewardEXP > 0 || rewardGold > 0 { logged.insert("+\(rewardEXP) EXP    +\(rewardGold) gold", at: min(1, logged.count)) }
        for item in found {
            let name = session.content.item(item.id)?.name ?? item.id
            logged.append(item.count > 1 ? "Found \(name) ×\(item.count)!" : "Found \(name)!")
        }
        for line in logged { session.post(line, won ? .reward : .battle) }
        MusicPlayer.shared.play(won ? "victory" : nil)
        if outcome == .defeat { SoundEffects.shared.play(.lose) }
        guard let newLevel else {
            phase = .finished
            return
        }
        // A level-up gets its own moment on the field before the card: after the first notes of
        // the victory fanfare, light pours down on the hero with the level-up jingle.
        message = levelLine(newLevel)
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            scene?.celebrateLevelUp(to: newLevel)
            SoundEffects.shared.play(.levelUp)
            Haptics.success()
            if scene != nil { try? await Task.sleep(for: .milliseconds(1500)) }
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
        for event in engine.defeatEnemiesForDebug() { apply(event) }
        roundFinished()
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
        rewardEXP = exp
        rewardGold = gold
        session.growParty()

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

        if let fighter = engine.combatants.first(where: { $0.petID != nil }), let petID = fighter.petID,
           let pet = session.data.pets.first(where: { $0.id == petID }) {
            if fighter.hp <= 0 {
                // Fainted companions earn nothing and sit out until they're healed.
                lines.append("\(pet.name) needs rest: use a potion or visit a healer.")
            } else {
                let share = Int((Double(exp) * (session.heroClass.petExpShare ?? 0.5)).rounded())
                if session.gainPetEXP(petID, share) > 0, let updated = session.data.pets.first(where: { $0.id == petID }) {
                    lines.append("\(pet.name) grew to level \(updated.level)!")
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
        session.save()
        return lines
    }
}

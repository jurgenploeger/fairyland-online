import Foundation
import Observation

struct BattleResult {
    let outcome: BattleOutcome
    let lines: [String]
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
    @ObservationIgnored weak var scene: BattleScene?
    @ObservationIgnored var onFinish: (@MainActor (BattleOutcome) -> Void)?
    private let engine: BattleEngine
    @ObservationIgnored private var pending: Pending?

    init(engine: BattleEngine, session: GameSession) {
        self.engine = engine
        self.session = session
        combatants = engine.combatants
        let names = engine.alive(on: .enemies).map(\.name)
        message = names.count == 1 ? "A wild \(names[0]) appears!" : "\(names.count) monsters appear!"
    }

    /// Builds a random encounter for the current map.
    static func encounter(_ encounters: MapDef.Encounters, session: GameSession) -> BattleController {
        let content = session.content
        var hero = Combatant(
            id: 0, side: .party, source: .hero, name: session.data.hero.name, art: "player_walk",
            level: session.data.hero.level, element: .neutral, stats: session.heroStats,
            hp: max(1, session.data.hero.hp), mp: session.data.hero.mp,
            skills: session.heroSkills.map(\.id), captureRate: 0
        )
        hero.skillLevels = Dictionary(uniqueKeysWithValues: session.heroSkills.map { ($0.id, session.skillLevel($0.id)) })
        var party: [Combatant] = [hero]
        if let pet = session.activePet, pet.hp > 0, let species = session.species(of: pet) {
            party.append(Combatant(
                id: 1, side: .party, source: .pet(pet.id), name: pet.name, art: species.art,
                level: pet.level, element: species.element, stats: session.stats(of: pet),
                hp: pet.hp, mp: pet.mp, skills: species.skills, captureRate: 0
            ))
        }

        let low = encounters.groupSize.first ?? 1
        let high = max(low, encounters.groupSize.last ?? low)
        let minLevel = encounters.levels.first ?? 1
        let maxLevel = max(minLevel, encounters.levels.last ?? minLevel)
        var enemies: [Combatant] = []
        for index in 0..<Int.random(in: low...high) {
            guard let id = pick(from: encounters.monsters), let species = content.monster(id) else { continue }
            let level = Int.random(in: minLevel...maxLevel)
            let stats = species.stats(at: level)
            enemies.append(Combatant(
                id: 10 + index, side: .enemies, source: .wild(id), name: species.name, art: species.art,
                level: level, element: species.element, stats: stats, hp: stats.hp, mp: stats.mp,
                skills: species.skills, captureRate: species.captureRate
            ))
        }
        // Tell duplicates apart: "Jelly Puff A", "Jelly Puff B".
        let counts = Dictionary(grouping: enemies, by: \.name).mapValues(\.count)
        var seen: [String: Int] = [:]
        for index in enemies.indices where counts[enemies[index].name, default: 0] > 1 {
            let name = enemies[index].name
            let letter = String(UnicodeScalar(UInt8(65 + seen[name, default: 0])))
            seen[name, default: 0] += 1
            enemies[index].name = "\(name) \(letter)"
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

    var hero: Combatant? { combatants.first(where: \.isHero) }
    var party: [Combatant] { combatants.filter { $0.side == .party } }
    var enemies: [Combatant] { combatants.filter { $0.side == .enemies } }
    var skills: [SkillDef] { session.heroSkills }
    var items: [ItemDef] { session.consumables }
    var partyIsFull: Bool { session.data.pets.count >= GameSession.maxPets }

    /// True when some monster is weak enough to capture (the Capture button only shows then).
    var canCapture: Bool {
        guard !partyIsFull else { return false }
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

    func cost(of skill: SkillDef) -> Int { GameSession.mpCost(of: skill, level: level(of: skill)) }

    func useSkill(_ skill: SkillDef) {
        guard let hero, hero.mp >= cost(of: skill) else {
            message = "Not enough MP for \(skill.name)."
            return
        }
        switch skill.target {
        case .enemy: beginTargeting(.skill(skill), targets: aliveEnemyIDs, prompt: "\(skill.name): choose a monster")
        case .ally: beginTargeting(.skill(skill), targets: aliveAllyIDs, prompt: "\(skill.name): choose who")
        case .allEnemies, .allAllies: submit(.skill(skill.id, target: -1))
        }
    }

    func useItem(_ item: ItemDef) {
        beginTargeting(.item(item), targets: aliveAllyIDs, prompt: "Use \(item.name) on…")
    }

    func capture() {
        guard !partyIsFull else {
            message = "You already have \(GameSession.maxPets) companions."
            return
        }
        beginTargeting(.capture, targets: aliveEnemyIDs, prompt: "Capture which monster?")
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
            case .tooHealthy: message = "\(name(id)) is too lively. Weaken it below half HP first!"
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
        if case .item(let id, _) = action { session.removeItem(id) }
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
            message = "\(name(actor)) attacks \(name(hit.target))!" + (hit.critical ? " Critical hit!" : "")
        case .skill(let actor, let skill, let level, let hits):
            mutate(actor) { $0.mp = max(0, $0.mp - GameSession.mpCost(of: skill, level: level)) }
            for hit in hits {
                if skill.kind == .heal {
                    mutate(hit.target) { $0.hp = min($0.stats.hp, $0.hp + hit.amount) }
                } else {
                    damage(hit)
                }
            }
            var text = "\(name(actor)) uses \(skill.name)\(level > 1 ? " Lv\(level)" : "")!"
            if hits.contains(where: { $0.effectiveness > 1 }) { text += " A weak spot!" }
            if hits.contains(where: { $0.effectiveness < 1 }) { text += " It was resisted…" }
            message = text
        case .item(let actor, let item, let target, let hp, let mp):
            mutate(target) {
                $0.hp += hp
                $0.mp += mp
            }
            message = "\(name(actor)) uses a \(item.name) on \(name(target))."
        case .defend(let actor):
            message = "\(name(actor)) is on guard."
        case .capture(_, let target, let success):
            if success { mutate(target) { $0.isCaptured = true } }
            message = success ? "Gotcha! \(name(target)) was captured!" : "Oh no! \(name(target)) broke free!"
        case .escape(_, let success):
            message = success ? "Got away safely!" : "Couldn't get away!"
        case .defeated(let id):
            let fighter = combatants.first { $0.id == id }
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
        switch engine.outcome {
        case .ongoing:
            phase = .command
            message = "What will \(hero?.name ?? "you") do?"
        case .victory:
            finish(.victory, lines: concludeVictory())
        case .defeat:
            session.faint()
            session.save()
            finish(.defeat, lines: ["\(hero?.name ?? "You") fainted…", "You wake up in town, a little bruised."])
        case .escaped:
            syncParty()
            session.save()
            finish(.escaped, lines: ["You got away safely."])
        }
    }

    private func finish(_ outcome: BattleOutcome, lines: [String]) {
        result = BattleResult(outcome: outcome, lines: lines)
        for line in lines { session.post(line, outcome == .victory ? .reward : .battle) }
        phase = .finished
        MusicPlayer.shared.play(outcome == .victory ? "victory" : nil)
    }

    /// Writes battle damage back to the hero and companion.
    private func syncParty() {
        if let hero = engine.hero {
            session.data.hero.hp = max(1, hero.hp)
            session.data.hero.mp = hero.mp
        }
        for fighter in engine.combatants {
            guard let petID = fighter.petID, let index = session.data.pets.firstIndex(where: { $0.id == petID }) else { continue }
            session.data.pets[index].hp = max(1, fighter.hp)
            session.data.pets[index].mp = fighter.mp
        }
    }

    private func concludeVictory() -> [String] {
        syncParty()
        let content = session.content
        var lines: [String] = []

        var exp = 0
        var gold = 0
        for foe in engine.combatants where foe.side == .enemies && !foe.isCaptured {
            guard let id = foe.speciesID, let species = content.monster(id) else { continue }
            exp += Int((Double(species.exp) * (1 + 0.35 * Double(foe.level - 1))).rounded())
            gold += Int((Double(species.gold) * (1 + 0.25 * Double(foe.level - 1))).rounded())
            session.record(.defeat, target: id)
        }
        session.data.gold += gold
        lines.append("+\(exp) EXP    +\(gold) gold")

        let skillsBefore = Set(session.heroSkills.map(\.id))
        if session.gainHeroEXP(exp) > 0 {
            lines.append("\(session.data.hero.name) reached level \(session.data.hero.level)!")
            for skill in session.heroSkills where !skillsBefore.contains(skill.id) {
                lines.append("Learned \(skill.name)!")
            }
            if session.canChooseClass {
                lines.append("You can choose a path now! Visit a guild master in town.")
            }
        }

        if let petID = engine.combatants.first(where: { $0.petID != nil })?.petID,
           let pet = session.data.pets.first(where: { $0.id == petID }) {
            let share = Int((Double(exp) * (session.heroClass.petExpShare ?? 0.5)).rounded())
            if session.gainPetEXP(petID, share) > 0, let updated = session.data.pets.first(where: { $0.id == petID }) {
                lines.append("\(pet.name) grew to level \(updated.level)!")
            }
        }

        for captured in engine.combatants where captured.isCaptured {
            guard let id = captured.speciesID, var pet = session.makePet(species: id, level: captured.level) else { continue }
            pet.hp = max(1, captured.hp)
            if session.addPet(pet) {
                lines.append("\(pet.name) joined your party!")
            }
        }

        if Double.random(in: 0..<1) < 0.25 {
            session.addItem("potion")
            lines.append("Found a Potion!")
        }
        session.save()
        return lines
    }
}

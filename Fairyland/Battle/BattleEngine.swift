import Foundation

nonisolated enum BattleSide: Sendable {
    case party, enemies

    var opposite: BattleSide { self == .party ? .enemies : .party }
}

/// One fighter in a battle: the hero, a companion, or a wild monster.
struct Combatant: Identifiable {
    enum Source: Equatable {
        case hero
        case pet(UUID)
        case wild(String)
    }

    let id: Int
    let side: BattleSide
    let source: Source
    var name: String
    let art: String
    let level: Int
    let element: Element
    let stats: Stats
    var hp: Int
    var mp: Int
    let skills: [String]
    let captureRate: Double
    var isDefending = false
    var isCaptured = false
    /// Skill id → level for the hero; monsters and companions scale with their own level.
    var skillLevels: [String: Int] = [:]

    func skillLevel(_ id: String) -> Int {
        skillLevels[id] ?? min(GameSession.maxSkillLevel, 1 + level / 4)
    }

    var isAlive: Bool { hp > 0 && !isCaptured }
    var isHero: Bool { source == .hero }
    var hpFraction: Double { stats.hp > 0 ? Double(hp) / Double(stats.hp) : 0 }

    var speciesID: String? {
        switch source {
        case .wild(let id): id
        default: nil
        }
    }

    var petID: UUID? {
        switch source {
        case .pet(let id): id
        default: nil
        }
    }
}

enum BattleAction {
    case attack(target: Int)
    /// For skills that hit everyone, `target` is ignored.
    case skill(String, target: Int)
    case item(String, target: Int)
    case capture(target: Int)
    case defend
    case escape
}

struct Hit {
    let target: Int
    let amount: Int
    /// Element multiplier: 1.5 weak spot, 0.75 resisted.
    let effectiveness: Double
    let critical: Bool
}

/// What happened, in order, so the scene can animate it.
enum BattleEvent {
    case attack(actor: Int, hit: Hit)
    case skill(actor: Int, skill: SkillDef, level: Int, hits: [Hit])
    case item(actor: Int, item: ItemDef, target: Int, hp: Int, mp: Int)
    case defend(actor: Int)
    case capture(actor: Int, target: Int, success: Bool)
    case escape(actor: Int, success: Bool)
    case defeated(Int)
    case message(String)
}

enum BattleOutcome: Equatable {
    case ongoing, victory, defeat, escaped
}

enum CaptureStatus: Equatable {
    case ready(chance: Double)
    case tooHealthy
    case impossible
}

/// Fairyland-style turn-based battle rules, with no UI. Each round the player picks the
/// hero's action; companions and monsters decide for themselves; everyone acts in speed order.
final class BattleEngine {
    private(set) var combatants: [Combatant]
    private(set) var outcome: BattleOutcome = .ongoing
    private let content: Content
    private let captureBonus: Double
    private var rng: SeededRandom

    init(party: [Combatant], enemies: [Combatant], content: Content, captureBonus: Double = 1, seed: UInt64 = .random(in: 0...UInt64.max)) {
        combatants = party + enemies
        self.content = content
        self.captureBonus = captureBonus
        rng = SeededRandom(seed: seed)
    }

    var hero: Combatant? { combatants.first(where: \.isHero) }

    func combatant(_ id: Int) -> Combatant? { combatants.first { $0.id == id } }

    func alive(on side: BattleSide) -> [Combatant] {
        combatants.filter { $0.side == side && $0.isAlive }
    }

    /// Monsters can be captured once they're below half HP. Weaker, more wounded monsters are easier.
    func captureStatus(of id: Int) -> CaptureStatus {
        guard let target = combatant(id), target.isAlive, target.side == .enemies, target.captureRate > 0 else { return .impossible }
        guard target.hpFraction <= 0.5 else { return .tooHealthy }
        let heroLevel = hero?.level ?? 1
        let levelFactor = min(1.5, max(0.4, 1 + Double(heroLevel - target.level) * 0.08))
        let chance = target.captureRate * (1.3 - target.hpFraction) * levelFactor * captureBonus
        return .ready(chance: min(0.95, max(0.05, chance)))
    }

    func resolveRound(heroAction: BattleAction) -> [BattleEvent] {
        guard outcome == .ongoing else { return [] }
        for index in combatants.indices {
            combatants[index].isDefending = false
        }
        // Guarding protects for the whole round, even against faster monsters.
        if case .defend = heroAction, let heroID = hero?.id {
            mutate(heroID) { $0.isDefending = true }
        }

        var initiative: [(id: Int, roll: Double)] = []
        for fighter in combatants where fighter.isAlive {
            initiative.append((fighter.id, Double(fighter.stats.speed) + Double.random(in: 0..<4, using: &rng)))
        }
        let order = initiative.sorted { $0.roll > $1.roll }.map { $0.id }

        var events: [BattleEvent] = []
        for actorID in order {
            guard outcome == .ongoing, let actor = combatant(actorID), actor.isAlive else { continue }
            let action: BattleAction = switch actor.source {
            case .hero: heroAction
            case .pet: companionAction(for: actor)
            case .wild: monsterAction(for: actor)
            }
            perform(action, by: actor, events: &events)
            updateOutcome()
        }
        return events
    }

    // MARK: - Actions

    private func perform(_ action: BattleAction, by actor: Combatant, events: inout [BattleEvent]) {
        switch action {
        case .attack(let targetID):
            guard let target = opponent(of: actor, preferring: targetID) else { return }
            let hit = physicalHit(from: actor, to: target, power: 1)
            events.append(.attack(actor: actor.id, hit: hit))
            applyDamage(hit, events: &events)

        case .skill(let skillID, let targetID):
            let level = actor.skillLevel(skillID)
            guard let skill = content.skill(skillID), actor.mp >= GameSession.mpCost(of: skill, level: level) else {
                perform(.attack(target: targetID), by: actor, events: &events)
                return
            }
            mutate(actor.id) { $0.mp -= GameSession.mpCost(of: skill, level: level) }
            // Each skill level adds 20% power.
            let boost = 1 + 0.2 * Double(level - 1)
            let hits = targets(for: skill, actor: actor, preferring: targetID).map { target -> Hit in
                switch skill.kind {
                case .physical: return physicalHit(from: actor, to: target, power: skill.power * boost)
                case .magic: return magicHit(from: actor, to: target, skill: skill, boost: boost)
                case .heal: return Hit(target: target.id, amount: Int(Double(healAmount(actor, skill)) * boost), effectiveness: 1, critical: false)
                }
            }
            events.append(.skill(actor: actor.id, skill: skill, level: level, hits: hits))
            for hit in hits {
                if skill.kind == .heal {
                    mutate(hit.target) { $0.hp = min($0.stats.hp, $0.hp + hit.amount) }
                } else {
                    applyDamage(hit, events: &events)
                }
            }

        case .item(let itemID, let targetID):
            guard let item = content.item(itemID), let target = ally(of: actor, preferring: targetID) else { return }
            let hp = min(item.heal ?? 0, target.stats.hp - target.hp)
            let mp = min(item.mp ?? 0, target.stats.mp - target.mp)
            mutate(target.id) {
                $0.hp += hp
                $0.mp += mp
            }
            events.append(.item(actor: actor.id, item: item, target: target.id, hp: hp, mp: mp))

        case .capture(let targetID):
            guard let target = combatant(targetID), target.isAlive else {
                events.append(.message("There's nothing left to capture."))
                return
            }
            guard case .ready(let chance) = captureStatus(of: targetID) else {
                events.append(.message("\(target.name) is too lively to capture!"))
                return
            }
            let success = Double.random(in: 0..<1, using: &rng) < chance
            if success { mutate(targetID) { $0.isCaptured = true } }
            events.append(.capture(actor: actor.id, target: targetID, success: success))

        case .defend:
            events.append(.defend(actor: actor.id))

        case .escape:
            let foes = alive(on: actor.side.opposite)
            let foeSpeed = foes.isEmpty ? 0 : foes.map(\.stats.speed).reduce(0, +) / foes.count
            let chance = min(0.95, max(0.25, 0.55 + Double(actor.stats.speed - foeSpeed) * 0.04))
            let success = Double.random(in: 0..<1, using: &rng) < chance
            events.append(.escape(actor: actor.id, success: success))
            if success { outcome = .escaped }
        }
    }

    private func companionAction(for pet: Combatant) -> BattleAction {
        guard let weakest = alive(on: .enemies).min(by: { $0.hp < $1.hp }) else { return .defend }
        let attacks = usableSkills(of: pet).filter { $0.kind != .heal }
        if let skill = attacks.randomElement(using: &rng), Double.random(in: 0..<1, using: &rng) < 0.35 {
            return .skill(skill.id, target: weakest.id)
        }
        return .attack(target: weakest.id)
    }

    private func monsterAction(for monster: Combatant) -> BattleAction {
        guard let target = alive(on: .party).randomElement(using: &rng) else { return .defend }
        if let skill = usableSkills(of: monster).randomElement(using: &rng), Double.random(in: 0..<1, using: &rng) < 0.3 {
            return .skill(skill.id, target: target.id)
        }
        return .attack(target: target.id)
    }

    private func usableSkills(of fighter: Combatant) -> [SkillDef] {
        fighter.skills.compactMap { content.skill($0) }.filter { GameSession.mpCost(of: $0, level: fighter.skillLevel($0.id)) <= fighter.mp }
    }

    // MARK: - Targeting

    private func opponent(of actor: Combatant, preferring id: Int) -> Combatant? {
        if let preferred = combatant(id), preferred.isAlive, preferred.side != actor.side { return preferred }
        return alive(on: actor.side.opposite).randomElement(using: &rng)
    }

    private func ally(of actor: Combatant, preferring id: Int) -> Combatant? {
        if let preferred = combatant(id), preferred.isAlive, preferred.side == actor.side { return preferred }
        return alive(on: actor.side).min { $0.hpFraction < $1.hpFraction }
    }

    private func targets(for skill: SkillDef, actor: Combatant, preferring id: Int) -> [Combatant] {
        switch skill.target {
        case .enemy: opponent(of: actor, preferring: id).map { [$0] } ?? []
        case .ally: ally(of: actor, preferring: id).map { [$0] } ?? []
        case .allEnemies: alive(on: actor.side.opposite)
        case .allAllies: alive(on: actor.side)
        }
    }

    // MARK: - Numbers

    private func physicalHit(from attacker: Combatant, to defender: Combatant, power: Double) -> Hit {
        var damage = Double(attacker.stats.attack) * power * 30 / (30 + Double(defender.stats.defense))
        damage *= Double.random(in: 0.9...1.1, using: &rng)
        let critical = Double.random(in: 0..<1, using: &rng) < 0.08
        if critical { damage *= 1.5 }
        if defender.isDefending { damage *= 0.5 }
        return Hit(target: defender.id, amount: max(1, Int(damage.rounded())), effectiveness: 1, critical: critical)
    }

    private func magicHit(from attacker: Combatant, to defender: Combatant, skill: SkillDef, boost: Double) -> Hit {
        let effectiveness = (skill.element ?? .neutral).multiplier(against: defender.element)
        var damage = Double(attacker.stats.magic) * skill.power * boost * 30 / (30 + Double(defender.stats.defense) / 2)
        damage *= effectiveness * Double.random(in: 0.9...1.1, using: &rng)
        if defender.isDefending { damage *= 0.5 }
        return Hit(target: defender.id, amount: max(1, Int(damage.rounded())), effectiveness: effectiveness, critical: false)
    }

    private func healAmount(_ caster: Combatant, _ skill: SkillDef) -> Int {
        Int((Double(caster.stats.magic) * skill.power + 8).rounded())
    }

    private func applyDamage(_ hit: Hit, events: inout [BattleEvent]) {
        guard let index = combatants.firstIndex(where: { $0.id == hit.target }), combatants[index].hp > 0 else { return }
        combatants[index].hp = max(0, combatants[index].hp - hit.amount)
        if combatants[index].hp == 0 { events.append(.defeated(hit.target)) }
    }

    private func mutate(_ id: Int, _ change: (inout Combatant) -> Void) {
        guard let index = combatants.firstIndex(where: { $0.id == id }) else { return }
        change(&combatants[index])
    }

    private func updateOutcome() {
        guard outcome == .ongoing else { return }
        if alive(on: .enemies).isEmpty {
            outcome = .victory
        } else if hero?.isAlive != true {
            outcome = .defeat
        }
    }
}

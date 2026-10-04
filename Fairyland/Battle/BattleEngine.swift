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
        /// A befriended adventurer fighting on your side.
        case ally(UUID)
        /// An adventurer you're duelling.
        case rival(UUID)
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
    /// A wild monster that ran away.
    var hasFled = false
    /// A rarer colour variant (tougher, harder to catch).
    var isRare = false
    /// Skill id → level for the hero; monsters and companions scale with their own level.
    var skillLevels: [String: Int] = [:]
    /// Bless: rounds left, and how much it raises strength and defense (0.25 = +25%).
    var blessRounds = 0
    var blessPower = 0.0
    /// Poison: bites left (one at the end of each round), and how much each takes.
    var poisonRounds = 0
    var poisonDamage = 0
    /// Curse: rounds left, and how much weaker its hits are (0.2 = 20%).
    var curseRounds = 0
    var cursePower = 0.0
    /// People only: their class and race, so each fights in their own style (BattleScene).
    var classID: String?
    var raceID: String?
    /// Which wave of a boss fight it comes in with (1 for everyone else).
    var wave = 1

    /// Strength and defense with any Bless on top.
    var attack: Double { Double(stats.attack) * (blessRounds > 0 ? 1 + blessPower : 1) }
    var defense: Double { Double(stats.defense) * (blessRounds > 0 ? 1 + blessPower : 1) }
    /// How hard its hits land: a curse takes some of the force out of them.
    var hitFactor: Double { curseRounds > 0 ? 1 - cursePower : 1 }
    /// Fainted, but still on the field to be revived (not sealed or run off).
    var isFallen: Bool { hp <= 0 && !isCaptured && !hasFled }

    func skillLevel(_ id: String) -> Int {
        skillLevels[id] ?? Self.naturalSkillLevel(for: level)
    }

    /// Monsters and companions grow into their skills with their own level, mastering them at 18.
    static func naturalSkillLevel(for level: Int) -> Int {
        min(GameSession.maxSkillLevel, 1 + level / 2)
    }

    var isAlive: Bool { hp > 0 && !isCaptured && !hasFled }
    var isHero: Bool { source == .hero }
    var hpFraction: Double { stats.hp > 0 ? Double(hp) / Double(stats.hp) : 0 }
    var mpFraction: Double { stats.mp > 0 ? Double(mp) / Double(stats.mp) : 0 }

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
    /// Wild monsters only: run away when nearly beaten.
    case flee

    /// Running away: nobody else needs telling what to do.
    var isEscape: Bool {
        if case .escape = self { return true }
        return false
    }
}

struct Hit {
    let target: Int
    let amount: Int
    /// Element multiplier: 1.5 weak spot, 0.75 resisted.
    let effectiveness: Double
    let critical: Bool
    /// Caught in the blast around the chosen target of a big spell.
    var splash = false
}

/// What happened, in order, so the scene can animate it.
enum BattleEvent {
    case attack(actor: Int, hit: Hit)
    case skill(actor: Int, skill: SkillDef, level: Int, hits: [Hit])
    case item(actor: Int, item: ItemDef, target: Int, hp: Int, mp: Int)
    case defend(actor: Int)
    /// `wobbles` is how many times the Seal Stone shakes before it seals or bursts open.
    case capture(actor: Int, target: Int, success: Bool, wobbles: Int)
    case escape(actor: Int, success: Bool)
    case fled(Int)
    case defeated(Int)
    case message(String)
    /// A poison or curse took hold: poison bites `rounds` times, a curse lasts `rounds` rounds after this one.
    case afflicted(target: Int, effect: Ailment, rounds: Int)
    /// A poison's bite at the end of a round.
    case ailmentDamage(target: Int, effect: Ailment, amount: Int)
    /// A boss fight's next wave steps onto the field (`number` of `of`), the last with the boss.
    case wave(number: Int, of: Int, arrivals: [Combatant])
}

enum BattleOutcome: Equatable {
    /// `fled`: the last monster ran away (you still get paid for the ones you beat).
    case ongoing, victory, fled, defeat, escaped
}

enum CaptureStatus: Equatable {
    case ready(chance: Double)
    /// Fairyland only let you seal the last monster standing.
    case notAlone
    case tooHealthy
    case impossible
}

/// Fairyland-style turn-based battle rules, with no UI. Each round the player picks the hero's
/// action and can give their companion orders; everyone else decides for themselves; everyone
/// acts in speed order.
final class BattleEngine {
    private(set) var combatants: [Combatant]
    private(set) var outcome: BattleOutcome = .ongoing
    private let content: Content
    private let captureBonus: Double
    private var rng: SeededRandom
    /// Rounds played so far; long fights make monsters warier.
    private(set) var round = 0
    /// Whether the hero throws a Seal Stone this round (everyone else holds back from the monster).
    private var sealing = false
    /// A boss fight comes in waves: the waves still to come, each stepping in once the one on the
    /// field is beaten. The last brings the boss.
    private var waves: [[Combatant]]
    /// The wave on the field, and how many there are in all (1 for an ordinary fight).
    private(set) var wave = 1
    let waveCount: Int
    /// No monster runs from a fight with a boss or an adventurer in it, or still to come.
    private let standsGround: Bool

    /// How many rounds Bless lasts after the one it's cast in.
    static let blessLength = 3

    /// A curse never takes more than half the force out of a fighter's hits.
    static let maxCurse = 0.5

    /// Like Fairyland's capsules: only below 20% HP.
    static let captureThreshold = 0.2

    /// `enemies` is the first wave; `waves` are the ones still to come (a boss fight's).
    init(party: [Combatant], enemies: [Combatant], content: Content, captureBonus: Double = 1,
         seed: UInt64 = .random(in: 0...UInt64.max), waves: [[Combatant]] = []) {
        combatants = party + enemies
        self.content = content
        self.captureBonus = captureBonus
        rng = SeededRandom(seed: seed)
        self.waves = waves
        // Numbered by the fighters themselves, so a fight can open at a later wave (debug launches).
        let first = enemies.first?.wave ?? 1
        wave = first
        waveCount = first + waves.count
        standsGround = (enemies + waves.joined()).contains { $0.captureRate == 0 }
    }

    var hero: Combatant? { combatants.first(where: \.isHero) }

    func combatant(_ id: Int) -> Combatant? { combatants.first { $0.id == id } }

    func alive(on side: BattleSide) -> [Combatant] {
        combatants.filter { $0.side == side && $0.isAlive }
    }

    /// Fairyland-style sealing: the last monster standing, below 20% HP. The weaker it is the
    /// better your odds; tougher, higher-level monsters and long fights make it harder.
    func captureStatus(of id: Int) -> CaptureStatus {
        guard let target = combatant(id), target.isAlive, target.side == .enemies, target.captureRate > 0 else { return .impossible }
        guard alive(on: .enemies).count == 1 else { return .notAlone }
        guard target.hpFraction <= Self.captureThreshold else { return .tooHealthy }
        let weakness = 1 + 2 * (Self.captureThreshold - target.hpFraction) / Self.captureThreshold   // 1…3
        let above = Double(target.level - (hero?.level ?? 1))
        let levelFactor = above > 0 ? max(0.4, 1 - 0.06 * above) : min(1.3, 1 - 0.03 * above)
        let fatigue = pow(0.92, Double(max(0, round - 1)))
        let chance = target.captureRate * 0.3 * weakness * levelFactor * fatigue * captureBonus
        return .ready(chance: min(0.75, max(0.03, chance)))
    }

    /// How much stronger a skill is at `level`: ×1 when learned, ×1.8 when mastered (level 10).
    static func skillBoost(_ level: Int) -> Double {
        1 + 0.8 * Double(min(level, GameSession.maxSkillLevel) - 1) / Double(GameSession.maxSkillLevel - 1)
    }

    /// Share of a spell's damage that also hits everyone else on the target's side: from
    /// skill level 5 up (60% of `splash`), growing to the full `splash` when mastered.
    static func splashFraction(of skill: SkillDef, level: Int) -> Double {
        guard let splash = skill.splash, level >= 5 else { return 0 }
        return splash * (0.6 + 0.4 * Double(min(level, GameSession.maxSkillLevel) - 5) / Double(GameSession.maxSkillLevel - 5))
    }

    /// A nearly beaten monster on its own may bolt.
    private func fleeChance(of monster: Combatant) -> Double {
        // Bosses (who can't be captured) stand their ground, and so do the monsters in their waves,
        // so beating the boss always wins the fight.
        guard monster.captureRate > 0, !standsGround,
              alive(on: .enemies).count == 1, monster.hpFraction <= Self.captureThreshold else { return 0 }
        let panic = (Self.captureThreshold - monster.hpFraction) / Self.captureThreshold
        return min(0.4, 0.05 + 0.15 * panic + 0.02 * Double(round))
    }

    /// `orders`: what the player told their companion to do, by fighter id (Fairyland let you
    /// command your pet each round). A companion without orders decides for itself.
    func resolveRound(heroAction: BattleAction, orders: [Int: BattleAction] = [:]) -> [BattleEvent] {
        guard outcome == .ongoing else { return [] }
        round += 1
        if case .capture = heroAction { sealing = true } else { sealing = false }
        for index in combatants.indices {
            combatants[index].isDefending = false
            if combatants[index].blessRounds > 0 { combatants[index].blessRounds -= 1 }
            if combatants[index].curseRounds > 0 { combatants[index].curseRounds -= 1 }
        }
        // Guarding protects for the whole round, even against faster monsters (a companion told to
        // guard too).
        if case .defend = heroAction, let heroID = hero?.id {
            mutate(heroID) { $0.isDefending = true }
        }
        for (id, order) in orders {
            if case .defend = order { mutate(id) { $0.isDefending = true } }
        }

        var initiative: [(id: Int, roll: Double)] = []
        for fighter in combatants where fighter.isAlive {
            initiative.append((fighter.id, Double(fighter.stats.speed) + Double.random(in: 0..<4, using: &rng)))
        }
        let order = initiative.sorted { $0.roll > $1.roll }.map { $0.id }

        var events: [BattleEvent] = []
        for actorID in order {
            // A wave beaten mid-round: nobody's left to fight until the next one steps in.
            if !waves.isEmpty, alive(on: .enemies).isEmpty { break }
            guard outcome == .ongoing, let actor = combatant(actorID), actor.isAlive else { continue }
            let action: BattleAction = switch actor.source {
            case .hero: heroAction
            case .pet: orders[actor.id] ?? companionAction(for: actor)
            case .wild: monsterAction(for: actor)
            case .ally, .rival: adventurerAction(for: actor)
            }
            perform(action, by: actor, events: &events)
            updateOutcome()
        }
        // Poison bites at the end of the round.
        for fighter in combatants where outcome == .ongoing && fighter.isAlive && fighter.poisonRounds > 0 {
            events.append(.ailmentDamage(target: fighter.id, effect: .poison, amount: fighter.poisonDamage))
            mutate(fighter.id) { $0.poisonRounds -= 1 }
            applyDamage(Hit(target: fighter.id, amount: fighter.poisonDamage, effectiveness: 1, critical: false), events: &events)
            updateOutcome()
        }
        // The wave on the field is beaten: the next one steps in for the next round.
        if outcome == .ongoing, alive(on: .enemies).isEmpty, !waves.isEmpty {
            let arrivals = waves.removeFirst()
            wave += 1
            combatants += arrivals
            events.append(.wave(number: wave, of: waveCount, arrivals: arrivals))
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
            // A mastered skill hits 80% harder than a fresh one, a little more each step.
            let boost = Self.skillBoost(level)
            let chosen = targets(for: skill, actor: actor, preferring: targetID)
            var hits = chosen.map { target -> Hit in
                switch skill.kind {
                case .physical: return physicalHit(from: actor, to: target, power: skill.power * boost)
                case .magic: return magicHit(from: actor, to: target, skill: skill, boost: boost)
                case .heal: return Hit(target: target.id, amount: Int(Double(healAmount(actor, skill)) * boost), effectiveness: 1, critical: false)
                // Revive: back on their feet with a share of their HP (more at higher levels).
                case .revive: return Hit(target: target.id, amount: max(1, Int(Double(target.stats.hp) * skill.power * boost)), effectiveness: 1, critical: false)
                case .buff, .curse, .field: return Hit(target: target.id, amount: 0, effectiveness: 1, critical: false)
                }
            }
            // Big spells spill over: the chosen target takes the full blast, the rest a share.
            let splash = Self.splashFraction(of: skill, level: level)
            if splash > 0, skill.target == .enemy, let main = chosen.first {
                for other in alive(on: main.side) where other.id != main.id {
                    var hit = magicHit(from: actor, to: other, skill: skill, boost: boost * splash)
                    hit.splash = true
                    hits.append(hit)
                }
            }
            events.append(.skill(actor: actor.id, skill: skill, level: level, hits: hits))
            for hit in hits {
                switch skill.kind {
                case .heal, .revive:
                    mutate(hit.target) { $0.hp = min($0.stats.hp, $0.hp + hit.amount) }
                case .buff:
                    let power = skill.power * boost
                    // Lasts this round and the next three.
                    mutate(hit.target) {
                        $0.blessRounds = Self.blessLength + 1
                        $0.blessPower = power
                    }
                case .physical, .magic:
                    applyDamage(hit, events: &events)
                case .curse, .field:
                    break
                }
            }
            // What it leaves behind on everyone it reached (the splash only hurts).
            if let affliction = skill.inflicts {
                for target in chosen {
                    afflict(target.id, with: affliction, from: actor, skill: skill, boost: boost, events: &events)
                }
            }

        case .item(let itemID, let targetID):
            guard let item = content.item(itemID) else { return }
            // If they fainted before your turn came, the item stays in the bag.
            guard let target = combatant(targetID), target.isAlive, target.side == actor.side else {
                events.append(.message("\(combatant(targetID)?.name ?? "They") fainted first, so the \(item.name) stays in your bag."))
                return
            }
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
            // Three wobbles means it held; a near miss shakes longer before bursting open.
            let wobbles = success ? 3 : Int.random(in: 0...2, using: &rng)
            events.append(.capture(actor: actor.id, target: targetID, success: success, wobbles: wobbles))

        case .flee:
            mutate(actor.id) { $0.hasFled = true }
            events.append(.fled(actor.id))

        case .defend:
            // On guard for the rest of the round (the hero's guard is up from the start of it).
            mutate(actor.id) { $0.isDefending = true }
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
        // Don't finish off the monster you're sealing.
        if sealing, case .ready = captureStatus(of: weakest.id) { return .defend }
        let attacks = usableSkills(of: pet).filter(\.kind.isHostile)
        if let skill = attacks.randomElement(using: &rng), Double.random(in: 0..<1, using: &rng) < 0.35 {
            return .skill(skill.id, target: weakest.id)
        }
        return .attack(target: weakest.id)
    }

    private func monsterAction(for monster: Combatant) -> BattleAction {
        guard let target = alive(on: .party).randomElement(using: &rng) else { return .defend }
        if Double.random(in: 0..<1, using: &rng) < fleeChance(of: monster) { return .flee }
        if let skill = usableSkills(of: monster).randomElement(using: &rng), Double.random(in: 0..<1, using: &rng) < 0.3 {
            return .skill(skill.id, target: target.id)
        }
        return .attack(target: target.id)
    }

    /// Adventurers fight like players: heal a friend in trouble, otherwise skills and attacks.
    private func adventurerAction(for fighter: Combatant) -> BattleAction {
        let skills = usableSkills(of: fighter)
        if let heal = skills.filter({ $0.kind == .heal }).max(by: { $0.power < $1.power }),
           let hurt = alive(on: fighter.side).filter({ $0.hpFraction < 0.4 }).min(by: { $0.hpFraction < $1.hpFraction }) {
            return .skill(heal.id, target: hurt.id)
        }
        guard let weakest = alive(on: fighter.side.opposite).min(by: { $0.hp < $1.hp }) else { return .defend }
        // Friends leave the monster you're sealing to you.
        if fighter.side == .party, sealing, case .ready = captureStatus(of: weakest.id) { return .defend }
        let attacks = skills.filter(\.kind.isHostile)
        if let skill = attacks.randomElement(using: &rng), Double.random(in: 0..<1, using: &rng) < 0.45 {
            return .skill(skill.id, target: weakest.id)
        }
        return .attack(target: weakest.id)
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
        case .fallenAlly: fallen(of: actor, preferring: id).map { [$0] } ?? []
        }
    }

    /// A fainted fighter on `actor`'s side to revive: the one chosen if they're still down.
    private func fallen(of actor: Combatant, preferring id: Int) -> Combatant? {
        if let preferred = combatant(id), preferred.isFallen, preferred.side == actor.side { return preferred }
        return combatants.first { $0.side == actor.side && $0.isFallen && !$0.isHero }
    }

    // MARK: - Numbers

    /// Defence softens hits against a constant that grows past level 30, so fights take about
    /// as many hits at level 100 as at level 30 (stats grow with level; a fixed 30 would not).
    private func armorConstant(for defender: Combatant) -> Double {
        30 * max(1, Double(defender.level) / 30)
    }

    private func physicalHit(from attacker: Combatant, to defender: Combatant, power: Double) -> Hit {
        let k = armorConstant(for: defender)
        var damage = attacker.attack * attacker.hitFactor * power * k / (k + defender.defense)
        damage *= Double.random(in: 0.9...1.1, using: &rng)
        let critical = Double.random(in: 0..<1, using: &rng) < 0.08
        if critical { damage *= 1.5 }
        if defender.isDefending { damage *= 0.5 }
        return Hit(target: defender.id, amount: max(1, Int(damage.rounded())), effectiveness: 1, critical: critical)
    }

    private func magicHit(from attacker: Combatant, to defender: Combatant, skill: SkillDef, boost: Double) -> Hit {
        let effectiveness = (skill.element ?? .neutral).multiplier(against: defender.element)
        let k = armorConstant(for: defender)
        var damage = Double(attacker.stats.magic) * attacker.hitFactor * skill.power * boost * k / (k + defender.defense / 2)
        damage *= effectiveness * Double.random(in: 0.9...1.1, using: &rng)
        if defender.isDefending { damage *= 0.5 }
        return Hit(target: defender.id, amount: max(1, Int(damage.rounded())), effectiveness: effectiveness, critical: false)
    }

    /// Lays a poison or curse on a fighter still standing, if it takes hold. A second dose doesn't
    /// stack: it lasts as long, and bites as hard, as the stronger of the two.
    private func afflict(_ id: Int, with affliction: Affliction, from caster: Combatant, skill: SkillDef, boost: Double,
                         events: inout [BattleEvent]) {
        guard let target = combatant(id), target.isAlive,
              Double.random(in: 0..<1, using: &rng) < (affliction.chance ?? 1) else { return }
        switch affliction.effect {
        case .poison:
            let damage = poisonDamage(from: caster, to: target, skill: skill, power: affliction.power * boost)
            mutate(id) {
                $0.poisonRounds = max($0.poisonRounds, affliction.rounds)
                $0.poisonDamage = max($0.poisonDamage, damage)
            }
        case .curse:
            // Like Bless: the rest of this round and the ones after.
            let power = min(Self.maxCurse, affliction.power * boost)
            mutate(id) {
                $0.curseRounds = max($0.curseRounds, affliction.rounds + 1)
                $0.cursePower = max($0.cursePower, power)
            }
        }
        events.append(.afflicted(target: id, effect: affliction.effect, rounds: affliction.rounds))
    }

    /// Each round's poison bite, fixed when it lands: a share of a hit from the caster, magic for
    /// spells and strength for bites, of the skill's element. Guard doesn't keep it out.
    private func poisonDamage(from caster: Combatant, to target: Combatant, skill: SkillDef, power: Double) -> Int {
        let k = armorConstant(for: target)
        let force = skill.kind == .physical ? caster.attack : Double(caster.stats.magic)
        let effectiveness = (skill.element ?? .neutral).multiplier(against: target.element)
        let damage = force * caster.hitFactor * power * effectiveness * k / (k + target.defense / 2)
        return max(1, Int(damage.rounded()))
    }

    private func healAmount(_ caster: Combatant, _ skill: SkillDef) -> Int {
        Int((Double(caster.stats.magic) * skill.power + 8).rounded())
    }

    private func applyDamage(_ hit: Hit, events: inout [BattleEvent]) {
        guard let index = combatants.firstIndex(where: { $0.id == hit.target }), combatants[index].hp > 0 else { return }
        combatants[index].hp = max(0, combatants[index].hp - hit.amount)
        if combatants[index].hp == 0 {
            // Fainting ends poison, curses and blessings; a revived fighter starts clean.
            combatants[index].poisonRounds = 0
            combatants[index].curseRounds = 0
            combatants[index].blessRounds = 0
            events.append(.defeated(hit.target))
        }
    }

    private func mutate(_ id: Int, _ change: (inout Combatant) -> Void) {
        guard let index = combatants.firstIndex(where: { $0.id == id }) else { return }
        change(&combatants[index])
    }

    private func updateOutcome() {
        guard outcome == .ongoing else { return }
        // A beaten wave with another to come isn't a win yet (the next one steps in at the round's end).
        if alive(on: .enemies).isEmpty, waves.isEmpty {
            outcome = combatants.contains { $0.side == .enemies && $0.hasFled } ? .fled : .victory
        } else if hero?.isAlive != true {
            outcome = .defeat
        }
    }

    #if DEBUG
    /// Debug launches (`win`): every monster drops at once, the waves still to come too.
    func defeatEnemiesForDebug() -> [BattleEvent] {
        for arrivals in waves { combatants += arrivals }
        waves = []
        var events: [BattleEvent] = []
        for index in combatants.indices where combatants[index].side == .enemies && combatants[index].isAlive {
            combatants[index].hp = 0
            events.append(.defeated(combatants[index].id))
        }
        updateOutcome()
        return events
    }

    /// Debug launches (`afflict`): the first monster is poisoned, the next one cursed, and the
    /// hero poisoned, so the screenshot shows the marks.
    func afflictForDebug() {
        let foes = alive(on: .enemies)
        if let first = foes.first {
            mutate(first.id) {
                $0.poisonRounds = 3
                $0.poisonDamage = 6
            }
        }
        if foes.count > 1 {
            mutate(foes[1].id) {
                $0.curseRounds = 3
                $0.cursePower = 0.2
            }
        }
        if let hero {
            mutate(hero.id) {
                $0.poisonRounds = 2
                $0.poisonDamage = 4
            }
        }
    }
    #endif
}

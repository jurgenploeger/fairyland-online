import CoreImage
import SpriteKit

/// The battle stage, Fairyland-style: the fight happens right where you were walking (a
/// snapshot of the map), fighters stand on ground circles in two diagonal lines, and every
/// skill has its own effect that grows with the skill's level.
final class BattleScene: SKScene {
    private let controller: BattleController
    private let art = ArtLibrary.shared
    /// Everything that shakes on big hits.
    private let stage = SKNode()
    private let backdrop: SKTexture?
    private lazy var blurredBackdrop: SKTexture? = backdrop.flatMap { Self.blur($0, radius: 5) }
    private var ground: SKNode?
    private var actors: [Int: BattleActor] = [:]
    private var markers: [SKNode] = []
    /// Fainted friends shown faintly while you choose who to revive.
    private var ghosts: Set<Int> = []

    init(controller: BattleController, size: CGSize, backdrop: SKTexture?) {
        self.controller = controller
        self.backdrop = backdrop
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = UIColor(red: 0.2, green: 0.35, blue: 0.3, alpha: 1)
        addChild(stage)
        for fighter in controller.combatants {
            let actor = BattleActor(fighter: fighter, art: art)
            if fighter.isHero {
                actor.setGear(weapon: controller.session.equipped(.weapon), accessory: controller.session.equipped(.accessory))
            }
            actors[fighter.id] = actor
            stage.addChild(actor)
        }
        controller.scene = self
        layout()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        MusicPlayer.shared.play(controller.music)
        layout()
        enter()
    }

    /// Both sides march in from off-stage at the start, monsters hopping into place.
    private func enter() {
        march(actors.values.sorted(by: { $0.fighterID < $1.fighterID }))
    }

    /// Fighters walk in from off-stage to their places, one after another (a boss fight's next
    /// wave comes in the same way).
    private func march(_ group: [BattleActor]) {
        for (index, actor) in group.enumerated() {
            let isEnemy = controller.enemies.contains { $0.id == actor.fighterID }
            let offset = isPortrait
                ? CGVector(dx: isEnemy ? -60 : 60, dy: isEnemy ? 160 : -160)
                : CGVector(dx: isEnemy ? -220 : 220, dy: 0)
            actor.position = actor.home + offset
            actor.alpha = 0
            // Track `home` every frame: the layout can still change while they walk in.
            let duration = 0.5
            let walkIn = SKAction.customAction(withDuration: duration) { node, elapsed in
                guard let actor = node as? BattleActor else { return }
                let t = min(1, elapsed / duration)
                let eased = 1 - (1 - t) * (1 - t)
                actor.position = actor.home + offset * (1 - eased)
                actor.alpha = min(1, t * 2)
            }
            actor.run(.sequence([.wait(forDuration: 0.08 * Double(index)), walkIn]), withKey: "enter")
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layout()
    }

    // MARK: - Layout

    private var isPortrait: Bool { size.height > size.width }
    /// How far a portrait line climbs for each point it runs right (26 up for 108 across).
    private static let portraitSlope: CGFloat = 26.0 / 108.0

    private func layout() {
        guard size.width > 1, size.height > 1 else { return }
        buildGround()
        // Leave room for the HUD: the log line on top, the command wheel bottom-right.
        let insets: (top: CGFloat, bottom: CGFloat) = isPortrait ? (130, 240) : (70, 40)
        let area = CGRect(x: 0, y: insets.bottom, width: size.width, height: max(120, size.height - insets.top - insets.bottom))
        if isPortrait {
            // Monsters up on the left looking down-right at your party, which stands lower on the
            // right looking back up-left; both lines sit around the middle of the screen.
            // A wide gap between the sides, so it reads as two lines facing off.
            arrange(controller.enemiesOnField, around: CGPoint(x: area.midX - 50, y: area.minY + area.height * 0.64), facing: .down)
            arrange(controller.party, around: CGPoint(x: area.midX + 50, y: area.minY + area.height * 0.1), facing: .up)
        } else {
            arrange(controller.enemiesOnField, around: CGPoint(x: area.minX + area.width * 0.28, y: area.midY + 4), facing: .right)
            arrange(controller.party, around: CGPoint(x: area.minX + area.width * 0.6, y: area.midY - 24), facing: .left)
        }
        showTargets(controller.validTargets)
    }

    /// Fighters stand in diagonal lines of up to five, like Fairyland's battle formation; a bigger
    /// group forms a second row behind the first. Companions stand right behind whoever they came
    /// with (yours behind you, a friend's behind them, a rival's behind the rival): the people make
    /// the line, and their companions a row back.
    private func arrange(_ group: [Combatant], around center: CGPoint, facing: Direction) {
        let ids = Set(group.map(\.id))
        let followers = group.filter { fighter in fighter.ownerID.map { ids.contains($0) } == true }
        guard !followers.isEmpty else {
            let rows = stride(from: 0, to: group.count, by: 5).map { Array(group[$0..<min($0 + 5, group.count)]) }
            arrange(rows: rows, around: center, facing: facing)
            return
        }
        let leaders = group.filter { fighter in !followers.contains { $0.id == fighter.id } }
        let front = rowShift(depth: 0.5, facing: facing)
        let backRow = rowShift(depth: -0.5, facing: facing)
        // From a fighter to the spot behind them, one row back.
        let behind = CGVector(dx: backRow.dx - front.dx, dy: backRow.dy - front.dy)
        let points = linePoints(count: leaders.count, around: center + front, facing: facing, trailing: behind)
        for (fighter, point) in zip(leaders, points) {
            actors[fighter.id]?.place(at: point, facing: Self.profile(facing))
        }
        for follower in followers {
            guard let index = leaders.firstIndex(where: { $0.id == follower.ownerID }) else { continue }
            actors[follower.id]?.place(at: points[index] + behind, facing: Self.profile(facing))
        }
    }

    private func arrange(rows: [[Combatant]], around center: CGPoint, facing: Direction) {
        for (index, row) in rows.enumerated() {
            // The first row stands at the back, away from the other side.
            let depth = CGFloat(index) - CGFloat(rows.count - 1) / 2
            arrangeLine(row, around: center + rowShift(depth: depth, facing: facing), facing: facing)
        }
    }

    /// Where a row stands from the middle of the formation, `depth` rows toward the other side
    /// (negative: back, away from it): up-left for monsters, down-right for you.
    private func rowShift(depth: CGFloat, facing: Direction) -> CGVector {
        let toward: CGFloat = facing == .right || facing == .down ? 1 : -1
        return isPortrait
            ? CGVector(dx: depth * 36 * (facing == .down ? 1 : -1), dy: depth * 74 * (facing == .down ? -1 : 1))
            : CGVector(dx: depth * 70 * toward, dy: -depth * 20)
    }

    /// Which way fighters look: across at the other side in profile, as in Fairyland's battles. In
    /// portrait the two lines face off up and down the screen, but people still turn sideways, your
    /// party to the left toward the monsters up on the left and those to the right, instead of
    /// showing their backs. (Monsters have only a front view, so they look the same either way.)
    private static func profile(_ facing: Direction) -> Direction {
        switch facing {
        case .up: .left
        case .down: .right
        default: facing
        }
    }

    private func arrangeLine(_ group: [Combatant], around center: CGPoint, facing: Direction) {
        for (fighter, point) in zip(group, linePoints(count: group.count, around: center, facing: facing)) {
            actors[fighter.id]?.place(at: point, facing: Self.profile(facing))
        }
    }

    /// Spots for a line of `count` fighters around `center`. `trailing`: from each one to the
    /// companion standing behind them, kept on screen too.
    private func linePoints(count: Int, around center: CGPoint, facing: Direction, trailing: CGVector = .zero) -> [CGPoint] {
        // In portrait a long line closes up and slides over so everyone stays on screen.
        let room = size.width - 100 - abs(trailing.dx)
        let spacing = isPortrait ? min(108, room / CGFloat(max(1, count - 1))) : 56
        var center = center
        if isPortrait, count > 1 {
            let half = spacing * CGFloat(count - 1) / 2
            center.x = min(max(center.x, 50 + half + max(0, -trailing.dx)), size.width - 50 - half - max(0, trailing.dx))
        }
        // Each fighter stands a step up from the last, at the same angle on both sides however
        // many stand in a line (a fixed step tilted a packed line of five more than a line of two).
        let rise = isPortrait ? spacing * Self.portraitSlope : -76
        // Only your party needs lifting clear of the command wheel; monsters stay where they are
        // so a long line (and a second row behind it) doesn't climb off the top.
        if isPortrait, count > 1, facing == .up {
            // Its lowest fighter stands where one alone would.
            center.y += rise * CGFloat(count - 1) / 2
        }
        return (0..<count).map { index in
            let offset = CGFloat(index) - CGFloat(count - 1) / 2
            return CGPoint(x: center.x + offset * spacing, y: center.y + offset * rise)
        }
    }

    private func buildGround() {
        ground?.removeFromParent()
        let node = SKNode()
        node.zPosition = -10_000
        if let backdrop {
            // The map you were standing on, softly blurred so the fighters stand out.
            let sprite = SKSpriteNode(texture: blurredBackdrop ?? backdrop)
            let scale = max(size.width / backdrop.size().width, size.height / backdrop.size().height)
            sprite.size = backdrop.size() * scale
            sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
            node.addChild(sprite)
        } else {
            let texture = art.tileTexture("tile_grass")
            let tile: CGFloat = 32
            for col in 0...Int(size.width / tile) {
                for row in 0...Int(size.height / tile) {
                    let sprite = SKSpriteNode(texture: texture, size: CGSize(width: tile, height: tile))
                    sprite.anchorPoint = .zero
                    sprite.position = CGPoint(x: CGFloat(col) * tile, y: CGFloat(row) * tile)
                    node.addChild(sprite)
                }
            }
        }
        let shade = SKSpriteNode(color: UIColor(red: 0.05, green: 0.08, blue: 0.2, alpha: backdrop == nil ? 0.3 : 0.38), size: size)
        shade.anchorPoint = .zero
        shade.zPosition = 2
        node.addChild(shade)
        stage.addChild(node)
        ground = node
    }

    /// Gaussian-blurs a texture once, clamping the edges so the borders don't fade out.
    private static func blur(_ texture: SKTexture, radius: Double) -> SKTexture? {
        let source = CIImage(cgImage: texture.cgImage())
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(source.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: source.extent),
              let image = CIContext(options: nil).createCGImage(output, from: source.extent)
        else { return nil }
        let blurred = SKTexture(cgImage: image)
        blurred.filteringMode = .linear
        return blurred
    }

    // MARK: - Targeting

    func showTargets(_ ids: [Int]) {
        markers.forEach { $0.removeFromParent() }
        markers = []
        for id in ghosts where !ids.contains(id) { actors[id]?.alpha = 0 }
        ghosts = ghosts.filter { ids.contains($0) }
        for id in ids {
            guard let actor = actors[id] else { continue }
            // A fainted friend (for Revive) has faded away: show it as a ghost to tap.
            if controller.combatants.first(where: { $0.id == id })?.isFallen == true {
                actor.alpha = 0.45
                ghosts.insert(id)
            }
            let arrow = SKLabelNode()
            arrow.attributedText = Nodes.outlined("▼", size: 20, color: UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1))
            // Above the name over the fighter's head.
            arrow.position = CGPoint(x: actor.position.x, y: actor.position.y + actor.nameHeight + 8)
            arrow.zPosition = 20_000
            arrow.run(.repeatForever(.sequence([.moveBy(x: 0, y: 5, duration: 0.3), .moveBy(x: 0, y: -5, duration: 0.3)])))
            stage.addChild(arrow)
            markers.append(arrow)
            actor.setHighlighted(true)
        }
        for (id, actor) in actors where !ids.contains(id) {
            actor.setHighlighted(false)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        // Fainted friends count too: they're who Revive is for.
        let candidates = actors.values.filter { controller.validTargets.contains($0.fighterID) }
        guard let tapped = candidates.min(by: { $0.center.distance(to: point) < $1.center.distance(to: point) }),
              tapped.center.distance(to: point) < 80
        else { return }
        controller.select(tapped.fighterID)
    }

    // MARK: - Playback

    func play(_ events: [BattleEvent]) async {
        var index = 0
        while index < events.count {
            // Everyone one blow knocks out (a sweep, a spell and its splash) falls at once.
            var fallen: [Int] = []
            while index < events.count, case .defeated(let id) = events[index] {
                fallen.append(id)
                index += 1
            }
            if fallen.isEmpty {
                await animate(events[index])
                index += 1
            } else {
                await defeat(fallen)
            }
            refreshBars()
        }
    }

    /// Fighters knocked out together fall together: a puff of black smoke each and one fade, so a
    /// sweep that wins the fight doesn't wait on every monster in turn.
    private func defeat(_ ids: [Int]) async {
        controller.applyDefeats(ids)
        let fallen = ids.compactMap { actors[$0] }
        for actor in fallen {
            SkillEffects.smoke(at: actor.center, in: stage)
            actor.run(.group([.fadeOut(withDuration: 0.4), .moveBy(x: 0, y: 14, duration: 0.4)]), withKey: "defeat")
        }
        await pause(fallen.isEmpty ? 0.2 : 0.6)
    }

    private func animate(_ event: BattleEvent) async {
        switch event {
        case .attack(let actorID, let hit):
            await attack(by: actorID, hit: hit) { self.controller.apply(event) }
            await pause(0.3)

        case .skill(let actorID, let skill, let level, let hits):
            controller.apply(event)
            shout(skill.name + "!", over: actorID, color: skill.element?.color, skill: skill)
            await castSkill(skill, level: level, from: actorID, hits: hits)
            await pause(0.35)

        case .item(_, _, let target, let hp, let mp):
            controller.apply(event)
            if let actor = actors[target] {
                SkillEffects.sparkles(on: actor, color: SkillEffects.healGreen, level: 1, in: stage)
                Effects.damageBurst(hp > 0 ? "+\(hp)" : "+\(mp) MP", style: .heal, at: actor.top, in: stage)
            }
            await pause(0.5)

        case .defend(let actorID):
            controller.apply(event)
            if let actor = actors[actorID] {
                SkillEffects.shield(on: actor, in: stage)
                Effects.floatingText("Guard!", color: UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1), at: actor.top, in: stage, size: 14)
            }
            await pause(0.45)

        case .capture(let actorID, let targetID, let success, let wobbles):
            controller.announce("\(controller.name(actorID)) throws a Seal Stone!")
            await captureAnimation(from: actorID, to: targetID, success: success, wobbles: wobbles)
            controller.apply(event)
            await pause(0.6)

        case .fled(let id):
            controller.apply(event)
            if let actor = actors[id] {
                // A panicked hop or two, then off it goes in a puff of dust.
                let away: CGFloat = actor.position.x > size.width / 2 ? 1 : -1
                let hop = SKAction.sequence([.moveBy(x: away * 14, y: 16, duration: 0.12), .moveBy(x: away * 14, y: -16, duration: 0.12)])
                await actor.run(.repeat(hop, count: 2))
                SkillEffects.smoke(at: actor.center, in: stage)
                await actor.run(.group([.moveBy(x: away * size.width * 0.6, y: 0, duration: 0.35), .fadeOut(withDuration: 0.35)]))
            }
            await pause(0.3)

        case .escape(_, let success):
            controller.apply(event)
            if success {
                let dx: CGFloat = isPortrait ? 0 : size.width
                let dy: CGFloat = isPortrait ? -size.height : 0
                for actor in actors.values where controller.party.contains(where: { $0.id == actor.fighterID }) {
                    actor.run(.moveBy(x: dx, y: dy, duration: 0.5), withKey: "escape")
                }
            }
            await pause(0.6)

        case .defeated(let id):
            await defeat([id])

        case .message:
            controller.apply(event)
            await pause(0.8)

        case .afflicted(let targetID, let effect, _):
            controller.apply(event)
            if let actor = actors[targetID] { SkillEffects.afflicted(actor, effect: effect, in: stage) }
            await pause(0.55)

        case .ailmentDamage(let targetID, _, let amount):
            controller.apply(event)
            if let actor = actors[targetID] {
                SkillEffects.poisonBite(on: actor, in: stage)
                Effects.damageBurst("\(amount)", style: .poison, at: actor.top, in: stage)
            }
            await pause(0.45)

        case .wave(_, _, let arrivals):
            controller.apply(event)
            // The beaten wave has left the field; the next marches in to take its place.
            for foe in controller.enemies where foe.wave < controller.wave {
                actors.removeValue(forKey: foe.id)?.removeFromParent()
            }
            var arriving: [BattleActor] = []
            for fighter in arrivals {
                let actor = BattleActor(fighter: fighter, art: art)
                actors[fighter.id] = actor
                stage.addChild(actor)
                arriving.append(actor)
            }
            layout()
            march(arriving)
            await pause(0.9 + 0.08 * Double(arriving.count))
        }
    }

    /// A plain attack in the fighter's own style. Fighters close in with a double slash; mages stay
    /// back and loose a bolt of magic from their staff; beast tamers pounce with claw marks; novices
    /// and monsters dash in with a single slash. Elves dart in quicker and leave a green shimmer,
    /// dwarves hit hard enough to shake the ground.
    private func attack(by actorID: Int, hit: Hit, apply: @escaping () -> Void) async {
        let fighter = controller.combatants.first { $0.id == actorID }
        let target = actors[hit.target]
        let landed: () -> Void = {
            apply()
            if fighter?.raceID == "dwarf" {
                self.shake(strength: 4)
                SkillEffects.burst(at: target?.position ?? .zero, color: UIColor(red: 0.8, green: 0.6, blue: 0.35, alpha: 1), count: 8, speed: 45, in: self.stage)
            }
            if fighter?.raceID == "elf", let target {
                SkillEffects.burst(at: target.center, color: UIColor(red: 0.55, green: 0.95, blue: 0.45, alpha: 1), count: 8, speed: 55, in: self.stage)
            }
            self.impact(hit, heal: false)
        }
        switch fighter?.classID ?? "" {
        case "mage":
            let violet = UIColor(red: 0.75, green: 0.5, blue: 1, alpha: 1)
            if let caster = actors[actorID] {
                caster.sprite.flash(violet)
                SkillEffects.magicCircle(at: caster.position, color: violet, radius: 30, duration: 0.25, in: stage)
            }
            await pause(0.15)
            await SkillEffects.projectile(from: actors[actorID]?.center, to: target?.center, color: violet, level: 1, trail: true, in: stage)
            if let target { SkillEffects.explosion(on: target, color: violet, level: 1, in: stage) }
            landed()
        case "tamer":
            await lunge(actorID, toward: hit.target, speed: fighter?.raceID == "elf" ? 0.7 : 1) {
                if let target { SkillEffects.claws(on: target, level: 2, in: self.stage) }
                landed()
            }
        case "fighter":
            await lunge(actorID, toward: hit.target, speed: fighter?.raceID == "elf" ? 0.7 : 1) {
                SkillEffects.slash(on: target, level: 3, in: self.stage)
                landed()
            }
        default:
            await lunge(actorID, toward: hit.target, speed: fighter?.raceID == "elf" ? 0.7 : 1) {
                SkillEffects.slash(on: target, level: 1, in: self.stage)
                landed()
            }
        }
    }

    /// Picks the effect for a skill; bigger and flashier at higher skill levels, and a full show
    /// (dimmed field, magic circles, an elemental finale) once the skill is mastered.
    private func castSkill(_ skill: SkillDef, level: Int, from actorID: Int, hits: [Hit]) async {
        let targets = hits.compactMap { actors[$0.target] }
        let heal = skill.kind == .heal || skill.kind == .revive
        let blessBlue = UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1)
        let color = skill.element?.color ?? (heal ? SkillEffects.healGreen : skill.kind == .buff ? blessBlue : .white)
        let style = skill.animation ?? (heal ? "heal" : skill.kind == .magic ? "fire" : "slash")
        actors[actorID]?.sprite.flash(color)
        // People gather themselves in their own way (class and race).
        let fighter = controller.combatants.first { $0.id == actorID }
        if let caster = actors[actorID], fighter?.classID != nil || fighter?.raceID != nil {
            SkillEffects.flourish(on: caster, classID: fighter?.classID, raceID: fighter?.raceID, color: color, in: stage)
        }
        // A mastered skill gets the whole stage: its name in gold, the field dims, a magic circle
        // and a pillar of light at the caster; the finale plays after the skill lands.
        // Your hero's and bosses' only: monsters, companions and friends master their skills by
        // level 18, and a show on every one of their turns would drag every battle out.
        let isBoss = fighter?.speciesID.flatMap { Content.shared.monster($0)?.boss } == true
        let mastered = level >= GameSession.maxSkillLevel && (fighter?.isHero == true || isBoss)
        var dimmer: SKNode?
        if mastered {
            SkillEffects.masterBanner(skill.name, level: level, size: size, in: self)
            dimmer = SkillEffects.ultimateStart(caster: actors[actorID], color: color, size: size, in: stage)
            await pause(0.75)
        }
        defer {
            if let dimmer { SkillEffects.ultimateEnd(dimmer, color: color, size: size, in: stage) }
        }
        // The effects grow in five tiers: every two skill levels look a step grander.
        let level = (level + 1) / 2
        if let caster = actors[actorID] {
            let hold = SkillEffects.charge(on: caster, color: color, level: level, in: stage)
            if hold > 0 { await pause(hold) }
        }
        if level >= 3 { SkillEffects.screenFlash(color: color, strength: 0.18 + 0.08 * CGFloat(level - 3), size: size, in: self) }
        // Revive and Bless: a pillar of light on the ally. A revived fighter rises back into view.
        if skill.kind == .revive || skill.kind == .buff {
            for target in targets {
                if skill.kind == .revive {
                    target.run(.group([.fadeIn(withDuration: 0.5), .move(to: target.home, duration: 0.5)]), withKey: "revive")
                }
                SkillEffects.lightPillar(on: target, level: level, in: stage)
            }
            await pause(0.4)
            for hit in hits {
                guard let target = actors[hit.target] else { continue }
                if skill.kind == .revive {
                    SkillEffects.sparkles(on: target, color: SkillEffects.healGreen, level: 2, in: stage)
                    Effects.damageBurst("+\(hit.amount)", style: .heal, at: target.top, in: stage)
                } else {
                    SkillEffects.shield(on: target, in: stage)
                    Effects.floatingText("STR & DEF up!", color: blessBlue, at: target.top, in: stage, size: 13)
                }
            }
            for target in targets { SkillEffects.glory(on: target, color: color, level: level, in: stage) }
            if mastered {
                SkillEffects.ultimateFinale(on: targets, style: "holy", color: color, size: size, in: stage)
                await pause(0.7)
            }
            return
        }

        // Curses and poisons: a dark mote flies to the foe and sinks in (a mist spreads over all of
        // them at once). Each mark shows as it takes hold, in the events after this one.
        if skill.kind == .curse {
            let poison = skill.inflicts?.effect == .poison
            if skill.target != .allEnemies, let first = targets.first {
                await SkillEffects.projectile(from: actors[actorID]?.center, to: first.center, color: color, level: level, trail: true, in: stage)
            }
            for target in targets {
                if poison {
                    SkillEffects.poisonCloud(on: target, level: level, in: stage)
                } else {
                    SkillEffects.curseSpell(on: target, level: level, in: stage)
                }
            }
            await pause(0.35)
            return
        }

        switch style {
        case "slash":
            await lunge(actorID, toward: hits.first?.target ?? actorID) {
                for target in targets { SkillEffects.slash(on: target, level: level, in: self.stage) }
                self.impactAll(hits, heal: false)
            }
        case "whirlwind":
            if let actor = actors[actorID] {
                await actor.run(.group([.rotate(byAngle: .pi * 4, duration: 0.45), .sequence([.scale(to: 1.15, duration: 0.2), .scale(to: 1, duration: 0.25)])]))
                actor.zRotation = 0
            }
            for target in targets { SkillEffects.whirl(on: target, level: level, in: stage) }
            impactAll(hits, heal: false)
        case "fire" where skill.element == .fire:
            await SkillEffects.fireball(from: actors[actorID]?.center, to: targets.first?.center, level: level, in: stage)
            for target in targets { SkillEffects.fireBlast(on: target, level: level, in: stage) }
            impactAll(hits, heal: false)
        case "fire":
            // Magic of another element in the fire style: a glowing bolt in its own colour.
            await SkillEffects.projectile(from: actors[actorID]?.center, to: targets.first?.center, color: color, level: level, trail: true, in: stage)
            for target in targets { SkillEffects.explosion(on: target, color: color, level: level, in: stage) }
            impactAll(hits, heal: false)
        case "stone":
            var erupts: TimeInterval = 0.25
            for target in targets { erupts = SkillEffects.stoneSpikes(under: target, level: level, in: stage) }
            await pause(erupts)
            shake(strength: 2 + CGFloat(level))
            impactAll(hits, heal: false)
        case "leaves":
            for target in targets { SkillEffects.leafCyclone(around: target, level: level, in: stage) }
            await pause(0.45)
            impactAll(hits, heal: false)
        case "water":
            await SkillEffects.waterOrb(from: actors[actorID]?.center, to: targets.first?.center, level: level, in: stage)
            for target in targets { SkillEffects.waterSplash(on: target, level: level, in: stage) }
            impactAll(hits, heal: false)
        case "holy":
            for target in targets { SkillEffects.lightPillar(on: target, level: level, in: stage) }
            await pause(0.35)
            impactAll(hits, heal: heal)
        case "wild":
            for target in targets { SkillEffects.claws(on: target, level: level, in: stage) }
            await pause(0.2)
            impactAll(hits, heal: false)
        case "needles":
            for target in targets { SkillEffects.needles(on: target, level: level, in: stage) }
            await pause(0.35)
            impactAll(hits, heal: false)
        case "bounce":
            await leap(actorID, onto: hits.first?.target ?? actorID) {
                for target in targets { SkillEffects.shockwave(under: target, level: level, in: self.stage) }
                self.impactAll(hits, heal: false)
            }
        case "bite":
            await lunge(actorID, toward: hits.first?.target ?? actorID) {
                for target in targets { SkillEffects.bite(on: target, in: self.stage) }
                self.impactAll(hits, heal: false)
            }
        default:
            for target in targets { SkillEffects.sparkles(on: target, color: color, level: level, in: stage) }
            await pause(0.3)
            impactAll(hits, heal: heal)
        }
        for target in targets { SkillEffects.glory(on: target, color: color, level: level, in: stage) }
        if level >= 4, !heal { shake(strength: CGFloat(level - 2) * 3) }
        if mastered {
            await pause(0.2)
            SkillEffects.ultimateFinale(on: targets, style: style, color: color, size: size, in: stage)
            await pause(0.35)
            SkillEffects.screenFlash(color: .white, strength: 0.55, size: size, in: self)
            if !heal { shake(strength: 14) }
            await pause(0.6)
        }
    }

    // MARK: - Moves

    /// Dash toward the target, run `atContact`, dash back.
    private func lunge(_ actorID: Int, toward targetID: Int, speed: Double = 1, atContact: () -> Void) async {
        guard let actor = actors[actorID], let target = actors[targetID], actorID != targetID else {
            atContact()
            return
        }
        let offset = target.home - actor.home
        let step = offset.normalized * min(offset.length * 0.6, 150)
        let out = SKAction.move(to: actor.home + step, duration: 0.16 * speed)
        out.timingMode = .easeIn
        await actor.run(out)
        atContact()
        let back = SKAction.move(to: actor.home, duration: 0.22 * speed)
        back.timingMode = .easeOut
        await actor.run(back)
    }

    /// Jump in an arc onto the target and slam down.
    private func leap(_ actorID: Int, onto targetID: Int, atContact: () -> Void) async {
        guard let actor = actors[actorID], let target = actors[targetID] else {
            atContact()
            return
        }
        let landing = target.home + (actor.home - target.home).normalized * 40
        let rise = SKAction.group([.move(to: CGPoint(x: (actor.home.x + landing.x) / 2, y: max(actor.home.y, landing.y) + 90), duration: 0.22)])
        rise.timingMode = .easeOut
        let fall = SKAction.move(to: landing, duration: 0.16)
        fall.timingMode = .easeIn
        await actor.run(.sequence([rise, fall]))
        atContact()
        shake(strength: 4)
        await actor.run(.move(to: actor.home, duration: 0.25))
    }

    /// The move's name over whoever made it, with the skill's icon tile in front when there is one,
    /// so every cast (yours, a companion's, a monster's) shows what it was.
    private func shout(_ text: String, over actorID: Int, color: UIColor?, skill: SkillDef? = nil) {
        guard let actor = actors[actorID] else { return }
        let label = SKLabelNode()
        label.attributedText = Nodes.outlined(text, size: 15, color: Nodes.gold)
        label.verticalAlignmentMode = .center
        let group = SKNode()
        group.position = actor.top + CGVector(dx: 0, dy: 36)
        group.zPosition = 22_000
        group.addChild(label)
        if let skill, let tile = Self.skillTile(skill, size: 24) {
            let gap: CGFloat = 4
            let total = tile.frame.width + gap + label.frame.width
            tile.position = CGPoint(x: -total / 2 + tile.frame.width / 2, y: 0)
            label.position.x = tile.position.x + tile.frame.width / 2 + gap + label.frame.width / 2
            group.addChild(tile)
        }
        group.setScale(0.4)
        stage.addChild(group)
        group.run(.sequence([
            .scale(to: 1.1, duration: 0.12), .scale(to: 1, duration: 0.08),
            .wait(forDuration: 0.7), .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 12, duration: 0.3)]),
            .removeFromParent(),
        ]))
    }

    /// A skill's icon on its coloured tile, like `SkillIcon` in the menus.
    private static func skillTile(_ skill: SkillDef, size: CGFloat) -> SKNode? {
        guard let id = skill.art, let image = ArtLibrary.shared.artImage(id) else { return nil }
        let tile = SKShapeNode(rectOf: CGSize(width: size, height: size), cornerRadius: size * 0.26)
        tile.fillColor = skill.tileColor
        tile.strokeColor = UIColor(white: 1, alpha: 0.75)
        tile.lineWidth = 1.5
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        let picture = SKSpriteNode(texture: texture, size: CGSize(width: size * 0.84, height: size * 0.84))
        tile.addChild(picture)
        return tile
    }

    private func impactAll(_ hits: [Hit], heal: Bool) {
        for hit in hits { impact(hit, heal: heal) }
    }

    private func impact(_ hit: Hit, heal: Bool) {
        guard let target = actors[hit.target] else { return }
        if heal {
            SkillEffects.sparkles(on: target, color: SkillEffects.healGreen, level: 2, in: stage)
            Effects.damageBurst("+\(hit.amount)", style: .heal, at: target.top, in: stage)
            return
        }
        Effects.damageBurst("\(hit.amount)", style: hit.critical ? .critical : hit.splash ? .splash : .normal, at: target.top, in: stage)
        if hit.effectiveness > 1 {
            Effects.floatingText("Weak spot!", color: Nodes.gold, at: target.top + CGVector(dx: 0, dy: 22), in: stage, size: 12)
        } else if hit.effectiveness < 1 {
            Effects.floatingText("Resisted", color: UIColor(white: 0.85, alpha: 1), at: target.top + CGVector(dx: 0, dy: 22), in: stage, size: 11)
        }
        target.sprite.flash(.red)
        target.run(.sequence([.moveBy(x: 6, y: 0, duration: 0.04), .moveBy(x: -12, y: 0, duration: 0.06), .moveBy(x: 6, y: 0, duration: 0.04)]))
    }

    private func shake(strength: CGFloat) {
        stage.removeAction(forKey: "shake")
        stage.position = .zero
        var moves: [SKAction] = []
        for index in 0..<6 {
            let amount = strength * CGFloat(6 - index) / 6
            moves.append(.moveTo(x: index % 2 == 0 ? amount : -amount, duration: 0.035))
        }
        moves.append(.moveTo(x: 0, duration: 0.03))
        stage.run(.sequence(moves), withKey: "shake")
    }

    /// Fairyland-style sealing: the stone arcs over, draws the monster in, drops and wobbles
    /// (the suspense!), then either seals with a golden burst or cracks and the monster pops out.
    private func captureAnimation(from actorID: Int, to targetID: Int, success: Bool, wobbles: Int) async {
        guard let actor = actors[actorID], let target = actors[targetID] else { return }
        let stone = SKSpriteNode(texture: SkillEffects.sealStoneTexture)
        stone.size = CGSize(width: 26, height: 26)
        stone.position = actor.center
        stone.zPosition = 15_000
        stage.addChild(stone)

        // Everything else dims so the moment is about the stone.
        let dim = SKSpriteNode(color: .black, size: CGSize(width: size.width * 3, height: size.height * 3))
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dim.zPosition = 14_000
        dim.alpha = 0
        stage.addChild(dim)
        dim.run(.fadeAlpha(to: 0.35, duration: 0.4), withKey: "fade")

        // Throw: a high arc with a spin.
        let hover = target.center + CGVector(dx: 0, dy: target.height * 0.5 + 18)
        let arc = CGMutablePath()
        arc.move(to: stone.position)
        arc.addQuadCurve(to: hover, control: CGPoint(x: (stone.position.x + hover.x) / 2, y: max(stone.position.y, hover.y) + 90))
        let fly = SKAction.follow(arc, asOffset: false, orientToPath: false, duration: 0.55)
        fly.timingMode = .easeInEaseOut
        await stone.run(.group([fly, .rotate(byAngle: .pi * 3, duration: 0.55)]))
        stone.zRotation = 0

        // Draw the monster in: a flash, a beam, and it shrinks into the stone.
        SkillEffects.screenFlash(color: .white, strength: 0.5, size: size, in: self)
        let beam = SKSpriteNode(color: UIColor(red: 0.85, green: 0.75, blue: 1, alpha: 0.7), size: CGSize(width: 18, height: hover.y - target.position.y))
        beam.anchorPoint = CGPoint(x: 0.5, y: 0)
        beam.position = target.position
        beam.zPosition = 14_500
        beam.blendMode = .add
        stage.addChild(beam)
        beam.run(.sequence([.fadeOut(withDuration: 0.5), .removeFromParent()]), withKey: "fade")
        SkillEffects.implode(to: hover, color: UIColor(red: 0.8, green: 0.7, blue: 1, alpha: 1), in: stage)
        target.sprite.color = .white
        await target.run(.group([
            .customAction(withDuration: 0.15) { _, t in target.sprite.colorBlendFactor = t / 0.15 },
            .sequence([.wait(forDuration: 0.12), .group([.scale(to: 0.05, duration: 0.35), .move(to: hover, duration: 0.35), .fadeOut(withDuration: 0.35)])]),
        ]))

        // Drop and wobble.
        let ground = target.home + CGVector(dx: 0, dy: 6)
        let drop = SKAction.move(to: ground, duration: 0.28)
        drop.timingMode = .easeIn
        await stone.run(.sequence([drop, .moveBy(x: 0, y: 8, duration: 0.08), .moveBy(x: 0, y: -8, duration: 0.08)]))
        for index in 0..<wobbles {
            await pause(0.35)
            let tip = SKAction.sequence([
                .rotate(toAngle: 0.45, duration: 0.1), .rotate(toAngle: -0.45, duration: 0.16), .rotate(toAngle: 0, duration: 0.1),
            ])
            await stone.run(.group([tip, .sequence([.moveBy(x: 0, y: 4, duration: 0.12), .moveBy(x: 0, y: -4, duration: 0.12)])]))
            Effects.floatingText(String(repeating: "•", count: index + 1), color: Nodes.gold, at: ground + CGVector(dx: 0, dy: 26), in: stage, size: 16)
        }
        await pause(0.45)

        if success {
            SkillEffects.burst(at: stone.position, color: Nodes.gold, count: 30, speed: 110, in: stage)
            Effects.floatingText("Sealed!", color: Nodes.gold, at: stone.position + CGVector(dx: 0, dy: 34), in: stage, size: 24)
            await stone.run(.sequence([.scale(to: 1.5, duration: 0.12), .scale(to: 1.1, duration: 0.1)]))
            await pause(0.5)
            // The stone floats back to its new friend.
            let home = SKAction.move(to: actor.center, duration: 0.45)
            home.timingMode = .easeInEaseOut
            await stone.run(.group([home, .scale(to: 0.4, duration: 0.45), .sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.15)])]))
        } else {
            SkillEffects.screenFlash(color: .white, strength: 0.35, size: size, in: self)
            SkillEffects.burst(at: stone.position, color: UIColor(red: 0.75, green: 0.7, blue: 0.85, alpha: 1), count: 14, speed: 90, in: stage)
            stone.run(.group([.scale(to: 1.4, duration: 0.15), .fadeOut(withDuration: 0.15)]), withKey: "burst")
            target.position = target.home
            target.setScale(0.3)
            target.sprite.colorBlendFactor = 1
            await target.run(.group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.2)]))
            target.run(.customAction(withDuration: 0.3) { _, t in target.sprite.colorBlendFactor = 1 - t / 0.3 }, withKey: "unflash")
            Effects.floatingText("Broke free!", color: .white, at: target.top, in: stage, size: 18)
        }
        stone.removeFromParent()
        await dim.run(.fadeOut(withDuration: 0.3))
        dim.removeFromParent()
    }

    /// The hero levelled up with the win: light pours down on them in a burst of gold, "LEVEL UP!"
    /// fills the field, and their bars fill up (a new level restores HP and MP, so a hero who
    /// fell gets back up for it).
    func celebrateLevelUp(to level: Int) {
        guard let id = controller.hero?.id, let hero = actors[id] else { return }
        let gold = Nodes.gold
        hero.run(.group([.fadeIn(withDuration: 0.4), .move(to: hero.home, duration: 0.4)]), withKey: "revive")
        hero.setHealth(1, mana: 1)
        SkillEffects.screenFlash(color: gold, strength: 0.3, size: size, in: self)
        SkillEffects.lightPillar(on: hero, level: 5, in: stage)
        SkillEffects.glory(on: hero, color: gold, level: 5, in: stage)
        SkillEffects.burst(at: hero.center, color: gold, count: 24, speed: 130, in: stage)
        hero.sprite.run(.sequence([.moveBy(x: 0, y: 18, duration: 0.16), .moveBy(x: 0, y: -18, duration: 0.2)]), withKey: "cheer")

        let banner = SKNode()
        banner.position = CGPoint(x: size.width / 2, y: size.height * 0.58)
        banner.zPosition = 31_000
        let title = NameTag("LEVEL UP!", color: gold, size: 36, alignment: .center)
        let subtitle = NameTag("Level \(level)", color: .white, size: 18, alignment: .center)
        subtitle.position.y = -36
        banner.addChild(title)
        banner.addChild(subtitle)
        banner.setScale(0.3)
        banner.alpha = 0
        addChild(banner)
        SkillEffects.rays(at: banner.position, color: gold, count: 14, length: 150, width: 10, z: 30_900, in: self)
        banner.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .scale(to: 1.2, duration: 0.2)]),
            .scale(to: 1, duration: 0.12),
            .wait(forDuration: 1),
            .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 24, duration: 0.3)]),
            .removeFromParent(),
        ]))
    }

    /// Bars, and the marks of any poison or curse with the rounds it has left.
    func refreshBars() {
        for fighter in controller.combatants {
            actors[fighter.id]?.setHealth(fighter.hpFraction, mana: fighter.mpFraction)
            // A curse counts the round it's in too; show the rounds still to come.
            actors[fighter.id]?.setAilments(poison: fighter.poisonRounds, curse: max(0, fighter.curseRounds - 1))
        }
    }

    private func pause(_ seconds: TimeInterval) async {
        await run(.wait(forDuration: seconds))
    }

    #if DEBUG
    /// Debug launches (`cast=`): the hero casts a skill at the monsters (all of them, or the first)
    /// without playing a round. With `stopAt` the battle slows right down and freezes that many
    /// seconds into the cast, so a screenshot catches the effect mid-flight.
    func castForDebug(_ skillID: String, level: Int, stopAt: TimeInterval?) {
        guard let skill = Content.shared.skill(skillID), let hero = controller.combatants.first(where: { $0.isHero }) else { return }
        for actor in actors.values {
            actor.removeAction(forKey: "enter")
            actor.position = actor.home
            actor.alpha = 1
        }
        let foes = controller.enemiesOnField.map(\.id)
        let targets = skill.target == .allEnemies ? foes : Array(foes.prefix(1))
        let hits = targets.map { Hit(target: $0, amount: 12, effectiveness: 1, critical: false) }
        if let stopAt {
            speed = 0.03
            run(.sequence([.wait(forDuration: stopAt), .run { [weak self] in self?.isPaused = true }]))
        }
        shout(skill.name + "!", over: hero.id, color: skill.element?.color, skill: skill)
        Task { await castSkill(skill, level: level, from: hero.id, hits: hits) }
    }
    #endif
}

/// One fighter on the battle stage, drawn at 2× on a Fairyland-style ground circle.
final class BattleActor: SKNode {
    let fighterID: Int
    let sprite: SKSpriteNode
    private(set) var home: CGPoint = .zero
    private let cycle: WalkCycle
    private let bar: HealthBar
    private let ring: SKShapeNode

    init(fighter: Combatant, art: ArtLibrary) {
        fighterID = fighter.id
        cycle = art.walkCycle(fighter.art)
        let size = cycle.size * 2
        sprite = SKSpriteNode(texture: cycle.frames(.down).first, size: size)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.05)
        // Everyone with MP shows it in a blue bar under their HP.
        bar = HealthBar(width: 44, level: fighter.level, mana: fighter.stats.mp > 0)
        // Every ground circle is seen from the same angle: its height keeps to its width, so a
        // wide hero's circle isn't flatter than a monster's.
        let ringWidth = max(64, size.width * 0.85)
        ring = SKShapeNode(ellipseOf: CGSize(width: ringWidth, height: ringWidth * Self.ringAspect))
        super.init()
        ring.strokeColor = UIColor(white: 1, alpha: 0.55)
        ring.lineWidth = 2
        ring.fillColor = UIColor(white: 0, alpha: 0.18)
        ring.zPosition = -2
        addChild(ring)
        addChild(sprite)
        // Name, level and HP on one compact plate under the feet: the name in small letters
        // right on top of the bar, so nothing floats over the fighters' heads.
        bar.position = CGPoint(x: 0, y: -25)
        bar.fraction = CGFloat(fighter.hpFraction)
        bar.manaFraction = CGFloat(fighter.mpFraction)
        addChild(bar)
        // The same small gap over every head, wherever the art's top edge sits in its frame.
        nameHeight = size.height * (1 - sprite.anchorPoint.y - Self.emptyTop(of: sprite.texture)) + Self.nameGap
        let label = NameTag(fighter.name, size: 9)
        label.position = CGPoint(x: 0, y: bar.position.y + 2)
        addChild(label)
        sprite.run(IdleMotion.of(art: fighter.art).action(height: size.height, delay: .random(in: 0..<0.8)), withKey: "idle")
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    var height: CGFloat { sprite.size.height }
    var center: CGPoint { position + CGVector(dx: 0, dy: sprite.size.height * 0.45) }
    var top: CGPoint { position + CGVector(dx: 0, dy: sprite.size.height * 0.85) }
    /// Just over the head (the turn arrow points down at it).
    private(set) var nameHeight: CGFloat = 0
    private static let nameGap: CGFloat = 4
    /// A ground circle's height for its width (a monster's 68-wide circle stays 26 tall).
    private static let ringAspect: CGFloat = 26.0 / 68.0

    /// The share of `texture`'s height that's empty above the art.
    private static func emptyTop(of texture: SKTexture?) -> CGFloat {
        guard let image = texture?.cgImage(), image.width > 0, image.height > 0 else { return 0 }
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        // The bitmap's rows run top to bottom, like the image's.
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                return CGFloat(y) / CGFloat(height)
            }
        }
        return 0
    }

    func place(at point: CGPoint, facing direction: Direction) {
        home = point
        if !hasActions() { position = point }
        zPosition = -point.y
        sprite.texture = cycle.frames(direction).first
        facing = direction
        if let weapon = sprite.childNode(withName: "weapon") as? SKSpriteNode {
            GearArt.pose(weapon, facing: direction, height: sprite.size.height)
        }
    }

    private var facing: Direction = .down

    /// The hero's weapon in hand and accessory sparkle (drawn at the sprite's own scale).
    func setGear(weapon: ItemDef?, accessory: ItemDef?) {
        if let weapon, let node = GearArt.weapon(weapon, height: sprite.size.height) {
            sprite.addChild(node)
            GearArt.pose(node, facing: facing, height: sprite.size.height)
        }
        if let accessory, let aura = GearArt.aura(accessory, height: sprite.size.height) {
            addChild(aura)
        }
    }

    func setHealth(_ fraction: Double, mana: Double) {
        bar.fraction = CGFloat(fraction)
        bar.manaFraction = CGFloat(mana)
    }

    /// Poison's green drop and a curse's violet arrow beside the HP bar, each with its rounds left.
    private let marks = SKNode()
    private var shownPoison = 0
    private var shownCurse = 0

    func setAilments(poison: Int, curse: Int) {
        guard poison != shownPoison || curse != shownCurse else { return }
        shownPoison = poison
        shownCurse = curse
        if marks.parent == nil {
            marks.position = CGPoint(x: bar.position.x + 30, y: bar.position.y)
            addChild(marks)
        }
        marks.removeAllChildren()
        var x: CGFloat = 0
        for (rounds, effect) in [(poison, Ailment.poison), (curse, Ailment.curse)] where rounds > 0 {
            let tint = SkillEffects.color(of: effect)
            let icon: SKNode
            if let texture = SkillEffects.fxTexture(effect == .poison ? "status_poison" : "status_curse") {
                icon = SKSpriteNode(texture: texture, size: texture.size() * 2)
            } else {
                let dot = SKShapeNode(circleOfRadius: 5)
                dot.fillColor = tint
                dot.strokeColor = UIColor(white: 0, alpha: 0.7)
                icon = dot
            }
            icon.position = CGPoint(x: x, y: 0)
            marks.addChild(icon)
            let count = SKLabelNode()
            count.attributedText = Nodes.outlined("\(rounds)", size: 9, color: tint)
            count.verticalAlignmentMode = .center
            count.horizontalAlignmentMode = .left
            count.position = CGPoint(x: x + 9, y: -1)
            marks.addChild(count)
            x += 24
        }
    }

    func setHighlighted(_ highlighted: Bool) {
        ring.strokeColor = highlighted ? UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 0.95) : UIColor(white: 1, alpha: 0.55)
        ring.lineWidth = highlighted ? 3 : 2
    }
}

extension Element {
    var color: UIColor {
        switch self {
        case .fire: UIColor(red: 1, green: 0.5, blue: 0.2, alpha: 1)
        case .water: UIColor(red: 0.35, green: 0.65, blue: 1, alpha: 1)
        case .wood: UIColor(red: 0.45, green: 0.85, blue: 0.35, alpha: 1)
        case .earth: UIColor(red: 0.75, green: 0.55, blue: 0.3, alpha: 1)
        case .metal: UIColor(red: 0.85, green: 0.85, blue: 0.9, alpha: 1)
        case .light: UIColor(red: 1, green: 0.95, blue: 0.55, alpha: 1)
        case .dark: UIColor(red: 0.6, green: 0.4, blue: 0.85, alpha: 1)
        case .neutral: .white
        }
    }
}

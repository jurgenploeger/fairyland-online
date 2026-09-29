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
    private var ground: SKNode?
    private var actors: [Int: BattleActor] = [:]
    private var markers: [SKNode] = []

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
            actors[fighter.id] = actor
            stage.addChild(actor)
        }
        controller.scene = self
        layout()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        MusicPlayer.shared.play("battle")
        layout()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layout()
    }

    // MARK: - Layout

    private var isPortrait: Bool { size.height > size.width }

    private func layout() {
        guard size.width > 1, size.height > 1 else { return }
        buildGround()
        // Leave room for the HUD: log + party panel on top, the command wheel bottom-right.
        let insets: (top: CGFloat, bottom: CGFloat) = isPortrait ? (190, 240) : (70, 40)
        let area = CGRect(x: 0, y: insets.bottom, width: size.width, height: max(120, size.height - insets.top - insets.bottom))
        if isPortrait {
            arrange(controller.enemies, around: CGPoint(x: area.midX - 20, y: area.minY + area.height * 0.72), facing: .down)
            arrange(controller.party, around: CGPoint(x: area.midX - 40, y: area.minY + area.height * 0.2), facing: .up)
        } else {
            arrange(controller.enemies, around: CGPoint(x: area.minX + area.width * 0.28, y: area.midY + 4), facing: .right)
            arrange(controller.party, around: CGPoint(x: area.minX + area.width * 0.6, y: area.midY - 24), facing: .left)
        }
        showTargets(controller.validTargets)
    }

    /// Fighters stand in a diagonal line, like Fairyland's battle formation.
    private func arrange(_ group: [Combatant], around center: CGPoint, facing: Direction) {
        for (index, fighter) in group.enumerated() {
            let offset = CGFloat(index) - CGFloat(group.count - 1) / 2
            let point = isPortrait
                ? CGPoint(x: center.x + offset * 108, y: center.y - offset * 26)
                : CGPoint(x: center.x + offset * 56, y: center.y - offset * 76)
            actors[fighter.id]?.place(at: point, facing: facing)
        }
    }

    private func buildGround() {
        ground?.removeFromParent()
        let node = SKNode()
        node.zPosition = -10_000
        if let backdrop {
            // The map you were standing on, softly dimmed — Fairyland fought in place.
            let sprite = SKSpriteNode(texture: backdrop)
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
        let shade = SKSpriteNode(color: UIColor(red: 0.05, green: 0.08, blue: 0.2, alpha: 0.3), size: size)
        shade.anchorPoint = .zero
        shade.zPosition = 2
        node.addChild(shade)
        stage.addChild(node)
        ground = node
    }

    // MARK: - Targeting

    func showTargets(_ ids: [Int]) {
        markers.forEach { $0.removeFromParent() }
        markers = []
        for id in ids {
            guard let actor = actors[id] else { continue }
            let arrow = SKLabelNode()
            arrow.attributedText = Nodes.outlined("▼", size: 20, color: UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1))
            arrow.position = CGPoint(x: actor.position.x, y: actor.position.y + actor.height + 28)
            arrow.zPosition = 20_000
            arrow.run(.repeatForever(.sequence([.moveBy(x: 0, y: 6, duration: 0.3), .moveBy(x: 0, y: -6, duration: 0.3)])))
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
        let candidates = actors.values.filter { $0.alpha > 0.1 && controller.validTargets.contains($0.fighterID) }
        guard let tapped = candidates.min(by: { $0.center.distance(to: point) < $1.center.distance(to: point) }),
              tapped.center.distance(to: point) < 80
        else { return }
        controller.select(tapped.fighterID)
    }

    // MARK: - Playback

    func play(_ events: [BattleEvent]) async {
        for event in events {
            await animate(event)
            refreshBars()
        }
    }

    private func animate(_ event: BattleEvent) async {
        switch event {
        case .attack(let actorID, let hit):
            await lunge(actorID, toward: hit.target) {
                self.controller.apply(event)
                SkillEffects.slash(on: self.actors[hit.target], level: 1, in: self.stage)
                self.impact(hit, heal: false)
            }
            await pause(0.3)

        case .skill(let actorID, let skill, let level, let hits):
            controller.apply(event)
            shout(skill.name + (level > 1 ? " Lv\(level)" : "") + "!", over: actorID, color: skill.element?.color)
            await castSkill(skill, level: level, from: actorID, hits: hits)
            await pause(0.35)

        case .item(_, _, let target, let hp, let mp):
            controller.apply(event)
            if let actor = actors[target] {
                SkillEffects.sparkles(on: actor, color: SkillEffects.healGreen, level: 1, in: stage)
                let text = hp > 0 ? "+\(hp)" : "+\(mp) MP"
                Effects.floatingText(text, color: SkillEffects.healGreen, at: actor.top, in: stage, size: 16)
            }
            await pause(0.5)

        case .defend(let actorID):
            controller.apply(event)
            if let actor = actors[actorID] {
                SkillEffects.shield(on: actor, in: stage)
                Effects.floatingText("Guard!", color: UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1), at: actor.top, in: stage, size: 14)
            }
            await pause(0.45)

        case .capture(let actorID, let targetID, let success):
            controller.announce("\(controller.name(actorID)) throws a capture charm!")
            await captureAnimation(from: actorID, to: targetID, success: success)
            controller.apply(event)
            await pause(0.6)

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
            controller.apply(event)
            if let actor = actors[id] {
                SkillEffects.smoke(at: actor.center, in: stage)
                await actor.run(.group([.fadeOut(withDuration: 0.4), .moveBy(x: 0, y: 14, duration: 0.4)]))
            }
            await pause(0.2)

        case .message:
            controller.apply(event)
            await pause(0.8)
        }
    }

    /// Picks the effect for a skill; bigger and flashier at higher skill levels.
    private func castSkill(_ skill: SkillDef, level: Int, from actorID: Int, hits: [Hit]) async {
        let targets = hits.compactMap { actors[$0.target] }
        let heal = skill.kind == .heal
        let color = skill.element?.color ?? (heal ? SkillEffects.healGreen : .white)
        actors[actorID]?.sprite.flash(color)
        if level >= 3 { SkillEffects.screenFlash(color: color, strength: 0.18 + 0.06 * CGFloat(level - 3), size: size, in: self) }

        switch skill.animation ?? (heal ? "heal" : skill.kind == .magic ? "fire" : "slash") {
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
        case "fire":
            await SkillEffects.projectile(from: actors[actorID]?.center, to: targets.first?.center, color: color, level: level, trail: true, in: stage)
            for target in targets { SkillEffects.explosion(on: target, color: color, level: level, in: stage) }
            impactAll(hits, heal: false)
        case "stone":
            for target in targets { SkillEffects.spikes(under: target, level: level, in: stage) }
            await pause(0.25)
            impactAll(hits, heal: false)
        case "leaves":
            for target in targets { SkillEffects.leafStorm(around: target, level: level, in: stage) }
            await pause(0.45)
            impactAll(hits, heal: false)
        case "water":
            await SkillEffects.projectile(from: actors[actorID]?.center, to: targets.first?.center, color: color, level: level, trail: false, in: stage)
            for target in targets { SkillEffects.splash(on: target, level: level, in: stage) }
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
        if level >= 4, !heal { shake(strength: CGFloat(level - 2) * 2.5) }
    }

    // MARK: - Moves

    /// Dash toward the target, run `atContact`, dash back.
    private func lunge(_ actorID: Int, toward targetID: Int, atContact: () -> Void) async {
        guard let actor = actors[actorID], let target = actors[targetID], actorID != targetID else {
            atContact()
            return
        }
        let offset = target.home - actor.home
        let step = offset.normalized * min(offset.length * 0.6, 150)
        let out = SKAction.move(to: actor.home + step, duration: 0.16)
        out.timingMode = .easeIn
        await actor.run(out)
        atContact()
        let back = SKAction.move(to: actor.home, duration: 0.22)
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

    private func shout(_ text: String, over actorID: Int, color: UIColor?) {
        guard let actor = actors[actorID] else { return }
        let label = SKLabelNode()
        label.attributedText = Nodes.outlined(text, size: 15, color: Nodes.gold)
        label.position = actor.top + CGVector(dx: 0, dy: 26)
        label.zPosition = 22_000
        label.setScale(0.4)
        stage.addChild(label)
        label.run(.sequence([
            .scale(to: 1.1, duration: 0.12), .scale(to: 1, duration: 0.08),
            .wait(forDuration: 0.7), .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 12, duration: 0.3)]),
            .removeFromParent(),
        ]))
    }

    private func impactAll(_ hits: [Hit], heal: Bool) {
        for hit in hits { impact(hit, heal: heal) }
    }

    private func impact(_ hit: Hit, heal: Bool) {
        guard let target = actors[hit.target] else { return }
        if heal {
            SkillEffects.sparkles(on: target, color: SkillEffects.healGreen, level: 2, in: stage)
            Effects.damageNumber("+\(hit.amount)", color: SkillEffects.healGreen, at: target.top, in: stage, big: false)
            return
        }
        Effects.damageNumber("\(hit.amount)", color: hit.critical ? Nodes.gold : .white, at: target.top, in: stage, big: hit.critical)
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

    private func captureAnimation(from actorID: Int, to targetID: Int, success: Bool) async {
        guard let actor = actors[actorID], let target = actors[targetID] else { return }
        let charm = SKShapeNode(circleOfRadius: 9)
        charm.fillColor = UIColor(red: 1, green: 0.55, blue: 0.75, alpha: 1)
        charm.strokeColor = .white
        charm.lineWidth = 2
        charm.glowWidth = 5
        charm.position = actor.center
        charm.zPosition = 15_000
        stage.addChild(charm)
        let arc = SKAction.move(to: target.center, duration: 0.4)
        arc.timingMode = .easeOut
        await charm.run(.group([arc, .rotate(byAngle: .pi * 4, duration: 0.4)]))
        let wiggle = SKAction.sequence([.rotate(byAngle: 0.35, duration: 0.1), .rotate(byAngle: -0.7, duration: 0.2), .rotate(byAngle: 0.35, duration: 0.1)])
        await target.run(.repeat(wiggle, count: 2))
        if success {
            await target.run(.group([.scale(to: 0.1, duration: 0.3), .fadeOut(withDuration: 0.3), .move(to: charm.position, duration: 0.3)]))
            SkillEffects.burst(at: charm.position, color: Nodes.gold, count: 24, speed: 90, in: stage)
            await charm.run(.sequence([.scale(to: 1.6, duration: 0.15), .fadeOut(withDuration: 0.25)]))
        } else {
            SkillEffects.burst(at: charm.position, color: .white, count: 12, speed: 70, in: stage)
            await charm.run(.fadeOut(withDuration: 0.2))
        }
        charm.removeFromParent()
    }

    private func refreshBars() {
        for fighter in controller.combatants {
            actors[fighter.id]?.setHealth(fighter.hpFraction)
        }
    }

    private func pause(_ seconds: TimeInterval) async {
        await run(.wait(forDuration: seconds))
    }
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
        bar = HealthBar(width: 50)
        ring = SKShapeNode(ellipseOf: CGSize(width: max(64, size.width * 0.85), height: 26))
        super.init()
        ring.strokeColor = UIColor(white: 1, alpha: 0.55)
        ring.lineWidth = 2
        ring.fillColor = UIColor(white: 0, alpha: 0.18)
        ring.zPosition = -2
        addChild(ring)
        addChild(sprite)
        bar.position = CGPoint(x: 0, y: -18)
        bar.fraction = CGFloat(fighter.hpFraction)
        addChild(bar)
        let label = Nodes.nameLabel("[Lv.\(fighter.level)] \(fighter.name)")
        label.position = CGPoint(x: 0, y: size.height + 2)
        addChild(label)
        sprite.run(.repeatForever(.sequence([.scaleY(to: 0.95, duration: 0.6), .scaleY(to: 1, duration: 0.6)])))
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    var height: CGFloat { sprite.size.height }
    var center: CGPoint { position + CGVector(dx: 0, dy: sprite.size.height * 0.45) }
    var top: CGPoint { position + CGVector(dx: 0, dy: sprite.size.height * 0.85) }

    func place(at point: CGPoint, facing direction: Direction) {
        home = point
        if !hasActions() { position = point }
        zPosition = -point.y
        sprite.texture = cycle.frames(direction).first
    }

    func setHealth(_ fraction: Double) {
        bar.fraction = CGFloat(fraction)
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

import SpriteKit

/// Poison and curses (Fairyland's dark arts): the spell sinking into its target, the word as it
/// takes hold, and poison's bite at the end of each round; and any stat a spell raises or lowers
/// (a buff, a curse), by how much. The marks by the HP bar are BattleActor's.
extension SkillEffects {
    static let poisonGreen = UIColor(red: 0.62, green: 0.92, blue: 0.32, alpha: 1)
    static let poisonViolet = UIColor(red: 0.72, green: 0.45, blue: 0.95, alpha: 1)
    static let curseViolet = UIColor(red: 0.6, green: 0.36, blue: 0.9, alpha: 1)

    /// The colour of an ailment's word, marks and effects.
    static func color(of effect: Ailment) -> UIColor {
        effect == .poison ? poisonGreen : curseViolet
    }

    /// A curse landing: a dark circle under the target and shadow drawn into it.
    static func curseSpell(on target: BattleActor, level: Int, in parent: SKNode) {
        magicCircle(at: target.position, color: curseViolet, radius: 26 + CGFloat(level) * 3, duration: 0.6, in: parent)
        implode(to: target.center, color: curseViolet, in: parent)
        target.sprite.flash(curseViolet)
    }

    /// A poison spell or mist: a sickly cloud welling up round the target, bubbling.
    static func poisonCloud(on target: BattleActor, level: Int, in parent: SKNode) {
        let cloud = glowSprite(poisonGreen, size: CGSize(width: 76, height: 48))
        cloud.position = target.center
        cloud.zPosition = 18_400
        cloud.alpha = 0
        parent.addChild(cloud)
        cloud.run(.sequence([
            .fadeAlpha(to: 0.55, duration: 0.2), .wait(forDuration: 0.3), .fadeOut(withDuration: 0.4), .removeFromParent(),
        ]))
        bubbles(on: target, count: 4 + level * 2, in: parent)
        target.sprite.flash(poisonGreen)
    }

    /// The poison or curse taking hold: its word over the target's head.
    static func afflicted(_ target: BattleActor, effect: Ailment, in parent: SKNode) {
        let tint = color(of: effect)
        switch effect {
        case .poison: bubbles(on: target, count: 5, in: parent)
        case .curse: implode(to: target.center, color: tint, in: parent)
        }
        Effects.floatingText(effect == .poison ? L("Poisoned!") : L("Cursed!"), color: tint,
                             at: target.top + CGVector(dx: 0, dy: 10), in: parent, size: 14)
    }

    /// Poison's bite at the end of a round: the target shudders green and bubbles rise off it.
    static func poisonBite(on target: BattleActor, in parent: SKNode) {
        target.sprite.flash(poisonGreen)
        bubbles(on: target, count: 4, in: parent)
        target.run(.sequence([
            .moveBy(x: 3, y: 0, duration: 0.05), .moveBy(x: -6, y: 0, duration: 0.08), .moveBy(x: 3, y: 0, duration: 0.05),
        ]), withKey: "shudder")
    }

    /// Raised stats: the blue of the up-arrow mark by the HP bar.
    static let raiseBlue = UIColor(red: 0.45, green: 0.8, blue: 1, alpha: 1)
    /// Lowered stats: the curse's violet, lighter so it reads on the field.
    static let lowerViolet = UIColor(red: 0.8, green: 0.6, blue: 1, alpha: 1)

    /// Stats raised or lowered: each by name and by how much over the fighter's head ("ATK +25%"
    /// in blue, "DEF −20%" in violet), held long enough to read, with motes of light rising off
    /// them for a raise and sinking for a drop.
    static func statChanges(_ changes: [StatChange], on target: BattleActor, in parent: SKNode) {
        guard !changes.isEmpty else { return }
        for (index, change) in changes.enumerated() {
            let line = NameTag("\(change.stat.short) \(BattleController.percent(change.amount))",
                               color: change.amount > 0 ? raiseBlue : lowerViolet, size: 14, alignment: .center)
            line.position = target.top + CGVector(dx: 0, dy: 30 + CGFloat(index) * 17)
            line.zPosition = 21_500
            line.setScale(0.4)
            line.alpha = 0
            parent.addChild(line)
            line.run(.sequence([
                .wait(forDuration: Double(index) * 0.08),
                .group([.fadeIn(withDuration: 0.1), .scale(to: 1.1, duration: 0.14)]),
                .scale(to: 1, duration: 0.08),
                .wait(forDuration: 0.9),
                .group([.moveBy(x: 0, y: 14, duration: 0.35), .fadeOut(withDuration: 0.35)]),
                .removeFromParent(),
            ]))
        }
        let up = changes.contains { $0.amount > 0 }
        let tint = up ? raiseBlue : lowerViolet
        target.sprite.flash(tint)
        for index in 0..<8 {
            let mote = glowSprite(tint, size: CGSize(width: 7, height: 7))
            let start: CGFloat = up ? .random(in: 0...12) : target.height * .random(in: 0.6...0.9)
            mote.position = target.position + CGVector(dx: .random(in: -20...20), dy: start)
            mote.alpha = 0
            parent.addChild(mote)
            let drift = SKAction.moveBy(x: 0, y: up ? 40 : -34, duration: 0.6)
            drift.timingMode = .easeOut
            mote.run(.sequence([
                .wait(forDuration: Double(index) * 0.04),
                .fadeIn(withDuration: 0.06),
                .group([drift, .scale(to: 0.4, duration: 0.6), .sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.3)])]),
                .removeFromParent(),
            ]))
        }
    }

    /// Little green (and now and then violet) bubbles rising off a fighter and popping.
    private static func bubbles(on target: BattleActor, count: Int, in parent: SKNode) {
        let texture = fxTexture("bubble")
        for index in 0..<count {
            let tint = index % 3 == 2 ? poisonViolet : poisonGreen
            let bubble: SKSpriteNode
            if let texture {
                bubble = SKSpriteNode(texture: texture, size: texture.size() * CGFloat.random(in: 1.4...2.2))
                bubble.color = tint
                bubble.colorBlendFactor = 1
            } else {
                bubble = glowSprite(tint, size: CGSize(width: 10, height: 10))
            }
            bubble.position = target.position + CGVector(dx: .random(in: -18...18), dy: .random(in: 4...max(6, target.height * 0.6)))
            bubble.zPosition = 18_500
            bubble.alpha = 0
            parent.addChild(bubble)
            let rise = SKAction.moveBy(x: .random(in: -6...6), y: .random(in: 22...40), duration: 0.7)
            rise.timingMode = .easeOut
            bubble.run(.sequence([
                .wait(forDuration: Double(index) * 0.05),
                .group([
                    .fadeIn(withDuration: 0.1), rise,
                    .sequence([.wait(forDuration: 0.45), .group([.scale(to: 1.5, duration: 0.15), .fadeOut(withDuration: 0.15)])]),
                ]),
                .removeFromParent(),
            ]))
        }
    }
}

import SpriteKit
import UIKit

/// Battle effects, one per skill `animation` in content/skills.json. Every effect grows with the
/// skill's level (1–5): longer beams, more particles, bigger explosions; on top of that, upgraded
/// skills gather power first and land in glory (`charge`, `glory`, `masterBanner`).
enum SkillEffects {
    static let healGreen = UIColor(red: 0.55, green: 1, blue: 0.6, alpha: 1)

    private static func glowSprite(_ color: UIColor, size: CGSize) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: SoftTextures.glow, size: size)
        sprite.color = color
        sprite.colorBlendFactor = 1
        sprite.blendMode = .add
        sprite.zPosition = 18_000
        return sprite
    }

    /// Long crossing light beams — Fairyland's signature blade effect.
    static func slash(on target: BattleActor?, level: Int, in parent: SKNode) {
        guard let target else { return }
        let beams = level >= 3 ? 2 : 1
        let colors = [UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1), UIColor(red: 1, green: 0.45, blue: 0.9, alpha: 1)]
        for index in 0..<beams {
            let beam = glowSprite(colors[index], size: CGSize(width: 90 + CGFloat(level) * 45, height: 10 + CGFloat(level) * 3))
            beam.position = target.center
            beam.zRotation = index == 0 ? -0.55 : 0.6
            beam.xScale = 0.05
            parent.addChild(beam)
            beam.run(.sequence([
                .wait(forDuration: Double(index) * 0.09),
                .scaleX(to: 1, duration: 0.08),
                .fadeOut(withDuration: 0.28),
                .removeFromParent(),
            ]))
        }
        burst(at: target.center, color: .white, count: 4 + level * 3, speed: 60, in: parent)
    }

    static func whirl(on target: BattleActor, level: Int, in parent: SKNode) {
        for index in 0..<(1 + level) {
            let ring = SKShapeNode(ellipseOf: CGSize(width: 50, height: 22))
            ring.strokeColor = UIColor(white: 1, alpha: 0.85)
            ring.lineWidth = 3
            ring.glowWidth = 2
            ring.position = target.position + CGVector(dx: 0, dy: CGFloat(index) * 14)
            ring.zPosition = 18_000
            ring.setScale(0.3)
            parent.addChild(ring)
            ring.run(.sequence([
                .wait(forDuration: Double(index) * 0.05),
                .group([.scale(to: 1.4 + CGFloat(level) * 0.1, duration: 0.3), .fadeOut(withDuration: 0.35), .rotate(byAngle: .pi, duration: 0.35)]),
                .removeFromParent(),
            ]))
        }
    }

    static func projectile(from start: CGPoint?, to end: CGPoint?, color: UIColor, level: Int, trail: Bool, in parent: SKNode) async {
        guard let start, let end else { return }
        let diameter = 20 + CGFloat(level) * 6
        let orb = glowSprite(color, size: CGSize(width: diameter, height: diameter))
        orb.position = start
        let core = glowSprite(.white, size: CGSize(width: diameter * 0.45, height: diameter * 0.45))
        orb.addChild(core)
        if trail {
            let emitter = SKEmitterNode()
            emitter.particleTexture = SoftTextures.glow
            emitter.particleColor = color
            emitter.particleColorBlendFactor = 1
            emitter.particleBlendMode = .add
            emitter.particleBirthRate = 120
            emitter.particleLifetime = 0.35
            emitter.particleSpeed = 20
            emitter.emissionAngleRange = .pi * 2
            emitter.particleScale = 0.35 + CGFloat(level) * 0.06
            emitter.particleScaleSpeed = -0.8
            emitter.particleAlphaSpeed = -2.5
            emitter.targetNode = parent
            orb.addChild(emitter)
        }
        parent.addChild(orb)
        let travel = SKAction.move(to: end, duration: 0.3)
        travel.timingMode = .easeIn
        await orb.run(travel)
        orb.removeFromParent()
    }

    static func explosion(on target: BattleActor, color: UIColor, level: Int, in parent: SKNode) {
        let flash = glowSprite(color, size: CGSize(width: 60, height: 60))
        flash.position = target.center
        flash.setScale(0.3)
        parent.addChild(flash)
        flash.run(.sequence([.group([.scale(to: 1.6 + CGFloat(level) * 0.35, duration: 0.25), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
        burst(at: target.center, color: color, count: 10 + level * 6, speed: 80 + CGFloat(level) * 18, in: parent)
        if level >= 3 {
            // A column of flame rising from the target.
            for index in 0..<(level * 3) {
                let flame = glowSprite(index % 2 == 0 ? color : UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1), size: CGSize(width: 22, height: 22))
                flame.position = target.position + CGVector(dx: .random(in: -18...18), dy: 0)
                parent.addChild(flame)
                flame.run(.sequence([
                    .wait(forDuration: Double(index) * 0.03),
                    .group([.moveBy(x: 0, y: 70 + CGFloat(level) * 12, duration: 0.45), .fadeOut(withDuration: 0.45), .scale(to: 0.3, duration: 0.45)]),
                    .removeFromParent(),
                ]))
            }
        }
    }

    /// Stone spikes erupting from the ground under the target.
    static func spikes(under target: BattleActor, level: Int, in parent: SKNode) {
        let count = 1 + (level + 1) / 2
        for index in 0..<count {
            let height = 34 + CGFloat(level) * 10 - CGFloat(index) * 6
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -9, y: 0))
            path.addLine(to: CGPoint(x: 0, y: height))
            path.addLine(to: CGPoint(x: 9, y: 0))
            path.closeSubpath()
            let spike = SKShapeNode(path: path)
            spike.fillColor = UIColor(red: 0.62, green: 0.48, blue: 0.32, alpha: 1)
            spike.strokeColor = UIColor(red: 0.3, green: 0.2, blue: 0.12, alpha: 1)
            spike.lineWidth = 2
            let spread = CGFloat(index) - CGFloat(count - 1) / 2
            spike.position = target.position + CGVector(dx: spread * 16, dy: -4 - abs(spread) * 4)
            spike.zPosition = target.zPosition + 1
            spike.yScale = 0.05
            parent.addChild(spike)
            spike.run(.sequence([
                .wait(forDuration: Double(index) * 0.06),
                .scaleY(to: 1.1, duration: 0.1), .scaleY(to: 1, duration: 0.05),
                .wait(forDuration: 0.35), .fadeOut(withDuration: 0.25), .removeFromParent(),
            ]))
        }
        burst(at: target.position, color: UIColor(red: 0.75, green: 0.62, blue: 0.45, alpha: 1), count: 6 + level * 3, speed: 50, in: parent)
    }

    static func leafStorm(around target: BattleActor, level: Int, in parent: SKNode) {
        let count = 8 + level * 5
        for index in 0..<count {
            let leaf = SKSpriteNode(texture: SoftTextures.leaf, size: CGSize(width: 10, height: 8))
            leaf.color = index % 3 == 0 ? UIColor(red: 0.95, green: 0.9, blue: 0.4, alpha: 1) : UIColor(red: 0.4, green: 0.85, blue: 0.35, alpha: 1)
            leaf.colorBlendFactor = 0.85
            leaf.zPosition = 18_000
            let radius = CGFloat.random(in: 26...(40 + CGFloat(level) * 6))
            let path = UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius * 0.5, width: radius * 2, height: radius)).cgPath
            leaf.position = target.center
            parent.addChild(leaf)
            leaf.run(.sequence([
                .wait(forDuration: Double(index) * 0.015),
                .group([.follow(path, asOffset: true, orientToPath: true, duration: 0.5), .moveBy(x: 0, y: 30, duration: 0.5)]),
                .fadeOut(withDuration: 0.15),
                .removeFromParent(),
            ]))
        }
    }

    static func splash(on target: BattleActor, level: Int, in parent: SKNode) {
        burst(at: target.center, color: UIColor(red: 0.5, green: 0.8, blue: 1, alpha: 1), count: 10 + level * 4, speed: 70, in: parent)
        let ripple = SKShapeNode(ellipseOf: CGSize(width: 40, height: 16))
        ripple.strokeColor = UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 0.9)
        ripple.lineWidth = 2
        ripple.position = target.position
        ripple.zPosition = target.zPosition - 1
        parent.addChild(ripple)
        ripple.run(.sequence([.group([.scale(to: 2 + CGFloat(level) * 0.3, duration: 0.4), .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
    }

    /// A beam of light from the sky (Blessing).
    static func lightPillar(on target: BattleActor, level: Int, in parent: SKNode) {
        let pillar = glowSprite(UIColor(red: 1, green: 0.95, blue: 0.6, alpha: 1), size: CGSize(width: 44 + CGFloat(level) * 8, height: 360))
        pillar.anchorPoint = CGPoint(x: 0.5, y: 0.05)
        pillar.position = target.position
        pillar.yScale = 0.05
        parent.addChild(pillar)
        pillar.run(.sequence([.scaleY(to: 1, duration: 0.15), .wait(forDuration: 0.2), .fadeOut(withDuration: 0.4), .removeFromParent()]))
        sparkles(on: target, color: UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1), level: level, in: parent)
    }

    /// Three glowing claw rakes (Wild Call).
    static func claws(on target: BattleActor, level: Int, in parent: SKNode) {
        for index in 0..<3 {
            let claw = glowSprite(UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1), size: CGSize(width: 70 + CGFloat(level) * 12, height: 7))
            claw.position = target.center + CGVector(dx: CGFloat(index - 1) * 12, dy: CGFloat(index - 1) * -6)
            claw.zRotation = -0.9
            claw.xScale = 0.05
            parent.addChild(claw)
            claw.run(.sequence([.wait(forDuration: Double(index) * 0.05), .scaleX(to: 1, duration: 0.07), .fadeOut(withDuration: 0.25), .removeFromParent()]))
        }
    }

    static func needles(on target: BattleActor, level: Int, in parent: SKNode) {
        for index in 0..<(6 + level * 3) {
            let needle = SKSpriteNode(color: UIColor(red: 0.45, green: 0.75, blue: 0.3, alpha: 1), size: CGSize(width: 2, height: 12))
            needle.position = target.center + CGVector(dx: .random(in: -30...30), dy: 90)
            needle.zPosition = 18_000
            parent.addChild(needle)
            needle.run(.sequence([
                .wait(forDuration: Double(index) * 0.025),
                .moveBy(x: 0, y: -80, duration: 0.16),
                .fadeOut(withDuration: 0.1),
                .removeFromParent(),
            ]))
        }
    }

    static func shockwave(under target: BattleActor, level: Int, in parent: SKNode) {
        let ring = SKShapeNode(ellipseOf: CGSize(width: 50, height: 20))
        ring.strokeColor = UIColor(white: 1, alpha: 0.9)
        ring.lineWidth = 3
        ring.position = target.position
        ring.zPosition = target.zPosition + 1
        parent.addChild(ring)
        ring.run(.sequence([.group([.scale(to: 2.2 + CGFloat(level) * 0.3, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        burst(at: target.position, color: UIColor(red: 0.8, green: 0.7, blue: 0.55, alpha: 1), count: 8 + level * 2, speed: 60, in: parent)
    }

    static func bite(on target: BattleActor, in parent: SKNode) {
        for side in [-1.0, 1.0] {
            let jaw = SKShapeNode(path: UIBezierPath(arcCenter: .zero, radius: 18, startAngle: 0.3, endAngle: .pi - 0.3, clockwise: true).cgPath)
            jaw.strokeColor = .white
            jaw.lineWidth = 4
            jaw.position = target.center + CGVector(dx: 0, dy: 16 * side)
            jaw.yScale = side
            jaw.zPosition = 18_000
            parent.addChild(jaw)
            jaw.run(.sequence([.moveBy(x: 0, y: -12 * side, duration: 0.1), .fadeOut(withDuration: 0.2), .removeFromParent()]))
        }
    }

    static func sparkles(on target: BattleActor, color: UIColor, level: Int, in parent: SKNode) {
        for index in 0..<(6 + level * 3) {
            let star = SKSpriteNode(texture: SoftTextures.star, size: CGSize(width: 9, height: 9))
            star.color = color
            star.colorBlendFactor = 0.6
            star.blendMode = .add
            star.position = target.position + CGVector(dx: .random(in: -26...26), dy: .random(in: 0...20))
            star.zPosition = 18_000
            star.alpha = 0
            parent.addChild(star)
            star.run(.sequence([
                .wait(forDuration: Double(index) * 0.04),
                .group([.fadeIn(withDuration: 0.1), .moveBy(x: 0, y: 60, duration: 0.6), .sequence([.wait(forDuration: 0.35), .fadeOut(withDuration: 0.25)])]),
                .removeFromParent(),
            ]))
        }
    }

    static func shield(on target: BattleActor, in parent: SKNode) {
        let bubble = SKShapeNode(ellipseOf: CGSize(width: target.sprite.size.width * 1.1, height: target.sprite.size.height * 0.95))
        bubble.fillColor = UIColor(red: 0.5, green: 0.75, blue: 1, alpha: 0.2)
        bubble.strokeColor = UIColor(red: 0.7, green: 0.9, blue: 1, alpha: 0.8)
        bubble.lineWidth = 2
        bubble.position = target.center
        bubble.zPosition = 18_000
        bubble.setScale(0.6)
        parent.addChild(bubble)
        bubble.run(.sequence([.scale(to: 1, duration: 0.15), .wait(forDuration: 0.35), .fadeOut(withDuration: 0.25), .removeFromParent()]))
    }

    /// Dark puffs when something is defeated, like Fairyland's black smoke.
    static func smoke(at point: CGPoint, in parent: SKNode) {
        for _ in 0..<9 {
            let puff = SKSpriteNode(texture: SoftTextures.glow, size: CGSize(width: 26, height: 26))
            puff.color = UIColor(white: 0.08, alpha: 1)
            puff.colorBlendFactor = 1
            puff.alpha = 0.85
            puff.position = point + CGVector(dx: .random(in: -18...18), dy: .random(in: -10...14))
            puff.zPosition = 18_000
            parent.addChild(puff)
            puff.run(.sequence([
                .group([.scale(to: .random(in: 1.6...2.4), duration: 0.6), .moveBy(x: .random(in: -10...10), y: 26, duration: 0.6), .fadeOut(withDuration: 0.6)]),
                .removeFromParent(),
            ]))
        }
    }

    // MARK: - Glory (upgraded skills)

    /// Power gathering around the caster before an upgraded skill (level 2+): rings of light close
    /// in and motes rise, more and brighter with every level; at the top level a golden sunburst
    /// opens behind them. Returns how long to hold before the skill itself plays.
    static func charge(on caster: BattleActor, color: UIColor, level: Int, in parent: SKNode) -> TimeInterval {
        guard level >= 2 else { return 0 }
        let gold = UIColor(red: 1, green: 0.85, blue: 0.35, alpha: 1)
        let tint = level >= 5 ? gold : color
        for index in 0..<(level - 1) {
            let ring = SKShapeNode(ellipseOf: CGSize(width: 70, height: 26))
            ring.strokeColor = tint.withAlphaComponent(0.9)
            ring.lineWidth = 2.5
            ring.glowWidth = 4
            ring.position = caster.position
            ring.zPosition = 18_000
            ring.setScale(2.2)
            ring.alpha = 0
            parent.addChild(ring)
            ring.run(.sequence([
                .wait(forDuration: Double(index) * 0.08),
                .group([.fadeIn(withDuration: 0.08), .scale(to: 0.5, duration: 0.3)]),
                .fadeOut(withDuration: 0.08), .removeFromParent(),
            ]))
        }
        for index in 0..<(level * 5) {
            let mote = glowSprite(index % 3 == 0 ? .white : tint, size: CGSize(width: 9, height: 9))
            mote.position = caster.position + CGVector(dx: .random(in: -26...26), dy: .random(in: -4...10))
            mote.alpha = 0
            parent.addChild(mote)
            mote.run(.sequence([
                .wait(forDuration: .random(in: 0...0.25)),
                .group([.fadeIn(withDuration: 0.06), .moveBy(x: 0, y: 46 + CGFloat(level) * 10, duration: 0.45), .scale(to: 0.3, duration: 0.45)]),
                .fadeOut(withDuration: 0.1), .removeFromParent(),
            ]))
        }
        let aura = glowSprite(tint, size: CGSize(width: 70 + CGFloat(level) * 14, height: 90 + CGFloat(level) * 16))
        aura.position = caster.center
        aura.zPosition = caster.zPosition - 1
        aura.alpha = 0
        parent.addChild(aura)
        aura.run(.sequence([.fadeAlpha(to: 0.35 + 0.1 * CGFloat(level - 2), duration: 0.15), .wait(forDuration: 0.25), .fadeOut(withDuration: 0.3), .removeFromParent()]))
        if level >= 5 {
            rays(at: caster.center, color: gold, count: 14, length: 120, width: 9, z: caster.zPosition - 2, in: parent)
        }
        return 0.25 + 0.06 * Double(level)
    }

    /// The landing of an upgraded skill on each target: a ring of light bursting outward (level 3+),
    /// light rays and a rain of sparkles (4+), all in gold at the top level.
    static func glory(on target: BattleActor, color: UIColor, level: Int, in parent: SKNode) {
        guard level >= 3 else { return }
        let gold = UIColor(red: 1, green: 0.85, blue: 0.35, alpha: 1)
        let tint = level >= 5 ? gold : color
        for index in 0..<(level - 2) {
            let ring = SKShapeNode(ellipseOf: CGSize(width: 40, height: 16))
            ring.strokeColor = index == 0 ? .white : tint
            ring.lineWidth = 3
            ring.glowWidth = 5
            ring.position = target.position
            ring.zPosition = 18_000
            ring.setScale(0.4)
            parent.addChild(ring)
            ring.run(.sequence([
                .wait(forDuration: Double(index) * 0.1),
                .group([.scale(to: 2.4 + CGFloat(level) * 0.4, duration: 0.45), .fadeOut(withDuration: 0.45)]),
                .removeFromParent(),
            ]))
        }
        guard level >= 4 else { return }
        rays(at: target.center, color: tint, count: level >= 5 ? 12 : 8, length: 70 + CGFloat(level) * 14, width: 7,
             z: target.zPosition - 1, in: parent)
        for _ in 0..<(level * 4) {
            let sparkle = SKSpriteNode(texture: SoftTextures.star, size: CGSize(width: 9, height: 9))
            sparkle.color = Bool.random() ? .white : tint
            sparkle.colorBlendFactor = 1
            sparkle.blendMode = .add
            sparkle.zPosition = 18_500
            sparkle.position = target.center + CGVector(dx: .random(in: -50...50), dy: .random(in: 40...90))
            sparkle.alpha = 0
            parent.addChild(sparkle)
            sparkle.run(.sequence([
                .wait(forDuration: .random(in: 0...0.35)),
                .group([.fadeIn(withDuration: 0.08), .moveBy(x: .random(in: -10...10), y: -70, duration: 0.6), .rotate(byAngle: .pi, duration: 0.6)]),
                .fadeOut(withDuration: 0.15), .removeFromParent(),
            ]))
        }
    }

    /// Beams of light fanning out from a point like a sunburst.
    static func rays(at point: CGPoint, color: UIColor, count: Int, length: CGFloat, width: CGFloat, z: CGFloat, in parent: SKNode) {
        for index in 0..<count {
            let ray = glowSprite(color, size: CGSize(width: length, height: width))
            ray.anchorPoint = CGPoint(x: 0, y: 0.5)
            ray.position = point
            ray.zPosition = z
            ray.zRotation = CGFloat(index) / CGFloat(count) * 2 * .pi
            ray.xScale = 0.05
            ray.alpha = 0.9
            parent.addChild(ray)
            ray.run(.sequence([
                .group([.scaleX(to: 1, duration: 0.18), .rotate(byAngle: 0.25, duration: 0.6)]),
                .fadeOut(withDuration: 0.4), .removeFromParent(),
            ]))
        }
    }

    /// A mastered skill (top level) announces itself: its name in big gold letters.
    static func masterBanner(_ name: String, level: Int, size: CGSize, in scene: SKScene) {
        let banner = NameTag("\(name) · Mastered", color: Nodes.gold, size: 26, alignment: .center)
        banner.position = CGPoint(x: size.width / 2, y: size.height * 0.6)
        banner.zPosition = 31_000
        banner.setScale(0.4)
        banner.alpha = 0
        scene.addChild(banner)
        banner.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .scale(to: 1.15, duration: 0.18)]),
            .scale(to: 1, duration: 0.1),
            .wait(forDuration: 0.6),
            .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 20, duration: 0.3)]),
            .removeFromParent(),
        ]))
    }

    static func screenFlash(color: UIColor, strength: CGFloat, size: CGSize, in scene: SKScene) {
        let flash = SKSpriteNode(color: color, size: size)
        flash.anchorPoint = .zero
        flash.alpha = strength
        flash.zPosition = 30_000
        scene.addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.35), .removeFromParent()]))
    }

    static func burst(at point: CGPoint, color: UIColor, count: Int, speed: CGFloat, in parent: SKNode) {
        for index in 0..<count {
            let bit = glowSprite(color, size: CGSize(width: 8, height: 8))
            bit.position = point
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi + .random(in: -0.2...0.2)
            let distance = speed * .random(in: 0.5...1)
            let move = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance * 0.7, duration: 0.4)
            move.timingMode = .easeOut
            parent.addChild(bit)
            bit.run(.sequence([.group([move, .fadeOut(withDuration: 0.4), .scale(to: 0.3, duration: 0.4)]), .removeFromParent()]))
        }
    }

    /// Motes swirling inward to a point (a monster being drawn into a Seal Stone).
    static func implode(to point: CGPoint, color: UIColor, in parent: SKNode) {
        for index in 0..<18 {
            let bit = glowSprite(color, size: CGSize(width: 7, height: 7))
            let angle = CGFloat(index) / 18 * 2 * .pi
            let distance = CGFloat.random(in: 50...80)
            bit.position = point + CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance * 0.7)
            bit.alpha = 0
            parent.addChild(bit)
            let swirl = SKAction.move(to: point, duration: 0.45)
            swirl.timingMode = .easeIn
            bit.run(.sequence([.wait(forDuration: Double(index % 6) * 0.03), .fadeIn(withDuration: 0.08),
                               .group([swirl, .scale(to: 0.3, duration: 0.45)]), .removeFromParent()]))
        }
    }

    /// A round lavender stone with a glowing rune ring: Fairyland's capture capsule.
    static let sealStoneTexture: SKTexture = {
        let size = CGSize(width: 52, height: 52)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
            let colors = [UIColor(red: 0.85, green: 0.8, blue: 1, alpha: 1).cgColor, UIColor(red: 0.45, green: 0.35, blue: 0.75, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.saveGState()
            UIBezierPath(ovalIn: rect).addClip()
            context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: rect.midX - 8, y: rect.midY - 10), startRadius: 2,
                                                 endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width / 2, options: .drawsAfterEndLocation)
            context.cgContext.restoreGState()
            let rune = UIBezierPath(ovalIn: rect.insetBy(dx: 10, dy: 10))
            UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 0.95).setStroke()
            rune.lineWidth = 3
            rune.stroke()
            let dot = UIBezierPath(ovalIn: CGRect(x: rect.midX - 4, y: rect.midY - 4, width: 8, height: 8))
            UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1).setFill()
            dot.fill()
            UIColor(white: 1, alpha: 0.7).setFill()
            UIBezierPath(ovalIn: CGRect(x: rect.minX + 9, y: rect.minY + 7, width: 12, height: 7)).fill()
            UIColor(red: 0.2, green: 0.12, blue: 0.35, alpha: 1).setStroke()
            let rim = UIBezierPath(ovalIn: rect)
            rim.lineWidth = 2.5
            rim.stroke()
        }
        return SKTexture(image: image)
    }()
}

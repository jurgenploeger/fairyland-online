import SpriteKit
import UIKit

/// The elemental spells in pixel art (art/sprites/fx_*.png, drawn by tools/fx_art.py): rock spikes
/// bursting out of cracked ground, a fireball that blooms into a blast, a cyclone of leaves, an orb
/// of water that splashes. Their pixels are drawn at 2× like every fighter (3× for the big tiers),
/// they grow in the same five tiers as the rest of SkillEffects, and each falls back to its old
/// glow effect if its sprites are missing.
extension SkillEffects {
    static func fxTexture(_ name: String) -> SKTexture? {
        ArtLibrary.shared.generatedTexture("fx_\(name)")
    }

    /// `fx_<name>_0` … `fx_<name>_<count - 1>`, or nil unless every frame is there.
    static func fxFrames(_ name: String, count: Int) -> [SKTexture]? {
        let frames = (0..<count).compactMap { fxTexture("\(name)_\($0)") }
        return frames.count == count ? frames : nil
    }

    private static func pixelSprite(_ texture: SKTexture, scale: CGFloat) -> SKSpriteNode {
        SKSpriteNode(texture: texture, size: texture.size() * scale)
    }

    /// Reveals a hidden sprite from its tip down, as if it were pushing up out of the ground (or,
    /// with `sinking`, hides it again from the bottom up), whole texture rows at a time so its
    /// pixels stay square. The sprite needs its anchor at its bottom edge and its pixel scale in
    /// xScale and yScale (each step resizes it to the rows it shows).
    private static func emerge(_ texture: SKTexture, duration: TimeInterval, sinking: Bool = false) -> SKAction {
        let rows = max(1, Int(texture.size().height.rounded()))
        let steps = min(rows, 8)
        var actions: [SKAction] = []
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let shown = sinking ? 1 - t * t : 1 - (1 - t) * (1 - t)
            let count = max(1, min(rows, Int((shown * CGFloat(rows)).rounded())))
            let fraction = CGFloat(count) / CGFloat(rows)
            let part = SKTexture(rect: CGRect(x: 0, y: 1 - fraction, width: 1, height: fraction), in: texture)
            part.filteringMode = .nearest
            actions.append(.setTexture(part, resize: true))
            if step == 1 && !sinking { actions.append(.unhide()) }
            actions.append(.wait(forDuration: duration / Double(steps)))
        }
        return .sequence(actions)
    }

    // MARK: - Stone

    /// Where the spikes stand round the target's feet: `dy` above zero is behind it. They flank
    /// the target (one in the middle would hide behind it), the tall ones behind poking up over
    /// its head. Each tier adds more; at the top tier a giant spike rises behind the target in
    /// place of the tall one, and a short one bursts up right under its feet from tier 4.
    private struct SpikeSpot {
        let art: String
        let dx: CGFloat
        let dy: CGFloat
        let scale: CGFloat
        let tiers: ClosedRange<Int>
    }

    private static let spikeSpots: [SpikeSpot] = [
        SpikeSpot(art: "spike_tall", dx: -20, dy: 8, scale: 2, tiers: 1...4),
        SpikeSpot(art: "spike_tall", dx: -6, dy: 12, scale: 3, tiers: 5...5),
        SpikeSpot(art: "spike_low", dx: -36, dy: -5, scale: 2, tiers: 1...5),
        SpikeSpot(art: "spike_mid", dx: 32, dy: 5, scale: 2, tiers: 1...5),
        SpikeSpot(art: "spike_low", dx: 30, dy: -9, scale: 2, tiers: 1...5),
        SpikeSpot(art: "spike_thin", dx: -50, dy: 3, scale: 2, tiers: 2...5),
        SpikeSpot(art: "spike_thin", dx: 50, dy: 1, scale: 2, tiers: 3...5),
        SpikeSpot(art: "spike_mid", dx: -38, dy: 11, scale: 2, tiers: 4...5),
        SpikeSpot(art: "spike_low", dx: -4, dy: -18, scale: 2, tiers: 4...5),
        SpikeSpot(art: "spike_thin", dx: 16, dy: 14, scale: 2, tiers: 5...5),
    ]

    /// Stone Spike: the ground under the target cracks and shudders, then rock spikes burst up
    /// round it from the middle outward (tall ones behind, short ones in front), heaving dust and
    /// throwing rocks, and knock it up off its feet; they stand a moment and sink back. `spread`
    /// widens the ring (a mastered skill's forest of spikes). Returns how long until they break
    /// through, when the hit should land.
    @discardableResult
    static func stoneSpikes(under target: BattleActor, level: Int, spread: CGFloat = 1, delay: TimeInterval = 0,
                            in parent: SKNode) -> TimeInterval {
        let spots = spikeSpots.filter { $0.tiers.contains(level) }.sorted { abs($0.dx) < abs($1.dx) }
        guard let crackTexture = fxTexture("crack"), spots.allSatisfy({ fxTexture($0.art) != nil }) else {
            spikes(under: target, level: level, in: parent)
            return 0.25
        }
        let base = target.position
        let erupt = delay + 0.16
        let crack = pixelSprite(crackTexture, scale: level >= 5 || spread > 1 ? 3 : 2)
        crack.position = base
        crack.zPosition = -8_600   // on the ground, under every fighter
        crack.alpha = 0
        crack.xScale = 0.3
        parent.addChild(crack)
        crack.run(.sequence([
            .wait(forDuration: delay),
            .group([.fadeIn(withDuration: 0.1), .scaleX(to: 1, duration: 0.14)]),
            .wait(forDuration: 0.85 + 0.05 * Double(level)),
            .fadeOut(withDuration: 0.4),
            .removeFromParent(),
        ]))
        // Pebbles hop on the cracking ground before it gives way.
        let rocks = ["rock_a", "rock_b", "rock_c"].compactMap { fxTexture($0) }
        for index in 0..<3 where !rocks.isEmpty {
            let spot = base + CGVector(dx: .random(in: -26...26), dy: .random(in: -6...6))
            toss(rocks[index % rocks.count], from: spot, ground: spot.y, power: 0.35, delay: delay + Double(index) * 0.04, in: parent)
        }
        for (index, spot) in spots.enumerated() {
            guard let texture = fxTexture(spot.art) else { continue }
            let foot = base + CGVector(dx: spot.dx * spread, dy: spot.dy * spread)
            let spike = SKSpriteNode(texture: texture)
            spike.setScale(spot.scale)
            spike.anchorPoint = CGPoint(x: 0.5, y: 0)
            // fx_art draws the foot three rows up from the bottom, over the soil it heaves up.
            spike.position = foot + CGVector(dx: 0, dy: -2 * spot.scale)
            spike.zPosition = -foot.y   // stands among the fighters: in front of them or behind
            spike.isHidden = true
            parent.addChild(spike)
            let start = erupt + Double(index) * 0.035
            let up = SKAction.moveBy(x: 0, y: 3 * spot.scale, duration: 0.05)
            up.timingMode = .easeOut
            let settle = SKAction.moveBy(x: 0, y: -3 * spot.scale, duration: 0.08)
            settle.timingMode = .easeIn
            spike.run(.sequence([
                .wait(forDuration: start),
                emerge(texture, duration: 0.1),
                up, settle,
                .wait(forDuration: max(0.15, 0.3 + 0.04 * Double(level) - Double(index) * 0.02)),
                emerge(texture, duration: 0.2, sinking: true),
                .removeFromParent(),
            ]))
            dust(at: foot + CGVector(dx: 0, dy: -2), z: spike.zPosition + 0.5, drift: spot.dx >= 0 ? 14 : -14,
                 delay: start + 0.04, scale: spot.scale, in: parent)
            for chunk in 0..<(spot.scale > 2 ? 3 : 1) where !rocks.isEmpty {
                toss(rocks[(index + chunk) % rocks.count], from: foot + CGVector(dx: 0, dy: 16 * spot.scale),
                     ground: foot.y - CGFloat.random(in: 0...12), power: 1 + 0.1 * CGFloat(level), delay: start + 0.05, in: parent)
            }
        }
        // The hit knocks the target up off its feet.
        let hop = 8 + 3 * CGFloat(level)
        let rise = SKAction.moveBy(x: 0, y: hop, duration: 0.08)
        rise.timingMode = .easeOut
        let land = SKAction.moveBy(x: 0, y: -hop, duration: 0.2)
        land.timingMode = .easeIn
        target.sprite.run(.sequence([.wait(forDuration: erupt + 0.05), rise, land]))
        return erupt + 0.08
    }

    /// A puff of dust that billows up, drifts and thins out.
    private static func dust(at point: CGPoint, z: CGFloat, drift: CGFloat, delay: TimeInterval, scale: CGFloat, in parent: SKNode) {
        guard let frames = fxFrames("dust", count: 4) else { return }
        let puff = pixelSprite(frames[0], scale: scale)
        puff.anchorPoint = CGPoint(x: 0.5, y: 0.15)
        puff.position = point
        puff.zPosition = z
        puff.isHidden = true
        parent.addChild(puff)
        puff.run(.sequence([
            .wait(forDuration: delay),
            .unhide(),
            .group([.animate(with: frames, timePerFrame: 0.09), .moveBy(x: drift, y: 6, duration: 0.36)]),
            .group([.fadeOut(withDuration: 0.2), .moveBy(x: drift * 0.4, y: 3, duration: 0.2)]),
            .removeFromParent(),
        ]))
    }

    /// A rock chunk thrown up in an arc: it tumbles, lands on the ground at `ground` and fades.
    private static func toss(_ texture: SKTexture, from point: CGPoint, ground: CGFloat, power: CGFloat, delay: TimeInterval,
                             in parent: SKNode) {
        let rock = pixelSprite(texture, scale: 2)
        rock.position = point
        rock.zPosition = -ground   // among the fighters, by where it lands: a rock behind one stays behind
        rock.isHidden = true
        parent.addChild(rock)
        let vx = CGFloat.random(in: -110...110) * power
        let vy = CGFloat.random(in: 180...280) * power
        let gravity: CGFloat = 1_100
        let duration: TimeInterval = 0.3 + 0.35 * Double(power)
        let flight = SKAction.customAction(withDuration: duration) { node, t in
            let height = point.y + vy * t - gravity * t * t / 2
            node.position = CGPoint(x: point.x + vx * t, y: max(ground, height))
        }
        rock.run(.sequence([
            .wait(forDuration: delay),
            .unhide(),
            .group([flight, .rotate(byAngle: .random(in: -7...7), duration: duration),
                    .sequence([.wait(forDuration: duration * 0.7), .fadeOut(withDuration: duration * 0.3)])]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Fire

    private static let emberColors: [UIColor] = [
        UIColor(red: 1, green: 0.96, blue: 0.75, alpha: 1),
        UIColor(red: 1, green: 0.79, blue: 0.24, alpha: 1),
        UIColor(red: 1, green: 0.49, blue: 0.11, alpha: 1),
        UIColor(red: 0.82, green: 0.23, blue: 0.08, alpha: 1),
    ]

    /// A spark one or two game pixels big that drifts off and dies out.
    private static func ember(at point: CGPoint, drift: CGVector, z: CGFloat, in parent: SKNode) {
        let side: CGFloat = Bool.random() ? 4 : 2
        let color = emberColors[Int.random(in: 0..<emberColors.count)]
        let spark = SKSpriteNode(color: color, size: CGSize(width: side, height: side))
        spark.position = point + CGVector(dx: .random(in: -4...4), dy: .random(in: -4...4))
        spark.zPosition = z
        parent.addChild(spark)
        let duration = TimeInterval.random(in: 0.25...0.45)
        let move = SKAction.moveBy(x: drift.dx, y: drift.dy, duration: duration)
        move.timingMode = .easeOut
        spark.run(.sequence([.group([move, .fadeOut(withDuration: duration)]), .removeFromParent()]))
    }

    /// Fire Bolt: a flickering fireball flies at the target, glowing and shedding embers.
    static func fireball(from start: CGPoint?, to end: CGPoint?, level: Int, in parent: SKNode) async {
        guard let start, let end else { return }
        guard let frames = fxFrames("fireball", count: 4) else {
            await projectile(from: start, to: end, color: Element.fire.color, level: level, trail: true, in: parent)
            return
        }
        let scale: CGFloat = level >= 3 ? 3 : 2
        let ball = pixelSprite(frames[0], scale: scale)
        ball.anchorPoint = CGPoint(x: 0.7, y: 0.5)   // its head (fx_art draws it 21 pixels in of 30)
        ball.position = start
        ball.zPosition = 18_200
        let heading = atan2(end.y - start.y, end.x - start.x)
        ball.zRotation = heading
        // Flying left it would turn upside down; flip it so its bright side stays on top.
        if end.x < start.x { ball.yScale = -1 }
        let glow = glowSprite(UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 1), size: CGSize(width: 44, height: 44) * (scale / 2))
        glow.zPosition = -1
        glow.alpha = 0.8
        ball.addChild(glow)
        parent.addChild(ball)
        // In an async function a plain run(_:) is SpriteKit's awaiting one: these go by key.
        ball.run(.repeatForever(.animate(with: frames, timePerFrame: 0.05)), withKey: "flicker")
        let back = CGVector(dx: -cos(heading), dy: -sin(heading))
        let count = 1 + level / 2
        ball.run(.repeatForever(.sequence([
            .run { [weak ball] in
                guard let ball else { return }
                for _ in 0..<count {
                    let push = CGFloat.random(in: 14...34)
                    let drift = CGVector(dx: back.dx * push, dy: back.dy * push + CGFloat.random(in: 8...26))
                    SkillEffects.ember(at: ball.position + back * (6 * scale), drift: drift, z: 18_150, in: parent)
                }
            },
            .wait(forDuration: 0.02),
        ])), withKey: "embers")
        let travel = SKAction.move(to: end, duration: 0.3)
        travel.timingMode = .easeIn
        await ball.run(travel)
        ball.removeAllActions()
        ball.removeFromParent()
    }

    /// The fireball bursting on the target: a white-hot flash blooms into fire that burns out into
    /// smoke, with embers flying; from tier 2 flames lick up round its feet and leave a scorch on
    /// the ground, and from tier 4 a column of flame roars up through it.
    static func fireBlast(on target: BattleActor, level: Int, in parent: SKNode) {
        guard let blast = fxFrames("blast", count: 6) else {
            explosion(on: target, color: Element.fire.color, level: level, in: parent)
            return
        }
        let scale: CGFloat = level >= 3 ? 3 : 2
        boom(blast, at: target.center, scale: scale, sparks: 10 + level * 5, in: parent)
        guard level >= 2 else { return }
        if let scorch = fxTexture("scorch") {
            let mark = pixelSprite(scorch, scale: scale)
            mark.position = target.position
            mark.zPosition = -8_600
            mark.alpha = 0
            parent.addChild(mark)
            mark.run(.sequence([.fadeAlpha(to: 0.9, duration: 0.1), .wait(forDuration: 0.9), .fadeOut(withDuration: 0.5), .removeFromParent()]))
        }
        guard let flames = fxFrames("flame", count: 4) else { return }
        let tongues = level * 2
        for index in 0..<tongues {
            let angle = CGFloat(index) / CGFloat(tongues) * 2 * .pi + .random(in: -0.3...0.3)
            let foot = target.position + CGVector(dx: cos(angle) * 30, dy: sin(angle) * 11)
            let tongue = pixelSprite(flames[index % flames.count], scale: 2)
            tongue.anchorPoint = CGPoint(x: 0.5, y: 0.05)
            tongue.position = foot
            tongue.zPosition = -foot.y   // in front of the target or behind, by where it stands
            tongue.yScale = 0.1
            parent.addChild(tongue)
            tongue.run(.repeatForever(.animate(with: flames, timePerFrame: 0.07)))
            tongue.run(.sequence([
                .wait(forDuration: 0.04 + Double(index) * 0.03),
                .scaleY(to: 1.2, duration: 0.1),
                .scaleY(to: 1, duration: 0.06),
                .wait(forDuration: 0.3),
                .group([.scaleY(to: 0.1, duration: 0.25), .fadeOut(withDuration: 0.25)]),
                .removeFromParent(),
            ]))
        }
        guard level >= 4 else { return }
        for index in 0..<(level * 2) {
            let tongue = pixelSprite(flames[index % flames.count], scale: 3)
            tongue.anchorPoint = CGPoint(x: 0.5, y: 0.05)
            tongue.position = target.position + CGVector(dx: .random(in: -16...16), dy: -4)
            tongue.zPosition = 18_100
            tongue.alpha = 0
            parent.addChild(tongue)
            tongue.run(.repeatForever(.animate(with: flames, timePerFrame: 0.06)))
            tongue.run(.sequence([
                .wait(forDuration: 0.08 + Double(index) * 0.04),
                .group([.fadeIn(withDuration: 0.05),
                        .moveBy(x: 0, y: 90 + 10 * CGFloat(level), duration: 0.5),
                        .scale(to: 0.5, duration: 0.5),
                        .sequence([.wait(forDuration: 0.25), .fadeOut(withDuration: 0.25)])]),
                .removeFromParent(),
            ]))
        }
    }

    /// The blast itself: a hot flash behind, the bloom playing through to smoke, embers flying.
    private static func boom(_ frames: [SKTexture], at point: CGPoint, scale: CGFloat, sparks: Int, in parent: SKNode) {
        let flash = glowSprite(UIColor(red: 1, green: 0.75, blue: 0.3, alpha: 1), size: CGSize(width: 70, height: 70))
        flash.position = point
        flash.setScale(0.4)
        parent.addChild(flash)
        flash.run(.sequence([.group([.scale(to: 0.8 + 0.6 * scale, duration: 0.2), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        let blast = pixelSprite(frames[0], scale: scale)
        blast.position = point
        blast.zPosition = 18_200
        parent.addChild(blast)
        blast.run(.sequence([
            .animate(with: Array(frames.prefix(5)), timePerFrame: 0.06),
            .setTexture(frames[frames.count - 1]),
            .group([.moveBy(x: 0, y: 26, duration: 0.45), .fadeOut(withDuration: 0.45)]),
            .removeFromParent(),
        ]))
        for _ in 0..<sparks {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 30...(40 + 20 * scale))
            let drift = CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance * 0.8 + 20)
            ember(at: point, drift: drift, z: 18_300, in: parent)
        }
    }

    /// A mastered fire spell's meteor: a big fireball streaking down from the top left onto a
    /// point and bursting. False if its sprites are missing (the caller draws the glow meteor).
    static func fireMeteor(onto point: CGPoint, delay: TimeInterval, size: CGSize, in parent: SKNode) -> Bool {
        guard let frames = fxFrames("fireball", count: 4), fxFrames("blast", count: 6) != nil else { return false }
        let start = point + CGVector(dx: -size.width * 0.45, dy: size.height * 0.6)
        let ball = pixelSprite(frames[0], scale: 3)
        ball.anchorPoint = CGPoint(x: 0.7, y: 0.5)
        ball.position = start
        ball.zRotation = atan2(point.y - start.y, point.x - start.x)
        ball.zPosition = 19_000
        ball.isHidden = true
        parent.addChild(ball)
        let fall = SKAction.move(to: point, duration: 0.32)
        fall.timingMode = .easeIn
        ball.run(.repeatForever(.animate(with: frames, timePerFrame: 0.05)))
        ball.run(.sequence([
            .wait(forDuration: delay),
            .unhide(),
            fall,
            .run {
                guard let blast = SkillEffects.fxFrames("blast", count: 6) else { return }
                SkillEffects.boom(blast, at: point, scale: 3, sparks: 18, in: parent)
            },
            .removeFromParent(),
        ]))
        return true
    }

    // MARK: - Wood

    /// Leaf Storm: wind streaks whip round the target and leaves (and petals, from tier 3) spin up
    /// round it in a widening cyclone, passing in front of it and behind, then scatter on the wind.
    static func leafCyclone(around target: BattleActor, level: Int, in parent: SKNode) {
        let kinds = ["leaf_green", "leaf_light", "leaf_green", "leaf_gold"] + (level >= 3 ? ["petal"] : [])
        let textures = kinds.compactMap { fxTexture($0) }
        guard textures.count == kinds.count else {
            leafStorm(around: target, level: level, in: parent)
            return
        }
        let base = target.position
        let behind = target.zPosition - 1
        let before = target.zPosition + 1
        let duration: TimeInterval = 0.7 + 0.04 * Double(level)
        let count = 12 + level * 5
        for index in 0..<count {
            let leaf = pixelSprite(textures[index % textures.count], scale: 2)
            let start = CGFloat(index) / CGFloat(count) * 2 * .pi
            let radius = CGFloat.random(in: 24...(34 + 5 * CGFloat(level)))
            let lift = CGFloat.random(in: 40...(64 + 10 * CGFloat(level)))
            let turns = CGFloat.random(in: 1.3...1.9)
            let spin = CGFloat.random(in: 7...13) * (Bool.random() ? 1 : -1)
            leaf.position = base
            leaf.alpha = 0
            parent.addChild(leaf)
            let orbit = SKAction.customAction(withDuration: duration) { node, elapsed in
                let t = elapsed / CGFloat(duration)
                let angle = start + t * turns * 2 * .pi
                let reach = radius * (0.75 + 0.45 * t)
                let x = base.x + cos(angle) * reach
                let y = base.y + 6 + lift * t + sin(angle) * reach * 0.35
                node.position = CGPoint(x: x, y: y)
                // The near half of the ring (lower on screen) passes in front of the target.
                node.zPosition = sin(angle) < 0 ? before : behind
                node.zRotation = elapsed * spin
            }
            // At the end it flies off along the ring, the way the wind was blowing.
            let last = start + turns * 2 * .pi
            let away = CGVector(dx: -sin(last), dy: cos(last) * 0.35) * 70
            leaf.run(.sequence([
                .wait(forDuration: Double(index) * 0.01),
                .group([orbit, .fadeIn(withDuration: 0.08)]),
                .group([.moveBy(x: away.dx, y: away.dy + 24, duration: 0.3), .fadeOut(withDuration: 0.3),
                        .rotate(byAngle: spin * 0.3, duration: 0.3)]),
                .removeFromParent(),
            ]))
        }
        // Wind streaks sweeping round: arches across the back, dips across the front.
        if let wind = fxTexture("wind") {
            let streaks = 2 + level
            for index in 0..<streaks {
                let streak = pixelSprite(wind, scale: 2)
                let direction: CGFloat = index % 2 == 0 ? 1 : -1
                let front = index % 2 == 0
                streak.xScale = direction
                streak.yScale = front ? -1 : 1
                streak.position = base + CGVector(dx: -24 * direction, dy: 14 + CGFloat(index) * 56 / CGFloat(streaks))
                streak.zPosition = front ? before : behind
                streak.alpha = 0
                parent.addChild(streak)
                streak.run(.sequence([
                    .wait(forDuration: Double(index) * 0.07),
                    .group([.moveBy(x: 48 * direction, y: 8, duration: 0.4),
                            .sequence([.fadeAlpha(to: 0.85, duration: 0.1), .wait(forDuration: 0.15), .fadeOut(withDuration: 0.15)])]),
                    .removeFromParent(),
                ]))
            }
        }
        guard level >= 4 else { return }
        let column = glowSprite(UIColor(red: 0.6, green: 1, blue: 0.5, alpha: 1), size: CGSize(width: 80, height: 150))
        column.anchorPoint = CGPoint(x: 0.5, y: 0.05)
        column.position = base
        column.zPosition = behind
        column.alpha = 0
        column.xScale = 0.4
        parent.addChild(column)
        column.run(.sequence([
            .group([.fadeAlpha(to: 0.5, duration: 0.15), .scaleX(to: 1, duration: 0.3)]),
            .wait(forDuration: 0.25),
            .group([.fadeOut(withDuration: 0.35), .scaleX(to: 1.4, duration: 0.35)]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Water

    /// A wobbling orb of water lobbed at the target, dripping as it flies.
    static func waterOrb(from start: CGPoint?, to end: CGPoint?, level: Int, in parent: SKNode) async {
        guard let start, let end else { return }
        guard let frames = fxFrames("orb", count: 2), fxTexture("drop") != nil else {
            await projectile(from: start, to: end, color: Element.water.color, level: level, trail: false, in: parent)
            return
        }
        let scale: CGFloat = level >= 3 ? 3 : 2
        let orb = pixelSprite(frames[0], scale: scale)
        orb.position = start
        orb.zPosition = 18_200
        parent.addChild(orb)
        orb.run(.repeatForever(.animate(with: frames, timePerFrame: 0.08)), withKey: "wobble")
        orb.run(.repeatForever(.sequence([
            .run { [weak orb] in
                guard let orb, let drop = SkillEffects.fxTexture("drop") else { return }
                SkillEffects.drip(drop, at: orb.position, in: parent)
            },
            .wait(forDuration: 0.045),
        ])), withKey: "drips")
        let top = CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + 40)
        let duration: TimeInterval = 0.34
        let lob = SKAction.customAction(withDuration: duration) { node, elapsed in
            let t = min(1, elapsed / CGFloat(duration))
            let u = 1 - t
            let a = u * u, b = 2 * u * t, c = t * t
            let x = a * start.x + b * top.x + c * end.x
            let y = a * start.y + b * top.y + c * end.y
            node.position = CGPoint(x: x, y: y)
        }
        await orb.run(lob)
        orb.removeAllActions()
        orb.removeFromParent()
    }

    private static func drip(_ texture: SKTexture, at point: CGPoint, in parent: SKNode) {
        let drop = pixelSprite(texture, scale: 2)
        drop.position = point + CGVector(dx: .random(in: -8...8), dy: .random(in: -6...2))
        drop.zPosition = 18_150
        parent.addChild(drop)
        let fall = SKAction.moveBy(x: .random(in: -6...6), y: -CGFloat.random(in: 24...40), duration: 0.35)
        fall.timingMode = .easeIn
        drop.run(.sequence([.group([fall, .sequence([.wait(forDuration: 0.2), .fadeOut(withDuration: 0.15)])]), .removeFromParent()]))
    }

    /// The orb bursting on the target: drops spray out and fall, a crown of water splashes up at
    /// its feet and settles into a ripple; bubbles rise from tier 3.
    static func waterSplash(on target: BattleActor, level: Int, in parent: SKNode) {
        guard let crownFrames = fxFrames("splash", count: 4), let drop = fxTexture("drop") else {
            splash(on: target, level: level, in: parent)
            return
        }
        let scale: CGFloat = level >= 3 ? 3 : 2
        let flash = glowSprite(UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1), size: CGSize(width: 60, height: 60))
        flash.position = target.center
        flash.setScale(0.4)
        parent.addChild(flash)
        flash.run(.sequence([.group([.scale(to: 1.4 + 0.2 * CGFloat(level), duration: 0.2), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        let crown = pixelSprite(crownFrames[0], scale: scale)
        crown.anchorPoint = CGPoint(x: 0.5, y: 4.0 / 30.0)   // its base line, 26 pixels down of 30
        crown.position = target.position
        crown.zPosition = target.zPosition + 1
        parent.addChild(crown)
        crown.run(.sequence([
            .animate(with: crownFrames, timePerFrame: 0.08),
            .fadeOut(withDuration: 0.25),
            .removeFromParent(),
        ]))
        for _ in 0..<(8 + level * 3) {
            spray(drop, from: target.center, in: parent)
        }
        guard level >= 3, let bubble = fxTexture("bubble") else { return }
        for index in 0..<(level * 2) {
            let rising = pixelSprite(bubble, scale: 2)
            rising.position = target.position + CGVector(dx: .random(in: -26...26), dy: .random(in: 4...30))
            rising.zPosition = 18_150
            rising.alpha = 0
            parent.addChild(rising)
            rising.run(.sequence([
                .wait(forDuration: 0.1 + Double(index) * 0.05),
                .group([.fadeIn(withDuration: 0.08), .moveBy(x: .random(in: -8...8), y: 50, duration: 0.6),
                        .sequence([.wait(forDuration: 0.45), .scale(to: 1.4, duration: 0.08), .fadeOut(withDuration: 0.07)])]),
                .removeFromParent(),
            ]))
        }
    }

    /// A drop thrown out of a splash in an arc, nose first, falling back down.
    private static func spray(_ texture: SKTexture, from point: CGPoint, in parent: SKNode) {
        let drop = pixelSprite(texture, scale: 2)
        drop.position = point
        drop.zPosition = 18_150
        parent.addChild(drop)
        let vx = CGFloat.random(in: -150...150)
        let vy = CGFloat.random(in: 80...240)
        let gravity: CGFloat = 900
        let duration: TimeInterval = 0.5
        let arc = SKAction.customAction(withDuration: duration) { node, t in
            let x = point.x + vx * t
            let y = point.y + vy * t - gravity * t * t / 2
            node.position = CGPoint(x: x, y: y)
            // The drop's round end leads: fx_drop points its tip up.
            node.zRotation = atan2(vy - gravity * t, vx) + .pi / 2
        }
        drop.run(.sequence([.group([arc, .sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.2)])]), .removeFromParent()]))
    }
}

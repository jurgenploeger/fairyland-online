import SpriteKit
import SwiftUI

/// A little living picture for a page of the story (IntroView), made of the game's own tiles,
/// scenery, people and monsters: the goddess gathering the tales, the bosses that have gone wrong,
/// your arrival in Meadowbrook, and a fight that ends in a capture. It loops; with Reduce Motion it
/// holds still.
struct StoryVignette: View {
    @State private var scene: StoryScene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ kind: StoryScene.Kind) {
        _scene = State(initialValue: StoryScene(kind: kind))
    }

    var body: some View {
        SpriteView(scene: scene, isPaused: reduceMotion, options: [.allowsTransparency])
            .aspectRatio(StoryScene.stage.width / StoryScene.stage.height, contentMode: .fit)
            .frame(maxWidth: 560)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUDStyle.frameMid.opacity(0.8), lineWidth: 2))
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

final class StoryScene: SKScene {
    enum Kind {
        /// Shiria gathers the world's fairy tales into one land.
        case gathering
        /// The Big Bad Wolf, the Rat King and the Drunk Dragon loom out of a dark, snowy wood.
        case shadows
        /// You walk into Meadowbrook with your companion, where Elder Oak is waiting.
        case arrival
        /// A fight: a blow, your companion's bite, and a Seal Stone that catches a monster.
        case battle
    }

    /// The scene's size in points; the view scales it to fit.
    static let stage = CGSize(width: 360, height: 170)
    private let kind: Kind
    private var built = false
    /// Where the ground meets the sky.
    private let horizon: CGFloat = 96

    init(kind: Kind) {
        self.kind = kind
        super.init(size: Self.stage)
        scaleMode = .aspectFill
        anchorPoint = .zero
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("StoryScene is made in code")
    }

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        switch kind {
        case .gathering: buildGathering()
        case .shadows: buildShadows()
        case .arrival: buildArrival()
        case .battle: buildBattle()
        }
    }

    // MARK: - Scenes

    private func buildGathering() {
        sky(UIColor(red: 0.45, green: 0.74, blue: 1, alpha: 1), UIColor(red: 1, green: 0.89, blue: 0.7, alpha: 1))
        ground(["tile_grass", "tile_grass", "tile_flowers"])
        prop("tree", 34, 90)
        prop("autumn_tree", 96, 100, scale: 0.7)
        prop("blossom_tree", 312, 92)
        prop("tree", 262, 102, scale: 0.65)
        // Shiria's light, high over the land, drawing every tale toward it.
        let light = glow(Nodes.gold, size: 110, at: CGPoint(x: 180, y: 136))
        light.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 1.4), .scale(to: 0.92, duration: 1.4)])))
        Ambience.twinkle(around: CGPoint(x: 180, y: 118), radius: 34, count: 6, in: self)
        run(.repeatForever(.sequence([.run { [weak self] in self?.riseToTheLight() }, .wait(forDuration: 0.28)])))
        // The tales already living there.
        pace(walker("pet_walk", 110, 40, facing: .right), distance: 70, duration: 1.8, pause: 1.2)
        walker("monster_jelly", 238, 26, facing: .left)
        walker("monster_pineapple", 290, 48, facing: .left)
        particles("petals")
    }

    private func buildShadows() {
        sky(UIColor(red: 0.12, green: 0.08, blue: 0.24, alpha: 1), UIColor(red: 0.24, green: 0.26, blue: 0.46, alpha: 1))
        ground(["tile_snow", "tile_snow", "tile_snow_path"])
        prop("snow_pine", 26, 88)
        prop("dead_tree", 92, 98, scale: 0.8)
        prop("snow_tree", 286, 96, scale: 0.85)
        prop("snow_pine", 336, 86)
        particles("snow")
        let gloom = SKSpriteNode(color: UIColor(red: 0.05, green: 0.03, blue: 0.14, alpha: 1), size: size)
        gloom.anchorPoint = .zero
        gloom.alpha = 0.35
        gloom.zPosition = 2_000
        addChild(gloom)
        // Each in turn looms out of the dark with a red glow, then fades back into it.
        let bosses = ["big_bad_wolf", "rat_king", "drunk_dragon"].compactMap { Content.shared.monster($0) }
        let turn: TimeInterval = 4
        for (index, boss) in bosses.enumerated() {
            let group = SKNode()
            group.position = CGPoint(x: 180, y: 34)
            group.zPosition = 3_000
            group.alpha = 0
            addChild(group)
            let red = glow(UIColor(red: 1, green: 0.2, blue: 0.25, alpha: 1), size: 130, at: CGPoint(x: 0, y: 40), in: group)
            red.alpha = 0.55
            red.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: 0.9), .fadeAlpha(to: 0.6, duration: 0.9)])))
            let creature = Walker(cycle: ArtLibrary.shared.walkCycle(boss.art), label: nil)
            creature.motion = IdleMotion.of(art: boss.art)
            creature.setScale(1.35)
            group.addChild(creature)
            let tag = NameTag(boss.name, color: UIColor(red: 1, green: 0.6, blue: 0.55, alpha: 1), size: 12)
            tag.position = CGPoint(x: 0, y: -18)
            group.addChild(tag)
            let shake = SKAction.sequence([.moveBy(x: 3, y: 0, duration: 0.05), .moveBy(x: -6, y: 0, duration: 0.1), .moveBy(x: 3, y: 0, duration: 0.05)])
            let appear = SKAction.sequence([
                .fadeIn(withDuration: 0.6), shake, .wait(forDuration: turn - 1.4), .fadeOut(withDuration: 0.6),
                .wait(forDuration: turn * Double(bosses.count - 1) + 0.2),
            ])
            group.run(.sequence([.wait(forDuration: 0.4 + turn * Double(index)), .repeatForever(appear)]))
        }
    }

    private func buildArrival() {
        sky(UIColor(red: 0.5, green: 0.78, blue: 1, alpha: 1), UIColor(red: 1, green: 0.92, blue: 0.75, alpha: 1))
        ground(["tile_grass", "tile_grass", "tile_flowers"])
        // The village street.
        for col in 0..<12 {
            let tile = SKSpriteNode(texture: ArtLibrary.shared.tileTexture("tile_town"), size: CGSize(width: 32, height: 32))
            tile.anchorPoint = .zero
            tile.position = CGPoint(x: CGFloat(col) * 32, y: 22)
            tile.zPosition = -850
            addChild(tile)
        }
        prop("house", 62, 86, scale: 0.9)
        prop("inn", 300, 86, scale: 0.9)
        prop("windmill", 176, 98, scale: 0.7)
        prop("street_lamp", 124, 62)
        prop("street_lamp", 236, 62)
        particles("petals")

        let elder = walker("npc_elder", 252, 36, facing: .left)
        let mark = SKLabelNode()
        mark.attributedText = Nodes.outlined("!", size: 22, color: Nodes.gold)
        mark.verticalAlignmentMode = .bottom
        mark.position = CGPoint(x: 0, y: elder.sprite.size.height * 0.95)
        mark.run(.repeatForever(.sequence([.moveBy(x: 0, y: 4, duration: 0.5), .moveBy(x: 0, y: -4, duration: 0.5)])))
        elder.addChild(mark)

        let hero = walker("player_walk", -24, 34, facing: .right)
        let pet = walker("pet_walk", -56, 30, facing: .right)
        let start = (hero: hero.position, pet: pet.position)
        let walk: TimeInterval = 3.2
        let arrive = SKAction.sequence([
            .run { [weak hero, weak pet] in
                hero?.position = start.hero
                pet?.position = start.pet
                hero?.alpha = 1
                pet?.alpha = 1
                hero?.face(.right)
                pet?.face(.right)
                hero?.setWalking(true)
                pet?.setWalking(true)
            },
            .run { [weak hero, weak pet] in
                hero?.run(.moveTo(x: 214, duration: walk))
                pet?.run(.moveTo(x: 182, duration: walk))
            },
            .wait(forDuration: walk),
            .run { [weak hero, weak pet] in
                hero?.setWalking(false)
                pet?.setWalking(false)
            },
            .wait(forDuration: 3),
            .run { [weak hero, weak pet] in
                hero?.run(.fadeOut(withDuration: 0.5))
                pet?.run(.fadeOut(withDuration: 0.5))
            },
            .wait(forDuration: 0.8),
        ])
        run(.repeatForever(arrive))
    }

    private func buildBattle() {
        sky(UIColor(red: 0.52, green: 0.8, blue: 1, alpha: 1), UIColor(red: 0.9, green: 0.96, blue: 0.85, alpha: 1))
        ground(["tile_grass", "tile_grass", "tile_flowers"])
        prop("tree", 20, 92)
        prop("blossom_tree", 340, 94)
        let jelly = walker("monster_jelly", 92, 30, facing: .right)
        let pineapple = walker("monster_pineapple", 66, 62, facing: .right)
        let hero = walker("player_walk", 268, 32, facing: .left)
        let pet = walker("pet_walk", 300, 62, facing: .left)
        let homes = (hero: hero.position, pet: pet.position, jelly: jelly.position)

        func lunge(_ node: Walker, by dx: CGFloat) -> SKAction {
            .sequence([
                .run { [weak node] in node?.setWalking(true) },
                .run { [weak node] in node?.run(.moveBy(x: dx, y: 0, duration: 0.3)) },
                .wait(forDuration: 0.3),
                .run { [weak node] in node?.setWalking(false) },
            ])
        }
        func hit(_ target: Walker, _ amount: Int) -> SKAction {
            .run { [weak self, weak target] in
                guard let self, let target else { return }
                Effects.damageBurst("\(amount)", style: .normal, at: target.position + CGVector(dx: 0, dy: target.sprite.size.height * 0.6), in: self)
                target.sprite.run(.sequence([
                    .colorize(with: .white, colorBlendFactor: 0.9, duration: 0.05),
                    .colorize(withColorBlendFactor: 0, duration: 0.2),
                ]))
                target.run(.sequence([.moveBy(x: -5, y: 0, duration: 0.06), .moveBy(x: 5, y: 0, duration: 0.1)]))
            }
        }
        let capture = SKAction.run { [weak self, weak jelly] in
            guard let self, let jelly else { return }
            let stone = self.prop("item_seal_stone", homes.hero.x - 12, homes.hero.y + 26, scale: 0.7)
            stone.zPosition = 4_000
            let end = jelly.position + CGVector(dx: 0, dy: 12)
            let arc = CGMutablePath()
            arc.move(to: stone.position)
            arc.addQuadCurve(to: end, control: CGPoint(x: (stone.position.x + end.x) / 2, y: 150))
            stone.run(.sequence([
                .group([.follow(arc, asOffset: false, orientToPath: false, duration: 0.7), .rotate(byAngle: -.pi * 3, duration: 0.7)]),
                .run { [weak self, weak jelly] in
                    guard let self, let jelly else { return }
                    jelly.run(.group([.scale(to: 0.1, duration: 0.35), .fadeOut(withDuration: 0.35)]))
                    Ambience.twinkle(around: end, radius: 18, count: 5, in: self)
                    Effects.floatingText(L("Sealed!"), color: Nodes.gold, at: end + CGVector(dx: 0, dy: 20), in: self, size: 18)
                },
                .wait(forDuration: 0.6),
                .fadeOut(withDuration: 0.3),
                .removeFromParent(),
            ]))
        }
        let round = SKAction.sequence([
            .wait(forDuration: 0.8),
            lunge(hero, by: -40), hit(jelly, 12), .wait(forDuration: 0.3), lunge(hero, by: 40),
            .wait(forDuration: 0.6),
            lunge(pet, by: -50), hit(pineapple, 7), .wait(forDuration: 0.3), lunge(pet, by: 50),
            .wait(forDuration: 0.7),
            capture,
            .wait(forDuration: 2.4),
            // The meadow fills up again for the next round.
            .run { [weak jelly, weak hero, weak pet] in
                jelly?.position = homes.jelly
                jelly?.setScale(1)
                jelly?.run(.fadeIn(withDuration: 0.5))
                hero?.position = homes.hero
                pet?.position = homes.pet
            },
            .wait(forDuration: 0.6),
        ])
        run(.repeatForever(round))
    }

    // MARK: - Pieces

    /// The sky behind the land: one colour at the top fading into another at the horizon.
    private func sky(_ top: UIColor, _ bottom: UIColor) {
        let height = size.height - horizon + 8
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 64), format: format).image { context in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 64), options: [])
        }
        let node = SKSpriteNode(texture: SKTexture(image: image), size: CGSize(width: size.width, height: height))
        node.anchorPoint = .zero
        node.position = CGPoint(x: 0, y: horizon - 8)
        node.zPosition = -1_000
        addChild(node)
    }

    /// The land up to the horizon, in the map's own tiles, mixed a little, with a soft shade where
    /// it meets the sky.
    private func ground(_ tiles: [String]) {
        let side: CGFloat = 32
        let rows = Int((horizon / side).rounded(.up)), cols = Int((size.width / side).rounded(.up))
        for row in 0..<rows {
            for col in 0..<cols {
                let id = tiles[(row * 5 + col * 3 + row * col) % tiles.count]
                let tile = SKSpriteNode(texture: ArtLibrary.shared.tileTexture(id), size: CGSize(width: side, height: side))
                tile.anchorPoint = .zero
                tile.position = CGPoint(x: CGFloat(col) * side, y: CGFloat(row) * side)
                tile.zPosition = -900
                addChild(tile)
            }
        }
        let edge = SKSpriteNode(color: UIColor(white: 0, alpha: 0.18), size: CGSize(width: size.width, height: 3))
        edge.anchorPoint = .zero
        edge.position = CGPoint(x: 0, y: horizon - 3)
        edge.zPosition = -800
        addChild(edge)
    }

    /// A piece of scenery standing on the ground at `x`, `y` (its feet); nearer things in front.
    @discardableResult
    private func prop(_ id: String, _ x: CGFloat, _ y: CGFloat, scale: CGFloat = 1) -> SKSpriteNode {
        let art = ArtLibrary.shared.sprite(id)
        let node = SKSpriteNode(texture: art.texture, size: CGSize(width: art.size.width * scale, height: art.size.height * scale))
        node.anchorPoint = CGPoint(x: 0.5, y: 0.05)
        node.position = CGPoint(x: x, y: y)
        node.zPosition = 500 - y
        addChild(node)
        return node
    }

    /// Someone (or something) standing at `x`, `y`: breathing, squishing or hopping as they do in the game.
    @discardableResult
    private func walker(_ art: String, _ x: CGFloat, _ y: CGFloat, facing: Direction) -> Walker {
        let node = Walker(cycle: ArtLibrary.shared.walkCycle(art), label: nil)
        node.motion = IdleMotion.of(art: art)
        node.face(facing)
        node.position = CGPoint(x: x, y: y)
        node.zPosition = 500 - y
        addChild(node)
        return node
    }

    /// Back and forth along the ground, resting at each end.
    private func pace(_ node: Walker, distance: CGFloat, duration: TimeInterval, pause: TimeInterval) {
        func leg(_ dx: CGFloat, _ facing: Direction) -> SKAction {
            .sequence([
                .run { [weak node] in
                    node?.face(facing)
                    node?.setWalking(true)
                },
                .moveBy(x: dx, y: 0, duration: duration),
                .run { [weak node] in node?.setWalking(false) },
                .wait(forDuration: pause),
            ])
        }
        node.run(.repeatForever(.sequence([leg(distance, .right), leg(-distance, .left)])))
    }

    /// A soft, glowing light.
    @discardableResult
    private func glow(_ color: UIColor, size side: CGFloat, at point: CGPoint, in parent: SKNode? = nil) -> SKSpriteNode {
        let node = SKSpriteNode(texture: SoftTextures.glow, size: CGSize(width: side, height: side))
        node.color = color
        node.colorBlendFactor = 1
        node.blendMode = .add
        node.position = point
        node.zPosition = parent == nil ? 1_500 : -1
        (parent ?? self).addChild(node)
        return node
    }

    /// One of the map ambiences' particles (petals, snow…), drifting over the whole picture.
    private func particles(_ kind: String) {
        for emitter in Ambience.emitters(kind) {
            emitter.position = CGPoint(x: size.width / 2, y: size.height / 2 + 30)
            emitter.particlePositionRange = CGVector(dx: size.width + 60, dy: size.height + 60)
            emitter.zPosition = 2_500
            addChild(emitter)
            emitter.advanceSimulationTime(TimeInterval(emitter.particleLifetime))
        }
    }

    /// A spark lifting off the land and drifting up into Shiria's light.
    private func riseToTheLight() {
        let star = SKSpriteNode(texture: SoftTextures.star, size: CGSize(width: 7, height: 7))
        star.color = Nodes.gold
        star.colorBlendFactor = 0.5
        star.blendMode = .add
        star.position = CGPoint(x: CGFloat.random(in: 10...350), y: CGFloat.random(in: 8...84))
        star.zPosition = 1_600
        star.alpha = 0
        addChild(star)
        let target = CGPoint(x: 180 + CGFloat.random(in: -14...14), y: 136 + CGFloat.random(in: -8...8))
        let fly = SKAction.move(to: target, duration: TimeInterval.random(in: 1.6...2.4))
        fly.timingMode = .easeIn
        star.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .group([fly, .sequence([.wait(forDuration: 1.2), .fadeOut(withDuration: 0.5)])]),
            .removeFromParent(),
        ]))
    }
}

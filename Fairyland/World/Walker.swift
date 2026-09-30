import SpriteKit

/// Anything that walks around a map: the hero, a companion, an NPC or a passer-by.
/// Walk sheets animate per direction; single-image sprites hop instead. Standing still,
/// everyone breathes gently so the world never looks frozen.
final class Walker: SKNode {
    let sprite: SKSpriteNode
    var walkSpeed: CGFloat = 88
    /// Waypoints still to walk, in world coordinates (tap-to-move).
    var path: [CGPoint] = []

    private(set) var facing: Direction = .down
    private var isWalking = false
    private var cycle: WalkCycle
    private var tag: NameTag?
    private var bubble: SKNode?
    /// Breathing while standing still; off for things that shouldn't, like gift boxes.
    var idles = true {
        didSet { if idles != oldValue { animate() } }
    }
    /// Monsters squish, hop or sway instead of breathing.
    var motion: IdleMotion = .breathe {
        didSet { if motion != oldValue { animate() } }
    }
    /// The hero fidgets when left standing: glances around, stretches.
    var fidgets = false {
        didSet { if fidgets, !isWalking { startFidgeting() } }
    }
    /// So a crowd doesn't breathe in unison.
    private let breathOffset = TimeInterval.random(in: 0..<1.6)

    init(cycle: WalkCycle, label: String?, labelColor: UIColor = .white) {
        self.cycle = cycle
        sprite = SKSpriteNode(texture: cycle.frames(.down).first, size: cycle.size)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.08)
        super.init()
        addChild(Nodes.shadow(width: cycle.size.width * 0.5))
        addChild(sprite)
        if let label {
            let tag = NameTag(label, color: labelColor, size: 11)
            tag.position = CGPoint(x: 0, y: cycle.size.height * 0.95)
            addChild(tag)
            self.tag = tag
        }
        animate()
    }

    /// Swaps the look (after customising the hero or recolouring a companion).
    func setCycle(_ cycle: WalkCycle) {
        self.cycle = cycle
        sprite.size = cycle.size
        animate()
    }

    /// Shows the weapon in hand.
    func setGear(weapon: ItemDef?) {
        sprite.childNode(withName: "weapon")?.removeFromParent()
        if let weapon, let node = GearArt.weapon(weapon, height: cycle.size.height) {
            sprite.addChild(node)
        }
        poseGear()
    }

    private func poseGear() {
        if let weapon = sprite.childNode(withName: "weapon") as? SKSpriteNode {
            GearArt.pose(weapon, facing: facing, height: cycle.size.height)
        }
    }

    func setLabel(_ text: String) {
        tag?.setText(text)
    }

    /// A speech bubble above the name tag for a few seconds.
    func say(_ text: String, for duration: TimeInterval = 3.5) {
        bubble?.removeFromParent()
        let node = Nodes.speechBubble(text)
        node.position = CGPoint(x: 0, y: (tag?.position.y ?? sprite.size.height) + 20)
        node.zPosition = 6_000
        node.alpha = 0
        node.setScale(0.6)
        addChild(node)
        bubble = node
        let pop = SKAction.group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.15)])
        node.run(.sequence([pop, .wait(forDuration: duration), .fadeOut(withDuration: 0.3), .removeFromParent()]))
    }

    /// Trails behind `leader` like a companion: close enough to feel together, never on top.
    func follow(_ leader: Walker, dt: TimeInterval) {
        let behind = leader.facing.vector * -1
        let goal = leader.facing.isHorizontal
            ? leader.position + behind * 34 + CGVector(dx: 0, dy: 6)
            : leader.position + behind * 14 + CGVector(dx: -30, dy: 0)
        let offset = goal - position
        let distance = offset.length
        if distance > 300 {
            position = goal
        } else if distance > 6 {
            let step = min(distance, max(walkSpeed, distance * 2) * CGFloat(dt))
            position = position + offset * (step / distance)
            face(Direction(offset, current: facing))
            setWalking(true)
        } else {
            setWalking(false)
            face(leader.facing)
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    var headTop: CGPoint { CGPoint(x: position.x, y: position.y + sprite.size.height + 14) }

    /// Walks along `path`; returns true while there's still somewhere to go.
    @discardableResult
    func followPath(dt: TimeInterval) -> Bool {
        guard let next = path.first else { return false }
        let offset = next - position
        let distance = offset.length
        let step = walkSpeed * CGFloat(dt)
        if distance <= step {
            position = next
            path.removeFirst()
        } else {
            position = position + offset * (step / distance)
            face(Direction(offset, current: facing))
        }
        return !path.isEmpty
    }

    func face(_ direction: Direction) {
        guard direction != facing else { return }
        facing = direction
        animate()
    }

    func setWalking(_ walking: Bool) {
        guard walking != isWalking else { return }
        isWalking = walking
        animate()
        if walking {
            removeAction(forKey: "fidget")
            removeAction(forKey: "glance")
        } else if fidgets {
            startFidgeting()
        }
    }

    private func startFidgeting() {
        let fidget = SKAction.sequence([.wait(forDuration: 5, withRange: 4), .run { [weak self] in self?.fidget() }])
        run(.repeatForever(fidget), withKey: "fidget")
    }

    /// Look left and right, or have a little stretch.
    private func fidget() {
        guard !isWalking else { return }
        if Bool.random() {
            let original = facing
            let sides: [Direction] = original.isHorizontal ? [.down, original == .left ? .right : .left] : [.left, .right].shuffled()
            run(.sequence([
                .run { [weak self] in self?.face(sides[0]) }, .wait(forDuration: 0.7),
                .run { [weak self] in self?.face(sides[1]) }, .wait(forDuration: 0.7),
                .run { [weak self] in self?.face(original) },
            ]), withKey: "glance")
        } else {
            let stretch = SKAction.sequence([.scaleY(to: 1.12, duration: 0.18), .scaleY(to: 0.94, duration: 0.12), .scaleY(to: 1, duration: 0.14)])
            stretch.timingMode = .easeInEaseOut
            sprite.run(stretch, withKey: "stretch")
        }
    }

    private func animate() {
        sprite.removeAction(forKey: "walk")
        sprite.removeAction(forKey: "idle")
        sprite.position = .zero
        sprite.xScale = 1
        sprite.yScale = 1
        sprite.zRotation = 0
        let frames = cycle.frames(facing)
        sprite.texture = frames.first
        poseGear()
        guard isWalking else {
            breathe()
            return
        }
        if frames.count > 1 {
            sprite.run(.repeatForever(.animate(with: frames, timePerFrame: 0.16)), withKey: "walk")
        } else {
            let up = SKAction.moveBy(x: 0, y: 5, duration: 0.13)
            up.timingMode = .easeOut
            let down = SKAction.moveBy(x: 0, y: -5, duration: 0.13)
            down.timingMode = .easeIn
            sprite.run(.repeatForever(.sequence([up, down])), withKey: "walk")
        }
    }

    /// Standing still: breathing for people, a squish, hop or sway for monsters.
    private func breathe() {
        guard idles else { return }
        sprite.run(motion.action(height: sprite.size.height, delay: breathOffset), withKey: "idle")
    }
}

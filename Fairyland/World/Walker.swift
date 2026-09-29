import SpriteKit

/// Anything that walks around a map: the hero, a companion, or an NPC.
/// Walk sheets animate per direction; single-image sprites hop instead.
final class Walker: SKNode {
    let sprite: SKSpriteNode
    var walkSpeed: CGFloat = 88
    /// Waypoints still to walk, in world coordinates (tap-to-move).
    var path: [CGPoint] = []

    private(set) var facing: Direction = .down
    private var isWalking = false
    private let cycle: WalkCycle

    init(cycle: WalkCycle, label: String?, labelColor: UIColor = .white) {
        self.cycle = cycle
        sprite = SKSpriteNode(texture: cycle.frames(.down).first, size: cycle.size)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.08)
        super.init()
        addChild(Nodes.shadow(width: cycle.size.width * 0.5))
        addChild(sprite)
        if let label {
            let tag = Nodes.nameLabel(label, color: labelColor)
            tag.position = CGPoint(x: 0, y: cycle.size.height * 0.95)
            addChild(tag)
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
    }

    private func animate() {
        sprite.removeAction(forKey: "walk")
        sprite.position = .zero
        let frames = cycle.frames(facing)
        sprite.texture = frames.first
        guard isWalking else { return }
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
}

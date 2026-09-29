import SpriteKit
import UIKit

/// Small reusable SpriteKit building blocks.
enum Nodes {
    static let ink = UIColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1)
    static let gold = UIColor(red: 1, green: 0.83, blue: 0.3, alpha: 1)
    /// Fairyland's yellow name tags.
    static let nameYellow = UIColor(red: 1, green: 0.95, blue: 0.35, alpha: 1)

    static func shadow(width: CGFloat) -> SKShapeNode {
        let node = SKShapeNode(ellipseOf: CGSize(width: width, height: width * 0.35))
        node.fillColor = UIColor(white: 0, alpha: 0.22)
        node.strokeColor = .clear
        node.zPosition = -1
        return node
    }

    /// A name tag above a character's head, like Fairyland's.
    static func nameLabel(_ text: String, color: UIColor = nameYellow) -> SKLabelNode {
        let label = SKLabelNode()
        label.attributedText = outlined(text, size: 9, color: color, monospaced: true)
        label.verticalAlignmentMode = .bottom
        label.zPosition = 5_000
        return label
    }

    static func outlined(_ text: String, size: CGFloat, color: UIColor, monospaced: Bool = false) -> NSAttributedString {
        let base = monospaced ? UIFont.monospacedSystemFont(ofSize: size, weight: .bold) : UIFont.systemFont(ofSize: size, weight: .heavy)
        let font = monospaced ? base : (base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base)
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .strokeColor: ink,
            .strokeWidth: -4,
        ])
    }
}

final class HealthBar: SKNode {
    private let fill: SKSpriteNode
    private let width: CGFloat

    var fraction: CGFloat = 1 {
        didSet {
            fill.size.width = max(0, width * min(fraction, 1))
            fill.color = fraction > 0.3 ? UIColor(red: 0.4, green: 0.85, blue: 0.35, alpha: 1) : UIColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1)
        }
    }

    init(width: CGFloat) {
        self.width = width
        fill = SKSpriteNode(color: .green, size: CGSize(width: width, height: 3))
        super.init()
        let background = SKSpriteNode(color: UIColor(white: 0, alpha: 0.6), size: CGSize(width: width + 2, height: 5))
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position.x = -width / 2
        fill.zPosition = 1
        addChild(background)
        addChild(fill)
        zPosition = 5_000
        fraction = 1
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }
}

extension SKSpriteNode {
    /// A quick hop toward `offset` and back, for attacks.
    func lunge(toward offset: CGVector) {
        let step = offset.normalized * 5
        run(.sequence([
            .moveBy(x: step.dx, y: step.dy, duration: 0.06),
            .moveBy(x: -step.dx, y: -step.dy, duration: 0.1),
        ]))
    }

    func flash(_ color: UIColor) {
        run(.sequence([
            .colorize(with: color, colorBlendFactor: 0.8, duration: 0.04),
            .colorize(withColorBlendFactor: 0, duration: 0.15),
        ]))
    }
}

/// Fire-and-forget visual effects; every node removes itself when done.
enum Effects {
    static func floatingText(_ text: String, color: UIColor, at point: CGPoint, in parent: SKNode, size: CGFloat = 12) {
        let label = SKLabelNode()
        label.attributedText = Nodes.outlined(text, size: size, color: color)
        label.verticalAlignmentMode = .bottom
        label.position = point
        label.zPosition = 10_000
        parent.addChild(label)
        let rise = SKAction.moveBy(x: 0, y: 26, duration: 0.9)
        rise.timingMode = .easeOut
        label.run(.sequence([
            .group([rise, .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.4)])]),
            .removeFromParent(),
        ]))
    }

    /// Big bouncy damage numbers.
    static func damageNumber(_ text: String, color: UIColor, at point: CGPoint, in parent: SKNode, big: Bool) {
        let label = SKLabelNode()
        label.attributedText = Nodes.outlined(text, size: big ? 26 : 20, color: color)
        label.verticalAlignmentMode = .bottom
        label.position = point
        label.zPosition = 21_000
        label.setScale(0.3)
        parent.addChild(label)
        let pop = SKAction.sequence([.scale(to: 1.35, duration: 0.1), .scale(to: 1, duration: 0.1)])
        let rise = SKAction.moveBy(x: .random(in: -8...8), y: 34, duration: 0.8)
        rise.timingMode = .easeOut
        label.run(.sequence([pop, .group([rise, .sequence([.wait(forDuration: 0.45), .fadeOut(withDuration: 0.35)])]), .removeFromParent()]))
    }

    /// Fairyland's destination marker: a spiral wand with four orange arrows closing in.
    static func tapMarker(at point: CGPoint, in parent: SKNode) {
        let marker = SKNode()
        marker.position = point
        marker.zPosition = -50_000
        parent.addChild(marker)

        let spiral = CGMutablePath()
        for step in 0...60 {
            let t = CGFloat(step) / 60 * 2.5 * 2 * .pi
            let radius = 1 + t * 1.1
            let p = CGPoint(x: cos(t) * radius, y: sin(t) * radius * 0.6 + 10)
            step == 0 ? spiral.move(to: p) : spiral.addLine(to: p)
        }
        let swirl = SKShapeNode(path: spiral)
        swirl.strokeColor = UIColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 1)
        swirl.lineWidth = 2.5
        swirl.glowWidth = 1
        let stick = SKShapeNode(rect: CGRect(x: -1, y: -2, width: 2, height: 12))
        stick.fillColor = .white
        stick.strokeColor = .clear
        stick.zRotation = 0.5
        marker.addChild(stick)
        marker.addChild(swirl)

        let orange = UIColor(red: 1, green: 0.6, blue: 0.1, alpha: 1)
        for index in 0..<4 {
            let angle = CGFloat(index) * .pi / 2
            let arrow = SKShapeNode(path: {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: -5, y: 4))
                path.addLine(to: CGPoint(x: 0, y: -2))
                path.addLine(to: CGPoint(x: 5, y: 4))
                return path
            }())
            arrow.strokeColor = orange
            arrow.lineWidth = 3
            arrow.lineCap = .round
            arrow.zRotation = angle + .pi / 2
            let out = CGVector(dx: cos(angle) * 22, dy: sin(angle) * 13)
            arrow.position = CGPoint(x: out.dx, y: out.dy + 6)
            marker.addChild(arrow)
            arrow.run(.repeat(.sequence([
                .moveBy(x: -out.dx * 0.3, y: -out.dy * 0.3, duration: 0.2),
                .moveBy(x: out.dx * 0.3, y: out.dy * 0.3, duration: 0.2),
            ]), count: 2))
        }
        marker.run(.sequence([.wait(forDuration: 0.8), .fadeOut(withDuration: 0.3), .removeFromParent()]))
    }

    static func burst(at point: CGPoint, color: UIColor, count: Int = 10, in parent: SKNode) {
        for index in 0..<count {
            let bit = SKSpriteNode(color: color, size: CGSize(width: 3, height: 3))
            bit.position = point
            bit.zPosition = 9_000
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
            let distance = CGFloat.random(in: 16...30)
            let move = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.45)
            move.timingMode = .easeOut
            parent.addChild(bit)
            bit.run(.sequence([.group([move, .fadeOut(withDuration: 0.45)]), .removeFromParent()]))
        }
    }
}

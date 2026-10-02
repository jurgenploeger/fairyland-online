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

    /// A cream speech bubble with a little tail, anchored at the tail's tip.
    static func speechBubble(_ text: String, maxWidth: CGFloat = 150) -> SKSpriteNode {
        let base = UIFont.systemFont(ofSize: 11, weight: .bold)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 11) } ?? base
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph])
        let textBox = string.boundingRect(with: CGSize(width: maxWidth, height: 200), options: [.usesLineFragmentOrigin], context: nil).integral
        let padding = CGSize(width: 9, height: 5)
        let tail: CGFloat = 6
        let bubble = CGRect(x: 1, y: 1, width: textBox.width + padding.width * 2, height: textBox.height + padding.height * 2)
        let canvas = CGSize(width: bubble.width + 2, height: bubble.height + tail + 2)
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            let shape = UIBezierPath(roundedRect: bubble, cornerRadius: min(10, bubble.height / 2))
            shape.move(to: CGPoint(x: bubble.midX - 5, y: bubble.maxY - 1))
            shape.addLine(to: CGPoint(x: bubble.midX, y: bubble.maxY + tail))
            shape.addLine(to: CGPoint(x: bubble.midX + 5, y: bubble.maxY - 1))
            UIColor(red: 1, green: 0.98, blue: 0.9, alpha: 0.96).setFill()
            shape.fill()
            ink.withAlphaComponent(0.8).setStroke()
            shape.lineWidth = 1.5
            shape.stroke()
            string.draw(with: CGRect(x: bubble.minX + padding.width, y: bubble.minY + padding.height, width: textBox.width, height: textBox.height),
                        options: [.usesLineFragmentOrigin], context: nil)
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        let node = SKSpriteNode(texture: texture, size: image.size)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        return node
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

/// How a creature fidgets while standing still (content/monsters.json `motion`); people breathe.
enum IdleMotion: String {
    case breathe, squish, hop, sway, bounce

    static func of(art: String) -> IdleMotion {
        Content.shared.monsters.first { $0.art == art }?.motion.flatMap(IdleMotion.init) ?? .breathe
    }

    /// A looping action for a sprite anchored at its feet, `height` points tall.
    func action(height: CGFloat, delay: TimeInterval) -> SKAction {
        func ease(_ action: SKAction, _ mode: SKActionTimingMode = .easeInEaseOut) -> SKAction {
            action.timingMode = mode
            return action
        }
        func scale(x: CGFloat, y: CGFloat, _ duration: TimeInterval) -> SKAction {
            .group([ease(.scaleX(to: x, duration: duration)), ease(.scaleY(to: y, duration: duration))])
        }
        let jump = max(4, height * 0.14)
        let loop: SKAction = switch self {
        case .breathe:
            .sequence([
                .group([scale(x: 0.98, y: 1.05, 0.9), ease(.moveBy(x: 0, y: 1, duration: 0.9))]),
                .group([scale(x: 1, y: 1, 0.9), ease(.moveBy(x: 0, y: -1, duration: 0.9))]),
            ])
        case .squish:
            .sequence([scale(x: 1.1, y: 0.86, 0.35), scale(x: 0.96, y: 1.06, 0.3), scale(x: 1, y: 1, 0.25), .wait(forDuration: 0.35)])
        case .hop:
            .sequence([
                .wait(forDuration: 0.9, withRange: 0.8),
                scale(x: 1.06, y: 0.9, 0.08),
                .group([ease(.moveBy(x: 0, y: jump, duration: 0.16), .easeOut), scale(x: 0.96, y: 1.08, 0.16)]),
                .group([ease(.moveBy(x: 0, y: -jump, duration: 0.14), .easeIn), scale(x: 1, y: 1, 0.14)]),
                scale(x: 1.06, y: 0.92, 0.06), scale(x: 1, y: 1, 0.08),
            ])
        case .sway:
            .sequence([ease(.rotate(toAngle: 0.08, duration: 0.8)), ease(.rotate(toAngle: -0.08, duration: 1.6)), ease(.rotate(toAngle: 0, duration: 0.8))])
        case .bounce:
            .sequence([
                .group([ease(.moveBy(x: 0, y: jump * 0.6, duration: 0.24), .easeOut), scale(x: 0.97, y: 1.05, 0.24)]),
                .group([ease(.moveBy(x: 0, y: -jump * 0.6, duration: 0.22), .easeIn), scale(x: 1, y: 1, 0.22)]),
                scale(x: 1.08, y: 0.9, 0.06), scale(x: 1, y: 1, 0.08),
            ])
        }
        return .sequence([.wait(forDuration: delay), .repeatForever(loop)])
    }
}

/// A name tag like Fairyland's: yellow text with a solid dark outline, and an optional
/// "[Lv.3]" prefix in cream. Drawn into a crisp texture (outline first, then the letters on
/// top) so the outline grows outward instead of eating into small text.
final class NameTag: SKNode {
    private let sprite = SKSpriteNode()
    private let color: UIColor
    private let size: CGFloat

    init(_ text: String, level: Int? = nil, color: UIColor = Nodes.nameYellow, size: CGFloat = 12,
         alignment: SKLabelVerticalAlignmentMode = .bottom) {
        self.color = color
        self.size = size
        super.init()
        zPosition = 5_000
        sprite.anchorPoint = CGPoint(x: 0.5, y: alignment == .top ? 1 : alignment == .center ? 0.5 : 0)
        addChild(sprite)
        setText(text, level: level)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setText(_ text: String, level: Int? = nil) {
        let image = Self.render(prefix: level.map { "[Lv.\($0)] " } ?? "", text: text, color: color, size: size)
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        sprite.texture = texture
        sprite.size = image.size
    }

    private static func render(prefix: String, text: String, color: UIColor, size: CGFloat) -> UIImage {
        let base = UIFont.systemFont(ofSize: size, weight: .heavy)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        let letters = NSMutableAttributedString(string: prefix, attributes: [.font: font, .foregroundColor: UIColor(red: 1, green: 0.97, blue: 0.86, alpha: 1)])
        letters.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        // A positive strokeWidth draws only the outline, centred on the glyph edge; the
        // letters drawn on top hide the inner half.
        let outline = NSAttributedString(string: prefix + text, attributes: [
            .font: font, .strokeColor: Nodes.ink, .strokeWidth: 34,
        ])
        let pad = ceil(size * 0.25)
        let textSize = letters.size()
        let canvas = CGSize(width: ceil(textSize.width) + pad * 2, height: ceil(textSize.height) + pad * 2)
        return UIGraphicsImageRenderer(size: canvas).image { context in
            let origin = CGPoint(x: pad, y: pad)
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 1.5, color: UIColor(white: 0, alpha: 0.45).cgColor)
            outline.draw(at: origin)
            context.cgContext.setShadow(offset: .zero, blur: 0)
            letters.draw(at: origin)
        }
    }
}

final class HealthBar: SKNode {
    private let fill: SKSpriteNode
    private var manaFill: SKSpriteNode?
    private let width: CGFloat

    var fraction: CGFloat = 1 {
        didSet {
            fill.size.width = max(0, width * min(fraction, 1))
            fill.color = fraction > 0.3 ? UIColor(red: 0.4, green: 0.85, blue: 0.35, alpha: 1) : UIColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1)
        }
    }

    var manaFraction: CGFloat = 1 {
        didSet { manaFill?.size.width = max(0, width * min(manaFraction, 1)) }
    }

    /// With a `level`, a small "Lv12" badge caps the bar's left end, so one compact plate shows both.
    /// With `mana`, a thin MP bar hangs under the HP bar.
    init(width: CGFloat, level: Int? = nil, mana: Bool = false) {
        self.width = width
        let thick: CGFloat = level == nil ? 3 : 4
        fill = SKSpriteNode(color: .green, size: CGSize(width: width, height: thick))
        super.init()
        var parts: [SKNode] = []
        let background = SKSpriteNode(color: UIColor(white: 0, alpha: 0.6), size: CGSize(width: width + 2, height: thick + 2))
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position.x = -width / 2
        fill.zPosition = 1
        parts += [background, fill]
        if mana {
            let y = -(thick + 2) / 2 - 2
            let back = SKSpriteNode(color: UIColor(white: 0, alpha: 0.6), size: CGSize(width: width + 2, height: 4))
            back.position.y = y
            let blue = SKSpriteNode(color: UIColor(red: 0.24, green: 0.52, blue: 0.95, alpha: 1), size: CGSize(width: width, height: 2))
            blue.anchorPoint = CGPoint(x: 0, y: 0.5)
            blue.position = CGPoint(x: -width / 2, y: y)
            blue.zPosition = 1
            manaFill = blue
            parts += [back, blue]
        }
        for part in parts { addChild(part) }
        if let level {
            let texture = SKTexture(image: Self.badge(level))
            let badge = SKSpriteNode(texture: texture)
            // Tucked over the bars' left end; everything shifts so the whole plate stays centred.
            let overlap: CGFloat = 3
            let shift = (badge.size.width - overlap) / 2
            badge.position.x = -width / 2 - badge.size.width / 2 + overlap + shift
            badge.position.y = mana ? -1 : 0
            badge.zPosition = 2
            addChild(badge)
            parts.forEach { $0.position.x += shift }
        }
        zPosition = 5_000
        fraction = 1
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// "Lv12" in cream on a dark rounded chip with a thin cream rim.
    private static func badge(_ level: Int) -> UIImage {
        let base = UIFont.systemFont(ofSize: 8.5, weight: .heavy)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 8.5) } ?? base
        let cream = UIColor(red: 1, green: 0.97, blue: 0.86, alpha: 1)
        let text = NSAttributedString(string: "Lv\(level)", attributes: [.font: font, .foregroundColor: cream])
        let textSize = text.size()
        let canvas = CGSize(width: ceil(textSize.width) + 8, height: 12)
        return UIGraphicsImageRenderer(size: canvas).image { _ in
            let chip = UIBezierPath(roundedRect: CGRect(origin: .zero, size: canvas).insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4)
            Nodes.ink.withAlphaComponent(0.9).setFill()
            chip.fill()
            cream.withAlphaComponent(0.7).setStroke()
            chip.lineWidth = 1
            chip.stroke()
            text.draw(at: CGPoint(x: (canvas.width - textSize.width) / 2, y: (canvas.height - textSize.height) / 2))
        }
    }
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
    enum BurstStyle {
        case normal, critical, heal, splash

        var colors: (fill: UIColor, rim: UIColor, text: UIColor) {
            switch self {
            case .normal: (UIColor(red: 1, green: 0.97, blue: 0.75, alpha: 1), UIColor(red: 1, green: 0.72, blue: 0.2, alpha: 1), Nodes.ink)
            case .critical: (UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 1), UIColor(red: 0.9, green: 0.15, blue: 0.2, alpha: 1), .white)
            case .heal: (UIColor(red: 0.8, green: 1, blue: 0.78, alpha: 1), UIColor(red: 0.3, green: 0.78, blue: 0.4, alpha: 1), Nodes.ink)
            case .splash: (UIColor(red: 0.93, green: 0.93, blue: 1, alpha: 1), UIColor(red: 0.6, green: 0.62, blue: 0.85, alpha: 1), Nodes.ink)
            }
        }

        var size: CGFloat {
            switch self {
            case .critical: 64
            case .splash: 38
            default: 50
            }
        }
    }

    /// A damage (or heal) number bursting out of a little comic "pow!" star.
    static func damageBurst(_ text: String, style: BurstStyle, at point: CGPoint, in parent: SKNode) {
        let image = burstImage(text, style: style)
        let texture = SKTexture(image: image)
        let node = SKSpriteNode(texture: texture, size: image.size)
        node.position = point + CGVector(dx: .random(in: -10...10), dy: 6)
        node.zPosition = 21_000
        node.setScale(0.2)
        node.zRotation = .random(in: -0.18...0.18)
        parent.addChild(node)
        let pop = SKAction.sequence([.scale(to: style == .critical ? 1.3 : 1.18, duration: 0.09), .scale(to: 1, duration: 0.08)])
        let rise = SKAction.moveBy(x: 0, y: 22, duration: 0.55)
        rise.timingMode = .easeOut
        node.run(.sequence([pop, .wait(forDuration: 0.3), .group([rise, .fadeOut(withDuration: 0.55), .scale(to: 0.85, duration: 0.55)]), .removeFromParent()]))
    }

    private static func burstImage(_ text: String, style: BurstStyle) -> UIImage {
        let side = style.size
        let (fill, rim, textColor) = style.colors
        let fontSize = side * (text.count > 3 ? 0.3 : 0.36)
        let base = UIFont.systemFont(ofSize: fontSize, weight: .black)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: fontSize) } ?? base
        let label = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: textColor])
        let outline = NSAttributedString(string: text, attributes: [.font: font, .strokeColor: textColor == .white ? Nodes.ink : UIColor.white, .strokeWidth: 22])
        let textSize = label.size()
        let width = max(side, textSize.width + side * 0.55)
        let canvas = CGSize(width: width + 4, height: side + 4)
        return UIGraphicsImageRenderer(size: canvas).image { _ in
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let points = style == .critical ? 14 : 11
            let star = UIBezierPath()
            for index in 0..<(points * 2) {
                let angle = CGFloat(index) / CGFloat(points * 2) * 2 * .pi - .pi / 2
                // Uneven spikes look hand-drawn.
                let reach: CGFloat = index.isMultiple(of: 2) ? (index % 4 == 0 ? 1 : 0.86) : 0.62
                let p = CGPoint(x: center.x + cos(angle) * width / 2 * reach, y: center.y + sin(angle) * side / 2 * reach)
                index == 0 ? star.move(to: p) : star.addLine(to: p)
            }
            star.close()
            rim.setFill()
            star.fill()
            let inner = UIBezierPath(ovalIn: CGRect(x: center.x - width * 0.3, y: center.y - side * 0.28, width: width * 0.6, height: side * 0.56))
            fill.setFill()
            inner.fill()
            Nodes.ink.withAlphaComponent(0.85).setStroke()
            star.lineWidth = 2
            star.stroke()
            let origin = CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2)
            outline.draw(at: origin)
            label.draw(at: origin)
        }
    }

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

    static let tapMarkerName = "tapMarker"

    /// Fairyland's destination marker: a purple swirl on the ground.
    static func tapMarker(at point: CGPoint, in parent: SKNode) {
        let marker = SKNode()
        marker.name = tapMarkerName
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
        swirl.lineWidth = 3
        swirl.glowWidth = 1
        marker.addChild(swirl)
        swirl.run(.repeat(.sequence([.scale(to: 1.15, duration: 0.2), .scale(to: 1, duration: 0.2)]), count: 2))
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

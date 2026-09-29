import SpriteKit

/// What your equipment looks like on the hero: the weapon in hand (drawn as a little pixel
/// sprite, in front of or behind the body depending on facing) and a sparkle for accessories.
/// Armour recolours the outfit instead (see `GameSession.rules(for:armor:)`).
enum GearArt {
    // MARK: Weapon

    /// A weapon sprite for `item`, sized for a character `height` points tall.
    static func weapon(_ item: ItemDef, height: CGFloat) -> SKSpriteNode? {
        guard item.type == .weapon else { return nil }
        let texture = texture(for: item.icon ?? "sword")
        let node = SKSpriteNode(texture: texture, size: CGSize(width: height * 0.42, height: height * 0.42))
        node.anchorPoint = CGPoint(x: 0.2, y: 0.2)   // the grip
        node.name = "weapon"
        return node
    }

    /// Holds the weapon in the right hand for the way the character faces.
    static func pose(_ weapon: SKSpriteNode, facing: Direction, height: CGFloat) {
        let hand = height * 0.34
        switch facing {
        case .down:
            weapon.position = CGPoint(x: height * 0.2, y: hand)
            weapon.xScale = 1
            weapon.zPosition = 1
        case .up:
            weapon.position = CGPoint(x: -height * 0.2, y: hand)
            weapon.xScale = -1
            weapon.zPosition = -1
        case .left:
            weapon.position = CGPoint(x: -height * 0.1, y: hand)
            weapon.xScale = -1
            weapon.zPosition = 1
        case .right:
            weapon.position = CGPoint(x: height * 0.1, y: hand)
            weapon.xScale = 1
            weapon.zPosition = -1
        }
    }

    private static var cache: [String: SKTexture] = [:]

    private static func texture(for shape: String) -> SKTexture {
        if let cached = cache[shape] { return cached }
        var c = PixelCanvas(width: 16, height: 16)
        let outline = PixelColor(0x2A1E2E)
        let wood = PixelColor(0x8A5A32)
        switch shape {
        case "wand":   // Oak staff: a knotted stick with a leafy top.
            line(&c, from: (1, 15), to: (11, 5), color: outline, width: 3)
            line(&c, from: (1, 15), to: (11, 5), color: wood, width: 1)
            c.ellipse(12.5, 3.5, 3.2, 3.2, outline)
            c.ellipse(12.5, 3.5, 2.3, 2.3, PixelColor(0x5CCB5F))
            c[12, 2] = PixelColor(0xB8F5A0)
        case "diamond":   // Crystal wand: slim silver rod, glowing crystal.
            line(&c, from: (2, 14), to: (10, 6), color: outline, width: 3)
            line(&c, from: (2, 14), to: (10, 6), color: PixelColor(0xD8DCE8), width: 1)
            c.fill(10, 1, 5, 5, outline)
            c.fill(11, 2, 3, 3, PixelColor(0x6FE6F2))
            c[11, 2] = .white
        case "axe":
            line(&c, from: (2, 15), to: (11, 6), color: outline, width: 3)
            line(&c, from: (2, 15), to: (11, 6), color: wood, width: 1)
            c.ellipse(11.5, 4.5, 4.2, 3.4, outline)
            c.ellipse(11.5, 4.5, 3.2, 2.4, PixelColor(0xB9C2CF))
            c[10, 3] = .white
        case "paw":   // Tamer whip: a handle and a curling lash.
            line(&c, from: (1, 15), to: (5, 11), color: outline, width: 3)
            line(&c, from: (1, 15), to: (5, 11), color: wood, width: 1)
            for (x, y) in [(6, 10), (7, 8), (8, 6), (10, 5), (12, 5), (13, 7), (12, 9), (10, 9)] {
                c[x, y] = PixelColor(0xC98A4B)
                c[x + 1, y] = outline
            }
        default:   // Sword: silver blade, gold guard, brown grip.
            line(&c, from: (5, 10), to: (14, 1), color: outline, width: 3)
            line(&c, from: (5, 10), to: (14, 1), color: PixelColor(0xE4E8F0), width: 1)
            line(&c, from: (3, 8), to: (7, 12), color: outline, width: 3)
            line(&c, from: (3, 8), to: (7, 12), color: PixelColor(0xF2C230), width: 1)
            line(&c, from: (1, 14), to: (4, 11), color: outline, width: 3)
            line(&c, from: (1, 14), to: (4, 11), color: wood, width: 1)
        }
        let texture = c.texture()
        cache[shape] = texture
        return texture
    }

    private static func line(_ c: inout PixelCanvas, from a: (Int, Int), to b: (Int, Int), color: PixelColor, width: Int) {
        let steps = max(abs(b.0 - a.0), abs(b.1 - a.1))
        for step in 0...steps {
            let t = Double(step) / Double(max(1, steps))
            let x = Int((Double(a.0) + Double(b.0 - a.0) * t).rounded())
            let y = Int((Double(a.1) + Double(b.1 - a.1) * t).rounded())
            let half = width / 2
            c.fill(x - half, y - half, width, width, color)
        }
    }

    // MARK: Accessory

    /// A few twinkles around the wearer, in the accessory's colour.
    static func aura(_ item: ItemDef, height: CGFloat) -> SKNode? {
        guard item.type == .accessory else { return nil }
        let color: UIColor = switch item.icon {
        case "clover": UIColor(red: 0.55, green: 1, blue: 0.5, alpha: 1)
        case "gem": UIColor(red: 1, green: 0.45, blue: 0.5, alpha: 1)
        default: UIColor(red: 1, green: 0.88, blue: 0.45, alpha: 1)
        }
        let aura = SKNode()
        aura.name = "aura"
        aura.zPosition = 2
        for index in 0..<3 {
            let star = SKSpriteNode(texture: SoftTextures.star, size: CGSize(width: 7, height: 7))
            star.color = color
            star.colorBlendFactor = 1
            star.blendMode = .add
            star.alpha = 0
            aura.addChild(star)
            let hop = SKAction.run {
                star.position = CGPoint(x: .random(in: -height * 0.35...height * 0.35), y: .random(in: height * 0.2...height * 0.9))
            }
            let twinkle = SKAction.sequence([hop, .fadeIn(withDuration: 0.3), .wait(forDuration: 0.2), .fadeOut(withDuration: 0.5),
                                             .wait(forDuration: 0.6, withRange: 0.8)])
            star.run(.sequence([.wait(forDuration: 0.5 * Double(index)), .repeatForever(twinkle)]))
        }
        return aura
    }
}

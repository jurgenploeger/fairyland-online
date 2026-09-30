import SpriteKit
import UIKit

/// The whimsy layer of a map: drifting petals or fireflies, butterflies, cloud shadows,
/// a colour mood and a soft vignette. Driven by the `ambience` block in content/maps.json.
final class Ambience {
    private let tint: SKSpriteNode?
    private let vignette: SKSpriteNode?

    init(_ def: MapDef.Ambience?, world: SKNode, camera: SKCameraNode, bounds: CGRect, seed: String) {
        var rng = SeededRandom(text: seed + "/ambience")

        // One kind, or several joined with "+" (e.g. "snow+sparkles").
        for kind in (def?.particles ?? "").split(separator: "+").map(String.init) {
            guard let emitter = Self.particles(kind) else { continue }
            emitter.targetNode = world
            emitter.zPosition = 30_000
            camera.addChild(emitter)
            // Already drifting when you arrive, instead of starting from an empty sky.
            emitter.advanceSimulationTime(TimeInterval(emitter.particleLifetime))
            if kind == "snow" {
                // Big close flakes that move with the camera, rushing past in front of the world.
                let near = Self.nearSnow()
                near.zPosition = 30_500
                camera.addChild(near)
                near.advanceSimulationTime(TimeInterval(near.particleLifetime))
            }
        }

        for _ in 0..<(def?.butterflies ?? 0) {
            let point = CGPoint(x: .random(in: bounds.minX...bounds.maxX, using: &rng), y: .random(in: bounds.minY...bounds.maxY, using: &rng))
            world.addChild(Self.butterfly(at: point, rng: &rng))
        }

        if def?.clouds == true {
            let count = max(3, Int(bounds.width * bounds.height / 1_400_000))
            for _ in 0..<count {
                world.addChild(Self.cloudShadow(bounds: bounds, rng: &rng))
            }
        }

        if let hex = def?.tint, let color = UIColor(hex: hex) {
            let node = SKSpriteNode(color: color, size: CGSize(width: 3000, height: 3000))
            node.alpha = CGFloat(def?.tintAlpha ?? 0.15)
            node.zPosition = 45_000
            camera.addChild(node)
            tint = node
        } else {
            tint = nil
        }

        if let strength = def?.vignette, strength > 0 {
            let node = SKSpriteNode(texture: SoftTextures.vignette)
            node.alpha = CGFloat(strength)
            node.zPosition = 46_000
            camera.addChild(node)
            vignette = node
        } else {
            vignette = nil
        }
    }

    func resize(to size: CGSize) {
        vignette?.size = CGSize(width: size.width * 1.15, height: size.height * 1.15)
    }

    /// A few stars twinkling around a point (fairy rings, fountains).
    static func twinkle(around point: CGPoint, radius: CGFloat, count: Int, in parent: SKNode) {
        for index in 0..<count {
            let star = SKSpriteNode(texture: SoftTextures.star, size: CGSize(width: 7, height: 7))
            star.blendMode = .add
            star.position = point + CGVector(dx: .random(in: -radius...radius), dy: .random(in: -radius * 0.6...radius * 0.6) + 10)
            star.zPosition = 24_000
            star.alpha = 0
            let blink = SKAction.sequence([
                .fadeIn(withDuration: 0.5), .wait(forDuration: 0.3), .fadeOut(withDuration: 0.6), .wait(forDuration: .random(in: 0.4...1.4)),
            ])
            star.run(.sequence([.wait(forDuration: Double(index) * 0.35), .repeatForever(blink)]))
            parent.addChild(star)
        }
    }

    // MARK: Particles

    /// The near layer of a snowfall: fewer, bigger, faster flakes in screen space, a little soft.
    private static func nearSnow() -> SKEmitterNode {
        let emitter = SKEmitterNode()
        // Out of focus: a plain soft blur, faintly blue so it shows over snow.
        emitter.particleTexture = SoftTextures.glow
        emitter.particleColor = UIColor(red: 0.9, green: 0.94, blue: 1, alpha: 1)
        emitter.particleColorBlendFactor = 1
        emitter.particlePositionRange = CGVector(dx: 1100, dy: 700)
        emitter.position = CGPoint(x: 0, y: 120)
        emitter.particleBirthRate = 5
        emitter.particleLifetime = 8
        emitter.particleLifetimeRange = 2
        emitter.particleSpeed = 55
        emitter.particleSpeedRange = 20
        emitter.emissionAngle = -.pi / 2 - 0.15
        emitter.emissionAngleRange = 0.35
        emitter.xAcceleration = 6
        emitter.particleScale = 0.35
        emitter.particleScaleRange = 0.12
        emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.8, 0.8, 0], times: [0, 0.1, 0.85, 1])
        return emitter
    }

    private static func particles(_ kind: String) -> SKEmitterNode? {
        let emitter = SKEmitterNode()
        emitter.particlePositionRange = CGVector(dx: 1200, dy: 1200)
        switch kind {
        case "petals", "leaves":
            emitter.particleTexture = kind == "petals" ? SoftTextures.petal : SoftTextures.leaf
            emitter.particleBirthRate = 2.2
            emitter.particleLifetime = 12
            emitter.particleSpeed = 20
            emitter.particleSpeedRange = 10
            emitter.emissionAngle = -.pi * 0.7
            emitter.emissionAngleRange = 0.6
            emitter.xAcceleration = -2
            emitter.yAcceleration = -3
            emitter.particleRotationRange = .pi * 2
            emitter.particleRotationSpeed = 1.4
            emitter.particleScale = 2
            emitter.particleScaleRange = 0.8
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.95, 0.95, 0], times: [0, 0.1, 0.8, 1])
        case "fireflies":
            emitter.particleTexture = SoftTextures.glow
            emitter.particleColor = UIColor(red: 0.8, green: 1, blue: 0.45, alpha: 1)
            emitter.particleColorBlendFactor = 1
            emitter.particleBlendMode = .add
            emitter.particleBirthRate = 4
            emitter.particleLifetime = 7
            emitter.particleLifetimeRange = 3
            emitter.particleSpeed = 9
            emitter.particleSpeedRange = 6
            emitter.emissionAngleRange = .pi * 2
            emitter.particleScale = 0.35
            emitter.particleScaleRange = 0.2
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 1, 0.2, 1, 0], times: [0, 0.2, 0.5, 0.75, 1])
        case "sparkles":
            emitter.particleTexture = SoftTextures.star
            emitter.particleBlendMode = .add
            emitter.particleBirthRate = 7
            emitter.particleLifetime = 1.6
            emitter.particleLifetimeRange = 0.8
            emitter.particleSpeed = 3
            emitter.emissionAngleRange = .pi * 2
            emitter.particleScale = 1.5
            emitter.particleScaleRange = 1
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 1, 0], times: [0, 0.4, 1])
        case "snow":
            // Far flakes: small, slow and many, settling with the ground as you walk.
            emitter.particleTexture = SoftTextures.flake
            emitter.particleBirthRate = 40
            emitter.particleLifetime = 12
            emitter.particleLifetimeRange = 4
            emitter.particleSpeed = 24
            emitter.particleSpeedRange = 10
            emitter.emissionAngle = -.pi / 2
            emitter.emissionAngleRange = 0.5
            emitter.xAcceleration = 3
            emitter.particleScale = 0.16
            emitter.particleScaleRange = 0.07
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.95, 0.95, 0], times: [0, 0.1, 0.85, 1])
        case "dust":
            emitter.particleTexture = SoftTextures.glow
            emitter.particleColor = UIColor(red: 1, green: 0.88, blue: 0.62, alpha: 1)
            emitter.particleColorBlendFactor = 1
            emitter.particleBirthRate = 6
            emitter.particleLifetime = 10
            emitter.particleSpeed = 34
            emitter.particleSpeedRange = 14
            emitter.emissionAngle = 0.15
            emitter.emissionAngleRange = 0.3
            emitter.particleScale = 0.16
            emitter.particleScaleRange = 0.1
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.6, 0.6, 0], times: [0, 0.2, 0.8, 1])
        case "motes":
            emitter.particleTexture = SoftTextures.glow
            emitter.particleColor = UIColor(red: 0.55, green: 0.85, blue: 1, alpha: 1)
            emitter.particleColorBlendFactor = 1
            emitter.particleBlendMode = .add
            emitter.particleBirthRate = 3
            emitter.particleLifetime = 9
            emitter.particleLifetimeRange = 3
            emitter.particleSpeed = 6
            emitter.emissionAngle = .pi / 2
            emitter.emissionAngleRange = 1
            emitter.particleScale = 0.3
            emitter.particleScaleRange = 0.15
            emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.8, 0.3, 0.8, 0], times: [0, 0.25, 0.5, 0.75, 1])
        default:
            return nil
        }
        emitter.advanceSimulationTime(12)
        return emitter
    }

    // MARK: Butterflies

    private static func butterfly(at point: CGPoint, rng: inout SeededRandom) -> SKNode {
        let colors: [UInt32] = [0xF8BBD0, 0xFFF59D, 0xB3E5FC, 0xE1BEE7, 0xFFCC80]
        let color = PixelColor(colors[Int.random(in: 0..<colors.count, using: &rng)])
        let frames = [SoftTextures.butterfly(color: color, open: true), SoftTextures.butterfly(color: color, open: false)]
        let sprite = SKSpriteNode(texture: frames[0], size: CGSize(width: 21, height: 15))
        sprite.position = point
        sprite.zPosition = 25_000
        sprite.run(.repeatForever(.animate(with: frames, timePerFrame: 0.11)))

        // A lazy loop that always returns home, so butterflies never drift off the map.
        var moves: [SKAction] = []
        var total = CGVector.zero
        for _ in 0..<5 {
            let step = CGVector(dx: .random(in: -70...70, using: &rng), dy: .random(in: -50...50, using: &rng))
            total = CGVector(dx: total.dx + step.dx, dy: total.dy + step.dy)
            let move = SKAction.moveBy(x: step.dx, y: step.dy, duration: .random(in: 2...4, using: &rng))
            move.timingMode = .easeInEaseOut
            moves.append(move)
        }
        let home = SKAction.moveBy(x: -total.dx, y: -total.dy, duration: 3)
        home.timingMode = .easeInEaseOut
        moves.append(home)
        sprite.run(.repeatForever(.sequence(moves)))
        let bob = SKAction.sequence([.moveBy(x: 0, y: 4, duration: 0.5), .moveBy(x: 0, y: -4, duration: 0.5)])
        sprite.run(.repeatForever(bob))
        return sprite
    }

    // MARK: Clouds

    private static func cloudShadow(bounds: CGRect, rng: inout SeededRandom) -> SKNode {
        let width = CGFloat.random(in: 380...620, using: &rng)
        let cloud = SKSpriteNode(texture: SoftTextures.cloud, size: CGSize(width: width, height: width * 0.45))
        cloud.color = .black
        cloud.colorBlendFactor = 1
        cloud.alpha = 0.1
        cloud.zPosition = 20_000
        let left = bounds.minX - width
        let right = bounds.maxX + width
        let startX = CGFloat.random(in: left...right, using: &rng)
        cloud.position = CGPoint(x: startX, y: .random(in: bounds.minY...bounds.maxY, using: &rng))
        let speed = CGFloat.random(in: 9...16, using: &rng)
        // Drift east, wrap around, repeat.
        let first = SKAction.moveTo(x: right, duration: TimeInterval((right - startX) / speed))
        let loop = SKAction.repeatForever(.sequence([.moveTo(x: left, duration: 0), .moveTo(x: right, duration: TimeInterval((right - left) / speed))]))
        cloud.run(.sequence([first, loop]))
        return cloud
    }
}

/// Small generated textures for effects: soft glows, petals, butterflies, the vignette.
enum SoftTextures {
    static let glow: SKTexture = radial(size: 32, colors: [.white, UIColor(white: 1, alpha: 0)])
    /// A snowflake: white with a pale blue rim, so it still shows against snowy ground.
    static let flake: SKTexture = radial(size: 32, colors: [
        .white, .white, UIColor(red: 0.93, green: 0.96, blue: 1, alpha: 1),
        UIColor(red: 0.62, green: 0.72, blue: 0.88, alpha: 0.6), UIColor(red: 0.62, green: 0.72, blue: 0.88, alpha: 0),
    ])
    static let cloud: SKTexture = radial(size: 128, colors: [.white, UIColor(white: 1, alpha: 0.6), UIColor(white: 1, alpha: 0)])
    static let vignette: SKTexture = radial(size: 256, colors: [UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.9)])
    /// White at the top fading to clear at the bottom (distance haze).
    static let fade: SKTexture = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 4, height: 128)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor.white.cgColor, UIColor(white: 1, alpha: 0.35).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            let locations: [CGFloat] = [0, 0.45, 1]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return SKTexture(image: image)
    }()

    static let petal: SKTexture = pixel(width: 3, height: 3) { c in
        c.fill(0, 0, 3, 3, PixelColor(0xF8BBD0))
        c[1, 1] = PixelColor(0xFFE4EE)
        c[0, 0] = .clear
    }

    static let leaf: SKTexture = pixel(width: 4, height: 3) { c in
        c.fill(0, 0, 4, 3, PixelColor(0xFFB74D))
        c[0, 0] = .clear
        c[3, 2] = .clear
        c.fill(0, 1, 4, 1, PixelColor(0xF57C00))
    }

    static let star: SKTexture = pixel(width: 5, height: 5) { c in
        c.fill(2, 0, 1, 5, .white)
        c.fill(0, 2, 5, 1, .white)
    }

    static func butterfly(color: PixelColor, open: Bool) -> SKTexture {
        pixel(width: 7, height: 5) { c in
            if open {
                c.fill(0, 0, 3, 3, color)
                c.fill(4, 0, 3, 3, color)
                c.fill(1, 3, 2, 2, color.shaded(0.85))
                c.fill(4, 3, 2, 2, color.shaded(0.85))
            } else {
                c.fill(2, 0, 1, 4, color)
                c.fill(4, 0, 1, 4, color)
            }
            c.fill(3, 0, 1, 5, PixelColor(0x3E2723))
        }
    }

    private static func pixel(width: Int, height: Int, draw: (inout PixelCanvas) -> Void) -> SKTexture {
        var canvas = PixelCanvas(width: width, height: height)
        draw(&canvas)
        return canvas.texture()
    }

    private static func radial(size: CGFloat, colors: [UIColor]) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            let cgColors = colors.map(\.cgColor) as CFArray
            let locations: [CGFloat] = colors.indices.map { CGFloat($0) / CGFloat(max(1, colors.count - 1)) }
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations) else { return }
            let center = CGPoint(x: size / 2, y: size / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size / 2, options: [])
        }
        return SKTexture(image: image)
    }
}

extension UIColor {
    /// "#RRGGBB"
    convenience init?(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

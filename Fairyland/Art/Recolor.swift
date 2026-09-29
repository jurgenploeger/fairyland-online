import CoreGraphics
import Foundation

/// A free "derived" sprite: an existing sprite with a palette swap, like classic games made
/// villagers and monster variants. Declared in art/assets.json as
/// `"derive": { "from": "player_walk", "recolor": [ … ] }`.
nonisolated struct Derivation: Decodable, Sendable {
    let from: String
    let recolor: [RecolorRule]
}

/// Changes pixels whose colour falls in a hue range (optionally only saturated or bright ones).
/// Hues are in degrees; a range like [330, 20] wraps around red.
nonisolated struct RecolorRule: Decodable, Sendable {
    let hue: [Double]?
    let minSaturation: Double?
    let maxSaturation: Double?
    let minValue: Double?
    let maxValue: Double?
    /// Set the hue to this…
    let to: Double?
    /// …or rotate it by this many degrees.
    let shift: Double?
    /// Multipliers for saturation and brightness.
    let saturation: Double?
    let value: Double?

    func matches(hue h: Double, saturation s: Double, value v: Double) -> Bool {
        guard s >= (minSaturation ?? 0.15), s <= (maxSaturation ?? 1), v >= (minValue ?? 0), v <= (maxValue ?? 1) else { return false }
        guard let range = hue, range.count == 2 else { return true }
        return range[0] <= range[1] ? (h >= range[0] && h <= range[1]) : (h >= range[0] || h <= range[1])
    }
}

enum Recolor {
    /// Applies the first matching rule to every opaque pixel. Outlines and greys stay put
    /// unless a rule explicitly asks for low saturation.
    nonisolated static func apply(_ rules: [RecolorRule], to image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3])
            guard alpha > 0 else { continue }
            // Un-premultiply, recolour in HSV, premultiply again.
            let r = Double(pixels[index]) / alpha, g = Double(pixels[index + 1]) / alpha, b = Double(pixels[index + 2]) / alpha
            var (h, s, v) = hsv(r, g, b)
            guard let rule = rules.first(where: { $0.matches(hue: h, saturation: s, value: v) }) else { continue }
            if let to = rule.to { h = to } else if let shift = rule.shift { h = (h + shift).truncatingRemainder(dividingBy: 360) }
            if h < 0 { h += 360 }
            s = min(1, s * (rule.saturation ?? 1))
            v = min(1, v * (rule.value ?? 1))
            let (nr, ng, nb) = rgb(h, s, v)
            pixels[index] = UInt8(max(0, min(255, (nr * alpha).rounded())))
            pixels[index + 1] = UInt8(max(0, min(255, (ng * alpha).rounded())))
            pixels[index + 2] = UInt8(max(0, min(255, (nb * alpha).rounded())))
        }
        return context.makeImage()
    }

    nonisolated private static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maximum = max(r, g, b), minimum = min(r, g, b), delta = maximum - minimum
        var hue = 0.0
        if delta > 0 {
            if maximum == r { hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maximum == g { hue = 60 * ((b - r) / delta + 2) }
            else { hue = 60 * ((r - g) / delta + 4) }
        }
        if hue < 0 { hue += 360 }
        return (hue, maximum == 0 ? 0 : delta / maximum, maximum)
    }

    nonisolated private static func rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let c = v * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double) = switch h {
        case ..<60: (c, x, 0)
        case ..<120: (x, c, 0)
        case ..<180: (0, c, x)
        case ..<240: (0, x, c)
        case ..<300: (x, 0, c)
        default: (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}

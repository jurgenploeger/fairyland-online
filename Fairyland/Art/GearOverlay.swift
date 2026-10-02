import CoreGraphics
import Foundation

/// What the hero has on, beyond the outfit's colours: the cut of their armour and their boots.
nonisolated struct GearLook: Sendable, Hashable {
    /// The armour's cut (content/items.json `wear`): vest | mail | plate | robe | cloak.
    var wear: String?
    /// Trim colour for buttons, clasps and hems, "#RRGGBB" (`accent`).
    var accent: String?
    /// Speed boots: the boots turn sky blue.
    var boots = false

    var isPlain: Bool { wear == nil && !boots }
}

/// Draws worn gear onto a walk sheet, frame by frame. It finds the outfit (the green tunic) on the
/// original sheet, then on the recoloured sheet adds what that kind of armour looks like: chain
/// links, an open vest, pauldrons and a helmet, a robe's long hem, a cape and hood. Helmets and hoods
/// cover all the hair (a beard stays). tools/gear_preview.py is the same algorithm in Python, to tune
/// it without a Mac.
enum GearOverlay {
    nonisolated static func apply(_ gear: GearLook, original: CGImage, dressed: CGImage, frame: Int = 48,
                                  directions: [String] = ["up", "right", "down", "left"]) -> CGImage? {
        guard !gear.isPlain, original.width == dressed.width, original.height == dressed.height,
              let base = Bitmap(original), var out = Bitmap(dressed) else { return dressed }
        let accent = color(hex: gear.accent) ?? RGB(0.95, 0.78, 0.25)
        // How this body's head is built, measured once on the first facing-down frame.
        var head: Head?
        if gear.wear == "plate" || gear.wear == "cloak", let down = directions.firstIndex(of: "down") {
            head = Head(measuring: base, origin: (0, down * frame), size: frame)
        }
        for (row, facing) in directions.enumerated() {
            for column in 0..<(base.width / frame) {
                dress(&out, base: base, origin: (column * frame, row * frame), size: frame, facing: facing, gear: gear,
                      accent: accent, head: head)
            }
        }
        return out.image()
    }

    // MARK: One frame

    nonisolated private static func dress(_ out: inout Bitmap, base: Bitmap, origin: (x: Int, y: Int), size: Int,
                                          facing: String, gear: GearLook, accent: RGB, head: Head?) {
        // Frame-local helpers. `opaque` and `outfit` read the original sheet.
        func opaque(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < size && y < size && base.alpha(origin.x + x, origin.y + y) > 0.5
        }
        func outfit(_ x: Int, _ y: Int) -> Bool {
            guard opaque(x, y) else { return false }
            let (h, s, _) = hsv(base.rgb(origin.x + x, origin.y + y))
            return h >= 85 && h <= 170 && s >= 0.3
        }
        func put(_ x: Int, _ y: Int, _ c: RGB, onlyEmpty: Bool = false) {
            guard x >= 0, y >= 0, x < size, y < size, !onlyEmpty || !opaque(x, y) else { return }
            out.set(origin.x + x, origin.y + y, c)
        }

        var cells: [(x: Int, y: Int)] = []
        for y in 0..<size { for x in 0..<size where outfit(x, y) { cells.append((x, y)) } }
        guard let first = cells.first else { return }
        var x0 = first.x, x1 = first.x, y0 = first.y, y1 = first.y
        for cell in cells {
            x0 = min(x0, cell.x); x1 = max(x1, cell.x); y0 = min(y0, cell.y); y1 = max(y1, cell.y)
        }
        var feet = 0
        for y in 0..<size where (0..<size).contains(where: { opaque($0, y) }) { feet = y }
        let mid = median(cells.map { out.rgb(origin.x + $0.x, origin.y + $0.y) })
        let dark = mid.scaled(0.55), light = mid.mixed(with: RGB(1, 1, 1), 0.35)
        let outline = RGB(0.16, 0.12, 0.18)
        let cx = (x0 + x1) / 2

        switch gear.wear {
        case "mail":
            // Chain links: a fine checker over the tunic.
            for cell in cells {
                if (cell.x + cell.y) % 2 == 0 {
                    out.set(origin.x + cell.x, origin.y + cell.y, light)
                } else if (cell.x + 2 * cell.y) % 4 == 1 {
                    out.set(origin.x + cell.x, origin.y + cell.y, dark)
                }
            }
        case "vest":
            // Worn open over a light shirt, with two buttons.
            guard facing == "down" else { break }
            for cell in cells where abs(cell.x - cx) <= 1 && cell.y < y1 - 1 {
                out.set(origin.x + cell.x, origin.y + cell.y, cell.x == cx ? RGB(0.8, 0.74, 0.62) : RGB(0.93, 0.88, 0.76))
            }
            put(cx - 2, y0 + 3, accent)
            put(cx + 2, y0 + 3, accent)
        case "plate":
            // Round pauldrons on the shoulders, lit from the top left, and a shine down the chest.
            let pads = switch facing {
            case "right": [x1 - 1]
            case "left": [x0 + 1]
            default: [x0 + 1, x1 - 1]
            }
            for px in pads {
                for dy in -1...2 {
                    for dx in -2...2 where Double(dx * dx) + pow(Double(dy) - 0.6, 2) * 1.6 <= 4.4 {
                        var c = dy <= 0 ? light : mid
                        if dy == 2 || (abs(dx) == 2 && dy >= 1) { c = dark }
                        put(px + dx, y0 + dy, c)
                    }
                }
                put(px - 1, y0 - 1, RGB(1, 1, 1))
            }
            if facing == "down" || facing == "up" {
                for y in (y0 + 3)..<max(y0 + 3, y1) where outfit(cx, y) { out.set(origin.x + cx, origin.y + y, light) }
                if facing == "down" { put(cx, y0 + 4, accent) }
            }
        case "robe":
            // The hem drops past the knees, flaring a little, with a trimmed edge.
            var bottom: [Int: Int] = [:]
            for cell in cells { bottom[cell.x] = max(bottom[cell.x] ?? 0, cell.y) }
            let hemTop = bottom.values.max() ?? y1
            let hemBottom = feet - 2
            let columns = bottom.filter { $0.value >= hemTop - 2 }.map(\.key)
            guard hemBottom > hemTop, let lx = columns.min(), let rx = columns.max() else { break }
            for y in (hemTop + 1)...hemBottom {
                let flare = (y - hemTop + 1) / 2
                for x in (lx - flare)...(rx + flare) {
                    put(x, y, x == lx - flare || x == rx + flare ? dark : mid)
                }
            }
            let flare = (hemBottom - hemTop + 1) / 2
            for x in (lx - flare)...(rx + flare) {
                put(x, hemBottom, dark)
                put(x, hemBottom - 1, accent)
            }
        case "cloak":
            let top = y0, hem = feet - 3
            guard hem > top else { break }
            if facing == "up" {
                // From behind: the cape covers the back, widening toward the hem.
                for y in top...hem {
                    let w = (y - top) / 3
                    for x in (x0 - w)...(x1 + w) {
                        let edge = x == x0 - w || x == x1 + w || y == hem
                        put(x, y, edge ? outline : (x == cx - 2 ? light : mid))
                    }
                }
            } else {
                // From the front or side: the cape shows just outside the body's outline.
                for y in (top + 1)...hem {
                    guard let left = (0..<size).first(where: { opaque($0, y) }),
                          let right = (0..<size).last(where: { opaque($0, y) }) else { continue }
                    let flare = (y - top) / 5
                    // (x, whether it's the cape's outer edge)
                    var spots: [(Int, Bool)] = []
                    switch facing {
                    case "down":
                        spots = [(left - 1 - flare, true), (right + 1 + flare, true)]
                        if flare > 0 { spots += [(left - flare, false), (right + flare, false)] }
                    case "right":
                        spots = [(left - 1 - flare, true)]
                        for k in 0...flare { spots.append((left - k, false)) }
                    default:
                        spots = [(right + 1 + flare, true)]
                        for k in 0...flare { spots.append((right + k, false)) }
                    }
                    for (x, outer) in spots { put(x, y, outer ? outline : mid, onlyEmpty: true) }
                }
                if facing == "down" {
                    put(cx, top, accent)
                    put(cx - 1, top, accent)
                    put(cx, top + 1, accent.scaled(0.7))
                }
            }
        default:
            break
        }
        if let head {
            coverHead(&out, base: base, origin: origin, size: size, facing: facing, head: head,
                      hood: gear.wear == "cloak", mid: mid, accent: accent)
        }

        if gear.boots {
            // Brown boots near the feet turn sky blue.
            for y in max(0, feet - 5)...feet {
                for x in 0..<size where opaque(x, y) {
                    let (h, s, v) = hsv(out.rgb(origin.x + x, origin.y + y))
                    guard h >= 7, h <= 43, s > 0.35, v < 0.75 else { continue }
                    out.set(origin.x + x, origin.y + y, rgb(209, min(1, s * 0.9), min(1, v * 1.5)))
                }
            }
        }
    }

    // MARK: Helmets and hoods

    /// Hair on the original sheet: the same rule content/appearance.json recolours (hue 12-58, bright).
    nonisolated private static func isHair(_ base: Bitmap, _ x: Int, _ y: Int) -> Bool {
        guard base.alpha(x, y) >= 0.5 else { return false }
        let (h, s, v) = hsv(base.rgb(x, y))
        return h >= 12 && h <= 58 && s >= 0.55 && v >= 0.55
    }

    nonisolated private static func isSkin(_ base: Bitmap, _ x: Int, _ y: Int) -> Bool {
        guard base.alpha(x, y) >= 0.5 else { return false }
        let (h, s, v) = hsv(base.rgb(x, y))
        return h <= 40 && s > 0.15 && s < 0.55 && v > 0.6
    }

    /// A darker hair strand: the same hues, dimmer. Only counts when it touches the bright hair.
    nonisolated private static func isHairish(_ base: Bitmap, _ x: Int, _ y: Int) -> Bool {
        guard base.alpha(x, y) >= 0.5, !isSkin(base, x, y) else { return false }
        let (h, s, v) = hsv(base.rgb(x, y))
        return h >= 5 && h <= 62 && s >= 0.3 && v >= 0.2
    }

    /// Top of the head: the first row with at least four hair pixels (skips a lone spike's tip).
    nonisolated private static func crown(_ base: Bitmap, origin: (x: Int, y: Int), size: Int) -> Int? {
        (0..<size).first { y in (0..<size).filter { isHair(base, origin.x + $0, origin.y + y) }.count >= 4 }
    }

    /// Every hair pixel of the head (frame-local, row by row): bright hair on the scalp, flooded out
    /// through darker strands (long hair, sideburns, a beard). A belt buckle or boots don't touch it.
    nonisolated private static func hairMask(_ base: Bitmap, origin: (x: Int, y: Int), size: Int, top: Int, brow: Int) -> [Bool] {
        var mask = [Bool](repeating: false, count: size * size)
        var stack: [(x: Int, y: Int)] = []
        for y in max(0, top)..<min(size, max(top, brow)) {
            for x in 0..<size where isHair(base, origin.x + x, origin.y + y) {
                mask[y * size + x] = true
                stack.append((x, y))
            }
        }
        while let cell = stack.popLast() {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let x = cell.x + dx, y = cell.y + dy
                guard x >= 0, y >= 0, x < size, y < size, !mask[y * size + x],
                      isHairish(base, origin.x + x, origin.y + y) else { continue }
                mask[y * size + x] = true
                stack.append((x, y))
            }
        }
        return mask
    }

    /// The scalp's hair, columns `x0...x1`, over rows `top..<brow`.
    nonisolated private static func scalp(_ base: Bitmap, origin: (x: Int, y: Int), size: Int, top: Int, brow: Int) -> (x0: Int, x1: Int)? {
        var x0 = Int.max, x1 = Int.min
        for y in max(0, top)..<min(size, max(top, brow)) {
            for x in 0..<size where isHair(base, origin.x + x, origin.y + y) {
                x0 = min(x0, x); x1 = max(x1, x)
            }
        }
        return x0 <= x1 ? (x0, x1) : nil
    }

    /// How a body's head is built: rows from the crown down to the face, and whether it has a beard.
    nonisolated private struct Head: Sendable {
        var drop = 10
        var bearded = false

        init(measuring base: Bitmap, origin: (x: Int, y: Int), size: Int) {
            guard let top = GearOverlay.crown(base, origin: origin, size: size) else { return }
            // The face starts at the first row with three skin pixels side by side (the forehead, not an ear).
            for y in top..<size {
                var run = 0
                if (0..<size).contains(where: { x in
                    run = GearOverlay.isSkin(base, origin.x + x, origin.y + y) ? run + 1 : 0
                    return run >= 3
                }) {
                    drop = y - top
                    break
                }
            }
            // A beard: plenty of hair under the chin.
            let brow = top + drop, chin = brow + 5
            guard chin < size, let span = GearOverlay.scalp(base, origin: origin, size: size, top: top, brow: brow) else { return }
            let hair = GearOverlay.hairMask(base, origin: origin, size: size, top: top, brow: brow)
            let cx = Double(span.x0 + span.x1) / 2
            var count = 0
            for y in chin..<min(size, chin + 6) {
                for x in 0..<size where abs(Double(x) - cx) < 4 && hair[y * size + x] { count += 1 }
            }
            bearded = count >= 12
        }
    }

    /// A helmet (plate) or hood (cloak) over the hair: a smooth dome from the crown down to the chin that
    /// leaves the face open. Tufts outside the dome are erased, and long hair below it is covered too (a
    /// mail neck guard, or the hood's cloth); a beard in front of the face stays.
    nonisolated private static func coverHead(_ out: inout Bitmap, base: Bitmap, origin: (x: Int, y: Int), size: Int,
                                              facing: String, head: Head, hood: Bool, mid: RGB, accent: RGB) {
        guard let top = crown(base, origin: origin, size: size) else { return }
        let brow = top + head.drop, chin = brow + 5
        guard brow < size, let span = scalp(base, origin: origin, size: size, top: top, brow: brow) else { return }
        let hair = hairMask(base, origin: origin, size: size, top: top, brow: brow)
        let cx = Double(span.x0 + span.x1) / 2
        let half = Double(span.x1 - span.x0) / 2 + (hood ? 1 : 0.5)
        let lid = top - (hood ? 1 : 0)
        let reach = Double(brow - lid)
        let side = facing == "right" ? 1.0 : facing == "left" ? -1.0 : 0
        let dark = mid.scaled(0.55), light = mid.mixed(with: RGB(1, 1, 1), 0.4)
        let outline = RGB(0.16, 0.12, 0.18)

        func inside(_ x: Int, _ y: Int) -> Bool {
            guard y >= lid, y <= chin else { return false }
            let dy = Double(max(0, brow - y)) / reach
            return pow((Double(x) - cx) / half, 2) + dy * dy <= 1
        }
        func beard(_ x: Int, _ y: Int) -> Bool {
            guard head.bearded, y >= brow + 3, facing != "up" else { return false }
            return side != 0 ? (Double(x) - cx) * side > -1 : abs(Double(x) - cx) < half - 3
        }
        func filled(_ x: Int, _ y: Int) -> Bool { out.alpha(origin.x + x, origin.y + y) >= 0.5 }

        var painted = [Bool](repeating: false, count: size * size)
        func paint(_ x: Int, _ y: Int, _ c: RGB) {
            out.set(origin.x + x, origin.y + y, c)
            painted[y * size + x] = true
        }
        for y in 0..<min(size, chin + 1) {
            for x in 0..<size {
                let bx = origin.x + x, by = origin.y + y
                if inside(x, y) {
                    if y >= brow && facing != "up" {
                        // The face stays open: only hair, and empty pixels beside or behind it, get covered.
                        let empty = base.alpha(bx, by) < 0.5
                        let behind = side != 0 ? (Double(x) - cx) * side < 0 : abs(Double(x) - cx) >= half - 2
                        guard (hair[y * size + x] && !beard(x, y)) || (empty && behind) else { continue }
                    }
                    let lit = (Double(x) - cx) / half - Double(brow - y) / reach * 0.8
                    paint(x, y, lit < -0.55 ? light : lit > 0.55 ? dark : mid)
                } else if y < brow && base.alpha(bx, by) >= 0.5 && !isSkin(base, bx, by) {
                    out.clear(bx, by)          // a tuft poking out of the helmet
                }
            }
        }
        // Long hair below the dome or behind the head: a mail neck guard, or the hood's cloth.
        for y in brow..<size {
            for x in 0..<size where !painted[y * size + x] && hair[y * size + x] && !beard(x, y) {
                if hood {
                    paint(x, y, (x + 2 * y) % 7 == 0 ? dark : mid)
                } else {
                    paint(x, y, (x + y) % 2 == 0 ? mid : dark)
                }
            }
        }
        // Dark outline round the outside, and an inner rim where it meets the face.
        var rim: [(x: Int, y: Int, color: RGB)] = []
        for y in 0..<size {
            for x in 0..<size {
                let near = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)].filter { $0.0 >= 0 && $0.1 >= 0 && $0.0 < size && $0.1 < size }
                let isPainted = painted[y * size + x]
                if !isPainted && !filled(x, y) && near.contains(where: { painted[$0.1 * size + $0.0] }) {
                    rim.append((x, y, outline))
                } else if isPainted && y >= brow - 1 && facing != "up" && near.contains(where: {
                    !painted[$0.1 * size + $0.0] && filled($0.0, $0.1) && !hair[$0.1 * size + $0.0]
                }) {
                    rim.append((x, y, hood ? dark : accent))
                }
            }
        }
        for cell in rim { out.set(origin.x + cell.x, origin.y + cell.y, cell.color) }
        if hood {
            // A soft point at the top of the hood, falling back behind the head.
            let tip = Int((cx - 2 * side + 0.5).rounded(.down))
            if lid >= 1, tip >= 0, tip < size {
                out.set(origin.x + tip, origin.y + lid - 1, outline)
                out.set(origin.x + tip, origin.y + lid, mid)
            }
        } else {
            // A crest over the top, from the brow back.
            let ridge = Int((cx - side + 0.5).rounded(.down))
            if ridge >= 0, ridge < size, lid < brow - 1 {
                for y in max(0, lid)..<(brow - 1) where painted[y * size + ridge] {
                    out.set(origin.x + ridge, origin.y + y, accent)
                }
            }
        }
    }

    // MARK: Colour helpers

    nonisolated struct RGB: Sendable {
        var r, g, b: Double
        init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
        func scaled(_ k: Double) -> RGB { RGB(min(1, r * k), min(1, g * k), min(1, b * k)) }
        func mixed(with other: RGB, _ t: Double) -> RGB {
            RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
        }
    }

    nonisolated private static func median(_ colors: [RGB]) -> RGB {
        func mid(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return sorted.isEmpty ? 0.5 : sorted[sorted.count / 2]
        }
        return RGB(mid(colors.map(\.r)), mid(colors.map(\.g)), mid(colors.map(\.b)))
    }

    nonisolated private static func color(hex: String?) -> RGB? {
        guard let hex, let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) else { return nil }
        return RGB(Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }

    /// Hue in degrees, saturation and value in 0...1.
    nonisolated private static func hsv(_ c: RGB) -> (Double, Double, Double) {
        let maximum = max(c.r, c.g, c.b), minimum = min(c.r, c.g, c.b), delta = maximum - minimum
        var hue = 0.0
        if delta > 0 {
            if maximum == c.r { hue = 60 * ((c.g - c.b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maximum == c.g { hue = 60 * ((c.b - c.r) / delta + 2) }
            else { hue = 60 * ((c.r - c.g) / delta + 4) }
        }
        if hue < 0 { hue += 360 }
        return (hue, maximum == 0 ? 0 : delta / maximum, maximum)
    }

    nonisolated private static func rgb(_ h: Double, _ s: Double, _ v: Double) -> RGB {
        let c = v * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double) = switch h {
        case ..<60: (c, x, 0)
        case ..<120: (x, c, 0)
        case ..<180: (0, c, x)
        case ..<240: (0, x, c)
        case ..<300: (x, 0, c)
        default: (c, 0, x)
        }
        return RGB(r + m, g + m, b + m)
    }

    // MARK: Pixels

    /// RGBA pixels, rows top to bottom like the image (premultiplied, as Core Graphics keeps them).
    nonisolated private struct Bitmap {
        let width: Int, height: Int
        var pixels: [UInt8]

        init?(_ image: CGImage) {
            let w = image.width, h = image.height
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let drawn: Bool = data.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            width = w
            height = h
            pixels = data
        }

        func alpha(_ x: Int, _ y: Int) -> Double { Double(pixels[(y * width + x) * 4 + 3]) / 255 }

        func rgb(_ x: Int, _ y: Int) -> RGB {
            let i = (y * width + x) * 4
            let a = max(1, Double(pixels[i + 3]))
            return RGB(Double(pixels[i]) / a, Double(pixels[i + 1]) / a, Double(pixels[i + 2]) / a)
        }

        /// Makes a pixel fully transparent.
        mutating func clear(_ x: Int, _ y: Int) {
            let i = (y * width + x) * 4
            pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
        }

        /// Paints a fully opaque pixel.
        mutating func set(_ x: Int, _ y: Int, _ c: RGB) {
            let i = (y * width + x) * 4
            pixels[i] = UInt8(max(0, min(255, (c.r * 255).rounded())))
            pixels[i + 1] = UInt8(max(0, min(255, (c.g * 255).rounded())))
            pixels[i + 2] = UInt8(max(0, min(255, (c.b * 255).rounded())))
            pixels[i + 3] = 255
        }

        func image() -> CGImage? {
            let w = width, h = height
            var copy = pixels
            return copy.withUnsafeMutableBytes { buffer in
                CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
            }
        }
    }
}

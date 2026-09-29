import SpriteKit
import UIKit

nonisolated struct ArtManifest: Decodable {
    let assets: [ArtAsset]
}

/// One entry of art/assets.json. The `request` block is only used by tools/rd.py.
nonisolated struct ArtAsset: Decodable {
    let id: String
    /// walk_sheet | npc | monster | tile | prop | building
    let kind: String
    /// Frame size in pixels for walk sheets.
    let frame: Int?
    /// Which direction each sheet row faces, top to bottom.
    let directions: [String]?
    /// Optional draw-size multiplier. Stick to whole numbers to keep pixels square.
    let scale: Double?
    /// A free palette-swapped copy of another sprite (used until this one gets its own PNG).
    let derive: Derivation?
}

/// A texture plus the size it should be drawn at.
struct SpriteArt {
    let texture: SKTexture
    let size: CGSize
}

/// A directional walk cycle. The first frame of each direction doubles as the idle pose.
struct WalkCycle {
    let frames: [Direction: [SKTexture]]
    let size: CGSize

    func frames(_ direction: Direction) -> [SKTexture] {
        frames[direction] ?? frames[.down] ?? []
    }
}

/// Loads Retro Diffusion sprites from the bundled `art/` folder, falling back to
/// placeholder pixel art for anything that hasn't been generated yet.
final class ArtLibrary {
    static let shared = ArtLibrary()

    private let manifest: ArtManifest
    private var textures: [String: SKTexture] = [:]
    private var cycles: [String: WalkCycle] = [:]
    private var images: [String: UIImage] = [:]
    /// Sprites made at runtime (the customised hero, recoloured companions), keyed by id.
    private var runtime: [String: (asset: ArtAsset, key: String)] = [:]

    init() {
        do {
            guard let url = Bundle.main.url(forResource: "assets", withExtension: "json", subdirectory: "art") else {
                throw CocoaError(.fileNoSuchFile)
            }
            manifest = try JSONDecoder().decode(ArtManifest.self, from: Data(contentsOf: url))
        } catch {
            print("⚠️ Couldn't read art/assets.json: \(error)")
            manifest = ArtManifest(assets: [])
        }
    }

    /// Registers (or updates) a recoloured copy of `base` under `id`, e.g. the customised hero.
    /// `key` identifies the look, so re-registering the same look is free.
    func register(_ id: String, from base: String, recolor rules: [RecolorRule], key: String) {
        guard runtime[id]?.key != key else { return }
        let kind = asset(base)?.kind ?? "monster"
        runtime[id] = (ArtAsset(id: id, kind: kind, frame: nil, directions: nil, scale: nil, derive: Derivation(from: base, recolor: rules)), key)
        textures[id] = nil
        cycles[id] = nil
        images = images.filter { $0.key != id && !$0.key.hasPrefix(id + "#") }
    }

    /// A one-off recoloured portrait for pickers and previews (cached by `key`).
    func preview(from base: String, recolor rules: [RecolorRule], key: String, facing direction: Direction = .down) -> UIImage {
        let id = "preview:" + base + ":" + key
        register(id, from: base, recolor: rules, key: key)
        return image(id, facing: direction)
    }

    func asset(_ id: String) -> ArtAsset? {
        guard let own = manifest.assets.first(where: { $0.id == id }) ?? runtime[id]?.asset else { return nil }
        guard let derive = own.derive, let base = manifest.assets.first(where: { $0.id == derive.from }) else { return own }
        return ArtAsset(id: own.id, kind: own.kind, frame: own.frame ?? base.frame, directions: own.directions ?? base.directions,
                        scale: own.scale ?? base.scale, derive: derive)
    }

    private func kind(of id: String) -> String {
        asset(id)?.kind ?? "monster"
    }

    private func pngURL(_ id: String) -> URL? {
        Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "art/sprites")
    }

    /// The generated PNG for `id` (art/sprites/<id>.png), or nil if it doesn't exist yet.
    func generatedTexture(_ id: String) -> SKTexture? {
        if let cached = textures[id] { return cached }
        guard let image = sourceImage(id) else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        textures[id] = texture
        return texture
    }

    /// The sprite's own PNG, or — for derived sprites — its base's PNG with the palette swap applied.
    private func sourceImage(_ id: String, depth: Int = 0) -> CGImage? {
        if let url = pngURL(id), let image = UIImage(contentsOfFile: url.path)?.cgImage { return image }
        guard depth < 3, let derive = asset(id)?.derive, let base = sourceImage(derive.from, depth: depth + 1) else { return nil }
        return Recolor.apply(derive.recolor, to: base)
    }

    func tileTexture(_ id: String) -> SKTexture {
        generatedTexture(id) ?? Placeholder.canvas(for: id, kind: "tile").texture()
    }

    private func tileImage(_ id: String) -> CGImage {
        sourceImage(id) ?? Placeholder.canvas(for: id, kind: "tile").cgImage()
    }

    private var blended: [String: SKTexture] = [:]

    /// A road tile whose edges (per `mask`: 1 north, 2 east, 4 south, 8 west) give way to
    /// `ground` along a soft wavy line with a darker rim, and rounded corners where two
    /// edges meet, so roads read as winding paths instead of squares.
    func roadTile(_ path: String, on ground: String, mask: Int) -> SKTexture {
        let key = "\(path)|\(ground)|\(mask)"
        if let cached = blended[key] { return cached }
        let road = tileImage(path)
        let size = max(road.width, 16)
        func pixels(_ image: CGImage) -> [UInt8] {
            var buffer = [UInt8](repeating: 0, count: size * size * 4)
            let context = CGContext(data: &buffer, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return buffer
        }
        let roadPixels = pixels(road)
        let grassPixels = pixels(tileImage(ground))
        var out = roadPixels
        let n = mask & 1 != 0, e = mask & 2 != 0, s = mask & 4 != 0, w = mask & 8 != 0
        // Edge inset (share of the tile), wobbling with a period that tiles seamlessly.
        func inset(_ along: Double) -> Double { 0.2 + 0.06 * sin(along * 4 * .pi) + 0.03 * sin(along * 10 * .pi + 1) }
        let corner = 0.42
        func roadDepth(_ x: Double, _ y: Double) -> Double {
            // Signed distance inside the road shape (in tile units); y = 0 is north.
            var depth = 1.0
            if n { depth = min(depth, y - inset(x)) }
            if s { depth = min(depth, (1 - y) - inset(x)) }
            if w { depth = min(depth, x - inset(y)) }
            if e { depth = min(depth, (1 - x) - inset(y)) }
            // Round the outside corners.
            for (cornerX, cornerY, open) in [(0.0, 0.0, n && w), (1.0, 0.0, n && e), (0.0, 1.0, s && w), (1.0, 1.0, s && e)] where open {
                let cx = cornerX == 0 ? corner : 1 - corner, cy = cornerY == 0 ? corner : 1 - corner
                let inCorner = (cornerX == 0 ? x < cx : x > cx) && (cornerY == 0 ? y < cy : y > cy)
                if inCorner {
                    let distance = ((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot()
                    depth = min(depth, (corner - inset(0.5)) - distance)
                }
            }
            return depth
        }
        let rim = 1.2 / Double(size)
        for py in 0..<size {
            for px in 0..<size {
                let x = (Double(px) + 0.5) / Double(size), y = (Double(py) + 0.5) / Double(size)
                let depth = roadDepth(x, y)
                let index = (py * size + px) * 4
                if depth < 0 {
                    for c in 0..<4 { out[index + c] = grassPixels[index + c] }
                } else if depth < rim {
                    for c in 0..<3 { out[index + c] = UInt8(Double(roadPixels[index + c]) * 0.72) }
                }
            }
        }
        let provider = CGDataProvider(data: Data(out) as CFData)!
        let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        blended[key] = texture
        return texture
    }

    /// Animation frames for a water tile (a generated tile is a single frame).
    func waterFrames(_ id: String) -> [SKTexture] {
        if let texture = generatedTexture(id) { return [texture] }
        return [Placeholder.water(frame: 0).texture(), Placeholder.water(frame: 1).texture()]
    }

    /// A single image: the whole PNG, or the front-facing frame of a walk sheet.
    func sprite(_ id: String) -> SpriteArt {
        let kind = kind(of: id)
        if kind == "walk_sheet" {
            let cycle = walkCycle(id)
            return SpriteArt(texture: cycle.frames(.down).first ?? SKTexture(), size: cycle.size)
        }
        let scale = CGFloat(asset(id)?.scale ?? 1)
        if let texture = generatedTexture(id) {
            return SpriteArt(texture: texture, size: texture.size() * scale)
        }
        let texture = Placeholder.canvas(for: id, kind: kind).texture()
        return SpriteArt(texture: texture, size: texture.size() * (Placeholder.scale(for: kind) * scale))
    }

    /// Frames per direction. Single images become a one-frame cycle (they hop instead of walking).
    func walkCycle(_ id: String) -> WalkCycle {
        if let cached = cycles[id] { return cached }
        let cycle = makeWalkCycle(id)
        cycles[id] = cycle
        return cycle
    }

    private func makeWalkCycle(_ id: String) -> WalkCycle {
        let asset = asset(id)
        let kind = kind(of: id)
        let scale = CGFloat(asset?.scale ?? 1)

        guard kind == "walk_sheet" else {
            let art = sprite(id)
            return WalkCycle(frames: Dictionary(uniqueKeysWithValues: Direction.allCases.map { ($0, [art.texture]) }), size: art.size)
        }

        guard let sheet = generatedTexture(id) else {
            var frames: [Direction: [SKTexture]] = [:]
            for direction in Direction.allCases {
                frames[direction] = (0..<4).map { Placeholder.canvas(for: id, kind: kind, direction: direction, frame: $0).texture() }
            }
            return WalkCycle(frames: frames, size: CGSize(width: 48, height: 48) * scale)
        }

        let frameSize = CGFloat(asset?.frame ?? 48)
        let pixels = sheet.size()
        let layout = SheetLayout(asset: asset, width: pixels.width, height: pixels.height)
        var frames: [Direction: [SKTexture]] = [:]
        for direction in layout.directions {
            frames[direction] = layout.cells(for: direction).map { cell in
                // SpriteKit texture rects are normalised with the origin at the bottom-left.
                let rect = CGRect(
                    x: CGFloat(cell.column) * frameSize / pixels.width,
                    y: 1 - CGFloat(cell.row + 1) * frameSize / pixels.height,
                    width: frameSize / pixels.width,
                    height: frameSize / pixels.height
                )
                let texture = SKTexture(rect: rect, in: sheet)
                texture.filteringMode = .nearest
                return texture
            }
        }
        return WalkCycle(frames: frames, size: CGSize(width: frameSize, height: frameSize) * scale)
    }

    /// A portrait for SwiftUI screens (unscaled pixels — draw with `.interpolation(.none)`).
    /// Walk sheets can be shown facing any direction.
    func image(_ id: String, facing direction: Direction = .down) -> UIImage {
        let cacheKey = direction == .down ? id : id + "#" + direction.rawValue
        if let cached = images[cacheKey] { return cached }
        let asset = asset(id)
        let kind = kind(of: id)
        var cgImage: CGImage?
        if let full = sourceImage(id) {
            if kind == "walk_sheet" {
                let frame = CGFloat(asset?.frame ?? 48)
                let layout = SheetLayout(asset: asset, width: CGFloat(full.width), height: CGFloat(full.height))
                if let cell = layout.cells(for: direction).first {
                    cgImage = full.cropping(to: CGRect(x: CGFloat(cell.column) * frame, y: CGFloat(cell.row) * frame, width: frame, height: frame))
                }
            } else {
                cgImage = full
            }
        }
        let image = UIImage(cgImage: cgImage ?? Placeholder.canvas(for: id, kind: kind, direction: direction).cgImage())
        images[cacheKey] = image
        return image
    }
}

/// Where each direction's frames sit in a walk sheet: one row per direction (the usual
/// layout), or all frames on one row split evenly. Row order comes from `directions`.
private struct SheetLayout {
    let directions: [Direction]
    let columns: Int
    let rows: Int

    init(asset: ArtAsset?, width: CGFloat, height: CGFloat) {
        let frame = CGFloat(asset?.frame ?? 48)
        directions = (asset?.directions ?? Direction.allCases.map(\.rawValue)).compactMap(Direction.init(rawValue:))
        columns = max(1, Int(width / frame))
        rows = max(1, Int(height / frame))
    }

    func cells(for direction: Direction) -> [(column: Int, row: Int)] {
        guard let index = directions.firstIndex(of: direction) else { return [] }
        if rows >= directions.count {
            return (0..<columns).map { ($0, index) }
        }
        let perDirection = max(1, columns / max(1, directions.count))
        return (0..<perDirection).map { (index * perDirection + $0, 0) }
    }
}

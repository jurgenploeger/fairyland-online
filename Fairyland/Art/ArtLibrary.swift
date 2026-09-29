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

    func asset(_ id: String) -> ArtAsset? {
        manifest.assets.first { $0.id == id }
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
        guard let url = pngURL(id), let image = UIImage(contentsOfFile: url.path) else { return nil }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        textures[id] = texture
        return texture
    }

    func tileTexture(_ id: String) -> SKTexture {
        generatedTexture(id) ?? Placeholder.canvas(for: id, kind: "tile").texture()
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

    /// A portrait for SwiftUI screens (front-facing, unscaled pixels — draw with `.interpolation(.none)`).
    func image(_ id: String) -> UIImage {
        if let cached = images[id] { return cached }
        let asset = asset(id)
        let kind = kind(of: id)
        var cgImage: CGImage?
        if let url = pngURL(id), let full = UIImage(contentsOfFile: url.path)?.cgImage {
            if kind == "walk_sheet" {
                let frame = CGFloat(asset?.frame ?? 48)
                let layout = SheetLayout(asset: asset, width: CGFloat(full.width), height: CGFloat(full.height))
                if let cell = layout.cells(for: .down).first {
                    cgImage = full.cropping(to: CGRect(x: CGFloat(cell.column) * frame, y: CGFloat(cell.row) * frame, width: frame, height: frame))
                }
            } else {
                cgImage = full
            }
        }
        let image = UIImage(cgImage: cgImage ?? Placeholder.canvas(for: id, kind: kind).cgImage())
        images[id] = image
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

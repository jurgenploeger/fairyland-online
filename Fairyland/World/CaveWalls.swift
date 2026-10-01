import SpriteKit

/// A cave's rock, drawn as raised walls: each rock cell next to the floor is a block with a
/// stone top and lit faces where it drops to the floor, sorted in depth with everyone walking
/// around, so you pass in front of walls and disappear behind them. Rock deeper in is one flat
/// raised layer underneath. Walls standing between you and the camera turn see-through.
final class CaveWalls {
    private var blocks: [GridPoint: SKSpriteNode] = [:]
    private var faded: [GridPoint] = []

    /// Faces, edges and soft shadows (in points) around each block's texture.
    private static let pad: CGFloat = 10
    private static let fadeAlpha: CGFloat = 0.35
    /// The tops of the walls are in shadow, so they stand apart from the lit floor.
    private static let topShade: CGFloat = 0.45

    init(map: WorldMap, cave: MapDef.Cave, world: SKNode, art: ArtLibrary, margin: Int) {
        let tile = WorldMap.tileSize
        let height = CGFloat(cave.height ?? 40)
        let tops = (0..<4).map { art.tileVariant(cave.rock, $0).cgImage() }

        // Beyond the map it's rock too, except the tunnels the roads leave through.
        var mouths: Set<GridPoint> = []
        for exit in map.def.exits {
            for i in 0..<margin {
                switch exit.edge {
                case .north, .south:
                    let edgeRow = exit.edge == .north ? map.rows - 1 : 0
                    for col in 0..<map.columns where !map.rock.contains(GridPoint(col: col, row: edgeRow)) {
                        mouths.insert(GridPoint(col: col, row: exit.edge == .north ? map.rows + i : -1 - i))
                    }
                case .east, .west:
                    let edgeCol = exit.edge == .east ? map.columns - 1 : 0
                    for row in 0..<map.rows where !map.rock.contains(GridPoint(col: edgeCol, row: row)) {
                        mouths.insert(GridPoint(col: exit.edge == .east ? map.columns + i : -1 - i, row: row))
                    }
                }
            }
        }
        func isRock(_ cell: GridPoint) -> Bool {
            map.contains(cell) ? map.rock.contains(cell) : !mouths.contains(cell)
        }

        let (atlas, blockSize) = Self.atlas(tops: tops, height: height)
        guard atlas.count == 64 else { return }
        let groups: [SKTileGroup] = tops.map { top in
            let texture = SKTexture(cgImage: top)
            texture.filteringMode = .nearest
            return SKTileGroup(tileDefinition: SKTileDefinition(texture: texture, size: CGSize(width: tile, height: tile)))
        }
        let deep = SKTileMapNode(tileSet: SKTileSet(tileGroups: groups), columns: map.columns + margin * 2, rows: map.rows + margin * 2,
                                 tileSize: CGSize(width: tile, height: tile))
        deep.anchorPoint = .zero
        deep.color = .black
        deep.colorBlendFactor = Self.topShade
        deep.position = CGPoint(x: -CGFloat(margin) * tile, y: -CGFloat(margin) * tile)

        let half = WorldMap.project(CGPoint(x: tile, y: tile)).y / 2
        for row in -margin..<(map.rows + margin) {
            for col in -margin..<(map.columns + margin) {
                let cell = GridPoint(col: col, row: row)
                guard isRock(cell) else { continue }
                let variant = WorldScene.variant(of: cell)
                // Only rock near the floor needs its own block; the rest is the flat layer.
                let nearFloor = (-2...2).contains { dr in (-2...2).contains { dc in !isRock(GridPoint(col: col + dc, row: row + dr)) } }
                guard nearFloor else {
                    deep.setTileGroup(groups[variant], forColumn: col + margin, row: row + margin)
                    continue
                }
                var faces = 0
                if !isRock(GridPoint(col: col - 1, row: row)) { faces |= 1 }   // west face, lower left
                if !isRock(GridPoint(col: col, row: row - 1)) { faces |= 2 }   // south face, lower right
                if !isRock(GridPoint(col: col, row: row + 1)) { faces |= 4 }   // north edge drops away
                if !isRock(GridPoint(col: col + 1, row: row)) { faces |= 8 }   // east edge drops away
                let node = SKSpriteNode(texture: atlas[variant * 16 + faces], size: blockSize)
                let center = WorldMap.project(CGPoint(x: (CGFloat(col) + 0.5) * tile, y: (CGFloat(row) + 0.5) * tile))
                node.anchorPoint = CGPoint(x: 0.5, y: Self.pad / blockSize.height)
                node.position = center + CGVector(dx: 0, dy: -half)
                node.zPosition = -center.y
                world.addChild(node)
                blocks[cell] = node
            }
        }
        let squash = SKNode()
        squash.yScale = 0.5
        let turn = SKNode()
        turn.zRotation = .pi / 4
        squash.addChild(turn)
        turn.addChild(deep)
        squash.position.y = height
        squash.zPosition = -99_000
        world.addChild(squash)
    }

    /// Walls in front of `cell` (the ones that could hide whoever stands there) turn see-through.
    func reveal(around cell: GridPoint) {
        var hiding: [GridPoint] = []
        for dr in -2...0 {
            for dc in -2...0 where dr != 0 || dc != 0 {
                let near = GridPoint(col: cell.col + dc, row: cell.row + dr)
                if blocks[near] != nil { hiding.append(near) }
            }
        }
        for old in faded where !hiding.contains(old) {
            blocks[old]?.run(.fadeAlpha(to: 1, duration: 0.25), withKey: "fade")
        }
        for new in hiding where !faded.contains(new) {
            blocks[new]?.run(.fadeAlpha(to: Self.fadeAlpha, duration: 0.25), withKey: "fade")
        }
        faded = hiding
    }

    /// Every kind of block in one texture (so they draw together): four top variants × which of
    /// the four sides meet the floor. Index `variant * 16 + faces`. Also returns a block's size in points.
    private static func atlas(tops: [CGImage], height: CGFloat) -> ([SKTexture], CGSize) {
        let tile = WorldMap.tileSize
        let c = CGFloat(0.5).squareRoot()
        let width = 2 * tile * c, depth = tile * c
        let scale: CGFloat = 2
        let cell = CGSize(width: width + pad * 2, height: depth + height + pad * 2)
        let cellPixels = (w: Int((cell.width * scale).rounded(.up)) + 2, h: Int((cell.height * scale).rounded(.up)) + 2)
        let size = (w: cellPixels.w * 8, h: cellPixels.h * 8)
        guard let context = CGContext(data: nil, width: size.w, height: size.h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return ([], cell) }
        context.interpolationQuality = .none
        let bottom = CGPoint(x: width / 2, y: 0)
        let left = CGPoint(x: 0, y: depth / 2), right = CGPoint(x: width, y: depth / 2), top = CGPoint(x: width / 2, y: depth)
        let lift = CGVector(dx: 0, dy: height)

        func line(_ a: CGPoint, _ b: CGPoint, _ color: UIColor, _ lineWidth: CGFloat) {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
            context.move(to: a)
            context.addLine(to: b)
            context.strokePath()
        }
        /// A wall face from `a` to `b` along the floor, up to the top: the rock texture sheared
        /// onto it, shaded darker toward the floor.
        func face(_ a: CGPoint, _ b: CGPoint, texture: CGImage, shade: CGFloat) {
            let along = CGVector(dx: (b.x - a.x) / tile, dy: (b.y - a.y) / tile)
            context.saveGState()
            context.concatenate(CGAffineTransform(a: along.dx, b: along.dy, c: 0, d: 1, tx: a.x, ty: a.y))
            context.clip(to: CGRect(x: 0, y: 0, width: tile, height: height))
            var y: CGFloat = 0
            while y < height {
                context.draw(texture, in: CGRect(x: 0, y: y, width: tile, height: tile))
                y += tile
            }
            context.setFillColor(UIColor(white: 0, alpha: shade).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: tile, height: height))
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [UIColor(white: 0, alpha: 0.45).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray,
                                      locations: [0, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height * 0.7), options: [])
            context.restoreGState()
        }
        /// A soft shadow on the floor in front of a face (`out` points away from the wall).
        func floorShadow(_ a: CGPoint, _ b: CGPoint, out: CGVector) {
            let path = CGMutablePath()
            path.move(to: a)
            path.addLine(to: b)
            path.addLine(to: b + out)
            path.addLine(to: a + out)
            path.closeSubpath()
            context.saveGState()
            context.addPath(path)
            context.clip()
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [UIColor(white: 0, alpha: 0.4).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray,
                                      locations: [0, 1])!
            context.drawLinearGradient(gradient, start: mid, end: mid + out, options: [])
            context.restoreGState()
        }

        var textures: [SKTexture] = []
        var origins: [CGPoint] = []
        for variant in 0..<4 {
            for faces in 0..<16 {
                let index = variant * 16 + faces
                let origin = CGPoint(x: CGFloat((index % 8) * cellPixels.w + 1), y: CGFloat((index / 8) * cellPixels.h + 1))
                origins.append(origin)
                context.saveGState()
                context.translateBy(x: origin.x, y: origin.y)
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: pad, y: pad)
                if faces & 1 != 0 { floorShadow(bottom, left, out: CGVector(dx: -pad * 0.9, dy: -pad * 0.45)) }
                if faces & 2 != 0 { floorShadow(bottom, right, out: CGVector(dx: pad * 0.9, dy: -pad * 0.45)) }
                // The faces use a different variant from the top so they don't line up with it.
                let side = tops[(variant + 1) % 4]
                if faces & 1 != 0 { face(bottom, left, texture: side, shade: 0.12) }
                if faces & 2 != 0 { face(bottom, right, texture: side, shade: 0.32) }
                // The top: the rock tile turned into the raised diamond.
                context.saveGState()
                context.concatenate(CGAffineTransform(a: c, b: c / 2, c: -c, d: c / 2, tx: bottom.x, ty: height))
                // A hair bigger than the cell, so neighbouring tops overlap instead of leaving seams.
                let cover = CGRect(x: -0.6, y: -0.6, width: tile + 1.2, height: tile + 1.2)
                context.draw(tops[variant], in: cover)
                context.setFillColor(UIColor(white: 0, alpha: Self.topShade).cgColor)
                context.fill(cover)
                context.restoreGState()
                // Light catches the lips above the faces; the back edges, where the rock drops
                // away out of sight, get a dark rim.
                if faces & 1 != 0 { line(bottom + lift, left + lift, UIColor(white: 1, alpha: 0.45), 1.5) }
                if faces & 2 != 0 { line(bottom + lift, right + lift, UIColor(white: 1, alpha: 0.3), 1.5) }
                if faces & 4 != 0 { line(left + lift, top + lift, UIColor(white: 0, alpha: 0.55), 1.5) }
                if faces & 8 != 0 { line(top + lift, right + lift, UIColor(white: 0, alpha: 0.55), 1.5) }
                if faces & 3 == 3 { line(bottom, bottom + lift, UIColor(white: 0, alpha: 0.35), 1) }
                context.restoreGState()
            }
        }
        guard let image = context.makeImage() else { return ([], cell) }
        let sheet = SKTexture(cgImage: image)
        sheet.filteringMode = .nearest
        for origin in origins {
            let rect = CGRect(x: origin.x / CGFloat(size.w), y: origin.y / CGFloat(size.h),
                              width: cell.width * scale / CGFloat(size.w), height: cell.height * scale / CGFloat(size.h))
            let texture = SKTexture(rect: rect, in: sheet)
            texture.filteringMode = .nearest
            textures.append(texture)
        }
        return (textures, cell)
    }
}

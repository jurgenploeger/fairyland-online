import SpriteKit

/// Joystick input shared between the SwiftUI HUD and the scene (read every frame).
final class InputState {
    /// -1...1 on each axis, y up.
    var move: CGVector = .zero
}

/// One map: ground, scenery, NPCs, passers-by, the hero and their companion.
///
/// Like Fairyland, monsters aren't shown on the map — walking through the wild can start
/// a random battle. Walk off the edge where a road leaves the map to travel to the next map.
final class WorldScene: SKScene {
    var onEncounter: (@MainActor (MapDef.Encounters, SKTexture?) -> Void)?
    var onTalk: (@MainActor (NPCDef) -> Void)?
    var onTravel: (@MainActor (MapDef.Exit) -> Void)?
    var onFirstFrame: (@MainActor () -> Void)?
    /// A duel with another adventurer is starting (you challenged them, or they picked a fight).
    var onDuel: (@MainActor (Adventurer, SKTexture?) -> Void)?
    /// Set while menus, dialogs or transitions are up.
    var isInputLocked = false

    let def: MapDef
    private let session: GameSession
    private let input: InputState
    private let art = ArtLibrary.shared
    private let map: WorldMap
    private var rng: SeededRandom
    private let world = SKNode()
    private let cam = SKCameraNode()
    private let player: Walker
    private var follower: Walker?
    private var npcs: [(def: NPCDef, node: Walker, marker: SKLabelNode)] = []
    private var talkTarget: String?
    private var lastCell: GridPoint
    private var stepsSinceBattle = 0
    private var lastUpdate: TimeInterval = 0
    private var noticeTimer: TimeInterval = 0
    private var hasLeft = false
    private var ambience: Ambience?
    private var lighting: Lighting?
    private var crowd: Crowd?
    /// Friends in your party walk behind you in a little line.
    private var allies: [(id: UUID, node: Walker)] = []
    /// Roads that stay closed until a quest is done: the barricade nodes and the cells they block.
    private var barricades: [(exit: MapDef.Exit, nodes: [SKNode], cells: Set<GridPoint>)] = []
    private var lastBlockedNotice = Date.distantPast
    private var leftFoot = false
    /// Darkens the screen as you walk toward the edge of the map, so leaving is obvious.
    private let edgeFade = SKSpriteNode(color: .black, size: .zero)

    private let walkSpeed: CGFloat = 88
    private let talkRange: CGFloat = 50

    /// Pinch to zoom in on the ground around you, or out for a wider view. Kept from map to map.
    private static var zoom: CGFloat = 1
    private static let zoomRange: ClosedRange<CGFloat> = 0.85...2.2
    private var pinchStartZoom: CGFloat = 1
    private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))

    /// `entry` is the edge the player walked in through, or nil to use the saved position.
    init(map def: MapDef, session: GameSession, input: InputState, entry: Edge?) {
        // Characters made for this map pick up its light.
        if let palette = def.theme.palette, let hex = palette.light, let color = UIColor(hex: hex) {
            Walker.light = (color, CGFloat(palette.lightStrength ?? 0.4))
        } else {
            Walker.light = nil
        }
        let map = WorldMap(def: def)
        let player = Walker(cycle: ArtLibrary.shared.walkCycle(GameSession.heroArt), label: session.data.hero.name)
        player.fidgets = true
        self.def = def
        self.session = session
        self.input = input
        self.map = map
        self.player = player
        rng = SeededRandom(text: def.id + "/props")

        var start = map.center(of: map.center)
        if let entry {
            start = map.center(of: map.entryCell(from: entry))
        } else if let saved = session.playerPosition {
            start = saved
        }
        player.position = start
        lastCell = map.cell(at: start)

        super.init(size: CGSize(width: 874, height: 402))
        scaleMode = .resizeFill
        backgroundColor = .black
        build()
        // Don't start on top of scenery (e.g. an old save).
        if !map.isWalkable(lastCell), let open = map.nearestWalkable(to: lastCell) {
            player.position = map.center(of: open)
            lastCell = open
        }
        session.playerPosition = player.position
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        view.addGestureRecognizer(pinch)
        cam.setScale(1 / Self.zoom)
        if session.mapName != def.name {
            session.post("You arrive at \(def.name).")
            if def.danger == true {
                session.post("⚔ Danger zone! Adventurers here may pick a fight.", .battle)
            }
            session.startChat(on: def.name)
        }
        session.mapName = def.name
        session.mapCell = lastCell
        MusicPlayer.shared.play(def.music)
        lastUpdate = 0
    }

    override func willMove(from view: SKView) {
        view.removeGestureRecognizer(pinch)
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { pinchStartZoom = Self.zoom }
        Self.zoom = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, pinchStartZoom * gesture.scale))
        cam.setScale(1 / Self.zoom)
    }

    // MARK: - Building the map

    private func build() {
        art.use(palette: def.theme.palette, for: def.id)
        addChild(world)
        addChild(cam)
        camera = cam

        world.addChild(makeGround())
        placeSurroundings()
        placeLilyPads()
        placeFence()
        placeBuildings()
        placeDecor()
        placeNPCs()
        crowd = Crowd(def: def, map: map, world: world)
        crowd?.onChat = { [weak session] speaker, text, kind in session?.postChat(text, from: speaker, kind: kind) }
        crowd?.onChallenge = { [weak self] rival in
            guard let self, !self.isInputLocked else { return }
            self.startDuel(with: rival)
        }
        placeFairyRings()
        placeProps()
        placeSignposts()
        placeBarricades()

        world.addChild(player)
        refreshHero()
        refreshFollower()
        refreshAllies()
        cam.position = player.position
        edgeFade.alpha = 0
        edgeFade.size = CGSize(width: size.width * 1.2, height: size.height * 1.2)
        edgeFade.zPosition = 40_000
        cam.addChild(edgeFade)
        ambience = Ambience(def.ambience, world: world, camera: cam, bounds: map.bounds, seed: def.id)
        ambience?.resize(to: size)
        lighting = Lighting(def.ambience, world: world, camera: cam, bounds: map.bounds, seed: def.id)
        lighting?.resize(to: size)
        lighting?.follow(cam.position)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        edgeFade.size = CGSize(width: size.width * 1.2, height: size.height * 1.2)
        ambience?.resize(to: size)
        lighting?.resize(to: size)
    }

    private func makeGround() -> SKNode {
        let tileSize = CGSize(width: WorldMap.tileSize, height: WorldMap.tileSize)
        let theme = def.theme
        let waterID = theme.water ?? "tile_water"
        let water = SKTileGroup(tileDefinition: SKTileDefinition(textures: art.waterFrames(waterID), size: tileSize, timePerFrame: 0.9))
        var groups: [String: SKTileGroup] = ["water": water]
        func group(_ key: String, _ texture: () -> SKTexture) -> SKTileGroup {
            if let known = groups[key] { return known }
            let made = SKTileGroup(tileDefinition: SKTileDefinition(texture: texture(), size: tileSize))
            groups[key] = made
            return made
        }
        // Accent patches (flower meadows, moss) blend in as soft blobs. Not in towns, where the
        // accent is terrace paving and stays square.
        let patchAccent = (theme.accentPatches ?? 0) > 0 && theme.accent != nil && theme.accent != theme.ground
        /// Which cells of the 3×3 around `cell` are `kind` (bit row * 3 + col, row 0 north).
        func mask(_ cell: GridPoint, _ kind: Ground) -> Int {
            let own = map.ground[cell.row][cell.col] == kind
            var bits = 0
            for dy in -1...1 {
                for dx in -1...1 {
                    let next = GridPoint(col: cell.col + dx, row: cell.row + dy)
                    // Off the map a road or patch carries on; water doesn't.
                    let hit = map.contains(next) ? map.ground[next.row][next.col] == kind : own && kind != .water
                    if hit { bits |= 1 << ((1 - dy) * 3 + dx + 1) }
                }
            }
            return bits
        }
        /// The water cells of the 5×5 around `cell` (bit row * 5 + col, row 0 north), for shorelines.
        func poolMask(_ cell: GridPoint) -> Int {
            var bits = 0
            for dy in -2...2 {
                for dx in -2...2 {
                    let next = GridPoint(col: cell.col + dx, row: cell.row + dy)
                    if map.contains(next), map.ground[next.row][next.col] == .water { bits |= 1 << ((2 - dy) * 5 + dx + 2) }
                }
            }
            return bits
        }
        // Plain tiles come in four versions that fit together in any order, so big areas don't
        // repeat. Animated placeholder water keeps its single animated tile.
        let waterVaries = art.waterFrames(waterID).count == 1
        func plain(_ id: String, _ variant: Int) -> SKTileGroup {
            group("\(id)#\(variant)") { art.tileVariant(id, variant) }
        }
        let full = 0b111_111_111, sides = 0b010_101_010
        var picks: [(col: Int, row: Int, group: SKTileGroup)] = []
        for row in 0..<map.rows {
            for col in 0..<map.columns {
                let cell = GridPoint(col: col, row: row)
                let kind = map.ground[row][col]
                let road = mask(cell, .path), pond = mask(cell, .water)
                let variant = Self.variant(of: cell)
                let patch = patchAccent ? mask(cell, .accent) : 0
                // What shows between the soft shapes: the cell's own ground, or for a road, pond or
                // patch cell the ground around it.
                let base: String = switch kind {
                case .ground: theme.ground
                case .border: theme.border ?? theme.ground
                case .accent where !patchAccent: theme.accent ?? theme.ground
                default: mask(cell, .border) & sides != 0 ? (theme.border ?? theme.ground) : theme.ground
                }
                var layers: [ArtLibrary.GroundLayer] = []
                if patch != 0, let accent = theme.accent { layers.append(.init(tile: accent, mask: patch, style: .patch)) }
                if road != 0 { layers.append(.init(tile: theme.path, mask: road, style: .road)) }
                if pond != 0 { layers.append(.init(tile: waterID, mask: poolMask(cell), style: .water)) }
                let chosen: SKTileGroup
                if pond == full {
                    chosen = waterVaries ? plain(waterID, variant) : water
                } else if road == full, pond == 0 {
                    chosen = plain(theme.path, variant)
                } else if layers.isEmpty {
                    chosen = plain(base, variant)
                } else if let accent = theme.accent, patch == full, road == 0, pond == 0 {
                    chosen = plain(accent, variant)
                } else {
                    // Shorelines depend on where they are (see organicTile), so each gets its own tile.
                    let place = pond != 0 ? "@\(col),\(row)" : ""
                    let key = base + "|" + layers.map { "\($0.style)\($0.mask)" }.joined(separator: "|") + place
                    chosen = group(key) { art.organicTile(base: base, layers: layers, cell: cell, variant: variant) }
                }
                picks.append((col, row, chosen))
            }
        }
        let tileMap = SKTileMapNode(tileSet: SKTileSet(tileGroups: Array(groups.values)), columns: map.columns, rows: map.rows, tileSize: tileSize)
        tileMap.anchorPoint = .zero
        for pick in picks {
            tileMap.setTileGroup(pick.group, forColumn: pick.col, row: pick.row)
        }
        // Soft patches of colour over the whole ground, so it isn't one flat colour.
        let grid = SKNode()
        grid.addChild(tileMap)
        if let variation = Lighting.groundVariation(columns: map.columns, rows: map.rows, tile: WorldMap.tileSize, palette: theme.palette, seed: def.id) {
            variation.zPosition = 1
            grid.addChild(variation)
        }
        let ground = projected(grid)
        ground.zPosition = -100_000
        return ground
    }

    /// Which of a tile's four versions a cell shows: a hash, so neighbours differ without a pattern.
    private static func variant(of cell: GridPoint) -> Int {
        var hash = UInt64(bitPattern: Int64(cell.col)) &* 0x9E37_79B9_7F4A_7C15
        hash ^= UInt64(bitPattern: Int64(cell.row)) &* 0xC2B2_AE3D_27D4_EB4F
        hash ^= hash >> 29
        hash = hash &* 0xBF58_476D_1CE4_E5B9
        hash ^= hash >> 32
        return Int(hash % 4)
    }

    /// Wraps grid-space ground so it renders in Fairyland's isometric 2.5D view:
    /// turned 45° and squashed to half height (matches `WorldMap.project`).
    private func projected(_ node: SKNode) -> SKNode {
        let squash = SKNode()
        squash.yScale = 0.5
        let turn = SKNode()
        turn.zRotation = .pi / 4
        squash.addChild(turn)
        turn.addChild(node)
        return squash
    }

    /// Scenery beyond the map's edge, so small maps never show black bars (e.g. in portrait).
    /// Roads carry on out through the exits.
    private func placeSurroundings() {
        let margin = 14
        let tile = WorldMap.tileSize
        let tileSize = CGSize(width: tile, height: tile)
        let theme = def.theme
        let fill = SKTileGroup(tileDefinition: SKTileDefinition(texture: art.tileTexture(theme.border ?? theme.ground), size: tileSize))
        let road = SKTileGroup(tileDefinition: SKTileDefinition(texture: art.tileTexture(theme.path), size: tileSize))
        let columns = map.columns + margin * 2
        let rows = map.rows + margin * 2
        let surroundings = SKTileMapNode(tileSet: SKTileSet(tileGroups: [fill, road]), columns: columns, rows: rows, tileSize: tileSize, fillWith: fill)
        surroundings.anchorPoint = .zero
        surroundings.position = CGPoint(x: -CGFloat(margin) * tile, y: -CGFloat(margin) * tile)
        let projectedSurroundings = projected(surroundings)
        projectedSurroundings.zPosition = -100_001
        world.addChild(projectedSurroundings)

        // Extend each exit's road straight out to the edge of the surroundings.
        var roadCells: Set<GridPoint> = []
        for exit in def.exits {
            for i in 0..<margin {
                switch exit.edge {
                case .north, .south:
                    let edgeRow = exit.edge == .north ? map.rows - 1 : 0
                    for col in 0..<map.columns where map.ground[edgeRow][col] == .path {
                        roadCells.insert(GridPoint(col: col, row: exit.edge == .north ? map.rows + i : -1 - i))
                    }
                case .east, .west:
                    let edgeCol = exit.edge == .east ? map.columns - 1 : 0
                    for row in 0..<map.rows where map.ground[row][edgeCol] == .path {
                        roadCells.insert(GridPoint(col: exit.edge == .east ? map.columns + i : -1 - i, row: row))
                    }
                }
            }
        }
        for cell in roadCells {
            surroundings.setTileGroup(road, forColumn: cell.col + margin, row: cell.row + margin)
        }

        // A loose treeline, keeping the roads clear.
        guard let decor = theme.props.first(where: \.blocking)?.art else { return }
        let sprite = art.sprite(decor)
        var decorRNG = SeededRandom(text: def.id + "/surroundings")
        for row in -margin..<(map.rows + margin) {
            for col in -margin..<(map.columns + margin) {
                let outside = row < 0 || col < 0 || row >= map.rows || col >= map.columns
                guard outside, Double.random(in: 0..<1, using: &decorRNG) < 0.14 else { continue }
                let nearRoad = (-1...1).contains { dc in (-1...1).contains { dr in roadCells.contains(GridPoint(col: col + dc, row: row + dr)) } }
                guard !nearRoad else { continue }
                addScenery(sprite, at: GridPoint(col: col, row: row))
            }
        }
    }

    private func placeFence() {
        guard !map.fenceCells.isEmpty else { return }
        let fence = art.sprite("fence")
        for cell in map.fenceCells {
            map.occupy(cell, blocking: true)
            addScenery(fence, at: cell)
        }
    }

    /// Houses take a 3×2 footprint above their anchor tile.
    private func placeBuildings() {
        for lot in map.lots {
            addScenery(art.sprite(lot.art), at: lot.anchor)
        }
        for decor in map.streetDecor {
            let lamp = addScenery(art.sprite(decor.art), at: decor.cell)
            if decor.art == "street_lamp" {
                // A warm glow around each lamp.
                let glow = SKSpriteNode(texture: SoftTextures.glow, size: CGSize(width: 70, height: 50))
                glow.color = UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 1)
                glow.colorBlendFactor = 1
                glow.blendMode = .add
                glow.alpha = 0.35
                glow.position = map.center(of: decor.cell) + CGVector(dx: 0, dy: 34)
                // Just behind the lamp: whoever stands in front hides the glow, whoever is behind is lit.
                glow.zPosition = lamp.zPosition - 0.5
                glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.5, duration: 1.4), .fadeAlpha(to: 0.3, duration: 1.4)])))
                world.addChild(glow)
            }
        }
        placeTerraces()
        for building in def.buildings ?? [] {
            let anchor = map.offset(building.x, building.y)
            for dc in -1...1 {
                for dr in 0...1 { map.occupy(GridPoint(col: anchor.col + dc, row: anchor.row + dr), blocking: true) }
            }
            addScenery(art.sprite(building.art), at: anchor)
        }
    }

    /// Layered stone terraces like Fairyland's: the paved top sits behind a stone wall face
    /// on the two edges facing you, balustrades run along every edge, pillars stand on the
    /// corners, and stairs break the front wall where you can climb up.
    private func placeTerraces() {
        let rail = art.sprite("stone_balustrade"), pillar = art.sprite("wall_pillar"), steps = art.sprite("stone_stairs")
        let stone = art.tileTexture(def.theme.accent ?? "tile_scree")
        let tile = WorldMap.tileSize
        let wallHeight: CGFloat = 22
        for terrace in map.terraces {
            let o = terrace.origin
            let last = GridPoint(col: o.col + terrace.width - 1, row: o.row + terrace.height - 1)
            // The wall face hangs under the inner edge of the border ring (the border cells block).
            let south = (row: CGFloat(o.row + 1) * tile, from: CGFloat(o.col + 1) * tile, to: CGFloat(last.col) * tile)
            let west = (col: CGFloat(o.col + 1) * tile, from: CGFloat(o.row + 1) * tile, to: CGFloat(last.row) * tile)
            let stairsSouth = terrace.stairs.first { $0.row == o.row }.map { (CGFloat($0.col) * tile, CGFloat($0.col + 1) * tile) }
            let stairsWest = terrace.stairs.first { $0.col == o.col }.map { (CGFloat($0.row) * tile, CGFloat($0.row + 1) * tile) }
            var faces: [(CGPoint, CGPoint)] = []
            func span(_ a: CGFloat, _ b: CGFloat, gap: (CGFloat, CGFloat)?, point: (CGFloat) -> CGPoint) {
                if let gap, gap.0 > a, gap.1 < b {
                    faces.append((point(a), point(gap.0)))
                    faces.append((point(gap.1), point(b)))
                } else {
                    faces.append((point(a), point(b)))
                }
            }
            span(south.from, south.to, gap: stairsSouth) { WorldMap.project(CGPoint(x: $0, y: south.row)) }
            span(west.from, west.to, gap: stairsWest) { WorldMap.project(CGPoint(x: west.col, y: $0)) }
            for (a, b) in faces {
                let path = CGMutablePath()
                path.move(to: a)
                path.addLine(to: b)
                path.addLine(to: b + CGVector(dx: 0, dy: -wallHeight))
                path.addLine(to: a + CGVector(dx: 0, dy: -wallHeight))
                path.closeSubpath()
                let face = SKShapeNode(path: path)
                face.fillTexture = stone
                face.fillColor = UIColor(white: 0.78, alpha: 1)
                face.strokeColor = UIColor(white: 0.25, alpha: 0.9)
                face.lineWidth = 1.5
                face.zPosition = -min(a.y, b.y) + 1
                world.addChild(face)
                // A lighter lip along the top edge.
                let lip = SKShapeNode(path: { let p = CGMutablePath(); p.move(to: a); p.addLine(to: b); return p }())
                lip.strokeColor = UIColor(white: 1, alpha: 0.55)
                lip.lineWidth = 2
                lip.zPosition = face.zPosition + 0.5
                world.addChild(lip)
            }
            // Railings, pillars and stairs on the border ring.
            for col in o.col...last.col {
                for row in o.row...last.row {
                    let cell = GridPoint(col: col, row: row)
                    guard col == o.col || row == o.row || col == last.col || row == last.row else { continue }
                    let corner = (col == o.col || col == last.col) && (row == o.row || row == last.row)
                    let sprite = terrace.stairs.contains(cell) ? steps : corner ? pillar : rail
                    let node = SKSpriteNode(texture: sprite.texture, size: sprite.size * (corner ? 0.6 : 0.7))
                    node.anchorPoint = CGPoint(x: 0.5, y: 0.1)
                    node.position = map.base(of: cell)
                    // Railings follow the edge they're on.
                    if !corner, col == o.col || col == last.col { node.xScale = -1 }
                    node.zPosition = -node.position.y
                    world.addChild(node)
                }
            }
        }
    }

    private func placeNPCs() {
        for npc in def.npcs ?? [] {
            let cell = map.offset(npc.x, npc.y)
            map.occupy(cell, blocking: true)
            let node = Walker(cycle: art.walkCycle(npc.art), label: npc.name)
            node.idles = npc.role != .chest
            if npc.role == .boss { node.motion = IdleMotion.of(art: npc.art) }
            node.position = map.center(of: cell)
            node.zPosition = -node.position.y
            let marker = SKLabelNode()
            marker.attributedText = Nodes.outlined("!", size: 18, color: Nodes.gold)
            marker.position = CGPoint(x: 0, y: node.sprite.size.height + 18)
            marker.zPosition = 6_000
            marker.isHidden = true
            marker.run(.repeatForever(.sequence([.moveBy(x: 0, y: 4, duration: 0.4), .moveBy(x: 0, y: -4, duration: 0.4)])))
            node.addChild(marker)
            world.addChild(node)
            npcs.append((npc, node, marker))
        }
        updateNotices()
    }

    /// Scenery from the theme. Props with `cluster` grow in groves around a random centre.
    private func placeProps() {
        for placement in def.theme.props {
            let sprite = art.sprite(placement.art)
            let groupSize = max(1, placement.cluster ?? 1)
            let spread = max(1, placement.spread ?? Int(Double(groupSize).squareRoot().rounded()) + 1)
            var placed = 0
            var attempts = 0
            while placed < placement.count, attempts < placement.count * 3 {
                attempts += 1
                let found: GridPoint? = if let radius = placement.within {
                    map.randomFreeCell(within: radius, using: &rng)
                } else {
                    map.randomFreeCell(using: &rng)
                }
                guard let middle = found else { break }
                let wanted = min(groupSize, placement.count - placed)
                var inGroup = 0
                for index in 0..<(wanted * 5) where inGroup < wanted {
                    let cell = index == 0 ? middle : GridPoint(
                        col: middle.col + Int.random(in: -spread...spread, using: &rng),
                        row: middle.row + Int.random(in: -spread...spread, using: &rng)
                    )
                    guard map.isFreeForScenery(cell, insideFence: placement.within != nil) else { continue }
                    map.occupy(cell, blocking: placement.blocking)
                    var scale: CGFloat = 1
                    if let range = placement.size, range.count == 2, range[0] <= range[1] {
                        scale = CGFloat(Double.random(in: range[0]...range[1], using: &rng))
                    }
                    let node = addScenery(sprite, at: cell, sway: placement.sway == true, jitter: true, scale: scale)
                    if placement.shadow == true { Lighting.shadow(under: node, in: world) }
                    if let hex = placement.glow, let color = UIColor(hex: hex) { Lighting.glow(behind: node, color: color, in: world, rng: &rng) }
                    inGroup += 1
                }
                placed += inGroup
            }
        }
    }

    /// Hand-placed decorations (fountains, blossom trees) from the map's `decor` list.
    private func placeDecor() {
        for decor in def.decor ?? [] {
            let anchor = map.offset(decor.x, decor.y)
            let sprite = art.sprite(decor.art)
            let blocking = decor.blocking ?? true
            let footprint = max(1, Int(sprite.size.width / WorldMap.tileSize * 0.75))
            for dc in 0..<footprint {
                map.occupy(GridPoint(col: anchor.col + dc - footprint / 2, row: anchor.row), blocking: blocking)
            }
            addScenery(sprite, at: anchor, sway: decor.art.contains("tree") || decor.art.contains("flower"))
            if decor.art.contains("fountain") {
                Ambience.twinkle(around: map.center(of: anchor) + CGVector(dx: 0, dy: 30), radius: 30, count: 4, in: world)
            }
        }
    }

    /// Circles of mushrooms with a sparkle in the middle, like the ones fairies dance in.
    private func placeFairyRings() {
        guard let rings = def.theme.fairyRings else { return }
        let sprite = art.sprite(rings.art)
        for _ in 0..<rings.count {
            for _ in 0..<30 {
                guard let middle = map.randomFreeCell(using: &rng) else { break }
                let area = (-2...2).flatMap { dr in (-2...2).map { dc in GridPoint(col: middle.col + dc, row: middle.row + dr) } }
                guard area.allSatisfy({ map.isFreeForScenery($0) }) else { continue }
                area.forEach { map.occupy($0, blocking: false) }
                let origin = map.center(of: middle)
                for index in 0..<9 {
                    let angle = CGFloat(index) / 9 * 2 * .pi
                    let node = SKSpriteNode(texture: sprite.texture, size: sprite.size * 0.75)
                    node.anchorPoint = CGPoint(x: 0.5, y: 0.1)
                    node.position = origin + CGVector(dx: cos(angle) * 52, dy: sin(angle) * 36)
                    node.zPosition = -node.position.y
                    world.addChild(node)
                }
                Ambience.twinkle(around: origin, radius: 26, count: 5, in: world)
                break
            }
        }
    }

    private func placeLilyPads() {
        let sprite = art.sprite("lily_pad")
        var padRNG = SeededRandom(text: def.id + "/lilies")
        for pond in map.ponds {
            for _ in 0..<min(4, max(1, pond.count / 8)) {
                guard let cell = pond.randomElement(using: &padRNG) else { continue }
                let node = SKSpriteNode(texture: sprite.texture, size: sprite.size)
                node.position = map.center(of: cell) + CGVector(dx: .random(in: -6...6, using: &padRNG), dy: .random(in: -6...6, using: &padRNG))
                node.zPosition = -99_000
                node.run(.repeatForever(.sequence([
                    .rotate(toAngle: 0.08, duration: 2.2, shortestUnitArc: true),
                    .rotate(toAngle: -0.08, duration: 2.2, shortestUnitArc: true),
                ])))
                world.addChild(node)
            }
        }
    }

    /// A small sign where each road leaves the map.
    private func placeSignposts() {
        for exit in def.exits {
            guard let destination = Content.shared.map(exit.to) else { continue }
            let text = switch exit.edge {
            case .north: "▲ \(destination.name)"
            case .south: "▼ \(destination.name)"
            case .east: "\(destination.name) ▶"
            case .west: "◀ \(destination.name)"
            }
            let label = SKLabelNode()
            label.attributedText = Nodes.outlined(text, size: 11, color: Nodes.gold)
            let cell = map.entryCell(from: exit.edge)
            label.position = map.center(of: cell) + CGVector(dx: 0, dy: 26)
            label.zPosition = 4_000
            world.addChild(label)
        }
    }

    /// A fence across each road that a quest hasn't opened yet, with a little lock sign.
    private func placeBarricades() {
        for exit in def.exits where !session.canTravel(exit) {
            let cells = map.roadCells(near: exit.edge)
            guard !cells.isEmpty else { continue }
            var nodes: [SKNode] = []
            let fence = art.sprite("fence")
            for cell in cells {
                let node = SKSpriteNode(texture: fence.texture, size: fence.size)
                node.anchorPoint = CGPoint(x: 0.5, y: 0.05)
                node.position = map.base(of: cell)
                node.zPosition = -node.position.y
                world.addChild(node)
                nodes.append(node)
            }
            let middle = cells[cells.count / 2]
            let sign = SKLabelNode()
            sign.attributedText = Nodes.outlined("Closed", size: 12, color: UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1))
            sign.position = map.center(of: middle) + CGVector(dx: 0, dy: 44)
            sign.zPosition = 4_500
            sign.run(.repeatForever(.sequence([.moveBy(x: 0, y: 3, duration: 0.6), .moveBy(x: 0, y: -3, duration: 0.6)])))
            world.addChild(sign)
            nodes.append(sign)
            barricades.append((exit, nodes, Set(cells)))
        }
    }

    /// A finished quest opened a road while you were here: the barricade poofs away.
    private func openBarricades() {
        barricades.removeAll { barricade in
            guard session.canTravel(barricade.exit) else { return false }
            for node in barricade.nodes {
                SkillEffects.smoke(at: node.position, in: world)
                node.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
            }
            return true
        }
    }

    @discardableResult
    private func addScenery(_ sprite: SpriteArt, at cell: GridPoint, sway: Bool = false, jitter: Bool = false, scale: CGFloat = 1) -> SKSpriteNode {
        let node = SKSpriteNode(texture: sprite.texture, size: CGSize(width: sprite.size.width * scale, height: sprite.size.height * scale))
        node.anchorPoint = CGPoint(x: 0.5, y: 0.05)
        var position = map.base(of: cell)
        if jitter {
            // Nudge off the grid so groves look planted by nature, not a spreadsheet.
            position.x += .random(in: -7...7, using: &rng)
            position.y += .random(in: -5...5, using: &rng)
        }
        node.position = position
        node.zPosition = -node.position.y
        if sway {
            let duration = TimeInterval.random(in: 1.8...2.8, using: &rng)
            let lean = CGFloat.random(in: 0.018...0.03, using: &rng)
            let left = SKAction.rotate(toAngle: lean, duration: duration, shortestUnitArc: true)
            let right = SKAction.rotate(toAngle: -lean, duration: duration, shortestUnitArc: true)
            left.timingMode = .easeInEaseOut
            right.timingMode = .easeInEaseOut
            node.zRotation = .random(in: -lean...lean, using: &rng)
            node.run(.repeatForever(.sequence([left, right])))
        }
        world.addChild(node)
        return node
    }

    /// One pixel per tile, for the HUD minimap.
    private(set) lazy var minimap = UIImage(cgImage: map.overviewImage())

    /// Everything the map screen needs.
    func overview() -> (image: UIImage, player: CGPoint, companion: CGPoint?, name: String, exits: [MapDef.Exit]) {
        func unit(_ point: CGPoint) -> CGPoint {
            map.unitPosition(of: map.cell(at: point))
        }
        return (minimap, unit(player.position), follower.map { unit($0.position) }, def.name, def.exits)
    }

    // MARK: - Companion

    private var followerKey: String?
    private var heroKey: String?

    /// Keeps the companion in sync: switched, renamed or recoloured.
    private func refreshFollower() {
        let pet = session.activePet
        let key = pet.map { "\($0.id)|\($0.name)" }
        guard key != followerKey else { return }
        followerKey = key
        let previous = follower?.position
        follower?.removeFromParent()
        follower = nil
        guard let pet else { return }
        let node = Walker(cycle: art.walkCycle(session.artID(for: pet)), label: pet.name)
        node.motion = IdleMotion.of(art: session.artID(for: pet))
        node.position = previous ?? player.position + CGVector(dx: -30, dy: 0)
        node.walkSpeed = 110
        world.addChild(node)
        follower = node
    }

    /// Picks up a new look or name from the Character screen.
    private func refreshHero() {
        let key = "\(session.data.hero.name)|\(session.heroLookKey)"
        guard key != heroKey else { return }
        if heroKey != nil {
            player.setCycle(art.walkCycle(GameSession.heroArt))
            player.setLabel(session.data.hero.name)
        }
        player.setGear(weapon: session.equipped(.weapon), accessory: session.equipped(.accessory))
        heroKey = key
    }


    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isInputLocked, let point = touches.first?.location(in: world) else { return }
        if let npc = npcs.first(where: { ($0.node.position + CGVector(dx: 0, dy: 24)).distance(to: point) < 34 }) {
            talkTarget = npc.def.id
            player.path = map.path(from: player.position, to: npc.node.position)
            return
        }
        talkTarget = nil
        crowd?.greet(at: point, from: player.position)
        player.path = map.path(from: player.position, to: point)
        if let destination = player.path.last {
            Effects.tapMarker(at: destination, in: world)
        }
    }

    /// Keeps the walking party in sync with who's in it.
    private func refreshAllies() {
        let members = session.partyMembers
        guard members.map(\.id) != allies.map(\.id) else { return }
        for ally in allies where !members.contains(where: { $0.id == ally.id }) {
            SkillEffects.smoke(at: ally.node.position, in: world)
            ally.node.removeFromParent()
        }
        allies = members.map { friend in
            if let existing = allies.first(where: { $0.id == friend.id }) { return existing }
            let node = Walker(cycle: art.walkCycle(session.artID(for: friend)), label: friend.name, labelColor: HUDStyle.partyGreen)
            node.walkSpeed = 105
            // Recruited on this map: they start where they stood.
            node.position = crowd?.position(of: friend.id) ?? player.position + CGVector(dx: -40, dy: -10)
            crowd?.remove(friend.id, poof: false)
            world.addChild(node)
            return (friend.id, node)
        }
    }

    /// A duel: the same white flash as a monster encounter.
    func startDuel(with rival: Adventurer) {
        guard !isInputLocked else { return }
        isInputLocked = true
        player.path = []
        player.setWalking(false)
        let flash = SKSpriteNode(color: UIColor(red: 1, green: 0.4, blue: 0.35, alpha: 1), size: size)
        flash.alpha = 0
        flash.zPosition = 50_000
        cam.addChild(flash)
        Task {
            await flash.run(.sequence([.fadeAlpha(to: 0.7, duration: 0.1), .fadeAlpha(to: 0, duration: 0.1), .fadeAlpha(to: 0.7, duration: 0.1), .fadeAlpha(to: 0, duration: 0.1)]))
            flash.removeFromParent()
            onDuel?(rival, snapshot())
        }
    }

    /// After a duel you won, the rival skulks off.
    func dismissAdventurer(_ id: UUID) {
        crowd?.remove(id, poof: true)
        if session.nearbyAdventurer?.id == id { session.nearbyAdventurer = nil }
    }

    func adventurerSays(_ line: String, _ id: UUID) {
        crowd?.say(line, from: id)
    }

    /// You said something in the Chat window: a bubble over your head, and maybe an answer.
    func heroSay(_ text: String) {
        player.say(text)
        session.postChat(text, from: session.data.hero.name, kind: .you)
        crowd?.reply(near: player.position)
    }

    /// Called by the HUD's Talk button.
    func talkToNearby() {
        guard let id = session.nearbyNPC, let npc = npcs.first(where: { $0.def.id == id }) else { return }
        startTalking(to: npc.def, node: npc.node)
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        if let onFirstFrame {
            self.onFirstFrame = nil
            onFirstFrame()
        }
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 1.0 / 20)
        lastUpdate = currentTime

        if isInputLocked {
            player.setWalking(false)
        } else {
            movePlayer(dt)
            checkTalkTarget()
            checkCell()
        }
        follower?.follow(player, dt: dt)
        var leader: Walker = follower ?? player
        for ally in allies {
            ally.node.follow(leader, dt: dt)
            ally.node.zPosition = -ally.node.position.y
            leader = ally.node
        }
        crowd?.update(dt: dt, player: player.position)
        noticeTimer -= dt
        if noticeTimer <= 0 {
            noticeTimer = 0.4
            updateNotices()
            refreshFollower()
            refreshHero()
            refreshAllies()
            let nearby = crowd?.adventurer(near: player.position, within: 80)
            if session.nearbyAdventurer?.id != nearby?.id { session.nearbyAdventurer = nearby }
        }

        player.zPosition = -player.position.y
        if let follower { follower.zPosition = -follower.position.y }
        updateCamera(dt)
        updateEdgeFade(dt)
    }

    private func movePlayer(_ dt: TimeInterval) {
        let stick = input.move
        if stick.length > 0.15 {
            player.path = []
            talkTarget = nil
            let step = stick * (walkSpeed * CGFloat(dt))
            var next = player.position
            // Try each axis separately so you slide along walls instead of sticking.
            let alongX = CGPoint(x: next.x + step.dx, y: next.y)
            if canStand(at: alongX) { next = alongX }
            let alongY = CGPoint(x: next.x, y: next.y + step.dy)
            if canStand(at: alongY) { next = alongY }
            player.position = next
            player.face(Direction(stick, current: player.facing))
            player.setWalking(true)
        } else {
            player.setWalking(player.followPath(dt: dt) || !player.path.isEmpty)
        }
    }

    private func canStand(at point: CGPoint) -> Bool {
        let cell = map.rawCell(at: point)
        return map.isWalkable(cell) && !barricades.contains { $0.cells.contains(cell) }
    }

    private func checkTalkTarget() {
        guard let target = talkTarget, let npc = npcs.first(where: { $0.def.id == target }) else { return }
        if player.position.distance(to: npc.node.position) <= talkRange {
            startTalking(to: npc.def, node: npc.node)
        } else if player.path.isEmpty {
            talkTarget = nil
        }
    }

    private func startTalking(to npc: NPCDef, node: Walker) {
        talkTarget = nil
        player.path = []
        player.setWalking(false)
        player.face(Direction(node.position - player.position))
        onTalk?(npc)
    }

    private func checkCell() {
        let cell = map.cell(at: player.position)
        guard cell != lastCell else { return }
        if let barricade = barricades.first(where: { $0.cells.contains(cell) || map.exit(at: cell)?.to == $0.exit.to }) {
            // Closed road: back you go, with a hint about which quest opens it.
            player.position = map.center(of: lastCell)
            player.path = []
            if Date().timeIntervalSince(lastBlockedNotice) > 3 {
                lastBlockedNotice = Date()
                let place = Content.shared.map(barricade.exit.to)?.name ?? "there"
                let quest = barricade.exit.requires.flatMap { session.content.quest($0)?.title } ?? "a quest"
                session.post("The road to \(place) is closed. Finish “\(quest)” first.", .quest)
                player.say("It's closed…")
            }
            return
        }
        lastCell = cell
        if GameSettings.footsteps {
            // Alternate feet, a touch louder and softer.
            leftFoot.toggle()
            SoundEffects.shared.play(.step, volume: leftFoot ? 0.6 : 0.45)
        }
        session.playerPosition = player.position
        session.mapCell = cell

        if let exit = map.exit(at: cell), !hasLeft {
            hasLeft = true
            isInputLocked = true
            onTravel?(exit)
            return
        }

        guard let encounters = def.encounters else { return }
        stepsSinceBattle += 1
        if stepsSinceBattle > encounters.graceSteps, Double.random(in: 0..<1) < encounters.rate {
            stepsSinceBattle = 0
            startEncounter(encounters)
        }
    }

    private func startEncounter(_ encounters: MapDef.Encounters) {
        isInputLocked = true
        player.path = []
        player.setWalking(false)
        let flash = SKSpriteNode(color: .white, size: size)
        flash.alpha = 0
        flash.zPosition = 50_000
        cam.addChild(flash)
        Task {
            await flash.run(.sequence([
                .fadeAlpha(to: 0.85, duration: 0.08), .fadeAlpha(to: 0, duration: 0.08),
                .fadeAlpha(to: 0.85, duration: 0.08), .fadeAlpha(to: 0, duration: 0.08),
            ]))
            flash.removeFromParent()
            onEncounter?(encounters, snapshot())
        }
    }

    /// What's on screen right now, for the battle backdrop (Fairyland fights where you stand).
    private func snapshot() -> SKTexture? {
        let visible = CGRect(x: cam.position.x - size.width / 2, y: cam.position.y - size.height / 2, width: size.width, height: size.height)
        // The party is drawn by the battle itself, so leave them (and tap markers) out of the backdrop.
        let hidden: [SKNode] = [player, follower].compactMap { $0 } + world.children.filter { $0.name == Effects.tapMarkerName }
        hidden.forEach { $0.isHidden = true }
        defer { hidden.forEach { $0.isHidden = false } }
        return view?.texture(from: world, crop: visible)
    }

    /// Back from a battle (or a dialog): unlock input and pick up party changes.
    func resume() {
        openBarricades()
        isInputLocked = false
        lastUpdate = 0
        input.move = .zero
        refreshHero()
        refreshFollower()
        updateNotices()
    }

    // MARK: - Upkeep

    private func updateNotices() {
        var nearest: (id: String, distance: CGFloat)?
        for npc in npcs {
            if npc.def.role == .chest, session.isOpened(npc.def.id), npc.node.alpha > 0.5 {
                npc.node.run(.fadeAlpha(to: 0.35, duration: 0.3))
            }
            if npc.def.role == .boss, session.isDefeated(npc.def) {
                if !npc.node.isHidden {
                    SkillEffects.smoke(at: npc.node.position, in: world)
                    npc.node.isHidden = true
                }
                continue
            }
            let notice = session.notice(for: npc.def.id)
            npc.marker.isHidden = notice == nil
            if let notice {
                npc.marker.attributedText = Nodes.outlined(notice == .ready ? "?" : "!", size: 18, color: Nodes.gold)
            }
            let distance = player.position.distance(to: npc.node.position)
            if distance <= talkRange + 12, distance < (nearest?.distance ?? .infinity) {
                nearest = (npc.def.id, distance)
            }
            // Townsfolk at their posts turn to watch you pass, and glance around otherwise.
            if npc.def.role != .chest, npc.def.role != .boss {
                if distance < 130 {
                    npc.node.face(Direction(player.position - npc.node.position, current: npc.node.facing))
                } else if Int.random(in: 0..<12) == 0 {
                    npc.node.face(Direction.allCases.randomElement() ?? .down)
                }
            }
        }
        if session.nearbyNPC != nearest?.id { session.nearbyNPC = nearest?.id }
    }

    /// The last few steps toward an open road out fade to black.
    private func updateEdgeFade(_ dt: TimeInterval) {
        let cell = map.cell(at: player.position)
        let fadeCells = 4
        var target: CGFloat = 0
        for exit in def.exits where session.canTravel(exit) {
            let distance = map.distance(from: cell, to: exit.edge)
            guard distance < fadeCells else { continue }
            target = max(target, CGFloat(fadeCells - distance) / CGFloat(fadeCells) * 0.75)
        }
        if hasLeft { target = 0.85 }
        let t = dt == 0 ? 1 : min(1, CGFloat(dt) * 6)
        edgeFade.alpha += (target - edgeFade.alpha) * t
    }

    private func updateCamera(_ dt: TimeInterval) {
        // The diamond's corners are filled by the surroundings, so just follow the hero.
        let goal = player.position
        let t = dt == 0 ? 1 : min(1, CGFloat(dt) * 10)
        let eased = CGPoint(x: cam.position.x + (goal.x - cam.position.x) * t, y: cam.position.y + (goal.y - cam.position.y) * t)
        // Snap to whole screen pixels so pixel art doesn't shimmer (zooming changes their size).
        let scale = (view?.contentScaleFactor ?? 1) / cam.xScale
        cam.position = CGPoint(x: (eased.x * scale).rounded() / scale, y: (eased.y * scale).rounded() / scale)
        lighting?.follow(cam.position)
    }
}

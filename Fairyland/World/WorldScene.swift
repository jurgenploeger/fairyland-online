import SpriteKit

/// Joystick input shared between the SwiftUI HUD and the scene (read every frame).
final class InputState {
    /// -1...1 on each axis, y up.
    var move: CGVector = .zero
}

/// One map: ground, scenery, NPCs, the hero and their companion.
///
/// Like Fairyland, monsters aren't shown on the map — walking through the wild can start
/// a random battle. Walk off the edge where a road leaves the map to travel to the next map.
final class WorldScene: SKScene {
    var onEncounter: (@MainActor (MapDef.Encounters, SKTexture?) -> Void)?
    var onTalk: (@MainActor (NPCDef) -> Void)?
    var onTravel: (@MainActor (MapDef.Exit) -> Void)?
    var onFirstFrame: (@MainActor () -> Void)?
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
    private var followerPetID: UUID?
    private var npcs: [(def: NPCDef, node: Walker, marker: SKLabelNode)] = []
    private var talkTarget: String?
    private var lastCell: GridPoint
    private var stepsSinceBattle = 0
    private var lastUpdate: TimeInterval = 0
    private var noticeTimer: TimeInterval = 0
    private var hasLeft = false
    private var ambience: Ambience?

    private let walkSpeed: CGFloat = 88
    private let talkRange: CGFloat = 50

    /// `entry` is the edge the player walked in through, or nil to use the saved position.
    init(map def: MapDef, session: GameSession, input: InputState, entry: Edge?) {
        let map = WorldMap(def: def)
        let player = Walker(cycle: ArtLibrary.shared.walkCycle("player_walk"), label: session.data.hero.name)
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
        if session.mapName != def.name {
            session.post("You arrive at \(def.name).")
        }
        session.mapName = def.name
        session.mapCell = lastCell
        MusicPlayer.shared.play(def.music)
        lastUpdate = 0
    }

    // MARK: - Building the map

    private func build() {
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
        placeFairyRings()
        placeProps()
        placeSignposts()

        world.addChild(player)
        refreshFollower()
        cam.position = player.position
        ambience = Ambience(def.ambience, world: world, camera: cam, bounds: map.bounds, seed: def.id)
        ambience?.resize(to: size)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        ambience?.resize(to: size)
    }

    private func makeGround() -> SKNode {
        let tileSize = CGSize(width: WorldMap.tileSize, height: WorldMap.tileSize)
        let theme = def.theme
        func group(_ id: String) -> SKTileGroup {
            SKTileGroup(tileDefinition: SKTileDefinition(texture: art.tileTexture(id), size: tileSize))
        }
        let water = SKTileGroup(tileDefinition: SKTileDefinition(textures: art.waterFrames(theme.water ?? "tile_water"), size: tileSize, timePerFrame: 0.9))
        let groups: [Ground: SKTileGroup] = [
            .ground: group(theme.ground),
            .path: group(theme.path),
            .accent: group(theme.accent ?? theme.ground),
            .border: group(theme.border ?? theme.ground),
            .water: water,
        ]
        let tileMap = SKTileMapNode(
            tileSet: SKTileSet(tileGroups: Array(groups.values)),
            columns: map.columns,
            rows: map.rows,
            tileSize: tileSize
        )
        tileMap.anchorPoint = .zero
        for row in 0..<map.rows {
            for col in 0..<map.columns {
                tileMap.setTileGroup(groups[map.ground[row][col]], forColumn: col, row: row)
            }
        }
        let ground = projected(tileMap)
        ground.zPosition = -100_000
        return ground
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
        for building in def.buildings ?? [] {
            let anchor = map.offset(building.x, building.y)
            for dc in -1...1 {
                for dr in 0...1 { map.occupy(GridPoint(col: anchor.col + dc, row: anchor.row + dr), blocking: true) }
            }
            addScenery(art.sprite(building.art), at: anchor)
        }
    }

    private func placeNPCs() {
        for npc in def.npcs ?? [] {
            let cell = map.offset(npc.x, npc.y)
            map.occupy(cell, blocking: true)
            let node = Walker(cycle: art.walkCycle(npc.art), label: npc.name)
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
            let spread = max(1, Int(Double(groupSize).squareRoot().rounded()) + 1)
            var placed = 0
            var attempts = 0
            while placed < placement.count, attempts < placement.count * 3 {
                attempts += 1
                guard let middle = map.randomFreeCell(using: &rng) else { break }
                let wanted = min(groupSize, placement.count - placed)
                var inGroup = 0
                for index in 0..<(wanted * 5) where inGroup < wanted {
                    let cell = index == 0 ? middle : GridPoint(
                        col: middle.col + Int.random(in: -spread...spread, using: &rng),
                        row: middle.row + Int.random(in: -spread...spread, using: &rng)
                    )
                    guard map.isFreeForScenery(cell) else { continue }
                    map.occupy(cell, blocking: placement.blocking)
                    addScenery(sprite, at: cell, sway: placement.sway == true, jitter: true)
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
                guard area.allSatisfy(map.isFreeForScenery) else { continue }
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

    private func addScenery(_ sprite: SpriteArt, at cell: GridPoint, sway: Bool = false, jitter: Bool = false) {
        let node = SKSpriteNode(texture: sprite.texture, size: sprite.size)
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

    private func refreshFollower() {
        let pet = session.activePet
        guard pet?.id != followerPetID || (pet == nil) != (follower == nil) else { return }
        follower?.removeFromParent()
        follower = nil
        followerPetID = pet?.id
        guard let pet, let species = session.species(of: pet) else { return }
        let node = Walker(cycle: art.walkCycle(species.art), label: pet.name)
        node.position = player.position + CGVector(dx: -30, dy: 0)
        node.walkSpeed = 110
        world.addChild(node)
        follower = node
    }

    private func updateFollower(_ dt: TimeInterval) {
        guard let follower else { return }
        let behind = player.facing.vector * -1
        let goal = player.facing.isHorizontal
            ? player.position + behind * 34 + CGVector(dx: 0, dy: 6)
            : player.position + behind * 14 + CGVector(dx: -30, dy: 0)
        let offset = goal - follower.position
        let distance = offset.length
        if distance > 300 {
            follower.position = goal
        } else if distance > 6 {
            let step = min(distance, max(follower.walkSpeed, distance * 2) * CGFloat(dt))
            follower.position = follower.position + offset * (step / distance)
            follower.face(Direction(offset, current: follower.facing))
            follower.setWalking(true)
        } else {
            follower.setWalking(false)
            follower.face(player.facing)
        }
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
        player.path = map.path(from: player.position, to: point)
        if let destination = player.path.last {
            Effects.tapMarker(at: destination, in: world)
        }
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
        updateFollower(dt)
        noticeTimer -= dt
        if noticeTimer <= 0 {
            noticeTimer = 0.4
            updateNotices()
            refreshFollower()
        }

        player.zPosition = -player.position.y
        if let follower { follower.zPosition = -follower.position.y }
        updateCamera(dt)
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
        map.isWalkable(map.rawCell(at: point))
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
        lastCell = cell
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
        return view?.texture(from: world, crop: visible)
    }

    /// Back from a battle (or a dialog): unlock input and pick up party changes.
    func resume() {
        isInputLocked = false
        lastUpdate = 0
        input.move = .zero
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
            let notice = session.notice(for: npc.def.id)
            npc.marker.isHidden = notice == nil
            if let notice {
                npc.marker.attributedText = Nodes.outlined(notice == .ready ? "?" : "!", size: 18, color: Nodes.gold)
            }
            let distance = player.position.distance(to: npc.node.position)
            if distance <= talkRange + 12, distance < (nearest?.distance ?? .infinity) {
                nearest = (npc.def.id, distance)
            }
        }
        if session.nearbyNPC != nearest?.id { session.nearbyNPC = nearest?.id }
    }

    private func updateCamera(_ dt: TimeInterval) {
        // The diamond's corners are filled by the surroundings, so just follow the hero.
        let goal = player.position
        let t = dt == 0 ? 1 : min(1, CGFloat(dt) * 10)
        let eased = CGPoint(x: cam.position.x + (goal.x - cam.position.x) * t, y: cam.position.y + (goal.y - cam.position.y) * t)
        // Snap to whole screen pixels so pixel art doesn't shimmer.
        let scale = view?.contentScaleFactor ?? 1
        cam.position = CGPoint(x: (eased.x * scale).rounded() / scale, y: (eased.y * scale).rounded() / scale)
    }
}

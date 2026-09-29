import GameplayKit

nonisolated enum Ground {
    case ground, path, accent, border, water
}

nonisolated struct GridPoint: Hashable {
    var col: Int
    var row: Int
}

extension GridPoint {
    init(_ vector: vector_int2) {
        self.init(col: Int(vector.x), row: Int(vector.y))
    }

    var vector: vector_int2 { vector_int2(Int32(col), Int32(row)) }
}

/// The grid for one map: ground layout, blocked cells, exits and A* pathfinding.
///
/// Fairyland Online was 2.5D, not flat top-down: the grid is turned 45° and squashed to half
/// height (a 2:1 isometric diamond). Game logic works on the square grid; `project` and
/// `unproject` convert to and from on-screen positions.
final class WorldMap {
    /// Size of a grid cell before projection (on screen a cell is a ~62×31 diamond).
    static let tileSize: CGFloat = 44

    static func project(_ grid: CGPoint) -> CGPoint {
        let c = CGFloat(0.5).squareRoot()
        return CGPoint(x: (grid.x - grid.y) * c, y: (grid.x + grid.y) * c * 0.5)
    }

    static func unproject(_ point: CGPoint) -> CGPoint {
        let c = CGFloat(0.5).squareRoot()
        let difference = point.x / c
        let sum = point.y / (c * 0.5)
        return CGPoint(x: (sum + difference) / 2, y: (sum - difference) / 2)
    }
    /// Width of the grass ring outside a fenced town.
    static let townBorder = 2

    let def: MapDef
    let columns: Int
    let rows: Int
    let center: GridPoint
    /// ground[row][col], row 0 at the bottom (SpriteKit's y-up).
    private(set) var ground: [[Ground]]
    private(set) var fenceCells: [GridPoint] = []
    /// Each pond's water cells, for lily pads.
    private(set) var ponds: [[GridPoint]] = []
    private var occupied: Set<GridPoint> = []
    private var blocked: Set<GridPoint> = []
    private let graph: GKGridGraph<GKGridGraphNode>

    /// The projected map's on-screen bounding box.
    var bounds: CGRect {
        let width = CGFloat(columns) * Self.tileSize
        let height = CGFloat(rows) * Self.tileSize
        let corners = [CGPoint.zero, CGPoint(x: width, y: 0), CGPoint(x: 0, y: height), CGPoint(x: width, y: height)].map(Self.project)
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    init(def: MapDef) {
        self.def = def
        columns = def.width
        rows = def.height
        center = GridPoint(col: def.width / 2, row: def.height / 2)
        ground = Array(repeating: Array(repeating: .ground, count: def.width), count: def.height)
        graph = GKGridGraph(
            fromGridStartingAt: vector_int2(0, 0),
            width: Int32(def.width),
            height: Int32(def.height),
            diagonalsAllowed: true
        )
        // Seeded by the map id, so every map looks the same each time you visit.
        var rng = SeededRandom(text: def.id)
        if def.fence == true { layOutTownBorder() }
        for exit in def.exits { carveRoad(to: exit.edge, &rng) }
        if def.theme.water != nil, let count = def.theme.ponds { digPonds(count, &rng) }
        if def.theme.accent != nil {
            if let patches = def.theme.accentPatches {
                paintAccentPatches(patches, &rng)
            } else {
                scatterAccents(&rng)
            }
        }
    }

    // MARK: Coordinates

    /// The cell under an on-screen point, clamped to the map.
    func cell(at point: CGPoint) -> GridPoint {
        let raw = rawCell(at: point)
        return GridPoint(col: min(max(raw.col, 0), columns - 1), row: min(max(raw.row, 0), rows - 1))
    }

    /// The cell under an on-screen point, possibly outside the map.
    func rawCell(at point: CGPoint) -> GridPoint {
        let grid = Self.unproject(point)
        return GridPoint(col: Int((grid.x / Self.tileSize).rounded(.down)), row: Int((grid.y / Self.tileSize).rounded(.down)))
    }

    /// A cell relative to the map centre (content uses x/y offsets, y up).
    func offset(_ x: Int, _ y: Int) -> GridPoint {
        GridPoint(col: center.col + x, row: center.row + y)
    }

    /// On-screen centre of a cell's diamond.
    func center(of cell: GridPoint) -> CGPoint {
        Self.project(CGPoint(x: (CGFloat(cell.col) + 0.5) * Self.tileSize, y: (CGFloat(cell.row) + 0.5) * Self.tileSize))
    }

    /// Where something standing in `cell` should be anchored.
    func base(of cell: GridPoint) -> CGPoint {
        center(of: cell) + CGVector(dx: 0, dy: -4)
    }

    /// 0...1 position of a cell for maps and minimaps (top-left origin, north up).
    func unitPosition(of cell: GridPoint) -> CGPoint {
        CGPoint(x: (CGFloat(cell.col) + 0.5) / CGFloat(columns), y: 1 - (CGFloat(cell.row) + 0.5) / CGFloat(rows))
    }

    func contains(_ cell: GridPoint) -> Bool {
        cell.col >= 0 && cell.row >= 0 && cell.col < columns && cell.row < rows
    }

    func isWalkable(_ cell: GridPoint) -> Bool {
        contains(cell) && !blocked.contains(cell)
    }

    // MARK: Exits

    /// The exit edge `cell` touches, if any — step on the outermost row of an exit to leave.
    func exit(at cell: GridPoint) -> MapDef.Exit? {
        def.exits.first { exit in
            switch exit.edge {
            case .north: cell.row == rows - 1
            case .south: cell.row == 0
            case .east: cell.col == columns - 1
            case .west: cell.col == 0
            }
        }
    }

    /// How many cells `cell` is from the edge of `exit` (0 = standing on the way out).
    func distance(from cell: GridPoint, to edge: Edge) -> Int {
        switch edge {
        case .north: rows - 1 - cell.row
        case .south: cell.row
        case .east: columns - 1 - cell.col
        case .west: cell.col
        }
    }

    /// Road cells one step in from `edge`, where a barricade closes a road.
    func roadCells(near edge: Edge) -> [GridPoint] {
        switch edge {
        case .north: (0..<columns).filter { ground[rows - 2][$0] == .path }.map { GridPoint(col: $0, row: rows - 2) }
        case .south: (0..<columns).filter { ground[1][$0] == .path }.map { GridPoint(col: $0, row: 1) }
        case .east: (0..<rows).filter { ground[$0][columns - 2] == .path }.map { GridPoint(col: columns - 2, row: $0) }
        case .west: (0..<rows).filter { ground[$0][1] == .path }.map { GridPoint(col: 1, row: $0) }
        }
    }

    /// Where you arrive when entering through `edge`: on the road, a couple of tiles in.
    func entryCell(from edge: Edge) -> GridPoint {
        let cell = switch edge {
        case .north: GridPoint(col: roadColumn(near: rows - 3), row: rows - 3)
        case .south: GridPoint(col: roadColumn(near: 2), row: 2)
        case .east: GridPoint(col: columns - 3, row: roadRow(near: columns - 3))
        case .west: GridPoint(col: 2, row: roadRow(near: 2))
        }
        return nearestWalkable(to: cell) ?? center
    }

    /// The road column closest to the centre on `row` (roads are two tiles wide).
    private func roadColumn(near row: Int) -> Int {
        (0..<columns).filter { ground[row][$0] == .path }.min { abs($0 - center.col) < abs($1 - center.col) } ?? center.col
    }

    private func roadRow(near col: Int) -> Int {
        (0..<rows).filter { ground[$0][col] == .path }.min { abs($0 - center.row) < abs($1 - center.row) } ?? center.row
    }

    // MARK: Placement

    /// Reserves a cell; blocking things also take it out of the walk graph.
    func occupy(_ cell: GridPoint, blocking: Bool) {
        guard contains(cell) else { return }
        occupied.insert(cell)
        guard blocking, !blocked.contains(cell), let node = graph.node(atGridPosition: cell.vector) else { return }
        graph.remove([node])
        blocked.insert(cell)
    }

    /// Whether scenery may go in `cell`: free, off roads and water, clear of the centre and
    /// the arrival spots, and (in fenced towns) outside the fence.
    func isFreeForScenery(_ cell: GridPoint) -> Bool {
        guard cell.col >= 1, cell.row >= 1, cell.col < columns - 1, cell.row < rows - 1 else { return false }
        guard !occupied.contains(cell) else { return false }
        let tile = ground[cell.row][cell.col]
        guard tile != .path, tile != .water else { return false }
        guard max(abs(cell.col - center.col), abs(cell.row - center.row)) > 2 else { return false }
        if def.fence == true, tile != .border { return false }
        for entry in entryCells where max(abs(cell.col - entry.col), abs(cell.row - entry.row)) <= 2 {
            return false
        }
        return true
    }

    private var cachedEntryCells: [GridPoint]?

    private var entryCells: [GridPoint] {
        if let cachedEntryCells { return cachedEntryCells }
        let cells = def.exits.map { entryCell(from: $0.edge) }
        cachedEntryCells = cells
        return cells
    }

    /// A random free cell for scenery.
    func randomFreeCell(using rng: inout SeededRandom) -> GridPoint? {
        for _ in 0..<400 {
            let cell = GridPoint(col: Int.random(in: 1..<(columns - 1), using: &rng), row: Int.random(in: 1..<(rows - 1), using: &rng))
            if isFreeForScenery(cell) { return cell }
        }
        return nil
    }

    /// A walkable cell within `radius` of `cell` for background characters to stroll to:
    /// never on the map's edge (where the exits are), and inside the fence in towns.
    func strollTarget(near cell: GridPoint, radius: Int, using rng: inout some RandomNumberGenerator) -> GridPoint? {
        for _ in 0..<24 {
            let candidate = GridPoint(col: cell.col + Int.random(in: -radius...radius, using: &rng),
                                      row: cell.row + Int.random(in: -radius...radius, using: &rng))
            guard candidate.col > 0, candidate.row > 0, candidate.col < columns - 1, candidate.row < rows - 1,
                  isWalkable(candidate) else { continue }
            if def.fence == true, ground[candidate.row][candidate.col] == .border { continue }
            return candidate
        }
        return nil
    }

    // MARK: Pathfinding

    /// Waypoints from `start` to `end` around blocked cells. Empty if unreachable.
    func path(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        guard let startCell = nearestWalkable(to: cell(at: start)),
              let goalCell = nearestWalkable(to: cell(at: end)),
              let from = graph.node(atGridPosition: startCell.vector),
              let to = graph.node(atGridPosition: goalCell.vector)
        else { return [] }

        // Stop exactly where the player tapped when that spot is walkable.
        let goal = goalCell == cell(at: end) ? end : center(of: goalCell)
        if startCell == goalCell { return [goal] }

        let nodes = graph.findPath(from: from, to: to).compactMap { $0 as? GKGridGraphNode }
        guard nodes.count > 1 else { return [] }
        var points = nodes.dropFirst().map { center(of: GridPoint($0.gridPosition)) }
        points[points.count - 1] = goal
        return points
    }

    func nearestWalkable(to cell: GridPoint) -> GridPoint? {
        if isWalkable(cell) { return cell }
        for radius in 1...8 {
            for dr in -radius...radius {
                for dc in -radius...radius where max(abs(dr), abs(dc)) == radius {
                    let candidate = GridPoint(col: cell.col + dc, row: cell.row + dr)
                    if isWalkable(candidate) { return candidate }
                }
            }
        }
        return nil
    }

    // MARK: Generation

    /// Towns: a grass ring around the edge with a fence just inside it and gates at the exits.
    private func layOutTownBorder() {
        let ring = Self.townBorder
        for row in 0..<rows {
            for col in 0..<columns {
                let inset = min(col, row, columns - 1 - col, rows - 1 - row)
                if inset < ring {
                    ground[row][col] = .border
                } else if inset == ring {
                    fenceCells.append(GridPoint(col: col, row: row))
                }
            }
        }
    }

    /// A road from the centre out through an exit, winding along a smooth curve and swelling
    /// and narrowing a little (towns keep theirs tidier). The last stretch runs straight at
    /// the edge so exits and arrivals line up.
    private func carveRoad(to edge: Edge, _ rng: inout SeededRandom) {
        let fenced = def.fence == true
        let start = CGPoint(x: CGFloat(center.col) + 0.5, y: CGFloat(center.row) + 0.5)
        let (end, inward): (CGPoint, CGVector) = switch edge {
        case .east: (CGPoint(x: CGFloat(columns), y: start.y), CGVector(dx: -1, dy: 0))
        case .west: (CGPoint(x: 0, y: start.y), CGVector(dx: 1, dy: 0))
        case .north: (CGPoint(x: start.x, y: CGFloat(rows)), CGVector(dx: 0, dy: -1))
        case .south: (CGPoint(x: start.x, y: 0), CGVector(dx: 0, dy: 1))
        }
        let side = CGVector(dx: -inward.dy, dy: inward.dx)
        let approach = end + inward * 5
        let length = start.distance(to: approach)

        // Waypoints along the way, pushed sideways by a smooth random drift.
        var points = [start]
        let count = max(2, Int(length / 8))
        var drift: CGFloat = 0
        let sway: CGFloat = fenced ? 1 : 6
        for k in 1..<count {
            drift = min(max(drift + CGFloat.random(in: -3...3, using: &rng), -sway), sway)
            let t = CGFloat(k) / CGFloat(count)
            var point = CGPoint(x: start.x + (approach.x - start.x) * t, y: start.y + (approach.y - start.y) * t) + side * drift
            point.x = min(max(point.x, 4), CGFloat(columns - 4))
            point.y = min(max(point.y, 4), CGFloat(rows - 4))
            points.append(point)
        }
        points += [approach, end]

        // Paint along a Catmull-Rom curve through the waypoints.
        var travelled: CGFloat = 0
        for index in 0..<(points.count - 1) {
            let p0 = points[max(0, index - 1)], p1 = points[index], p2 = points[index + 1], p3 = points[min(points.count - 1, index + 2)]
            let steps = max(4, Int(p1.distance(to: p2) * 4))
            for step in 0...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let point = Self.catmullRom(p0, p1, p2, p3, t)
                travelled += p1.distance(to: p2) / CGFloat(steps)
                let halfWidth = fenced ? 1.05 : 1.05 + 0.35 * sin(travelled / 6)
                paintRoad(around: point, radius: halfWidth)
            }
        }
    }

    private func paintRoad(around point: CGPoint, radius: CGFloat) {
        let reach = Int(radius.rounded(.up)) + 1
        let middle = GridPoint(col: Int(point.x), row: Int(point.y))
        for dr in -reach...reach {
            for dc in -reach...reach {
                let cell = GridPoint(col: middle.col + dc, row: middle.row + dr)
                guard contains(cell) else { continue }
                let cellCenter = CGPoint(x: CGFloat(cell.col) + 0.5, y: CGFloat(cell.row) + 0.5)
                guard cellCenter.distance(to: point) <= radius else { continue }
                ground[cell.row][cell.col] = .path
                fenceCells.removeAll { $0 == cell }   // gate
            }
        }
    }

    private static func catmullRom(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let t2 = t * t, t3 = t2 * t
        func blend(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
            0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
        }
        return CGPoint(x: blend(p0.x, p1.x, p2.x, p3.x), y: blend(p0.y, p1.y, p2.y, p3.y))
    }

    /// Which sides of a road cell touch something that isn't road (for soft road edges):
    /// bit 1 north, 2 east, 4 south, 8 west.
    func roadEdgeMask(_ cell: GridPoint) -> Int {
        func open(_ dc: Int, _ dr: Int) -> Bool {
            let next = GridPoint(col: cell.col + dc, row: cell.row + dr)
            // Off the map the road carries on (exits), so that side stays road.
            guard contains(next) else { return false }
            return ground[next.row][next.col] != .path
        }
        return (open(0, 1) ? 1 : 0) | (open(1, 0) ? 2 : 0) | (open(0, -1) ? 4 : 0) | (open(-1, 0) ? 8 : 0)
    }

    private func scatterAccents(_ rng: inout SeededRandom) {
        for row in 0..<rows {
            for col in 0..<columns where ground[row][col] == .ground && Double.random(in: 0..<1, using: &rng) < 0.06 {
                ground[row][col] = .accent
            }
        }
    }

    /// Soft round patches — flower meadows, shell beaches.
    private func paintAccentPatches(_ count: Int, _ rng: inout SeededRandom) {
        for _ in 0..<count {
            let middle = GridPoint(col: Int.random(in: 0..<columns, using: &rng), row: Int.random(in: 0..<rows, using: &rng))
            let radius = Double.random(in: 1.5...4.5, using: &rng)
            let reach = Int(radius.rounded(.up))
            for dr in -reach...reach {
                for dc in -reach...reach {
                    let cell = GridPoint(col: middle.col + dc, row: middle.row + dr)
                    guard contains(cell), ground[cell.row][cell.col] == .ground else { continue }
                    let distance = (Double(dc * dc + dr * dr)).squareRoot()
                    if distance <= radius, Double.random(in: 0..<1, using: &rng) < 0.8 - distance / radius * 0.4 {
                        ground[cell.row][cell.col] = .accent
                    }
                }
            }
        }
    }

    /// Wobbly ponds, kept away from roads, the centre and each other.
    private func digPonds(_ count: Int, _ rng: inout SeededRandom) {
        for _ in 0..<count {
            for _ in 0..<60 {
                let rx = Double.random(in: 2.5...6.5, using: &rng)
                let ry = Double.random(in: 2...4.5, using: &rng)
                let middle = GridPoint(col: Int.random(in: 8..<max(9, columns - 8), using: &rng), row: Int.random(in: 8..<max(9, rows - 8), using: &rng))
                guard max(abs(middle.col - center.col), abs(middle.row - center.row)) > 8 else { continue }
                var cells: [GridPoint] = []
                for dr in -Int(ry + 1)...Int(ry + 1) {
                    for dc in -Int(rx + 1)...Int(rx + 1) {
                        let distance = pow(Double(dc) / rx, 2) + pow(Double(dr) / ry, 2)
                        if distance <= 1 + Double.random(in: -0.18...0.12, using: &rng) {
                            cells.append(GridPoint(col: middle.col + dc, row: middle.row + dr))
                        }
                    }
                }
                let clear = cells.allSatisfy { cell in
                    contains(cell) && !isNear(cell, within: 2) { $0 == .path || $0 == .water }
                }
                guard clear, !cells.isEmpty else { continue }
                for cell in cells {
                    ground[cell.row][cell.col] = .water
                    occupy(cell, blocking: true)
                }
                ponds.append(cells)
                break
            }
        }
    }

    private func isNear(_ cell: GridPoint, within radius: Int, where matches: (Ground) -> Bool) -> Bool {
        for dr in -radius...radius {
            for dc in -radius...radius {
                let other = GridPoint(col: cell.col + dc, row: cell.row + dr)
                if contains(other), matches(ground[other.row][other.col]) { return true }
            }
        }
        return false
    }

    // MARK: Map screen

    /// One pixel per tile, for the map screen.
    func overviewImage() -> CGImage {
        let tileColors: [(String, UInt32)] = [
            ("dark", 0x2E5E5A), ("sand", 0xF2D78F), ("shell", 0xF2D78F), ("town", 0xD8CDBB), ("path", 0xD9B77A),
        ]
        func color(forTile id: String) -> PixelColor {
            PixelColor(tileColors.first { id.contains($0.0) }?.1 ?? 0x5DBB4C)
        }
        let theme = def.theme
        var canvas = PixelCanvas(width: columns, height: rows)
        for row in 0..<rows {
            for col in 0..<columns {
                let cell = GridPoint(col: col, row: row)
                var pixel: PixelColor = switch ground[row][col] {
                case .ground: color(forTile: theme.ground)
                case .accent: color(forTile: theme.accent ?? theme.ground).shaded(1.08)
                case .path: PixelColor(0xE8C98C)
                case .border: color(forTile: theme.border ?? theme.ground)
                case .water: PixelColor(0x4FA3E0)
                }
                if blocked.contains(cell), ground[row][col] != .water { pixel = pixel.shaded(0.55) }
                // PixelCanvas is top-down; the map is bottom-up.
                canvas[col, rows - 1 - row] = pixel
            }
        }
        return canvas.cgImage()
    }
}

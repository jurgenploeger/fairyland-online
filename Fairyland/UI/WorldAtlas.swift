import SwiftUI

/// The whole world at a glance, like Fairyland's world map: every place on the roads between
/// them, turned like the game's isometric view so north points up-left and east up-right, the way
/// you walk out of a map on screen. A compass in the corner says so. Places you haven't been to show as "???", and roads a quest hasn't opened
/// yet show a lock. Tap a place to read about it.
struct WorldAtlas: View {
    let session: GameSession
    @State private var selected: String?
    @State private var pulse = false

    enum Status: Equatable {
        case here, visited, undiscovered
        case locked(quest: String?)
    }

    private struct Road: Identifiable {
        let a: MapDef
        let b: MapDef
        let locked: Bool
        let known: Bool
        var id: String { a.id + "|" + b.id }
    }

    /// One step east moves a place a cell right and a cell up; one step north, a cell left and a cell up.
    private let cell = CGSize(width: 64, height: 46)
    private var maps: [MapDef] { Content.shared.maps.filter { $0.world?.count == 2 } }
    /// Screen column (east minus north) and row from the bottom (east plus north) of a place.
    private func spot(_ map: MapDef) -> (across: Int, up: Int) {
        let world = map.world ?? [0, 0]
        return (world[0] - world[1], world[0] + world[1])
    }
    private var minAcross: Int { maps.map { spot($0).across }.min() ?? 0 }
    private var maxAcross: Int { maps.map { spot($0).across }.max() ?? 0 }
    private var minUp: Int { maps.map { spot($0).up }.min() ?? 0 }
    private var maxUp: Int { maps.map { spot($0).up }.max() ?? 0 }

    var body: some View {
        VStack(spacing: 8) {
            ScrollViewReader { reader in
                ScrollView([.vertical, .horizontal], showsIndicators: false) {
                    atlas
                }
                .frame(maxHeight: 400)
                .onAppear { reader.scrollTo(session.data.mapID, anchor: .center) }
            }
            .background(Color(red: 0.16, green: 0.42, blue: 0.62))
            .overlay(alignment: .topTrailing) { AtlasCompass().padding(6).allowsHitTesting(false) }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HUDStyle.cream.opacity(0.6), lineWidth: 2))

            caption
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var atlas: some View {
        let size = CGSize(width: CGFloat(maxAcross - minAcross + 1) * cell.width, height: CGFloat(maxUp - minUp + 1) * cell.height)
        return ZStack(alignment: .topLeading) {
            ForEach(roads) { road in
                Path { path in
                    path.move(to: center(of: road.a))
                    path.addLine(to: center(of: road.b))
                }
                .stroke(road.known ? HUDStyle.plate : HUDStyle.plate.opacity(0.35),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: road.locked ? [5, 7] : []))
                if road.locked {
                    IconImage(.lock, size: 12)
                        .foregroundStyle(HUDStyle.ink)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(HUDStyle.gold))
                        .position(midpoint(road))
                }
            }
            ForEach(maps) { map in
                PlaceBadge(map: map, status: status(of: map), selected: selected == map.id, pulse: pulse)
                    .frame(width: cell.width + 12)
                    // The id and tap go on the badge itself: after .position they'd cover the whole
                    // atlas, and "scroll to where you are" would centre the atlas instead of you.
                    .id(map.id)
                    .onTapGesture { selected = map.id }
                    .position(center(of: map))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: Caption

    private var caption: some View {
        Text(captionText)
            .font(HUDStyle.font(11))
            .foregroundStyle(HUDStyle.cream)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var captionText: String {
        guard let map = Content.shared.map(selected ?? session.data.mapID) else { return "" }
        switch status(of: map) {
        case .here:
            return "You are here: \(map.name)\(levels(map))"
        case .visited:
            return "\(map.name)\(levels(map))"
        case .undiscovered:
            return "Not discovered yet. Follow the roads to find it."
        case .locked(let quest):
            return "Locked. Finish “\(quest ?? "a quest")” to open the road."
        }
    }

    private func levels(_ map: MapDef) -> String {
        if map.fence == true { return " · town" }
        guard let range = map.encounters?.levels, range.count == 2 else { return "" }
        return " · monsters Lv \(range[0])–\(range[1])"
    }

    // MARK: State

    func status(of map: MapDef) -> Status {
        if map.id == session.data.mapID { return .here }
        if session.hasVisited(map.id) { return .visited }
        // Roads into it from places you've been.
        let roads = maps.filter { session.hasVisited($0.id) }.flatMap { from in from.exits.filter { $0.to == map.id } }
        if roads.isEmpty || roads.contains(where: { session.canTravel($0) }) { return .undiscovered }
        return .locked(quest: roads.lazy.compactMap(\.requires).first.flatMap { session.content.quest($0)?.title })
    }

    private var roads: [Road] {
        var seen = Set<String>()
        var result: [Road] = []
        for map in maps {
            for exit in map.exits {
                guard let other = Content.shared.map(exit.to), other.world?.count == 2 else { continue }
                let key = [map.id, other.id].sorted().joined(separator: "|")
                guard seen.insert(key).inserted else { continue }
                let back = other.exits.filter { $0.to == map.id }
                let locked = !session.canTravel(exit) || back.contains { !session.canTravel($0) }
                let known = session.hasVisited(map.id) || session.hasVisited(other.id)
                result.append(Road(a: map, b: other, locked: locked, known: known))
            }
        }
        return result
    }

    // MARK: Layout

    private func center(of map: MapDef) -> CGPoint {
        let at = spot(map)
        return CGPoint(x: (CGFloat(at.across - minAcross) + 0.5) * cell.width,
                       y: (CGFloat(maxUp - at.up) + 0.5) * cell.height)
    }

    private func midpoint(_ road: Road) -> CGPoint {
        let a = center(of: road.a), b = center(of: road.b)
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

/// A little compass rose, turned like the atlas: N up-left, E up-right.
private struct AtlasCompass: View {
    var body: some View {
        let reach: CGFloat = 17
        // The same slant as a step between places on the atlas.
        let slope: CGFloat = 46.0 / 64.0
        let dy = reach * slope / (1 + slope * slope).squareRoot()
        let dx = reach / (1 + slope * slope).squareRoot()
        ZStack {
            Circle().fill(HUDStyle.ink.opacity(0.55)).frame(width: 54, height: 54)
            Path { path in
                path.move(to: CGPoint(x: 27 - dx, y: 27 - dy)); path.addLine(to: CGPoint(x: 27 + dx, y: 27 + dy))
                path.move(to: CGPoint(x: 27 + dx, y: 27 - dy)); path.addLine(to: CGPoint(x: 27 - dx, y: 27 + dy))
            }
            .stroke(HUDStyle.cream.opacity(0.7), lineWidth: 1.5)
            ForEach(["N", "E", "S", "W"], id: \.self) { label in
                let sx: CGFloat = label == "E" || label == "S" ? 1 : -1
                let sy: CGFloat = label == "S" || label == "W" ? 1 : -1
                Text(label)
                    .font(HUDStyle.font(label == "N" ? 11 : 9))
                    .foregroundStyle(label == "N" ? HUDStyle.gold : HUDStyle.cream)
                    .position(x: 27 + sx * (dx + 5), y: 27 + sy * (dy + 5))
            }
        }
        .frame(width: 54, height: 54)
        .accessibilityHidden(true)
    }
}

/// One place on the world map: a coloured badge (themed by its ground) with its name, or a
/// mystery badge until you've been there.
private struct PlaceBadge: View {
    let map: MapDef
    let status: WorldAtlas.Status
    let selected: Bool
    let pulse: Bool

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if status == .here {
                    Circle().fill(HUDStyle.gold.opacity(0.35)).frame(width: pulse ? 50 : 38, height: pulse ? 50 : 38)
                }
                Circle()
                    .fill(known ? tint : HUDStyle.ink.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(ring, lineWidth: status == .here || selected ? 3 : 2))
                switch status {
                case .locked:
                    IconImage(.lock, size: 15).foregroundStyle(HUDStyle.cream.opacity(0.8))
                case .undiscovered:
                    Text("?").font(HUDStyle.font(16)).foregroundStyle(HUDStyle.cream.opacity(0.8))
                case .here, .visited:
                    if map.fence == true { IconImage(.star, size: 15).foregroundStyle(HUDStyle.ink) }
                }
            }
            .frame(height: 50)
            Text(known ? map.name : "???")
                .font(HUDStyle.font(9))
                .foregroundStyle(status == .here ? HUDStyle.gold : known ? HUDStyle.cream : HUDStyle.cream.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .shadow(color: HUDStyle.ink, radius: 0, x: 1, y: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(known ? map.name : "Undiscovered place")
        .accessibilityAddTraits(.isButton)
    }

    private var known: Bool { status == .here || status == .visited }

    private var ring: Color {
        if status == .here { return HUDStyle.gold }
        return selected ? HUDStyle.cream : HUDStyle.cream.opacity(known ? 0.8 : 0.4)
    }

    /// A colour for the kind of place, from its ground tile.
    private var tint: Color {
        let ground = map.theme.ground
        if map.fence == true { return Color(red: 0.98, green: 0.78, blue: 0.45) }
        if ground.contains("snow") { return Color(red: 0.9, green: 0.95, blue: 1) }
        if ground.contains("desert") || ground.contains("sand") { return Color(red: 0.95, green: 0.83, blue: 0.5) }
        if ground.contains("cave") || ground.contains("scree") { return Color(red: 0.62, green: 0.64, blue: 0.72) }
        if ground.contains("dark") { return Color(red: 0.55, green: 0.45, blue: 0.75) }
        if ground.contains("swamp") { return Color(red: 0.55, green: 0.62, blue: 0.35) }
        if ground.contains("forest") { return Color(red: 0.36, green: 0.68, blue: 0.36) }
        return Color(red: 0.52, green: 0.82, blue: 0.42)
    }
}

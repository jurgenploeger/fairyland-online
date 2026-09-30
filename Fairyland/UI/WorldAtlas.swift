import SwiftUI

/// The whole world at a glance, like Fairyland's world map: every place on the roads between
/// them, north up. Places you haven't been to show as "???", and roads a quest hasn't opened
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

    private let cell = CGSize(width: 84, height: 70)
    private var maps: [MapDef] { Content.shared.maps.filter { $0.world?.count == 2 } }
    private var minX: Int { maps.compactMap { $0.world?[0] }.min() ?? 0 }
    private var maxX: Int { maps.compactMap { $0.world?[0] }.max() ?? 0 }
    private var minY: Int { maps.compactMap { $0.world?[1] }.min() ?? 0 }
    private var maxY: Int { maps.compactMap { $0.world?[1] }.max() ?? 0 }

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
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HUDStyle.cream.opacity(0.6), lineWidth: 2))

            caption
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var atlas: some View {
        let size = CGSize(width: CGFloat(maxX - minX + 1) * cell.width, height: CGFloat(maxY - minY + 1) * cell.height)
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
                    .frame(width: cell.width - 4)
                    .position(center(of: map))
                    .id(map.id)
                    .onTapGesture { selected = map.id }
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
        let world = map.world ?? [0, 0]
        return CGPoint(x: (CGFloat(world[0] - minX) + 0.5) * cell.width,
                       y: (CGFloat(maxY - world[1]) + 0.5) * cell.height)
    }

    private func midpoint(_ road: Road) -> CGPoint {
        let a = center(of: road.a), b = center(of: road.b)
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
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

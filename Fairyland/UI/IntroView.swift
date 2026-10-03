import SwiftUI

/// The onboarding before a new hero is made: the story, how to play, and the whole world map.
/// Also opens from the title screen ("Story & how to play").
struct IntroView: View {
    /// What the last page's button says ("Create your hero", or "Done" when just reading).
    let finishTitle: String
    let onFinish: () -> Void
    @State private var page: Int

    private static let pageCount = 3

    init(finishTitle: String, startPage: Int = 0, onFinish: @escaping () -> Void) {
        self.finishTitle = finishTitle
        self.onFinish = onFinish
        _page = State(initialValue: min(max(0, startPage), Self.pageCount - 1))
    }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                Group {
                    switch page {
                    case 0: StoryPage()
                    case 1: HowToPlayPage()
                    default: WorldPage()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 720)
            .background(HUDStyle.panel)
            .id(page)
            .transition(.opacity)

            HStack(spacing: 10) {
                Button("Skip", action: onFinish)
                    .buttonStyle(PixelButtonStyle(compact: true))
                    .opacity(page == Self.pageCount - 1 ? 0 : 1)
                    .disabled(page == Self.pageCount - 1)
                Spacer()
                PageDots(count: Self.pageCount, current: page)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { page -= 1 }
                } label: {
                    Label("Back", icon: .arrowLeft)
                }
                .buttonStyle(PixelButtonStyle(compact: true))
                .opacity(page == 0 ? 0.4 : 1)
                .disabled(page == 0)
                Button {
                    if page == Self.pageCount - 1 {
                        onFinish()
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) { page += 1 }
                    }
                } label: {
                    Label(page == Self.pageCount - 1 ? finishTitle : "Next", icon: .arrowRight)
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
            }
            .frame(maxWidth: 720)
        }
        .padding(16)
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? HUDStyle.gold : HUDStyle.cream.opacity(0.45))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

private struct PageTitle: View {
    let text: String
    let icon: GameIcon

    var body: some View {
        Label(text, icon: icon, size: 18)
            .font(HUDStyle.font(18))
            .foregroundStyle(HUDStyle.gold)
            .shadow(color: HUDStyle.frameDark, radius: 0, x: 1, y: 1)
    }
}

// MARK: - Story

private struct StoryPage: View {
    /// The three the story names, in its order: one row that fits any screen, and the rest of the
    /// bosses stay a surprise.
    private let bosses = ["big_bad_wolf", "rat_king", "drunk_dragon"].compactMap { Content.shared.monster($0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageTitle(text: "Once upon a time", icon: .book)
            Text("Long ago, the goddess Shiria gathered the world's fairy tales into one land: Fairyland. Villages grew up between the stories, and adventurers came from far and wide to explore them.")
            Text("Lately the tales have been going wrong. A Big Bad Wolf prowls the Snow White Forest. A Rat King has cut off the dwarves of Goldburg. A dragon drinks at the oasis in Genie Desert and scares away the caravans.")
            Text("You arrive in Meadowbrook as a new adventurer, with the whole of Fairyland ahead of you.")
            if !bosses.isEmpty {
                HStack(alignment: .bottom, spacing: 18) {
                    ForEach(bosses) { boss in
                        VStack(spacing: 4) {
                            SpriteImage(art: boss.art, size: 72)
                            Text(boss.name).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
        .font(HUDStyle.font(12))
        .foregroundStyle(HUDStyle.cream)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - How to play

private struct Tip {
    let icon: GameIcon
    let title: String
    let text: String
}

private struct HowToPlayPage: View {
    private let tips: [Tip] = [
        Tip(icon: .tap, title: "Walk", text: "Drag the stick in the corner, or tap the ground and your hero walks there."),
        Tip(icon: .sword, title: "Battle", text: "Monsters jump out as you explore the wild. Battles take turns: attack, cast a skill or use an item."),
        Tip(icon: .paw, title: "Companions", text: "Beat a group down to its last monster, weaken it below 20% health and throw a Seal Stone. Keep up to five."),
        Tip(icon: .star, title: "Grow", text: "Every level gives a skill point. At level 5, visit a guild master in town to become a Fighter, Mage or Beast Tamer."),
        Tip(icon: .book, title: "Quests", text: "Villagers with a gold ! have work for you. Quests reward you and open the roads to new places."),
        Tip(icon: .heart, title: "Towns", text: "Shops, healers and checkpoints wait in town. Your progress saves by itself."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageTitle(text: "How to play", icon: .sparkles)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(tips, id: \.title) { tip in
                    HStack(alignment: .top, spacing: 10) {
                        IconImage(tip.icon, size: 20)
                            .foregroundStyle(HUDStyle.gold)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tip.title).font(HUDStyle.font(13)).foregroundStyle(HUDStyle.gold)
                            Text(tip.text).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.cream)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - World map

private struct WorldPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageTitle(text: "The world of Fairyland", icon: .map)
            Text("Roads join every place to its neighbours. Your journey starts in Meadowbrook. Quests open the roads further out, where stronger monsters live.")
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.cream)
                .fixedSize(horizontal: false, vertical: true)
            IntroAtlas(highlight: Content.shared.startMap)
            HStack(spacing: 14) {
                Label { Text("Start") } icon: { Circle().fill(HUDStyle.gold).frame(width: 9, height: 9) }
                Label { Text("Town") } icon: { RoundedRectangle(cornerRadius: 2).strokeBorder(HUDStyle.gold, lineWidth: 2).frame(width: 10, height: 10) }
                Label { Text("Boss") } icon: { IconImage(.sword, size: 10).foregroundStyle(HUDStyle.hp) }
            }
            .font(HUDStyle.font(10))
            .foregroundStyle(HUDStyle.dim)
            .labelStyle(CompactLabelStyle())
        }
    }
}

/// Every map laid out by its roads: each exit puts the next map one step north, south, east or
/// west of the one it leaves, starting from the first map.
struct IntroAtlas: View {
    struct Place: Identifiable {
        let id: String
        let name: String
        let col: Int
        let row: Int
        let isTown: Bool
        let hasBoss: Bool
        let ground: UIImage
    }

    /// The place to mark with a gold dot.
    let highlight: String?
    private let places: [Place]
    private let roads: [(from: String, to: String)]
    private let cols: ClosedRange<Int>
    private let rows: ClosedRange<Int>
    private static let rowHeight: CGFloat = 46

    init(highlight: String?, content: Content = .shared) {
        self.highlight = highlight
        var spots: [String: (col: Int, row: Int)] = [content.startMap: (0, 0)]
        var taken: Set<[Int]> = [[0, 0]]
        var queue = [content.startMap]
        var roads: [(from: String, to: String)] = []
        var seen: Set<String> = []
        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard let map = content.map(id), let here = spots[id] else { continue }
            for exit in map.exits where content.map(exit.to) != nil {
                if seen.insert([id, exit.to].sorted().joined(separator: "|")).inserted {
                    roads.append((from: id, to: exit.to))
                }
                guard spots[exit.to] == nil else { continue }
                let step: (col: Int, row: Int) = switch exit.edge {
                case .north: (0, -1)
                case .south: (0, 1)
                case .east: (1, 0)
                case .west: (-1, 0)
                }
                var spot = (col: here.col + step.col, row: here.row + step.row)
                // Two roads can point at the same square: carry on in the same direction until one is free.
                while taken.contains([spot.col, spot.row]) {
                    spot = (spot.col + step.col, spot.row + step.row)
                }
                spots[exit.to] = spot
                taken.insert([spot.col, spot.row])
                queue.append(exit.to)
            }
        }
        places = content.maps.compactMap { map in
            guard let spot = spots[map.id] else { return nil }
            let ground = UIImage(cgImage: ArtLibrary.shared.tileTexture(map.theme.ground).cgImage())
            return Place(
                id: map.id, name: map.name, col: spot.col, row: spot.row,
                isTown: map.town != nil, hasBoss: map.npcs?.contains { $0.role == .boss } ?? false, ground: ground
            )
        }
        self.roads = roads
        let columns = places.map(\.col), lines = places.map(\.row)
        cols = (columns.min() ?? 0)...(columns.max() ?? 0)
        rows = (lines.min() ?? 0)...(lines.max() ?? 0)
    }

    var body: some View {
        GeometryReader { proxy in
            let byID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
            let cell = CGSize(width: proxy.size.width / CGFloat(cols.count), height: proxy.size.height / CGFloat(rows.count))
            ZStack {
                Path { path in
                    for road in roads {
                        guard let a = byID[road.from], let b = byID[road.to] else { continue }
                        path.move(to: center(of: a, cell: cell))
                        path.addLine(to: center(of: b, cell: cell))
                    }
                }
                .stroke(HUDStyle.plate.opacity(0.75), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))

                ForEach(places) { place in
                    PlaceBadge(place: place, isStart: place.id == highlight, width: cell.width)
                        .position(center(of: place, cell: cell))
                }
            }
        }
        .frame(height: CGFloat(rows.count) * Self.rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("World map of \(places.count) places, starting in \(places.first { $0.id == highlight }?.name ?? "Meadowbrook")")
    }

    private func center(of place: Place, cell: CGSize) -> CGPoint {
        CGPoint(
            x: (CGFloat(place.col - cols.lowerBound) + 0.5) * cell.width,
            y: (CGFloat(place.row - rows.lowerBound) + 0.5) * cell.height
        )
    }
}

private struct PlaceBadge: View {
    let place: IntroAtlas.Place
    let isStart: Bool
    let width: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            Image(uiImage: place.ground)
                .interpolation(.none)
                .resizable()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: place.isTown ? 4 : 11))
                .overlay(
                    RoundedRectangle(cornerRadius: place.isTown ? 4 : 11)
                        .strokeBorder(place.isTown ? HUDStyle.gold : HUDStyle.cream.opacity(0.8), lineWidth: 2)
                )
                .overlay(alignment: .topTrailing) {
                    if place.hasBoss {
                        IconImage(.sword, size: 10)
                            .foregroundStyle(HUDStyle.hp)
                            .padding(2)
                            .background(Circle().fill(HUDStyle.ink))
                            .offset(x: 6, y: -6)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isStart {
                        Circle().fill(HUDStyle.gold).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
                            .offset(x: -5, y: -5)
                    }
                }
            Text(place.name)
                .font(HUDStyle.font(9))
                .foregroundStyle(isStart ? HUDStyle.gold : HUDStyle.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: max(40, width - 4))
        }
    }
}

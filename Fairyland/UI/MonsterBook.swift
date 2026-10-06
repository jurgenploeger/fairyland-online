import SwiftUI

/// Every monster you've met in battle: a grid of tiles (dark silhouettes for the ones still to meet),
/// filterable by element. Tap one for its page: lore, element strengths, stats, skills, where it lives
/// and what it drops.
struct MonsterBook: View {
    let session: GameSession
    @State private var element: Element?
    @State private var selected: String?

    private var all: [MonsterDef] { session.content.monsters }
    private var seenCount: Int { all.filter { session.sighting(of: $0.id) != nil }.count }

    var body: some View {
        if let id = selected, let monster = session.content.monster(id), let sighting = session.sighting(of: id) {
            MonsterPage(session: session, monster: monster, sighting: sighting) { selected = nil }
        } else {
            grid
        }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Met {count} of {total} monsters", ["count": seenCount, "total": all.count]))
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.gold)
                Spacer()
            }
            Text(L("Every monster you meet in battle is written down here. Tap one to read about it."))
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.dim)
            milestone
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(nil)
                    ForEach(Element.allCases.filter { $0 != .neutral }, id: \.self) { chip($0) }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                ForEach(all.filter { element == nil || $0.element == element }) { monster in
                    tile(monster)
                }
            }
        }
    }

    /// The Book's next reward, and how close it is.
    @ViewBuilder
    private var milestone: some View {
        if let next = session.nextBookMilestone {
            let items = session.itemList(next.reward.items ?? [])
            let reward = items.map { L("{gold} gold and {items}", ["gold": next.reward.gold, "items": $0]) }
                ?? L("{gold} gold", ["gold": next.reward.gold])
            HStack(spacing: 8) {
                IconImage(.gift, size: 16)
                    .foregroundStyle(HUDStyle.gold)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("At {count} kinds: {reward}", ["count": next.count, "reward": reward]))
                        .font(HUDStyle.font(11))
                        .fixedSize(horizontal: false, vertical: true)
                    GlossyBar(fraction: CGFloat(min(seenCount, next.count)) / CGFloat(max(1, next.count)), color: HUDStyle.gold, height: 5)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(HUDStyle.gold.opacity(0.08)))
            .accessibilityElement(children: .combine)
        } else {
            Label(L("Every reward in the Book is yours."), icon: .badgeCheck, size: 14)
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.gold)
        }
    }

    private func chip(_ value: Element?) -> some View {
        let on = element == value
        return Button {
            element = value
        } label: {
            // The chosen element lights up as its gem; the others wear a small one.
            if let value, on {
                HStack(spacing: 4) {
                    IconImage(value.icon, size: 12)
                    Text(value.displayName)
                }
                .font(HUDStyle.font(10))
                .frame(height: 14)
                .onElementGem(value, horizontal: 9, vertical: 4)
            } else {
                HStack(spacing: 4) {
                    if let value { ElementIcon(element: value, size: 14).accessibilityHidden(true) }
                    Text(value?.displayName ?? L("All"))
                }
                .font(HUDStyle.font(10))
                .frame(height: 14)
                .foregroundStyle(on ? HUDStyle.ink : HUDStyle.cream)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(on ? HUDStyle.gold : .white.opacity(0.1)))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private func tile(_ monster: MonsterDef) -> some View {
        let seen = session.sighting(of: monster.id) != nil
        VStack(spacing: 3) {
            SpriteImage(art: monster.art, size: 48)
                .colorMultiply(seen ? .white : .black)
                .opacity(seen ? 1 : 0.55)
                .frame(width: 52, height: 52)
            Text(seen ? monster.name : "???")
                .font(HUDStyle.font(9))
                .foregroundStyle(seen ? HUDStyle.cream : HUDStyle.dim)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 24, alignment: .top)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(seen ? 0.08 : 0.03))
                .overlay(alignment: .topTrailing) {
                    if seen {
                        ElementIcon(element: monster.element, size: 16).padding(4)
                    }
                }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard seen else { return }
            SoundEffects.shared.play(.tap, volume: 0.7)
            selected = monster.id
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(seen ? "\(monster.name), \(monster.element.displayName)" : L("Not met yet"))
        .accessibilityAddTraits(seen ? .isButton : [])
    }
}

/// One monster's page in the book.
private struct MonsterPage: View {
    let session: GameSession
    let monster: MonsterDef
    let sighting: MonsterSighting
    let onBack: () -> Void

    /// Its stats at the highest level you've met it.
    private var stats: Stats { monster.stats(at: sighting.highestLevel) }

    private var homes: [String] {
        session.content.maps.filter { map in
            map.encounters?.monsters[monster.id] != nil || map.npcs?.contains { $0.monster == monster.id } == true
        }
        .map(\.name)
    }

    private var levels: String {
        sighting.lowestLevel == sighting.highestLevel ? L("Lv {level}", ["level": sighting.lowestLevel]) : L("Lv {low}–{high}", ["low": sighting.lowestLevel, "high": sighting.highestLevel])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onBack) {
                Label(L("All monsters"), icon: .arrowLeft, size: 12)
            }
            .buttonStyle(PixelButtonStyle(compact: true))

            HStack(alignment: .center, spacing: 12) {
                SpriteImage(art: monster.art, size: 84)
                    .frame(width: 92, height: 92)
                    .background(Circle().fill(Color(uiColor: monster.element.color).opacity(0.25)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(monster.name)
                        .font(HUDStyle.font(17))
                        .foregroundStyle(HUDStyle.gold)
                    HStack(spacing: 6) {
                        ElementBadge(element: monster.element)
                        if monster.boss == true { tag(L("Boss"), HUDStyle.hp) }
                        if monster.rare == true { tag(L("Rare"), HUDStyle.gold) }
                    }
                    Text(L("Met at {levels} · beaten {count}×", ["levels": levels, "count": sighting.defeated]))
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.dim)
                }
            }

            if let lore = monster.lore {
                Text(lore)
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.cream)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // A boss you've beaten keeps the story of its fall here, to read again.
            if monster.boss == true, let boss = session.content.boss(fighting: monster.id), session.isDefeated(boss),
               let victory = boss.victory {
                section(victory.title) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(victory.story.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .font(HUDStyle.font(11))
                                .foregroundStyle(HUDStyle.cream)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            section(L("Element")) {
                // Light and Dark hurt each other: say that once instead of "strong against" and "weak to" the same thing.
                let element = monster.element
                let mutual = element.strongAgainst.filter { element.weakTo.contains($0) }
                VStack(alignment: .leading, spacing: 4) {
                    if mutual.isEmpty {
                        elementLine(L("Strong against"), element.strongAgainst)
                        elementLine(L("Weak to"), element.weakTo)
                    } else {
                        ForEach(mutual, id: \.self) { other in
                            HStack(spacing: 6) {
                                ElementBadge(element: element)
                                Text(L("and")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.cream)
                                ElementBadge(element: other)
                                Text(L("hit each other extra hard")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.cream)
                            }
                        }
                    }
                }
            }

            section(L("Stats at Lv {level}", ["level": sighting.highestLevel])) {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        statCell(L("HP"), stats.hp, HUDStyle.hp)
                        statCell(L("MP"), stats.mp, HUDStyle.mp)
                        statCell(L("SPD"), stats.speed, HUDStyle.cream)
                    }
                    HStack(spacing: 8) {
                        statCell(L("ATK"), stats.attack, HUDStyle.cream)
                        statCell(L("DEF"), stats.defense, HUDStyle.cream)
                        statCell(L("MAG"), stats.magic, HUDStyle.cream)
                    }
                }
            }

            section(L("Skills")) {
                Text(monster.skills.compactMap { session.content.skill($0)?.name }.joined(separator: ", "))
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.cream)
            }

            if !homes.isEmpty {
                section(L("Found in")) {
                    Text(homes.joined(separator: ", "))
                        .font(HUDStyle.font(11))
                        .foregroundStyle(HUDStyle.cream)
                }
            }

            let drops = (monster.drops ?? []).compactMap { session.content.item($0.item) }
            if !drops.isEmpty {
                section(L("Rare drops")) {
                    HStack(spacing: 10) {
                        ForEach(drops) { item in
                            HStack(spacing: 4) {
                                ItemIcon(item: item, size: 24)
                                Text(item.name).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.cream)
                            }
                        }
                    }
                }
            }

            Label(monster.captureRate > 0 && monster.boss != true
                  ? L("Can be befriended: weaken it, then throw a Seal Stone with Capture.")
                  : L("Can't be befriended."), icon: .paw, size: 13)
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.dim)
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(HUDStyle.font(9))
            .foregroundStyle(HUDStyle.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
    }

    private func section<Body: View>(_ title: String, @ViewBuilder content: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.gold)
            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
    }

    @ViewBuilder
    private func elementLine(_ label: String, _ elements: [Element]) -> some View {
        HStack(spacing: 6) {
            Text(label).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.cream)
            if elements.isEmpty {
                Text(L("nothing in particular")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            } else {
                ForEach(elements, id: \.self) { ElementBadge(element: $0) }
            }
        }
    }

    private func statCell(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(HUDStyle.font(9)).foregroundStyle(HUDStyle.dim)
            Spacer(minLength: 2)
            Text("\(value)").font(HUDStyle.mono(11)).foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 5).fill(HUDStyle.ink.opacity(0.4)))
    }
}

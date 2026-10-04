import SwiftUI

/// Someone whose stats you can look at: you, one of your companions, or an adventurer (a friend in
/// your party, or anyone you meet on the map).
enum Profile: Equatable {
    case hero
    case pet(UUID)
    case adventurer(Adventurer)
}

/// Fairyland's character window: tap someone on the map, or a face in the top-left corner, to see
/// who they are and how strong: level, HP and MP, attack, defense, magic and speed, and what they
/// fight with.
struct ProfileCard: View {
    let session: GameSession
    let profile: Profile
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                if let facts = facts {
                    FLTitleBar(title: facts.name, icon: facts.icon, onClose: onClose)
                    // As tall as it needs, scrolling only on a short (landscape) screen.
                    ViewThatFits(in: .vertical) {
                        details(facts).padding(14)
                        ScrollView { details(facts).padding(14) }
                    }
                } else {
                    FLTitleBar(title: "Nobody here", onClose: onClose)
                    Text("They've gone on their way.")
                        .font(HUDStyle.font(12))
                        .foregroundStyle(HUDStyle.dim)
                        .padding(14)
                }
            }
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(HUDStyle.ink.opacity(0.94))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(HUDStyle.cream.opacity(0.8), lineWidth: 2))
            )
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .padding(14)
        }
    }

    private func details(_ facts: Facts) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                WalkingSprite(art: facts.art, size: 76)
                    .background(Circle().fill(.white.opacity(0.07)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(facts.kind)
                        .font(HUDStyle.font(13))
                        .foregroundStyle(HUDStyle.gold)
                    if let element = facts.element { ElementBadge(element: element) }
                    if let note = facts.note {
                        Text(note)
                            .font(HUDStyle.font(10))
                            .foregroundStyle(facts.noteColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            StatBar(label: "HP", value: facts.hp, maximum: facts.stats.hp, color: HUDStyle.hp)
            if facts.stats.mp > 0 {
                StatBar(label: "MP", value: facts.mp, maximum: facts.stats.mp, color: HUDStyle.mp)
            }
            if let exp = facts.exp {
                StatBar(label: "EXP", value: exp.have, maximum: exp.need, color: HUDStyle.exp)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                StatCell(name: "Attack", value: facts.stats.attack)
                StatCell(name: "Defense", value: facts.stats.defense)
                StatCell(name: "Magic", value: facts.stats.magic)
                StatCell(name: "Speed", value: facts.stats.speed)
            }
            ForEach(facts.lines, id: \.label) { line in
                VStack(alignment: .leading, spacing: 1) {
                    Text(line.label).font(HUDStyle.font(9)).foregroundStyle(HUDStyle.dim)
                    Text(line.text).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.cream)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Everything the window shows about them, worked out once.
    private struct Facts {
        var name: String
        var icon: GameIcon
        var art: String
        /// "Lv 42 · Human Fighter", "Lv 12 · Jelly Puff".
        var kind: String
        var element: Element?
        var note: String?
        var noteColor = HUDStyle.cream
        var stats: Stats
        var hp: Int
        var mp: Int
        var exp: (have: Int, need: Int)?
        /// "Gear", "Skills", "Companion"…
        var lines: [Line] = []
    }

    private struct Line {
        let label: String
        let text: String
    }

    private var facts: Facts? {
        let content = session.content
        switch profile {
        case .hero:
            let hero = session.data.hero
            let worn = [ItemType.weapon, .armor, .accessory].compactMap { session.equipped($0)?.name }
            var facts = Facts(name: hero.name, icon: .user, art: GameSession.heroArt,
                              kind: "Lv \(hero.level) · \(content.race(hero.raceID).name) \(session.heroClass.name)",
                              stats: session.heroStats, hp: hero.hp, mp: hero.mp,
                              exp: (hero.exp, GameSession.expToNext(level: hero.level)))
            if session.rebirths > 0 { facts.note = "Reborn \(session.rebirths)×" }
            facts.lines = [Line(label: "Gear", text: worn.isEmpty ? "Nothing worn" : worn.joined(separator: " · "))]
            return facts

        case .pet(let id):
            guard let pet = session.data.pets.first(where: { $0.id == id }), let species = session.species(of: pet) else { return nil }
            var facts = Facts(name: pet.name, icon: .paw, art: session.artID(for: pet), kind: "Lv \(pet.level) · \(species.name)",
                              element: species.element, stats: session.stats(of: pet), hp: pet.hp, mp: pet.mp,
                              exp: (pet.exp, GameSession.expToNext(level: pet.level)))
            if pet.hp <= 0 {
                facts.note = "Fainted: a potion or a healer wakes it up."
                facts.noteColor = HUDStyle.orange
            } else if session.data.activePetID == pet.id {
                facts.note = "Following you"
                facts.noteColor = HUDStyle.green
            }
            facts.lines = [Line(label: "Skills", text: Self.names(species.skills.compactMap { content.skill($0) }))]
            return facts

        case .adventurer(let person):
            // They're always at full strength away from a fight.
            let stats = session.stats(of: person)
            var facts = Facts(name: person.name, icon: .user, art: session.artID(for: person),
                              kind: "Lv \(person.level) · \(content.race(person.raceID).name) \(content.classDef(person.classID).name)",
                              stats: stats, hp: stats.hp, mp: stats.mp)
            if session.isInParty(person) {
                facts.note = "Travelling with you"
                facts.noteColor = HUDStyle.green
            } else if session.isFriend(person) {
                facts.note = "Your friend"
                facts.noteColor = HUDStyle.green
            } else if person.hostile {
                facts.note = "Looking for trouble!"
                facts.noteColor = Color(uiColor: Crowd.hostileColor)
            }
            facts.lines = [Line(label: "Skills", text: Self.names(session.skills(of: person)))]
            if let species = person.petSpecies.flatMap({ content.monster($0) }) {
                facts.lines.append(Line(label: "Companion", text: "\(species.name), Lv \(max(1, person.level - 1)), \(species.element.displayName)"))
            }
            return facts
        }
    }

    private static func names(_ skills: [SkillDef]) -> String {
        skills.isEmpty ? "None yet" : skills.map(\.name).joined(separator: ", ")
    }
}

import SwiftUI

/// Fairyland's target frame for another adventurer you're standing next to: who they are,
/// how strong, and what you can do (befriend, invite to your party, or duel in danger zones, where
/// a beaten adventurer drops everything they carry).
struct AdventurerCard: View {
    let coordinator: GameCoordinator
    let adventurer: Adventurer

    private var session: GameSession { coordinator.session }

    var body: some View {
        let stats = session.stats(of: adventurer)
        let content = session.content
        let danger = coordinator.world.def.danger == true
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SpriteImage(art: session.artID(for: adventurer), size: 46)
                    .background(Circle().fill(.white.opacity(0.08)))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(adventurer.name)
                            .foregroundStyle(Color(uiColor: adventurer.hostile ? Crowd.hostileColor : Crowd.adventurerColor))
                        Text("Lv \(adventurer.level)").foregroundStyle(HUDStyle.gold)
                        if session.isFriend(adventurer) {
                            IconImage(.heart, size: 12).foregroundStyle(HUDStyle.hp)
                        }
                    }
                    .font(HUDStyle.font(13))
                    Text("\(content.race(adventurer.raceID).name) · \(content.classDef(adventurer.classID).name)")
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.cream)
                    if let pet = adventurer.petSpecies.flatMap(content.monster) {
                        Text("with a \(pet.name)").font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                    }
                }
            }
            StatBar(label: "HP", value: stats.hp, maximum: stats.hp, color: HUDStyle.hp, labelWidth: 20)
                .frame(width: 190)
            HStack(spacing: 6) {
                if adventurer.hostile {
                    Text("Looking for trouble!").font(HUDStyle.font(10)).foregroundStyle(Color(uiColor: Crowd.hostileColor))
                } else if !session.isFriend(adventurer) {
                    Button { coordinator.befriend(adventurer) } label: { Label("Befriend", icon: .heart, size: 13) }
                        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                } else if !session.isInParty(adventurer), session.partyMembers.count < GameSession.maxAllies {
                    Button { coordinator.invite(adventurer) } label: { Label("Invite to party", icon: .user, size: 13) }
                        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                } else if session.partyMembers.count >= GameSession.maxAllies {
                    Text("Your party is full").font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                }
                if !adventurer.hostile {
                    Button { coordinator.trade(with: adventurer) } label: { Label("Trade", icon: .coins, size: 13) }
                        .buttonStyle(PixelButtonStyle(compact: true))
                }
                if danger {
                    Button { coordinator.challenge(adventurer) } label: { Label("Duel", icon: .sword, size: 13) }
                        .buttonStyle(PixelButtonStyle(tint: Color(red: 1, green: 0.55, blue: 0.5), compact: true))
                }
            }
            if danger {
                Text("Beat them and they drop everything they carry.")
                    .font(HUDStyle.font(9))
                    .foregroundStyle(HUDStyle.dim)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(HUDStyle.ink.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(HUDStyle.frameLight.opacity(0.8), lineWidth: 2))
        )
        .frame(maxWidth: 260)
    }
}

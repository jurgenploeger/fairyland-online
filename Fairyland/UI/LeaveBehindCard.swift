import SwiftUI

/// Your party is full and a new friend wants to join: pick who stays behind (it can be the
/// newcomer). Like Fairyland, you can't carry more than five companions.
struct LeaveBehindCard: View {
    let session: GameSession
    let onDone: () -> Void
    @State private var choice: UUID?

    var body: some View {
        let newcomer = session.pendingPet
        let everyone = session.data.pets + (newcomer.map { [$0] } ?? [])
        VStack(spacing: 12) {
            VStack(spacing: 3) {
                Text("Party full!")
                    .font(HUDStyle.font(24))
                    .foregroundStyle(HUDStyle.gold)
                Text("You can travel with \(GameSession.maxPets) companions. Who stays behind?")
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.cream)
                    .multilineTextAlignment(.center)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(everyone) { pet in
                    let isNew = pet.id == newcomer?.id
                    Button {
                        choice = pet.id
                    } label: {
                        VStack(spacing: 3) {
                            SpriteImage(art: session.artID(for: pet), size: 56)
                            Text(pet.name).font(HUDStyle.font(12)).lineLimit(1)
                            Text("Lv \(pet.level) · \(session.species(of: pet)?.name ?? "")")
                                .font(HUDStyle.font(9))
                                .foregroundStyle(HUDStyle.dim)
                                .lineLimit(1)
                        }
                        .foregroundStyle(HUDStyle.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(choice == pet.id ? HUDStyle.orange.opacity(0.35) : .white.opacity(0.07))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(choice == pet.id ? HUDStyle.orange : .clear, lineWidth: 2))
                        )
                        .overlay(alignment: .topTrailing) {
                            if isNew {
                                Text("NEW")
                                    .font(HUDStyle.font(9))
                                    .foregroundStyle(HUDStyle.ink)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(HUDStyle.gold))
                                    .padding(5)
                            }
                        }
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
            if let choice, let pet = everyone.first(where: { $0.id == choice }) {
                Button(pet.id == newcomer?.id ? "Let \(pet.name) go" : "Leave \(pet.name) behind") {
                    session.leaveBehind(choice)
                    onDone()
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.orange))
            } else {
                Text("Tap a companion").font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            }
        }
        .padding(20)
        .frame(maxWidth: 460)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(HUDStyle.ink.opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(HUDStyle.gold.opacity(0.9), lineWidth: 2))
        )
        .padding(20)
    }
}

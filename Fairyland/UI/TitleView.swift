import SwiftUI

/// Title screen: continue a saved game, or create a hero (name + race, like Fairyland).
struct TitleView: View {
    let onStart: (GameSession) -> Void

    @State private var creating = false
    @State private var name = "Hero"
    @State private var look = Look.standard
    @State private var raceID = "human"
    @State private var confirmNewGame = false
    private let savedGame = SaveStore.load()

    var body: some View {
        ZStack {
            // The icon's dreamy sky: gold, pink, blue.
            LinearGradient(
                colors: [Color(red: 1, green: 0.84, blue: 0.42), Color(red: 1, green: 0.66, blue: 0.78), Color(red: 0.5, green: 0.81, blue: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 440)
                        .padding(.top, 12)
                        .accessibilityLabel("Fairyland — a cozy pixel adventure")

                    if creating {
                        creation
                    } else {
                        menu
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { MusicPlayer.shared.play("title") }
        .alert("Start a new game?", isPresented: $confirmNewGame) {
            Button("New game", role: .destructive) { creating = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your saved game will be replaced when you begin.")
        }
    }

    private var menu: some View {
        VStack(spacing: 12) {
            SpriteImage(art: "player_walk", size: 96)
            if let savedGame {
                Button {
                    onStart(GameSession(data: savedGame))
                } label: {
                    Label("Continue: \(savedGame.hero.name), Lv \(savedGame.hero.level)", icon: .play)
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                Text("Your progress saves automatically.")
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.ink.opacity(0.6))
            }
            Button {
                if savedGame != nil { confirmNewGame = true } else { creating = true }
            } label: {
                Label("New game", icon: .sparkles)
            }
            .buttonStyle(PixelButtonStyle())
        }
    }

    private var creation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create your hero").font(HUDStyle.font(16)).foregroundStyle(HUDStyle.gold)
            LookEditor(name: $name, look: $look, raceID: raceID)

            Text("Race").font(HUDStyle.font(12)).foregroundStyle(HUDStyle.dim)
            AdaptiveStack(spacing: 10) {
                ForEach(Content.shared.races) { race in
                    RaceCard(race: race, selected: race.id == raceID)
                        .onTapGesture { raceID = race.id }
                }
            }

            HStack {
                Button("Back") { creating = false }
                    .buttonStyle(PixelButtonStyle(compact: true))
                Spacer()
                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    let session = GameSession.newGame(name: trimmed.isEmpty ? "Hero" : String(trimmed.prefix(12)), raceID: raceID, look: look)
                    session.save()
                    onStart(session)
                } label: {
                    Label("Begin adventure", icon: .arrowRight)
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
            }
        }
        .foregroundStyle(HUDStyle.cream)
        .padding(16)
        .frame(maxWidth: 640)
        .background(HUDStyle.panel)
    }
}

private struct RaceCard: View {
    let race: RaceDef
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(race.name).font(HUDStyle.font(14)).foregroundStyle(selected ? HUDStyle.gold : HUDStyle.cream)
            Text(race.description).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                .fixedSize(horizontal: false, vertical: true)
            Text("HP \(race.base.hp) · MP \(race.base.mp) · ATK \(race.base.attack) · DEF \(race.base.defense) · MAG \(race.base.magic) · SPD \(race.base.speed)")
                .font(HUDStyle.font(9))
                .foregroundStyle(HUDStyle.cream)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(selected ? 0.14 : 0.05))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? HUDStyle.gold : .clear, lineWidth: 2))
        )
        .contentShape(Rectangle())
    }
}

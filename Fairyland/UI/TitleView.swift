import SwiftUI

/// Title screen: continue a saved game, or create a hero (name + race, like Fairyland).
struct TitleView: View {
    let onStart: (GameSession) -> Void

    @State private var creating = false
    @State private var name = "Hero"
    @State private var look = Look(hair: Look.standard.hair, outfit: Look.standard.outfit, skin: Look.standard.skin, gender: "male")
    @State private var raceID = "human"
    @State private var confirmNewGame = false
    @State private var showingChangelog = false
    @State private var showingSettings = false
    /// The story pages: before a new hero is made, or read from the title menu.
    @State private var intro: IntroRequest? = DebugLaunch.introPage.map { IntroRequest(startPage: $0, thenCreate: false) }
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

            if let intro {
                IntroView(finishTitle: intro.thenCreate ? "Create your hero" : "Done", startPage: intro.startPage) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.intro = nil
                        if intro.thenCreate { creating = true }
                    }
                }
                .transition(.opacity)
            } else {
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
                        } else if showingChangelog {
                            ChangelogPanel { showingChangelog = false }
                        } else if showingSettings {
                            VStack(alignment: .leading, spacing: 12) {
                                SettingsView()
                                Button {
                                    showingSettings = false
                                } label: {
                                    Label("Back", icon: .arrowLeft)
                                }
                                .buttonStyle(PixelButtonStyle(compact: true))
                            }
                            .padding(16)
                            .frame(maxWidth: 640)
                            .background(HUDStyle.panel)
                        } else {
                            menu
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { MusicPlayer.shared.play("title") }
        .alert("Start a new game?", isPresented: $confirmNewGame) {
            Button("New game", role: .destructive) { startNewGame() }
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
                if savedGame != nil { confirmNewGame = true } else { startNewGame() }
            } label: {
                Label("New game", icon: .sparkles)
            }
            .buttonStyle(PixelButtonStyle())
            Button {
                showingChangelog = true
            } label: {
                Label("What's new · v\(Self.appVersion)", icon: .book)
            }
            .buttonStyle(PixelButtonStyle(compact: true))
            .padding(.top, 6)
            Button {
                showingSettings = true
            } label: {
                Label("Settings", icon: .settings)
            }
            .buttonStyle(PixelButtonStyle(compact: true))
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { intro = IntroRequest(startPage: 0, thenCreate: false) }
            } label: {
                Label("Story & how to play", icon: .book)
            }
            .buttonStyle(PixelButtonStyle(compact: true))
        }
    }

    /// A new game opens with the story pages, then hero creation.
    private func startNewGame() {
        withAnimation(.easeInOut(duration: 0.25)) { intro = IntroRequest(startPage: 0, thenCreate: true) }
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

extension TitleView {
    /// The version from project.yml (MARKETING_VERSION), falling back to the newest changelog entry.
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Content.shared.releases.first?.version ?? "?"
    }
}

/// Release notes from content/changelog.json, newest first.
private struct ChangelogPanel: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FLTitleBar(title: "What's new", icon: .book, onClose: onClose)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Content.shared.releases) { release in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("v\(release.version)").font(HUDStyle.font(16)).foregroundStyle(HUDStyle.gold)
                            Spacer()
                            Text(release.date).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                        }
                        Text(release.title).font(HUDStyle.font(13))
                        ForEach(release.notes, id: \.self) { note in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").foregroundStyle(HUDStyle.gold)
                                Text(note).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(HUDStyle.font(11))
                        }
                    }
                }
            }
            .padding(16)
        }
        .foregroundStyle(HUDStyle.cream)
        .frame(maxWidth: 640)
        .background(HUDStyle.panel)
    }
}

private struct IntroRequest {
    let startPage: Int
    /// Go on to hero creation afterwards (a new game), rather than back to the menu.
    let thenCreate: Bool
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

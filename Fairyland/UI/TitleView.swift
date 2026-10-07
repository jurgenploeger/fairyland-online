import SpriteKit
import SwiftUI
import UniformTypeIdentifiers

/// Title screen: continue a saved game, or create a hero (name + race, like Fairyland).
struct TitleView: View {
    let onStart: (GameSession) -> Void

    @State private var creating = false
    @State private var name = L("Hero")
    @State private var look = Look(hair: Look.standard.hair, outfit: Look.standard.outfit, skin: Look.standard.skin, gender: "male")
    @State private var raceID = "human"
    /// Your games, the last played first; the carousel shows one at a time.
    @State private var saves = SaveStore.all()
    @State private var selectedSlot: String?
    @State private var showingChangelog = false
    @State private var showingSettings = false
    @State private var showingLanguages = false
    /// Its language: switching rebuilds the screen's text in place.
    @State private var localizer = Localizer.shared
    /// Import a backup: the file picker, and what came of it.
    @State private var importing = false
    @State private var importNote: String?
    /// The story pages: before a new hero is made, or read from the title menu.
    @State private var intro: IntroRequest? = DebugLaunch.introPage.map { IntroRequest(startPage: $0, thenCreate: false) }
    /// The game the carousel is showing.
    private var selectedSave: SaveData? {
        saves.first { $0.slot == selectedSlot } ?? saves.first
    }

    var body: some View {
        ZStack {
            // The app icon's sky, its rays behind the logo at the top.
            StoryleafSky(raysFrom: UnitPoint(x: 0.5, y: 0.18))

            if let intro {
                IntroView(finishTitle: intro.thenCreate ? L("Create your hero") : L("Done"), startPage: intro.startPage) {
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
                            .accessibilityLabel(L("Storyleaf, a cozy pixel adventure"))

                        if creating {
                            creation
                        } else if showingLanguages {
                            LanguagePanel { showingLanguages = false }
                        } else if showingChangelog {
                            ChangelogPanel { showingChangelog = false }
                        } else if showingSettings {
                            VStack(alignment: .leading, spacing: 12) {
                                SettingsView()
                                Button {
                                    showingSettings = false
                                } label: {
                                    Label(L("Back"), icon: .arrowLeft)
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
                    .id(localizer.language)
                }
                // The language button, top right: the first thing a player who can't read English needs.
                if !creating, !showingLanguages {
                    Button {
                        showingSettings = false
                        showingChangelog = false
                        showingLanguages = true
                    } label: {
                        Label(localizer.current.name, icon: .globe)
                    }
                    .buttonStyle(PixelButtonStyle(compact: true))
                    .accessibilityLabel(L("Language: {language}", ["language": localizer.current.name]))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 8)
                    .padding(.trailing, 12)
                }
            }
        }
        .onAppear { MusicPlayer.shared.play("title") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .alert(importNote ?? "", isPresented: Binding(get: { importNote != nil }, set: { if !$0 { importNote = nil } })) {
            Button(L("OK"), role: .cancel) {}
        }
    }

    /// A backup from Files becomes a game of its own on the carousel (never over another one).
    private func importBackup(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? Data(contentsOf: url), let game = try? SaveStore.imported(raw) else {
            importNote = L("That file isn't a Storyleaf backup.")
            return
        }
        SaveStore.save(game)
        saves = SaveStore.all()
        // A copy of a game you still have doesn't show up twice (SaveStore.all keeps the first).
        if saves.contains(where: { $0.slot == game.slot }) {
            selectedSlot = game.slot
            importNote = L("{hero}, level {level}, is back!", ["hero": game.hero.name, "level": game.hero.level])
        } else {
            importNote = L("You already have this game.")
        }
    }

    private var menu: some View {
        VStack(spacing: 12) {
            if saves.isEmpty {
                SpriteImage(art: "player_walk", size: 96)
            } else {
                SaveCarousel(saves: saves, selection: $selectedSlot)
            }
            if let save = selectedSave {
                Button {
                    onStart(GameSession(data: save))
                } label: {
                    Label(L("Continue: {hero}, Lv {level}", ["hero": save.hero.name, "level": save.hero.level]), icon: .play)
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                Text(L("Your progress saves automatically."))
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.ink.opacity(0.6))
            }
            Button {
                // A new game gets its own save, next to the others.
                startNewGame()
            } label: {
                Label(L("New game"), icon: .sparkles)
            }
            .buttonStyle(PixelButtonStyle())
            Button {
                showingChangelog = true
            } label: {
                Label(L("What's new · v{version}", ["version": Self.appVersion]), icon: .book)
            }
            .buttonStyle(PixelButtonStyle(compact: true))
            .padding(.top, 6)
            Button {
                showingSettings = true
            } label: {
                Label(L("Settings"), icon: .settings)
            }
            .buttonStyle(PixelButtonStyle(compact: true))
            Button {
                importing = true
            } label: {
                Label(L("Import a backup"), icon: .arrowDown)
            }
            .buttonStyle(PixelButtonStyle(compact: true))
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { intro = IntroRequest(startPage: 0, thenCreate: false) }
            } label: {
                Label(L("Story & how to play"), icon: .book)
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
            Text(L("Create your hero")).font(HUDStyle.font(16)).foregroundStyle(HUDStyle.gold)
            LookEditor(name: $name, look: $look, raceID: raceID)

            Text(L("Race")).font(HUDStyle.font(12)).foregroundStyle(HUDStyle.dim)
            AdaptiveStack(spacing: 10) {
                ForEach(Content.shared.races) { race in
                    RaceCard(race: race, selected: race.id == raceID)
                        .onTapGesture { raceID = race.id }
                }
            }

            HStack {
                Button(L("Back")) { creating = false }
                    .buttonStyle(PixelButtonStyle(compact: true))
                Spacer()
                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    let session = GameSession.newGame(name: trimmed.isEmpty ? L("Hero") : String(trimmed.prefix(12)), raceID: raceID, look: look)
                    session.save()
                    onStart(session)
                } label: {
                    Label(L("Begin adventure"), icon: .arrowRight)
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

/// Release notes from content/changelog.json, newest first. Only the newest is open; tap any
/// other to read it.
private struct ChangelogPanel: View {
    let onClose: () -> Void
    @State private var open: Set<String> = Set(Content.shared.releases.prefix(1).map(\.id))

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FLTitleBar(title: L("What's new"), icon: .book, onClose: onClose)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Content.shared.releases) { release in
                    let isOpen = open.contains(release.id)
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                if isOpen { open.remove(release.id) } else { open.insert(release.id) }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("v\(release.version)").font(HUDStyle.font(16)).foregroundStyle(HUDStyle.gold)
                                    Spacer()
                                    Text(release.date).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                                    IconImage(isOpen ? .chevronUp : .chevronDown, size: 12)
                                        .foregroundStyle(HUDStyle.dim)
                                }
                                Text(release.title).font(HUDStyle.font(13))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(isOpen ? L("Hides the notes") : L("Shows the notes"))
                        if isOpen {
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
            }
            .padding(16)
        }
        .foregroundStyle(HUDStyle.cream)
        .frame(maxWidth: 640)
        .background(HUDStyle.panel)
    }
}

/// Your saved heroes, each as they look in the game; swipe between them when there's more than one.
private struct SaveCarousel: View {
    let saves: [SaveData]
    @Binding var selection: String?

    var body: some View {
        if saves.count == 1, let save = saves.first {
            SavedHeroCard(save: save)
        } else {
            TabView(selection: Binding(get: { selection ?? saves.first?.slot }, set: { selection = $0 })) {
                ForEach(saves, id: \.slot) { save in
                    SavedHeroCard(save: save)
                        .tag(save.slot)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 190)
        }
    }
}

private struct SavedHeroCard: View {
    let save: SaveData
    private let art: String

    init(save: SaveData) {
        self.save = save
        art = "title-hero-\(save.slot ?? "game")"
        GameSession.registerHero(save.hero, as: art)
    }

    var body: some View {
        let content = Content.shared
        // The companion walking with them, if one is out.
        let pet = save.pets.first { $0.id == save.activePetID }
        let petArt = pet.flatMap { content.monster($0.speciesID)?.art }
        VStack(spacing: 4) {
            IdlePair(hero: art, pet: petArt)
            Text(L("Lv {level} {class} · {map}", ["level": save.hero.level, "class": content.classDef(save.hero.classID).name, "map": content.map(save.mapID)?.name ?? ""]))
                .font(HUDStyle.font(10))
                .foregroundStyle(HUDStyle.ink.opacity(0.65))
            // When you last played it, so you can tell your games apart.
            if let savedAt = save.savedAt {
                Text(L("Played {time}", ["time": savedAt.formatted(.relative(presentation: .named).locale(Localizer.shared.locale))]))
                    .font(HUDStyle.font(9))
                    .foregroundStyle(HUDStyle.ink.opacity(0.5))
            }
        }
        .padding(.bottom, 28)   // room for the page dots
    }
}

/// The hero facing you, breathing like they do while standing in the game, and their companion
/// close beside them with its own idle motion (squish, hop, sway…). A tiny SpriteKit scene, so
/// both move exactly as they do on the map.
private struct IdlePair: View {
    @State private var scene: SKScene

    init(hero: String, pet: String?) {
        _scene = State(initialValue: Self.makeScene(hero: hero, pet: pet))
    }

    var body: some View {
        SpriteView(scene: scene, options: [.allowsTransparency])
            .frame(width: Self.size.width, height: Self.size.height)
            .accessibilityHidden(true)
    }

    private static let size = CGSize(width: 150, height: 104)

    private static func makeScene(hero: String, pet: String?) -> SKScene {
        let scene = SKScene(size: size)
        scene.backgroundColor = .clear
        scene.scaleMode = .aspectFit
        func add(_ art: String, height: CGFloat, x: CGFloat, motion: IdleMotion) {
            let cycle = ArtLibrary.shared.walkCycle(art)
            guard let texture = cycle.frames(.down).first, cycle.size.height > 0 else { return }
            texture.filteringMode = .nearest
            let node = SKSpriteNode(texture: texture, size: cycle.size * (height / cycle.size.height))
            node.anchorPoint = CGPoint(x: 0.5, y: 0.04)
            node.position = CGPoint(x: x, y: 2)
            scene.addChild(node)
            node.run(motion.action(height: node.size.height, delay: .random(in: 0..<0.6)))
        }
        if let pet {
            add(hero, height: 100, x: size.width / 2 - 18, motion: .breathe)
            add(pet, height: 58, x: size.width / 2 + 36, motion: IdleMotion.of(art: pet))
        } else {
            add(hero, height: 100, x: size.width / 2, motion: .breathe)
        }
        return scene
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
            Text(L("HP {hp} · MP {mp} · ATK {attack} · DEF {defense} · MAG {magic} · SPD {speed}", ["hp": race.base.hp, "mp": race.base.mp, "attack": race.base.attack, "defense": race.base.defense, "magic": race.base.magic, "speed": race.base.speed]))
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

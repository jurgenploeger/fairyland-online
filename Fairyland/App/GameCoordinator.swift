import Observation
import SpriteKit

enum MenuTab: String, CaseIterable, Identifiable {
    case character = "Character"
    case companions = "Companions"
    case bag = "Bag"
    case quests = "Quests"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: GameIcon {
        switch self {
        case .character: .user
        case .companions: .paw
        case .settings: .settings
        case .bag: .backpack
        case .quests: .book
        }
    }
}

/// Owns what's on screen: the current map, a battle, or a menu/dialog on top.
@Observable
final class GameCoordinator {
    enum Overlay: Equatable {
        case menu(MenuTab)
        case npc(String)
        case worldMap
        case chat
    }

    let session: GameSession
    let input: InputState
    private(set) var world: WorldScene
    private(set) var battle: BattleController?
    private(set) var overlay: Overlay?
    /// False until the first map frame has rendered (the loading curtain stays up until then).
    private(set) var isReady = false
    /// The map being travelled to, while its loading card is showing.
    private(set) var loadingMapName: String?
    /// How far the map build has got, 0...1, for the loading bar.
    private(set) var loadProgress: Double = 0
    @ObservationIgnored private var loadingStarted = Date()
    @ObservationIgnored private(set) var battleScene: BattleScene?
    /// Set by the app: saves are done, go back to the title screen.
    @ObservationIgnored var onQuitToTitle: (() -> Void)?

    init(session: GameSession) {
        let input = InputState()
        let map = Content.shared.map(session.data.mapID) ?? Content.shared.maps[0]
        self.session = session
        self.input = input
        session.markVisited(map.id)
        session.rescaleLevelsIfNeeded()
        session.handOutMissingStarterGifts()
        let began = Date()
        world = WorldScene(map: map, session: session, input: input, entry: nil)
        wire(world)
        build(world, mapID: map.id, began: began)
        startAutosave()
        session.onCastField = { [weak self] skill in self?.castField(skill) }
        SoundEffects.shared.preload()
    }

    /// Saves quietly every 20 seconds while exploring (and after every important moment elsewhere).
    private func startAutosave() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self else { return }
                if self.battle == nil { self.session.save() }
            }
        }
    }

    /// The scene SpriteKit should show right now.
    var scene: SKScene { battle != nil ? (battleScene ?? world) : world }

    /// Builds the scenery a piece at a time. The bar follows how long each piece took the last time
    /// this map loaded (on this phone); the first time, the scene's own rough guesses.
    private func build(_ scene: WorldScene, mapID: String, began: Date) {
        let learned = Self.learnedSteps(mapID)
        let gridDone = Date()
        loadProgress = learned?.first ?? 0.15
        Task { [weak self] in
            var marks = [gridDone]
            await scene.build { guess in
                marks.append(Date())
                let step = marks.count - 1
                if let learned, step < learned.count {
                    self?.loadProgress = learned[step]
                } else {
                    self?.loadProgress = 0.15 + guess * 0.8
                }
            }
            self?.loadTiming = (mapID, began, marks)
        }
    }

    /// When the current load began and when each of its steps finished, until the first frame.
    @ObservationIgnored private var loadTiming: (mapID: String, began: Date, marks: [Date])?

    private static func learnedSteps(_ mapID: String) -> [Double]? {
        UserDefaults.standard.array(forKey: "loadSteps." + mapID) as? [Double]
    }

    /// Remembers what share of the whole load each step took, for the next time.
    private func rememberLoadTiming() {
        guard let timing = loadTiming else { return }
        loadTiming = nil
        let total = Date().timeIntervalSince(timing.began)
        guard total > 0 else { return }
        let steps = timing.marks.map { min(0.99, $0.timeIntervalSince(timing.began) / total) }
        UserDefaults.standard.set(steps, forKey: "loadSteps." + timing.mapID)
    }

    private func wire(_ scene: WorldScene) {
        scene.onFirstFrame = { [weak self] in self?.finishLoading() }
        scene.onEncounter = { [weak self] encounters, backdrop in self?.startBattle(encounters, backdrop: backdrop) }
        scene.onTalk = { [weak self] npc in self?.open(.npc(npc.id)) }
        scene.onTravel = { [weak self] exit in self?.travel(through: exit) }
        scene.onDuel = { [weak self] rival, backdrop in self?.startDuel(with: rival, backdrop: backdrop) }
    }

    // MARK: Maps

    private func travel(through exit: MapDef.Exit) {
        guard let destination = Content.shared.map(exit.to) else {
            world.resume()
            return
        }
        SoundEffects.shared.play(.whoosh)
        go(to: destination, entry: exit.edge.opposite)
    }

    /// Shows the loading card first, then builds the (big) map behind it.
    private func go(to map: MapDef, entry: Edge?) {
        loadingMapName = map.name
        loadingStarted = Date()
        loadProgress = 0
        isReady = false
        Task {
            try? await Task.sleep(for: .milliseconds(280))
            loadMap(map, entry: entry)
        }
    }

    /// Keeps the loading card up long enough to read, then fades it out.
    private func finishLoading() {
        rememberLoadTiming()
        let remaining = 0.8 - Date().timeIntervalSince(loadingStarted)
        Task {
            loadProgress = 1
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            isReady = true
            DebugLaunch.markReady()
            loadingMapName = nil
        }
    }

    private func loadMap(_ map: MapDef, entry: Edge?) {
        session.data.mapID = map.id
        session.markVisited(map.id)
        session.bossesBeatenHere = []
        if entry == nil { session.playerPosition = nil }
        if entry != nil || map.fence == true { session.reachCheckpoint(map, entry: entry) }
        let began = Date()
        let scene = WorldScene(map: map, session: session, input: input, entry: entry)
        wire(scene)
        build(scene, mapID: map.id, began: began)
        input.move = .zero
        world = scene
        session.save()
    }

    // MARK: Battles

    func startBattle(_ encounters: MapDef.Encounters, backdrop: SKTexture? = nil) {
        let controller = BattleController.encounter(encounters, session: session)
        SoundEffects.shared.play(.encounter)
        controller.onFinish = { [weak self] outcome in self?.endBattle(outcome) }
        battleScene = BattleScene(controller: controller, size: world.size, backdrop: backdrop)
        input.move = .zero
        battle = controller
        isReady = true
        DebugLaunch.markReady()
    }

    /// The adventurer you're duelling, so they can leave the map if you win.
    private var rival: Adventurer?

    private func startDuel(with rival: Adventurer, backdrop: SKTexture?) {
        let controller = BattleController.duel(with: rival, session: session)
        controller.onFinish = { [weak self] outcome in self?.endBattle(outcome) }
        battleScene = BattleScene(controller: controller, size: world.size, backdrop: backdrop)
        input.move = .zero
        self.rival = rival
        battle = controller
        isReady = true
        DebugLaunch.markReady()
    }

    /// The boss you're fighting, so it disappears from the map once beaten.
    private var boss: NPCDef?

    func fightBoss(_ npc: NPCDef) {
        guard let controller = BattleController.boss(npc, session: session) else { return }
        overlay = nil
        controller.onFinish = { [weak self] outcome in self?.endBattle(outcome) }
        battleScene = BattleScene(controller: controller, size: world.size, backdrop: nil)
        input.move = .zero
        boss = npc
        battle = controller
        isReady = true
        DebugLaunch.markReady()
    }

    /// From the adventurer card: befriend, invite along, or challenge.
    func befriend(_ adventurer: Adventurer) {
        if session.befriend(adventurer) {
            world.adventurerSays(["Yay, friends! ^_^", "Sure! Let's adventure sometime!", "Friends! :D"].randomElement()!, adventurer.id)
        }
    }

    func invite(_ adventurer: Adventurer) {
        session.invite(adventurer.id)
        session.nearbyAdventurer = nil
    }

    func challenge(_ adventurer: Adventurer) {
        world.startDuel(with: adventurer)
    }

    private func endBattle(_ outcome: BattleOutcome) {
        battle = nil
        battleScene = nil
        if let rival, outcome == .victory { world.dismissAdventurer(rival.id) }
        rival = nil
        if let boss, outcome == .victory { session.defeatBoss(boss) }
        boss = nil
        if outcome == .defeat, let map = Content.shared.map(session.checkpoint.mapID) {
            // Fainted: wake up at the checkpoint.
            go(to: map, entry: session.checkpoint.entry)
        } else {
            world.resume()
        }
        session.save()
    }

    // MARK: Menus & dialogs

    func open(_ overlay: Overlay) {
        // Gift boxes aren't people: walking up and tapping opens them, no conversation.
        if case .npc(let id) = overlay, let npc = Content.shared.npc(id), npc.role == .chest {
            openChest(npc)
            return
        }
        self.overlay = overlay
        if case .npc = overlay { SoundEffects.shared.play(.talk) }
        if case .npc(let id) = overlay, let npc = Content.shared.npc(id), npc.role != .chest {
            session.postChat(npc.greeting, from: npc.name, kind: .npc)
            session.unreadChat = max(0, session.unreadChat - 1)
        }
        world.isInputLocked = true
        input.move = .zero
    }

    private func openChest(_ chest: NPCDef) {
        if session.isOpened(chest.id) {
            session.post("The \(chest.name.lowercased()) is empty.")
        } else if session.openChest(chest) != nil {
            session.save()
        } else {
            session.post("The ribbon is tied tight. Maybe someone in town knows who it's for.")
        }
    }

    /// A field spell cast from the Character screen. Bridge of Light carries you to your checkpoint.
    private func castField(_ skill: SkillDef) {
        guard battle == nil, skill.id == "bridge_of_light" else { return }
        let cost = GameSession.mpCost(of: skill, level: session.skillLevel(skill.id))
        guard session.data.hero.mp >= cost else {
            session.post("Not enough MP for \(skill.name).")
            return
        }
        let checkpoint = session.checkpoint
        guard let map = Content.shared.map(checkpoint.mapID) else { return }
        session.data.hero.mp -= cost
        overlay = nil
        session.post("A bridge of light carries you to \(session.checkpointName(checkpoint)).", .quest)
        SoundEffects.shared.play(.whoosh)
        go(to: map, entry: checkpoint.entry)
    }

    func closeOverlay() {
        SoundEffects.shared.play(.close, volume: 0.8)
        overlay = nil
        world.resume()
        session.save()
    }

    func talkToNearby() {
        world.talkToNearby()
    }

    func say(_ text: String) {
        world.heroSay(text)
    }
}

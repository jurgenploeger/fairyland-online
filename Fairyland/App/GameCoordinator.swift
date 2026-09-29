import Observation
import SpriteKit

enum MenuTab: String, CaseIterable, Identifiable {
    case character = "Character"
    case companions = "Companions"
    case bag = "Bag"
    case quests = "Quests"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .character: "person.fill"
        case .companions: "pawprint.fill"
        case .bag: "bag.fill"
        case .quests: "scroll.fill"
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
    }

    let session: GameSession
    let input: InputState
    private(set) var world: WorldScene
    private(set) var battle: BattleController?
    private(set) var overlay: Overlay?
    /// False until the first map frame has rendered (the loading curtain stays up until then).
    private(set) var isReady = false
    @ObservationIgnored private(set) var battleScene: BattleScene?

    init(session: GameSession) {
        let input = InputState()
        let map = Content.shared.map(session.data.mapID) ?? Content.shared.maps[0]
        self.session = session
        self.input = input
        world = WorldScene(map: map, session: session, input: input, entry: nil)
        wire(world)
    }

    /// The scene SpriteKit should show right now.
    var scene: SKScene { battle != nil ? (battleScene ?? world) : world }

    private func wire(_ scene: WorldScene) {
        scene.onFirstFrame = { [weak self] in self?.isReady = true }
        scene.onEncounter = { [weak self] encounters, backdrop in self?.startBattle(encounters, backdrop: backdrop) }
        scene.onTalk = { [weak self] npc in self?.open(.npc(npc.id)) }
        scene.onTravel = { [weak self] exit in self?.travel(through: exit) }
    }

    // MARK: Maps

    private func travel(through exit: MapDef.Exit) {
        guard let destination = Content.shared.map(exit.to) else {
            world.resume()
            return
        }
        loadMap(destination, entry: exit.edge.opposite)
    }

    private func loadMap(_ map: MapDef, entry: Edge?) {
        session.data.mapID = map.id
        if entry == nil { session.playerPosition = nil }
        let scene = WorldScene(map: map, session: session, input: input, entry: entry)
        wire(scene)
        input.move = .zero
        world = scene
        session.save()
    }

    // MARK: Battles

    func startBattle(_ encounters: MapDef.Encounters, backdrop: SKTexture? = nil) {
        let controller = BattleController.encounter(encounters, session: session)
        controller.onFinish = { [weak self] outcome in self?.endBattle(outcome) }
        battleScene = BattleScene(controller: controller, size: world.size, backdrop: backdrop)
        input.move = .zero
        battle = controller
        isReady = true
    }

    private func endBattle(_ outcome: BattleOutcome) {
        battle = nil
        battleScene = nil
        if outcome == .defeat, let town = Content.shared.map(session.data.mapID) {
            // Fainted: session.faint() already moved us to town.
            loadMap(town, entry: nil)
        } else {
            world.resume()
        }
        session.save()
    }

    // MARK: Menus & dialogs

    func open(_ overlay: Overlay) {
        self.overlay = overlay
        world.isInputLocked = true
        input.move = .zero
    }

    func closeOverlay() {
        overlay = nil
        world.resume()
        session.save()
    }

    func talkToNearby() {
        world.talkToNearby()
    }
}

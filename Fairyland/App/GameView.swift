import SwiftUI

/// The game screen: SpriteKit underneath, SwiftUI HUD and menus on top.
struct GameView: View {
    let coordinator: GameCoordinator
    /// The first-play tour of the HUD (see CoachMarks).
    @State private var touring = CoachMarks.shouldShow

    var body: some View {
        ZStack {
            SpriteKitView(scene: coordinator.scene)
                .ignoresSafeArea()

            if let battle = coordinator.battle {
                BattleView(controller: battle)
            } else {
                WorldHUD(coordinator: coordinator)
                switch coordinator.overlay {
                case .menu(let tab):
                    MenuView(session: coordinator.session, initialTab: tab, onClose: coordinator.closeOverlay, onQuitToTitle: coordinator.onQuitToTitle)
                case .worldMap:
                    MapOverlay(session: coordinator.session, onClose: coordinator.closeOverlay)
                case .chat:
                    ChatView(session: coordinator.session, onSay: coordinator.say, onClose: coordinator.closeOverlay)
                case .npc(let id):
                    if let npc = Content.shared.npc(id) {
                        NPCDialogView(npc: npc, session: coordinator.session, onClose: coordinator.closeOverlay, onFight: coordinator.fightBoss)
                    }
                case nil:
                    EmptyView()
                }
            }
        }
        .overlayPreferenceValue(CoachAnchors.self) { anchors in
            if touring, coordinator.isReady, coordinator.battle == nil, coordinator.overlay == nil {
                CoachMarksView(anchors: anchors) {
                    CoachMarks.markDone()
                    withAnimation(.easeOut(duration: 0.3)) { touring = false }
                }
                .transition(.opacity)
            }
        }
        .overlay {
            if !coordinator.isReady {
                if let name = coordinator.loadingMapName {
                    MapLoadingCard(mapName: name, progress: coordinator.loadProgress).transition(.opacity)
                } else {
                    LoadingCurtain(progress: coordinator.loadProgress).transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.4), value: coordinator.isReady)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

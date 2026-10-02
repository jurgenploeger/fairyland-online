import SwiftUI

/// The game screen: SpriteKit underneath, SwiftUI HUD and menus on top.
struct GameView: View {
    let coordinator: GameCoordinator

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
                    MapOverlay(overview: coordinator.world.overview(), session: coordinator.session, onClose: coordinator.closeOverlay)
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
        .overlay {
            if !coordinator.isReady {
                if let name = coordinator.loadingMapName {
                    MapLoadingCard(mapName: name).transition(.opacity)
                } else {
                    LoadingCurtain().transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.4), value: coordinator.isReady)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

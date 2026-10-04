import SwiftUI

/// The game screen: SpriteKit underneath, SwiftUI HUD and menus on top.
struct GameView: View {
    let coordinator: GameCoordinator
    /// The first-play tour of the HUD (see CoachMarks).
    @State private var touring = CoachMarks.shouldShow
    /// The chat window over a battle (the fight waits while you type).
    @State private var battleChat = false

    var body: some View {
        ZStack {
            SpriteKitView(scene: coordinator.scene)
                .ignoresSafeArea()

            if let battle = coordinator.battle {
                BattleView(controller: battle)
                // Chat stays one tap away mid-fight, under the battle log on the right.
                if !battleChat, battle.phase != .finished {
                    FLIconButton(icon: .talk, label: "Chat", size: 40, badge: coordinator.session.unreadChat > 0) {
                        coordinator.session.unreadChat = 0
                        battleChat = true
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 62)
                    .padding(.trailing, 14)
                }
                if battleChat {
                    ChatView(session: coordinator.session, onSay: coordinator.say) { battleChat = false }
                }
            } else {
                WorldHUD(coordinator: coordinator)
                switch coordinator.overlay {
                case .menu(let tab):
                    MenuView(session: coordinator.session, initialTab: tab, onClose: coordinator.closeOverlay, onQuitToTitle: coordinator.onQuitToTitle)
                case .worldMap:
                    MapOverlay(session: coordinator.session, onClose: coordinator.closeOverlay)
                case .trade(let adventurer):
                    TradeView(session: coordinator.session, adventurer: adventurer, onClose: coordinator.closeOverlay)
                case .chat:
                    ChatView(session: coordinator.session, onSay: coordinator.say, onClose: coordinator.closeOverlay)
                case .profile(let profile):
                    ProfileCard(session: coordinator.session, profile: profile, onClose: coordinator.closeOverlay)
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
        .onChange(of: coordinator.battle == nil) { battleChat = false }
        // The fight waits while you type, turn clock and all.
        .onChange(of: battleChat) { coordinator.battle?.holdTurnClock(battleChat, for: "chat") }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

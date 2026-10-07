import SwiftUI
import UIKit

@main
struct FairylandApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Load the player's language before any text is made: the title screen's default hero name
        // (`L("Hero")`) is set before anything else would have woken the Localizer, so it stayed English.
        _ = Localizer.shared
        DebugLaunch.applyLanguage()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        DebugLaunch.forcesLandscape ? .landscape : .allButUpsideDown
    }
}

/// Title screen until a game is started or continued.
struct RootView: View {
    @State private var coordinator: GameCoordinator?
    @State private var pending: GameSession?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if DebugLaunch.holdsLoadingCurtain {
                // Debug `curtain`: the loading screen, held part-way (screenshots of it).
                LoadingCurtain(progress: 0.41)
            } else if let coordinator {
                GameView(coordinator: coordinator)
            } else if let pending {
                LoadingCurtain()
                    .task {
                        // Let the curtain draw before the (heavier) map build starts.
                        try? await Task.sleep(for: .milliseconds(60))
                        let game = GameCoordinator(session: pending)
                        game.onQuitToTitle = { quitToTitle() }
                        coordinator = game
                    }
            } else {
                TitleView { session in
                    pending = session
                }
            }
        }
        .onAppear {
            if coordinator == nil, let session = DebugLaunch.session() {
                let coordinator = GameCoordinator(session: session)
                self.coordinator = coordinator
                DebugLaunch.apply(to: coordinator)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: coordinator?.session.save()
            case .active: MusicPlayer.shared.resume()
            default: break
            }
        }
    }

    /// Leaves the game for the title screen (Settings → Back to title; the game is already saved).
    private func quitToTitle() {
        coordinator = nil
        pending = nil
    }
}

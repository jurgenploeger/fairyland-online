import SwiftUI

/// Sound, feel and game options. A tab in the menu, and a panel on the title screen (where
/// there's no game to save or leave, so `session` is nil).
struct SettingsView: View {
    var session: GameSession?
    var onQuitToTitle: (() -> Void)?

    @AppStorage(GameSettings.musicVolumeKey) private var musicVolume = 1.0
    @AppStorage(GameSettings.soundVolumeKey) private var soundVolume = 1.0
    @AppStorage(GameSettings.footstepsKey) private var footsteps = true
    @AppStorage(GameSettings.hapticsKey) private var haptics = true
    @AppStorage(GameSettings.commandCompanionKey) private var commandCompanion = true
    @State private var music = MusicPlayer.shared
    @State private var justSaved = false
    @State private var confirmQuit = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Sound", icon: .volume) {
                VolumeRow(title: "Music", icon: music.isMuted ? .musicOff : .music, value: $musicVolume) {}
                    .onChange(of: musicVolume) { _, volume in MusicPlayer.shared.setVolume(volume) }
                Toggle(isOn: Binding(get: { !music.isMuted }, set: { on in if on == music.isMuted { music.toggleMute() } })) {
                    Text("Play music")
                }
                VolumeRow(title: "Sound effects", icon: .volume, value: $soundVolume) {
                    SoundEffects.shared.play(.coins)
                }
                Toggle("Footsteps", isOn: $footsteps)
            }

            section("Feel", icon: .tap) {
                Toggle("Vibration on hits and rewards", isOn: $haptics)
                    .onChange(of: haptics) { _, on in if on { Haptics.impact(.medium) } }
            }

            section("Battle", icon: .paw) {
                Toggle("Choose your companion's moves", isOn: $commandCompanion)
                Text("After your own choice, tell your companion what to do. Off, it fights on its own.")
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
            }

            if let session {
                section("Game", icon: .book) {
                    HStack(spacing: 10) {
                        Button {
                            session.save()
                            SoundEffects.shared.play(.questAccept, volume: 0.6)
                            justSaved = true
                        } label: {
                            Label(justSaved ? "Saved" : "Save now", icon: justSaved ? .check : .checkCircle)
                        }
                        .buttonStyle(PixelButtonStyle(compact: true))
                        if let onQuitToTitle {
                            Button {
                                confirmQuit = true
                            } label: {
                                Label("Back to title", icon: .arrowLeft)
                            }
                            .buttonStyle(PixelButtonStyle(compact: true))
                            .alert("Back to the title screen?", isPresented: $confirmQuit) {
                                Button("Save and leave") {
                                    session.save()
                                    onQuitToTitle()
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("Your game is saved first, so you can continue where you left off.")
                            }
                        }
                    }
                    Text("Your progress also saves by itself every few seconds.")
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.dim)
                }
            }

            if let session, let onQuitToTitle {
                section("Danger zone", icon: .close) {
                    Text("Deleting a game can't be undone.")
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.dim)
                    Button {
                        confirmDelete = true
                    } label: {
                        Label("Delete this game", icon: .close)
                    }
                    .buttonStyle(PixelButtonStyle(tint: Color(red: 0.9, green: 0.35, blue: 0.35), compact: true))
                    .alert("Delete \(session.data.hero.name)'s game?", isPresented: $confirmDelete) {
                        Button("Delete for good", role: .destructive) {
                            session.deleteGame()
                            onQuitToTitle()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("\(session.data.hero.name), level \(session.data.hero.level), and everything they carry will be gone for good.")
                    }
                }
            }

            section("About", icon: .star) {
                Text("Fairyland \(Self.version)")
                Text("A tribute to Fairyland Online (2007). Art made with Retro Diffusion, icons by Iconaut (MIT). Music and sound effects are synthesized in the game.")
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(HUDStyle.font(12))
        .foregroundStyle(HUDStyle.cream)
        .tint(HUDStyle.gold)
    }

    private func section<Content: View>(_ title: String, icon: GameIcon, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, icon: icon)
                .font(HUDStyle.font(14))
                .foregroundStyle(HUDStyle.gold)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// A labelled volume slider that plays a preview when you let go.
private struct VolumeRow: View {
    let title: String
    let icon: GameIcon
    @Binding var value: Double
    let onRelease: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            IconImage(icon, size: 14)
                .frame(width: 18)
            Text(title)
                .frame(width: 110, alignment: .leading)
            Slider(value: $value, in: 0...1, onEditingChanged: { editing in
                if !editing { onRelease() }
            })
            Text("\(Int((value * 100).rounded()))%")
                .font(HUDStyle.font(10))
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) volume")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

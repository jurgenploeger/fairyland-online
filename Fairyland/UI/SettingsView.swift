import SwiftUI
import UniformTypeIdentifiers

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
    @AppStorage(GameSettings.turnTimerKey) private var turnTimer = 10.0
    @State private var music = MusicPlayer.shared
    @State private var justSaved = false
    @State private var confirmQuit = false
    @State private var confirmDelete = false
    @State private var backup: SaveBackup?
    @State private var exporting = false
    @State private var backedUp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(L("Language"), icon: .globe) {
                LanguageList()
            }

            section(L("Sound"), icon: .volume) {
                VolumeRow(title: L("Music"), icon: music.isMuted ? .musicOff : .music, value: $musicVolume) {}
                    .onChange(of: musicVolume) { _, volume in MusicPlayer.shared.setVolume(volume) }
                Toggle(isOn: Binding(get: { !music.isMuted }, set: { on in if on == music.isMuted { music.toggleMute() } })) {
                    Text(L("Play music"))
                }
                VolumeRow(title: L("Sound effects"), icon: .volume, value: $soundVolume) {
                    SoundEffects.shared.play(.coins)
                }
                Toggle(L("Footsteps"), isOn: $footsteps)
            }

            section(L("Feel"), icon: .tap) {
                Toggle(L("Vibration on hits and rewards"), isOn: $haptics)
                    .onChange(of: haptics) { _, on in if on { Haptics.impact(.medium) } }
            }

            section(L("Battle"), icon: .paw) {
                Toggle(L("Choose your companion's moves"), isOn: $commandCompanion)
                Text(L("After your own choice, tell your companion what to do. Off, it fights on its own."))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
                TurnTimerRow(seconds: $turnTimer)
                Text(L("How long you have to pick each move before your hero attacks on their own. With VoiceOver or Switch Control on, there's no clock."))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let session {
                section(L("Game"), icon: .book) {
                    HStack(spacing: 10) {
                        Button {
                            session.save()
                            SoundEffects.shared.play(.questAccept, volume: 0.6)
                            justSaved = true
                        } label: {
                            Label(justSaved ? L("Saved") : L("Save now"), icon: justSaved ? .check : .checkCircle)
                        }
                        .buttonStyle(PixelButtonStyle(compact: true))
                        if let onQuitToTitle {
                            Button {
                                confirmQuit = true
                            } label: {
                                Label(L("Back to title"), icon: .arrowLeft)
                            }
                            .buttonStyle(PixelButtonStyle(compact: true))
                            .alert(L("Back to the title screen?"), isPresented: $confirmQuit) {
                                Button(L("Save and leave")) {
                                    session.save()
                                    onQuitToTitle()
                                }
                                Button(L("Cancel"), role: .cancel) {}
                            } message: {
                                Text(L("Your game is saved first, so you can continue where you left off."))
                            }
                        }
                    }
                    Text(L("Your progress also saves by itself every few seconds."))
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.dim)
                    Button {
                        session.save()
                        if let contents = try? JSONEncoder().encode(session.data) {
                            backup = SaveBackup(contents: contents)
                            exporting = true
                        }
                    } label: {
                        Label(backedUp ? L("Backed up") : L("Back up to Files"), icon: backedUp ? .check : .arrowUp)
                    }
                    .buttonStyle(PixelButtonStyle(compact: true))
                    .fileExporter(isPresented: $exporting, document: backup, contentType: .json,
                                  defaultFilename: SaveBackup.fileName(for: session.data)) { result in
                        if case .success = result { backedUp = true }
                    }
                    Text(L("Keep a copy in Files or iCloud Drive, for a new phone or in case the app is deleted. Bring it back with Import a backup on the title screen."))
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let session, let onQuitToTitle {
                section(L("Danger zone"), icon: .close) {
                    Text(L("Deleting a game can't be undone."))
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.dim)
                    Button {
                        confirmDelete = true
                    } label: {
                        Label(L("Delete this game"), icon: .close)
                    }
                    .buttonStyle(PixelButtonStyle(tint: Color(red: 0.9, green: 0.35, blue: 0.35), compact: true))
                    .alert(L("Delete {hero}'s game?", ["hero": session.data.hero.name]), isPresented: $confirmDelete) {
                        Button(L("Delete for good"), role: .destructive) {
                            session.deleteGame()
                            onQuitToTitle()
                        }
                        Button(L("Cancel"), role: .cancel) {}
                    } message: {
                        Text(L("{hero}, level {level}, and everything they carry will be gone for good.", ["hero": session.data.hero.name, "level": session.data.hero.level]))
                    }
                }
            }

            section(L("About"), icon: .star) {
                Text(L("Storyleaf {version}", ["version": Self.version]))
                Text(L("Art made with Retro Diffusion, icons by Iconaut (MIT). Music and sound effects are synthesized in the game."))
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

/// Time to choose in a fight: Off, 10, 20 or 30 seconds, as a row of pills.
private struct TurnTimerRow: View {
    @Binding var seconds: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                IconImage(.sword, size: 14)
                    .frame(width: 18)
                Text(L("Time to choose"))
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 6) {
                ForEach(GameSettings.turnTimerChoices, id: \.self) { choice in
                    let chosen = seconds == choice
                    Button {
                        seconds = choice
                    } label: {
                        Text(choice == 0 ? L("Off") : L("{seconds} s", ["seconds": Int(choice)]))
                            .font(HUDStyle.font(11))
                            .foregroundStyle(chosen ? HUDStyle.ink : HUDStyle.cream)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(Capsule().fill(chosen ? HUDStyle.gold : HUDStyle.ink.opacity(0.5)))
                            .overlay(Capsule().strokeBorder(HUDStyle.cream.opacity(chosen ? 0 : 0.4), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
        }
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
        .accessibilityLabel(L("{title} volume", ["title": title]))
        .accessibilityValue(L("{percent} percent", ["percent": Int((value * 100).rounded())]))
    }
}

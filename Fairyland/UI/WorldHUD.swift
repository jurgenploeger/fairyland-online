import SwiftUI

/// On-map HUD in Fairyland Online's style: H/M/P bars with a level badge and the calendar
/// plate top-left, a framed minimap top-right, the system log, joystick bottom-left and
/// a glossy toolbar bottom-right.
struct WorldHUD: View {
    let coordinator: GameCoordinator

    private var session: GameSession { coordinator.session }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 6) {
                StatusCluster(session: session)
                    .coachTarget(.status)
                CalendarPlate(session: session)
                SystemLog(lines: session.log)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)

            VStack(alignment: .trailing, spacing: 6) {
                MinimapWindow(
                    image: coordinator.world.minimap,
                    name: session.mapName,
                    cell: session.mapCell,
                    columns: coordinator.world.def.width,
                    rows: coordinator.world.def.height,
                    onOpen: { coordinator.open(.worldMap) }
                )
                .coachTarget(.minimap)
                HStack(spacing: 6) {
                    FLIconButton(icon: .settings, label: "Settings", size: 40) {
                        coordinator.open(.menu(.settings))
                    }
                    FLIconButton(icon: .talk, label: "Chat", size: 40, badge: session.unreadChat > 0) {
                        coordinator.open(.chat)
                    }
                    .coachTarget(.chat)
                }
                SavedBadge(lastSaved: session.lastSaved)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            JoystickView(input: coordinator.input)
                .coachTarget(.joystick)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 8)
                .padding(.bottom, 10)

            VStack(alignment: .trailing, spacing: 10) {
                if let id = session.nearbyNPC, let npc = Content.shared.npc(id) {
                    Button {
                        coordinator.talkToNearby()
                    } label: {
                        if npc.role == .chest {
                            Label("Open \(npc.name)", icon: .gift)
                        } else {
                            Label("Talk to \(npc.name)", icon: .talk)
                        }
                    }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                    .transition(.scale(scale: 0.7, anchor: .bottomTrailing).combined(with: .opacity))
                } else if let adventurer = session.nearbyAdventurer {
                    AdventurerCard(coordinator: coordinator, adventurer: adventurer)
                        .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
                }
                HStack(spacing: 7) {
                    // Settings has its own button up top, next to Chat.
                    ForEach(MenuTab.allCases.filter { $0 != .settings }) { tab in
                        FLIconButton(icon: tab.icon, label: tab.rawValue, badge: badge(for: tab)) {
                            coordinator.open(.menu(tab))
                        }
                    }
                }
                .coachTarget(.toolbar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.bottom, 14)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: session.nearbyNPC)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: session.nearbyAdventurer?.id)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func badge(for tab: MenuTab) -> Bool {
        switch tab {
        case .character: session.canChooseClass || session.unspentSkillPoints > 0
        case .quests: session.activeQuests.contains { session.status(of: $0) == .ready }
        case .bag: session.count(of: "pet_egg") > 0
        case .companions, .settings: false
        }
    }
}

/// H / M / P bars (hero HP, MP, companion HP) with Fairyland's round level badge.
private struct StatusCluster: View {
    let session: GameSession

    var body: some View {
        let hero = session.data.hero
        let stats = session.heroStats
        let pet = session.activePet
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(hero.name).font(HUDStyle.mono(11)).foregroundStyle(HUDStyle.nameYellow)
                    Text(session.heroClass.name).font(HUDStyle.mono(9)).foregroundStyle(HUDStyle.dim)
                }
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                TaggedBar(tag: "H", value: hero.hp, maximum: stats.hp, color: HUDStyle.hp)
                TaggedBar(tag: "M", value: hero.mp, maximum: stats.mp, color: HUDStyle.mp)
                if let pet {
                    TaggedBar(tag: "P", value: pet.hp, maximum: session.stats(of: pet).hp, color: HUDStyle.pet)
                }
            }
            LevelBadge(level: hero.level, glowing: session.canChooseClass || session.unspentSkillPoints > 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: 214)
        .background(HUDStyle.panel)
    }
}

private struct TaggedBar: View {
    let tag: String
    let value: Int
    let maximum: Int
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            StatBar(label: "", value: value, maximum: maximum, color: color, height: 10)
            Text(tag)
                .font(HUDStyle.mono(9))
                .foregroundStyle(.white)
                .frame(width: 14, height: 12)
                .background(RoundedRectangle(cornerRadius: 3).fill(HUDStyle.frameDark))
        }
    }
}

/// Fairyland's glossy "LEVEL UP" badge; glows when there's something to spend.
private struct LevelBadge: View {
    let level: Int
    let glowing: Bool
    @State private var pulse = false

    var body: some View {
        VStack(spacing: -2) {
            Text("LV").font(HUDStyle.mono(8))
            Text("\(level)").font(HUDStyle.font(17))
        }
        .foregroundStyle(.white)
        .shadow(color: HUDStyle.frameDark, radius: 0, x: 1, y: 1)
        .frame(width: 44, height: 44)
        .background(
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.7, green: 0.9, blue: 1), Color(red: 0.25, green: 0.55, blue: 0.9), HUDStyle.frameDark], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 30))
                .overlay(Circle().strokeBorder(HUDStyle.bevel, lineWidth: 2.5))
        )
        .shadow(color: glowing ? HUDStyle.gold.opacity(pulse ? 1 : 0.3) : .clear, radius: glowing ? 8 : 0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// The tan calendar plate with a sun or moon, and the EXP bar underneath.
private struct CalendarPlate: View {
    let session: GameSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let moment = GameClock.moment(at: context.date, since: session.data.startedAt)
            let hero = session.data.hero
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    IconImage(moment.isDaytime ? .sun : .moon, size: 14)
                        .foregroundStyle(moment.isDaytime ? HUDStyle.orange : Color(red: 0.35, green: 0.35, blue: 0.75))
                    Text(moment.text)
                        .font(HUDStyle.mono(10))
                        .foregroundStyle(HUDStyle.plateDark)
                    Spacer(minLength: 0)
                    IconImage(.coins, size: 12).foregroundStyle(HUDStyle.gold)
                    Text("\(session.data.gold)")
                        .font(HUDStyle.mono(10))
                        .foregroundStyle(HUDStyle.plateDark)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(HUDStyle.plateBackground)
                HStack(spacing: 3) {
                    Text("EXP").font(HUDStyle.mono(8)).foregroundStyle(.white)
                    StatBar(label: "", value: hero.exp, maximum: GameSession.expToNext(level: hero.level), color: HUDStyle.exp, height: 7, showsNumbers: false)
                }
                .padding(.horizontal, 4)
            }
            .frame(width: 214)
        }
    }
}

/// Fairyland's yellow system messages, fading after a few seconds.
private struct SystemLog: View {
    let lines: [GameSession.LogLine]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 1) {
                ForEach(lines.filter { context.date.timeIntervalSince($0.time) < 12 }.suffix(4)) { line in
                    Text(line.text)
                        .font(HUDStyle.mono(10))
                        .foregroundStyle(color(for: line.kind))
                        .shadow(color: .black, radius: 0, x: 1, y: 1)
                        .transition(.opacity)
                }
            }
            .frame(width: 240, alignment: .leading)
            .animation(.easeOut(duration: 0.3), value: lines.count)
        }
    }

    private func color(for kind: GameSession.LogLine.Kind) -> Color {
        switch kind {
        case .system: HUDStyle.nameYellow
        case .quest: Color(red: 0.55, green: 0.95, blue: 1)
        case .battle: .white
        case .reward: HUDStyle.green
        }
    }
}

/// A framed minimap window around the hero, with Fairyland's coordinates plate. Tap for the full map.
private struct MinimapWindow: View {
    let image: UIImage
    let name: String
    let cell: GridPoint
    let columns: Int
    let rows: Int
    let onOpen: () -> Void
    @AppStorage("minimapCollapsed") private var collapsed = false

    private let width: CGFloat = 150
    private let height: CGFloat = 100
    private let zoom: CGFloat = 5
    /// The rotated map layer must be big enough to cover the window's corners.
    private let layer: CGFloat = 420

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(name).font(HUDStyle.mono(10)).lineLimit(1)
                Spacer(minLength: 2)
                Button {
                    MusicPlayer.shared.toggleMute()
                } label: {
                    IconImage(MusicPlayer.shared.isMuted ? .musicOff : .music, size: 16)
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 20)
                }
                .accessibilityLabel(MusicPlayer.shared.isMuted ? "Turn music on" : "Turn music off")
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { collapsed.toggle() }
                } label: {
                    IconImage(collapsed ? .chevronDown : .close, size: 14)
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(HUDStyle.orange).overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1)))
                }
                .accessibilityLabel(collapsed ? "Show minimap" : "Hide minimap")
            }
            .foregroundStyle(.white)
            .shadow(color: HUDStyle.frameDark, radius: 0, x: 1, y: 1)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 3)
            .background(LinearGradient(colors: [HUDStyle.frameLight, HUDStyle.frameMid, HUDStyle.frameDark], startPoint: .top, endPoint: .bottom))

            if !collapsed {
                ZStack {
                    Color(red: 0.05, green: 0.12, blue: 0.22)
                    // Turned and squashed like the world, so "up" on the minimap is "up" on screen.
                    // The map rides in an overlay: an image bigger than the layer (maps over 84 tiles
                    // wide) must not resize or re-centre it, or the hero's cell drifts off the marker.
                    Color.clear
                        .frame(width: layer, height: layer)
                        .overlay(alignment: .topLeading) {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: CGFloat(columns) * zoom, height: CGFloat(rows) * zoom)
                                .offset(
                                    x: layer / 2 - (CGFloat(cell.col) + 0.5) * zoom,
                                    y: layer / 2 - (CGFloat(rows - 1 - cell.row) + 0.5) * zoom
                                )
                        }
                        .rotationEffect(.degrees(-45))
                        .scaleEffect(x: 1, y: 0.5)
                    Circle()
                        .fill(HUDStyle.gold)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
                }
                .frame(width: width, height: height)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                .accessibilityLabel("Open map")
                .accessibilityAddTraits(.isButton)

                Text("\(cell.col) : \(rows - 1 - cell.row)")
                    .font(HUDStyle.mono(10))
                    .foregroundStyle(HUDStyle.plateDark)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(HUDStyle.plateBackground)
                    .padding(4)
            }
        }
        .frame(width: width)
        .background(Color(red: 0.08, green: 0.2, blue: 0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUDStyle.bevel, lineWidth: 2.5))
        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
    }
}

/// Flashes briefly whenever the game autosaves.
private struct SavedBadge: View {
    let lastSaved: Date?
    @State private var visible = false

    var body: some View {
        Label("Saved", icon: .checkCircle, size: 13)
            .font(HUDStyle.font(10))
            .foregroundStyle(HUDStyle.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(HUDStyle.ink.opacity(0.8)))
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
            .onChange(of: lastSaved) {
                withAnimation(.easeOut(duration: 0.2)) { visible = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(.easeIn(duration: 0.4)) { visible = false }
                }
            }
            .accessibilityHidden(true)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 8))
            configuration.title
        }
    }
}

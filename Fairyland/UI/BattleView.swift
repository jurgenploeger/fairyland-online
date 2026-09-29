import SwiftUI

/// Battle HUD: log line and party status on top, a round command wheel bottom-right,
/// results at the end.
struct BattleView: View {
    let controller: BattleController

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                Text(controller.message)
                    .font(HUDStyle.font(13))
                    .foregroundStyle(HUDStyle.cream)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 520)
                    .background(Capsule().fill(HUDStyle.ink.opacity(0.88)).overlay(Capsule().strokeBorder(HUDStyle.cream.opacity(0.8), lineWidth: 2)))

                HStack {
                    PartyStatus(party: controller.party)
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .allowsHitTesting(false)

            commandArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 14)
                .padding(.bottom, 14)
                .allowsHitTesting(controller.phase != .animating)

            if controller.phase == .finished, let result = controller.result {
                ResultPanel(result: result, onContinue: controller.leave)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: controller.phase)
    }

    @ViewBuilder
    private var commandArea: some View {
        switch controller.phase {
        case .command:
            CommandWheel(controller: controller)
                .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
        case .skills:
            ChoiceCard(title: "Skills", icon: "sparkles", onBack: controller.back) {
                if controller.skills.isEmpty {
                    Text("No skills yet. You'll learn Bash at level 2.").font(HUDStyle.font(12)).foregroundStyle(HUDStyle.dim)
                }
                ForEach(controller.skills) { skill in
                    let affordable = (controller.hero?.mp ?? 0) >= controller.cost(of: skill)
                    ChoiceRow(action: { controller.useSkill(skill) }, enabled: affordable) {
                        Text(skill.name)
                        Text("Lv\(controller.level(of: skill))").font(HUDStyle.mono(10)).foregroundStyle(HUDStyle.frameDark)
                        if let element = skill.element { ElementBadge(element: element) }
                        Spacer()
                        Text("\(controller.cost(of: skill)) MP").foregroundStyle(HUDStyle.mp)
                    }
                }
            }
            .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
        case .items:
            ChoiceCard(title: "Items", icon: "bag.fill", onBack: controller.back) {
                if controller.items.isEmpty {
                    Text("Your bag is empty.").font(HUDStyle.font(12)).foregroundStyle(HUDStyle.dim)
                }
                ForEach(controller.items) { item in
                    ChoiceRow(action: { controller.useItem(item) }, enabled: true) {
                        Text(item.name)
                        Spacer()
                        Text("×\(controller.session.count(of: item.id))").foregroundStyle(HUDStyle.dim)
                    }
                }
            }
            .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
        case .target:
            HStack(spacing: 10) {
                Image(systemName: "hand.tap.fill").foregroundStyle(HUDStyle.gold)
                Text(controller.prompt).font(HUDStyle.font(13))
                Button("Cancel", action: controller.back)
                    .buttonStyle(PixelButtonStyle(compact: true))
            }
            .foregroundStyle(HUDStyle.cream)
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Capsule().fill(HUDStyle.ink.opacity(0.9)).overlay(Capsule().strokeBorder(HUDStyle.gold.opacity(0.8), lineWidth: 2)))
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .animating, .finished:
            EmptyView()
        }
    }
}

// MARK: - Command wheel

/// A big Attack button in the corner with a few round buttons curving around it.
/// Less-used commands hide behind "More"; Capture only appears when a monster is weak enough.
private struct CommandWheel: View {
    let controller: BattleController
    @State private var showMore = false

    private struct Command: Identifiable {
        let id: String
        let icon: String
        let tint: RoundCommandButton.Tint
        let action: () -> Void
    }

    private let size: CGFloat = 230
    private let mainSize: CGFloat = 88
    private let satelliteSize: CGFloat = 58
    private let orbit: CGFloat = 112

    private var satellites: [Command] {
        if showMore {
            return [
                Command(id: "Items", icon: "bag.fill", tint: .normal) { controller.openItems() },
                Command(id: "Guard", icon: "shield.fill", tint: .normal) { controller.defend() },
                Command(id: "Run", icon: "figure.run", tint: .normal) { controller.escape() },
                Command(id: "Back", icon: "xmark", tint: .quiet) { showMore = false },
            ]
        }
        var commands = [Command(id: "Skills", icon: "sparkles", tint: .normal) { controller.openSkills() }]
        if controller.canCapture {
            commands.append(Command(id: "Capture", icon: "heart.fill", tint: .special) { controller.capture() })
        }
        commands.append(Command(id: "More", icon: "ellipsis", tint: .quiet) { showMore = true })
        return commands
    }

    var body: some View {
        let main = CGPoint(x: size - mainSize / 2 - 4, y: size - mainSize / 2 - 4)
        let items = satellites
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, command in
                // Spread from straight left (180°) to straight up (270°).
                let angle = items.count == 1 ? 225.0 : 180 + 90 * Double(index) / Double(items.count - 1)
                let radians = angle * .pi / 180
                RoundCommandButton(title: command.id, icon: command.icon, size: satelliteSize, tint: command.tint, action: command.action)
                    .position(x: main.x + orbit * cos(radians), y: main.y + orbit * sin(radians))
                    .transition(.scale(scale: 0.2, anchor: .bottomTrailing).combined(with: .opacity))
            }
            RoundCommandButton(title: "Attack", icon: "bolt.fill", size: mainSize, tint: .primary) { controller.attack() }
                .position(main)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.38, dampingFraction: 0.68), value: showMore)
        .animation(.spring(response: 0.38, dampingFraction: 0.68), value: controller.canCapture)
    }
}

struct RoundCommandButton: View {
    enum Tint {
        case primary, normal, special, quiet
    }

    let title: String
    let icon: String
    let size: CGFloat
    let tint: Tint
    let action: () -> Void

    @State private var pulse = false

    private var colors: [Color] {
        switch tint {
        case .primary: [Color(red: 1, green: 0.62, blue: 0.45), Color(red: 0.9, green: 0.3, blue: 0.3)]
        case .special: [Color(red: 1, green: 0.92, blue: 0.55), Color(red: 0.98, green: 0.68, blue: 0.2)]
        case .normal: [.white, HUDStyle.cream, Color(red: 0.86, green: 0.78, blue: 0.64)]
        case .quiet: [Color(red: 0.42, green: 0.36, blue: 0.56), HUDStyle.ink]
        }
    }

    private var foreground: Color {
        switch tint {
        case .primary, .quiet: .white
        case .normal, .special: HUDStyle.ink
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.33, weight: .heavy))
                if size >= 80 {
                    Text(title).font(HUDStyle.font(12))
                }
            }
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(RadialGradient(colors: colors, center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.75))
                    .overlay(Circle().strokeBorder(.white.opacity(tint == .quiet ? 0.35 : 0.75), lineWidth: 2))
                    .overlay(
                        Ellipse().fill(.white.opacity(0.35))
                            .frame(width: size * 0.5, height: size * 0.2)
                            .offset(y: -size * 0.3)
                    )
            )
            .shadow(color: tint == .special ? HUDStyle.gold.opacity(pulse ? 0.9 : 0.3) : .black.opacity(0.4),
                    radius: tint == .special ? (pulse ? 12 : 5) : 4, x: 0, y: tint == .special ? 0 : 4)
        }
        .buttonStyle(RoundPressStyle())
        .overlay(alignment: .bottom) {
            if size < 80 {
                Text(title)
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.cream)
                    .shadow(color: .black, radius: 0, x: 1, y: 1)
                    .fixedSize()
                    .offset(y: 15)
            }
        }
        .onAppear {
            guard tint == .special else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel(title)
    }
}

private struct RoundPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Lists

private struct ChoiceCard<Content: View>: View {
    let title: String
    let icon: String
    let onBack: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(HUDStyle.font(14))
                    .foregroundStyle(HUDStyle.gold)
                Spacer()
                Button(action: onBack) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(HUDStyle.cream)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .accessibilityLabel("Back")
            }
            // Hug the rows; long lists scroll instead of growing past the scene.
            ViewThatFits(in: .vertical) {
                VStack(spacing: 6, content: content)
                ScrollView { VStack(spacing: 6, content: content) }
            }
            .frame(maxHeight: 220)
        }
        .padding(12)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(HUDStyle.ink.opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(HUDStyle.cream.opacity(0.8), lineWidth: 2))
        )
    }
}

private struct ChoiceRow<Label: View>: View {
    let action: () -> Void
    let enabled: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6, content: label)
                .font(HUDStyle.font(13))
                .foregroundStyle(HUDStyle.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(enabled ? HUDStyle.cream : HUDStyle.dim))
        }
        .buttonStyle(RoundPressStyle())
    }
}

// MARK: - Status & results

private struct PartyStatus: View {
    let party: [Combatant]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(party) { fighter in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(fighter.name)  Lv \(fighter.level)")
                        .font(HUDStyle.font(11))
                        .foregroundStyle(fighter.isHero ? HUDStyle.cream : HUDStyle.green)
                    StatBar(label: "HP", value: fighter.hp, maximum: fighter.stats.hp, color: HUDStyle.hp, labelWidth: 20)
                    if fighter.isHero {
                        StatBar(label: "MP", value: fighter.mp, maximum: fighter.stats.mp, color: HUDStyle.mp, labelWidth: 20)
                    }
                }
                .opacity(fighter.isAlive ? 1 : 0.45)
            }
        }
        .frame(width: 170)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(HUDStyle.ink.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(HUDStyle.cream.opacity(0.7), lineWidth: 2))
        )
    }
}

private struct ResultPanel: View {
    let result: BattleResult
    let onContinue: () -> Void

    private var title: String {
        switch result.outcome {
        case .victory: "Victory!"
        case .defeat: "Defeated…"
        case .escaped: "Escaped"
        case .ongoing: ""
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 10) {
                Text(title)
                    .font(HUDStyle.font(26))
                    .foregroundStyle(result.outcome == .victory ? HUDStyle.gold : HUDStyle.cream)
                ForEach(Array(result.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(HUDStyle.font(13))
                        .foregroundStyle(HUDStyle.cream)
                        .multilineTextAlignment(.center)
                }
                Button("Continue", action: onContinue)
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                    .padding(.top, 6)
            }
            .padding(22)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(HUDStyle.ink.opacity(0.92))
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(HUDStyle.cream.opacity(0.85), lineWidth: 2))
            )
            .padding(20)
        }
    }
}

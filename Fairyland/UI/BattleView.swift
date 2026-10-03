import SwiftUI

/// Battle HUD: the log line on top, the commands bottom-right, results at the end.
/// Names, levels, HP and the hero's MP sit on the fighters themselves.
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
                ResultPanel(result: result, session: controller.session, onContinue: controller.leave)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: controller.phase)
    }

    @ViewBuilder
    private var commandArea: some View {
        switch controller.phase {
        case .command:
            CommandPad(controller: controller)
                .padding(.top, 64)   // clear of the log line
                .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
        case .skills:
            ChoiceCard(title: "Skills", icon: .sparkles, onBack: controller.back) {
                if controller.skills.isEmpty {
                    EmptyNote(controller.skills.isEmpty && !controller.session.learnableSkills.isEmpty
                              ? "No skills yet.\nLearn one in the Character menu."
                              : controller.session.skillHint)
                }
                ForEach(controller.skills) { skill in
                    let affordable = (controller.hero?.mp ?? 0) >= controller.cost(of: skill)
                    let pinned = controller.session.isPinned(skill.id)
                    HStack(spacing: 6) {
                        ChoiceRow(action: { controller.useSkill(skill) }, enabled: affordable) {
                            SkillIcon(skill: skill, size: 26)
                            Text(skill.name)
                            Text("Lv\(controller.level(of: skill))").font(HUDStyle.mono(10)).foregroundStyle(HUDStyle.frameDark)
                            if let element = skill.element { ElementBadge(element: element) }
                            Spacer()
                            Text("\(controller.cost(of: skill)) MP").foregroundStyle(HUDStyle.mp)
                        }
                        // Pin it next to Attack.
                        Button { controller.togglePin(skill) } label: {
                            IconImage(pinned ? .star : .starOutline, size: 18)
                                .foregroundStyle(pinned ? HUDStyle.gold : HUDStyle.cream)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(HUDStyle.ink.opacity(0.85)))
                        }
                        .buttonStyle(RoundPressStyle())
                        .accessibilityLabel(pinned ? "Unpin \(skill.name)" : "Pin \(skill.name) to the quick bar")
                    }
                }
                if !controller.skills.isEmpty {
                    Text("Tap the star to pin up to \(GameSession.maxPinnedSkills) skills next to Attack.")
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.cream.opacity(0.8))
                }
            }
            .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
        case .items:
            ChoiceCard(title: "Items", icon: .backpack, onBack: controller.back) {
                if controller.items.isEmpty {
                    EmptyNote("Your bag is empty.\nShops in town sell potions.")
                }
                ForEach(controller.items) { item in
                    ChoiceRow(action: { controller.useItem(item) }, enabled: true) {
                        ItemIcon(item: item, size: 26)
                        Text(item.name)
                        Spacer()
                        Text("×\(controller.session.count(of: item.id))").foregroundStyle(HUDStyle.frameDark)
                    }
                }
            }
            .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
        case .target:
            HStack(spacing: 10) {
                IconImage(.tap, size: 18).foregroundStyle(HUDStyle.gold)
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

// MARK: - Commands

/// A big Attack button in the corner, and right beside it a column of round buttons built from
/// the bottom up: More, then Skills, then whatever else turns up (Capture when a monster is weak
/// enough, Items when someone is low on HP, pinned skills). Less-used commands hide behind More.
private struct CommandPad: View {
    let controller: BattleController
    @State private var showMore = false

    private let mainSize: CGFloat = 88
    private let buttonSize: CGFloat = 56

    var body: some View {
        let lowHP = controller.needsHealing
        HStack(alignment: .bottom, spacing: 14) {
            // Bottom to top.
            BottomUpColumns(maxRows: 4) {
                RoundCommandButton(title: showMore ? "Close" : "More", icon: showMore ? .close : .more, size: buttonSize, tint: .quiet) {
                    showMore.toggle()
                }
                if showMore {
                    if !lowHP {
                        command("Items", .backpack) { controller.openItems() }
                    }
                    command("Guard", .shield) { controller.defend() }
                    command("Run", .wind) { controller.escape() }
                } else {
                    command("Skills", .sparkles) { controller.openSkills() }
                    if lowHP {
                        command("Items", .heartPlus, tint: .heal) { controller.openItems() }
                    }
                    if controller.canCapture {
                        command("Capture", .heart, tint: .special) { controller.capture() }
                    }
                    ForEach(controller.pinnedSkills) { skill in
                        QuickSkillButton(controller: controller, skill: skill)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
            }
            RoundCommandButton(title: "Attack", icon: .sword, size: mainSize, tint: .primary) { controller.attack() }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: showMore)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: controller.canCapture)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: lowHP)
    }

    private func command(_ title: String, _ icon: GameIcon, tint: RoundCommandButton.Tint = .normal,
                         action: @escaping () -> Void) -> some View {
        RoundCommandButton(title: title, icon: icon, size: buttonSize, tint: tint, action: action)
            .transition(.scale(scale: 0.2).combined(with: .opacity))
    }
}

/// Stacks its views from the bottom up, centred in a column, and starts a new column to the left
/// after `maxRows` (or sooner if the next one wouldn't fit the height it's offered).
private struct BottomUpColumns: Layout {
    var maxRows: Int
    /// Room between buttons, so each label sits clear of the button above.
    var spacing: CGFloat = 26
    var columnSpacing: CGFloat = 14

    private func columns(_ sizes: [CGSize], maxHeight: CGFloat) -> [[Int]] {
        var columns: [[Int]] = [[]]
        var height: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let column = columns[columns.count - 1]
            let needed = column.isEmpty ? size.height : height + spacing + size.height
            if !column.isEmpty, column.count >= maxRows || needed > maxHeight {
                columns.append([index])
                height = size.height
            } else {
                columns[columns.count - 1].append(index)
                height = needed
            }
        }
        return columns
    }

    private func measure(_ subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = measure(subviews)
        let columns = columns(sizes, maxHeight: proposal.height ?? .infinity)
        let widths = columns.map { $0.map { sizes[$0].width }.max() ?? 0 }
        let heights = columns.map { column in
            column.map { sizes[$0].height }.reduce(0, +) + spacing * CGFloat(max(0, column.count - 1))
        }
        return CGSize(width: widths.reduce(0, +) + columnSpacing * CGFloat(max(0, columns.count - 1)),
                      height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measure(subviews)
        var x = bounds.maxX
        for column in columns(sizes, maxHeight: proposal.height ?? .infinity) {
            let width = column.map { sizes[$0].width }.max() ?? 0
            var y = bounds.maxY
            for index in column {
                subviews[index].place(at: CGPoint(x: x - width / 2, y: y), anchor: .bottom, proposal: ProposedViewSize(sizes[index]))
                y -= sizes[index].height + spacing
            }
            x -= width + columnSpacing
        }
    }
}

struct RoundCommandButton: View {
    enum Tint {
        /// special glows gold (Capture); heal glows green (Items when HP is low).
        case primary, normal, special, heal, quiet
    }

    let title: String
    let icon: GameIcon
    let size: CGFloat
    let tint: Tint
    let action: () -> Void

    @State private var pulse = false

    private var colors: [Color] {
        switch tint {
        case .primary: [Color(red: 1, green: 0.62, blue: 0.45), Color(red: 0.9, green: 0.3, blue: 0.3)]
        case .special: [Color(red: 1, green: 0.92, blue: 0.55), Color(red: 0.98, green: 0.68, blue: 0.2)]
        case .heal: [Color(red: 0.8, green: 1, blue: 0.75), Color(red: 0.3, green: 0.78, blue: 0.4)]
        case .normal: [.white, HUDStyle.cream, Color(red: 0.86, green: 0.78, blue: 0.64)]
        case .quiet: [Color(red: 0.42, green: 0.36, blue: 0.56), HUDStyle.ink]
        }
    }

    /// Buttons that want attention pulse with a coloured glow.
    private var glow: Color? {
        switch tint {
        case .special: HUDStyle.gold
        case .heal: HUDStyle.green
        default: nil
        }
    }

    private var foreground: Color {
        switch tint {
        case .primary, .quiet: .white
        case .normal, .special, .heal: HUDStyle.ink
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                IconImage(icon, size: size * 0.4)
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
            .shadow(color: glow?.opacity(pulse ? 0.9 : 0.3) ?? .black.opacity(0.4),
                    radius: glow == nil ? 4 : (pulse ? 12 : 5), x: 0, y: glow == nil ? 4 : 0)
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
            guard glow != nil else { return }
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
    let icon: GameIcon
    let onBack: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, icon: icon, size: 17)
                    .font(HUDStyle.font(14))
                    .foregroundStyle(HUDStyle.gold)
                Spacer()
                Button(action: onBack) {
                    IconImage(.close, size: 16)
                        .foregroundStyle(HUDStyle.cream)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .accessibilityLabel("Back")
            }
            // Hug the rows; long lists scroll instead of growing past the scene.
            ScrollView {
                VStack(spacing: 6, content: content)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(contentHeight, 1), 220))
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

/// A pinned skill beside Attack: one tap casts (or asks for a target).
private struct QuickSkillButton: View {
    let controller: BattleController
    let skill: SkillDef

    var body: some View {
        let cost = controller.cost(of: skill)
        let affordable = (controller.hero?.mp ?? 0) >= cost
        Button { controller.useSkill(skill) } label: {
            VStack(spacing: 2) {
                SkillIcon(skill: skill, size: 46)
                Text("\(cost) MP")
                    .font(HUDStyle.mono(10))
                    .foregroundStyle(affordable ? HUDStyle.cream : HUDStyle.dim)
                    .padding(.horizontal, 5)
                    .background(Capsule().fill(HUDStyle.ink.opacity(0.85)))
            }
            .opacity(affordable ? 1 : 0.5)
        }
        .buttonStyle(RoundPressStyle())
        .accessibilityLabel("\(skill.name), \(cost) MP")
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
                .padding(.leading, 6)
                .padding(.trailing, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(enabled ? HUDStyle.cream : HUDStyle.dim))
        }
        .buttonStyle(RoundPressStyle())
    }
}

// MARK: - Status & results

private struct ResultPanel: View {
    let result: BattleResult
    let session: GameSession
    let onContinue: () -> Void

    /// Summary first; then, if needed, who stays behind (full party) and skill choices.
    private enum Stage { case summary, release, levelUp }
    @State private var stage = Stage.summary

    private var title: String {
        switch result.outcome {
        case .victory: "Victory!"
        case .fled: "It got away…"
        case .defeat: "Defeated…"
        case .escaped: "Escaped"
        case .ongoing: ""
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            switch stage {
            case .summary:
                summary
            case .release:
                LeaveBehindCard(session: session, onDone: advance)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            case .levelUp:
                if let level = result.newLevel {
                    LevelUpCard(session: session, level: level, onDone: onContinue)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: stage)
    }

    private func advance() {
        if stage == .summary, session.pendingPet != nil {
            stage = .release
        } else if stage != .levelUp, result.newLevel != nil, session.unspentSkillPoints > 0 {
            stage = .levelUp
        } else {
            onContinue()
        }
    }

    private var summary: some View {
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
                Button("Continue", action: advance)
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

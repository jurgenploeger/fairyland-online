import SwiftUI
import UIKit

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

/// A big button in the corner (Attack unless you change it), and beside it a column of round buttons
/// built from the bottom up: More, then Skills, then whatever else turns up (Capture when a monster is
/// weak enough, Items when someone is low on HP, pinned skills). Less-used commands hide behind More.
/// Holding any button lets you rearrange them all.
private struct CommandPad: View {
    let controller: BattleController
    @State private var showMore = false
    /// Holding any button opens the arrange panel.
    @State private var arranging = false

    private let mainSize: CGFloat = 88
    private let buttonSize: CGFloat = 56

    var body: some View {
        if arranging {
            ArrangeButtonsCard(controller: controller) { arranging = false }
                .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
        } else {
            pad
        }
    }

    /// Your order (`GameSession.battleButtons`), split into the big button, the column beside it
    /// (bottom up, above More) and the More menu, leaving out what can't be used right now.
    private var sections: (main: String?, column: [String], more: [String]) {
        let order = controller.session.battleButtons.filter(isAvailable)
        let divider = order.firstIndex(of: GameSession.moreDivider) ?? order.endIndex
        var front = Array(order[..<divider])
        var more = Array(order[divider...].dropFirst())
        // Low on HP: Items comes out of More, glowing green.
        if controller.needsHealing, let index = more.firstIndex(of: "items") {
            more.remove(at: index)
            front.insert("items", at: min(1, front.count))
        }
        if front.isEmpty, !more.isEmpty { front.append(more.removeFirst()) }
        return (front.first, Array(front.dropFirst()), more)
    }

    private func isAvailable(_ id: String) -> Bool {
        id == "capture" ? controller.canCapture : true
    }

    private var pad: some View {
        let (main, column, more) = sections
        return HStack(alignment: .bottom, spacing: 14) {
            BottomUpColumns(maxRows: 4) {
                if !more.isEmpty {
                    RoundCommandButton(title: showMore ? "Close" : "More", icon: showMore ? .close : .more, size: buttonSize,
                                       tint: .quiet, onHold: arrange) {
                        showMore.toggle()
                    }
                }
                ForEach(showMore ? more : column, id: \.self) { id in
                    button(id, size: buttonSize)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
            if let main {
                button(main, size: mainSize)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: showMore)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: controller.canCapture)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: controller.needsHealing)
    }

    private func arrange() {
        showMore = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { arranging = true }
    }

    @ViewBuilder
    private func button(_ id: String, size: CGFloat) -> some View {
        let big = size == mainSize
        if id.hasPrefix("skill:"), let skill = controller.pinnedSkills.first(where: { "skill:\($0.id)" == id }) {
            QuickSkillButton(controller: controller, skill: skill, size: big ? 74 : 46, onHold: arrange)
        } else {
            let info = BattleCommand(id)
            RoundCommandButton(title: info.title, icon: id == "items" && controller.needsHealing ? .heartPlus : info.icon,
                               size: size, tint: tint(for: id, big: big), onHold: arrange) {
                perform(id)
            }
        }
    }

    private func tint(for id: String, big: Bool) -> RoundCommandButton.Tint {
        if id == "capture" { return .special }
        if id == "items", controller.needsHealing { return .heal }
        return big ? .primary : .normal
    }

    private func perform(_ id: String) {
        switch id {
        case "attack": controller.attack()
        case "skills": controller.openSkills()
        case "items": controller.openItems()
        case "guard": controller.defend()
        case "run": controller.escape()
        case "capture": controller.capture()
        default: break
        }
    }
}

/// The name and icon of a battle button id (see `GameSession.battleButtons`).
private struct BattleCommand {
    let title: String
    let icon: GameIcon

    init(_ id: String) {
        switch id {
        case "attack": title = "Attack"; icon = .sword
        case "skills": title = "Skills"; icon = .sparkles
        case "items": title = "Items"; icon = .backpack
        case "guard": title = "Guard"; icon = .shield
        case "run": title = "Run"; icon = .wind
        case "capture": title = "Capture"; icon = .heart
        default: title = "More"; icon = .more
        }
    }
}

/// Hold any battle button to get here: drag the buttons into any order. The top one becomes the
/// big button, the ones under "More menu" wait behind More.
private struct ArrangeButtonsCard: View {
    let controller: BattleController
    let onDone: () -> Void
    @State private var order: [String]

    init(controller: BattleController, onDone: @escaping () -> Void) {
        self.controller = controller
        self.onDone = onDone
        _order = State(initialValue: controller.session.battleButtons)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Arrange buttons")
                    .font(HUDStyle.font(14))
                    .foregroundStyle(HUDStyle.gold)
                Spacer()
                Button("Reset") { order = resetOrder }
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.cream)
                    .padding(.horizontal, 8)
                Button {
                    controller.arrangeButtons(order)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { onDone() }
                } label: {
                    Text("Done")
                        .font(HUDStyle.font(13))
                        .foregroundStyle(HUDStyle.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(HUDStyle.gold))
                }
            }
            Text("Drag to reorder. The top one is the big button.")
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.cream.opacity(0.8))
            List {
                ForEach(order, id: \.self) { id in
                    row(id)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                    // Something always has to be the big button.
                    if order.first == GameSession.moreDivider { order.swapAt(0, 1) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .environment(\.defaultMinListRowHeight, 36)
            .frame(height: min(CGFloat(order.count) * 40, 300))
        }
        .padding(12)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(HUDStyle.ink.opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(HUDStyle.cream.opacity(0.8), lineWidth: 2))
        )
    }

    /// The standard order, keeping your pinned skills beside the big button.
    private var resetOrder: [String] {
        let pins = order.filter { $0.hasPrefix("skill:") }
        var standard = GameSession.defaultBattleButtons
        standard.insert(contentsOf: pins, at: standard.firstIndex(of: GameSession.moreDivider) ?? standard.endIndex)
        return standard
    }

    @ViewBuilder
    private func row(_ id: String) -> some View {
        if id == GameSession.moreDivider {
            HStack(spacing: 6) {
                IconImage(.more, size: 16)
                Text("More menu")
                Rectangle().fill(HUDStyle.cream.opacity(0.4)).frame(height: 1)
            }
            .font(HUDStyle.font(12))
            .foregroundStyle(HUDStyle.cream.opacity(0.8))
        } else {
            HStack(spacing: 8) {
                if id.hasPrefix("skill:"), let skill = controller.pinnedSkills.first(where: { "skill:\($0.id)" == id }) {
                    SkillIcon(skill: skill, size: 24)
                    Text(skill.name)
                } else {
                    let info = BattleCommand(id)
                    IconImage(info.icon, size: 20)
                        .frame(width: 24)
                    Text(id == "capture" ? "Capture (when possible)" : info.title)
                }
                Spacer()
                if id == order.first {
                    Text("Big button")
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(HUDStyle.gold))
                }
            }
            .font(HUDStyle.font(13))
            .foregroundStyle(HUDStyle.cream)
        }
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
    var onHold: (() -> Void)? = nil
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
        PressButton(action: action, onHold: onHold) {
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

/// A button that shrinks while pressed; holding it calls `onHold` instead of `action`.
private struct PressButton<Label: View>: View {
    let action: () -> Void
    let onHold: (() -> Void)?
    @ViewBuilder let label: () -> Label
    @State private var pressed = false
    /// Set by a hold, so letting go afterwards doesn't also count as a tap.
    @State private var held = false

    var body: some View {
        label()
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: pressed)
            .onTapGesture {
                if held { held = false } else { action() }
            }
            .onLongPressGesture(minimumDuration: 0.45) {
                guard let onHold else { return }
                held = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onHold()
            } onPressingChanged: { pressing in
                pressed = pressing
                if pressing { held = false }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
            .accessibilityAction(named: "Arrange buttons") { onHold?() }
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
    var size: CGFloat = 46
    var onHold: (() -> Void)? = nil

    var body: some View {
        let cost = controller.cost(of: skill)
        let affordable = (controller.hero?.mp ?? 0) >= cost
        PressButton(action: { controller.useSkill(skill) }, onHold: onHold) {
            VStack(spacing: 2) {
                SkillIcon(skill: skill, size: size)
                Text("\(cost) MP")
                    .font(HUDStyle.mono(10))
                    .foregroundStyle(affordable ? HUDStyle.cream : HUDStyle.dim)
                    .padding(.horizontal, 5)
                    .background(Capsule().fill(HUDStyle.ink.opacity(0.85)))
            }
            .opacity(affordable ? 1 : 0.5)
        }
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

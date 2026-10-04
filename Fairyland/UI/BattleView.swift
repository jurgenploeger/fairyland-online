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

                if controller.waveCount > 1 {
                    WaveTracker(wave: controller.wave, total: controller.waveCount)
                }

                if let deadline = controller.turnDeadline, let total = BattleController.turnSeconds {
                    TurnClockBar(deadline: deadline, total: total)
                        .transition(.opacity)
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

            // Top left, across from the chat: how fast the fight plays, and Auto.
            if controller.phase != .finished {
                PaceControls(controller: controller)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 66)
                    .padding(.leading, 14)
            }

            if controller.phase == .finished, let result = controller.result {
                ResultPanel(result: result, session: controller.session, onContinue: controller.leave)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: controller.phase)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: controller.choosingForCompanion)
        .onAppear { controller.begin() }
    }

    @ViewBuilder
    private var commandArea: some View {
        switch controller.phase {
        case .command:
            if controller.choosingForCompanion {
                CompanionPad(controller: controller)
                    .padding(.top, 64)
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            } else {
                CommandPad(controller: controller)
                    .padding(.top, 64)   // clear of the log line
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            }
        case .skills where controller.choosingForCompanion:
            ChoiceCard(title: "\(controller.companion?.name ?? "Companion")'s skills", icon: .paw, onBack: controller.back) {
                if controller.companionSkills.isEmpty {
                    EmptyNote("No skills yet.")
                }
                ForEach(controller.companionSkills) { skill in
                    let price = controller.companionCost(of: skill)
                    ChoiceRow(action: { controller.useSkill(skill) }, enabled: (controller.companion?.mp ?? 0) >= price) {
                        SkillIcon(skill: skill, size: 26)
                        Text(skill.name)
                        Text("Lv\(controller.companionLevel(of: skill))").font(HUDStyle.mono(10)).foregroundStyle(HUDStyle.frameDark)
                        if let element = skill.element { ElementBadge(element: element) }
                        Spacer()
                        Text("\(price) MP").foregroundStyle(HUDStyle.mp)
                    }
                }
            }
            .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
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
                        ItemIcon(item: item, size: 26, count: controller.session.count(of: item.id))
                        Text(item.name)
                        Spacer()
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

/// A boss fight's waves: a pip for each, the boss's a star, gold once you've reached it.
private struct WaveTracker: View {
    let wave: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(wave == total ? "Boss wave" : "Wave \(wave) of \(total)")
                .font(HUDStyle.font(11))
                .padding(.trailing, 2)
            ForEach(1...total, id: \.self) { index in
                Group {
                    if index == total {
                        IconImage(.star, size: 11)
                    } else {
                        Circle().frame(width: 7, height: 7)
                    }
                }
                .foregroundStyle(index <= wave ? HUDStyle.gold : HUDStyle.cream.opacity(0.3))
            }
        }
        .foregroundStyle(HUDStyle.cream)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(HUDStyle.ink.opacity(0.8)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(wave == total ? "Boss wave, the last of \(total)" : "Wave \(wave) of \(total)")
    }
}

/// The time left to choose, draining under the log line, red for the last two seconds. When it
/// runs out the hero attacks. Narrow enough (about 144 points) to stay clear of the 1× and AUTO
/// buttons below it, even on a 375-point-wide phone.
private struct TurnClockBar: View {
    let deadline: Date
    let total: TimeInterval

    var body: some View {
        TimelineView(.animation) { context in
            let left = max(0, deadline.timeIntervalSince(context.date))
            let urgent = left <= 2
            HStack(spacing: 6) {
                IconImage(.sword, size: 12)
                GlossyBar(fraction: CGFloat(min(1, left / total)), color: urgent ? HUDStyle.hp : HUDStyle.gold, height: 7)
                    .frame(width: 80)
                Text("\(Int(left.rounded(.up)))s")
                    .font(HUDStyle.mono(10))
                    .frame(width: 24, alignment: .leading)
            }
            .foregroundStyle(urgent ? HUDStyle.hp : HUDStyle.cream)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(HUDStyle.ink.opacity(0.8)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time left to choose before you attack")
    }
}

// MARK: - Commands

/// A big button in the corner (Attack unless you change it) with More on top of it, and to its left
/// rows of round buttons filled from the bottom right: Skills, then whatever else turns up (Capture
/// when a monster is weak enough, Items when someone is low on HP, pinned skills). Less-used commands
/// hide behind More. Holding any button makes them all wiggle, like the iPhone home screen: drag
/// them into any order (onto the big button, or into the "Behind More" tray), then tap Done.
private struct CommandPad: View {
    let controller: BattleController
    @State private var showMore = false
    /// While rearranging: the whole order, `moreDivider` included (nil otherwise).
    @State private var editing: [String]?
    /// Where each button sits, for working out what a dragged button is over.
    @State private var frames: [String: CGRect] = [:]
    @State private var trayFrame: CGRect = .zero
    @State private var dragging: String?
    @State private var dragPoint: CGPoint = .zero
    /// The button last swapped with, so hovering over it doesn't swap back and forth.
    @State private var lastTarget: String?

    private let mainSize: CGFloat = 88
    private let buttonSize: CGFloat = 56
    private static let space = "commandPad"

    var body: some View {
        Group {
            if let editing {
                editPad(editing)
            } else {
                pad
            }
        }
        .coordinateSpace(name: Self.space)
        .onAppear { if DebugLaunch.arrangesButtons, editing == nil { arrange() } }
        // Moving the buttons around isn't choosing: the turn clock waits.
        .onChange(of: editing == nil) { _, settled in controller.holdTurnClock(!settled, for: "arrange") }
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
            // Rows beside the big button, filled right to left and wrapping upwards.
            RightToLeftRows {
                ForEach(showMore ? more : column, id: \.self) { id in
                    button(id, size: buttonSize)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
            // More sits on top of the big button, always in the same spot.
            VStack(spacing: 26) {
                if !more.isEmpty {
                    RoundCommandButton(title: showMore ? "Close" : "More", icon: showMore ? .close : .more, size: buttonSize,
                                       tint: .quiet, onHold: arrange) {
                        showMore.toggle()
                    }
                }
                if let main {
                    button(main, size: mainSize)
                }
            }
        }
        .padding(.leading, 14)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: showMore)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: controller.canCapture)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: controller.needsHealing)
    }

    private func arrange() {
        showMore = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { editing = controller.session.battleButtons }
    }

    // MARK: Rearranging

    private func editPad(_ order: [String]) -> some View {
        let divider = order.firstIndex(of: GameSession.moreDivider) ?? order.endIndex
        let main = order.first
        let row = Array(order[..<divider].dropFirst())
        let tray = Array(order[divider...].dropFirst())
        return VStack(alignment: .trailing, spacing: 22) {
            HStack(spacing: 8) {
                Text("Drag to rearrange")
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.cream)
                Button("Reset") { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { editing = resetOrder(order) } }
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.cream)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.15)))
                Button {
                    controller.arrangeButtons(order)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { editing = nil }
                } label: {
                    Text("Done")
                        .font(HUDStyle.font(13))
                        .foregroundStyle(HUDStyle.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(HUDStyle.gold))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(HUDStyle.ink.opacity(0.85)))

            // What waits behind More.
            VStack(alignment: .trailing, spacing: 8) {
                Text("Behind More")
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.cream.opacity(0.8))
                RightToLeftRows {
                    ForEach(tray, id: \.self) { id in editTile(id, size: buttonSize) }
                }
                .frame(minWidth: buttonSize * 2, minHeight: buttonSize, alignment: .bottomTrailing)
                .padding(.bottom, 16)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(HUDStyle.ink.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(HUDStyle.cream.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            )
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { trayFrame = $0 }
            .zIndex(tray.contains { $0 == dragging } ? 1 : 0)

            HStack(alignment: .bottom, spacing: 14) {
                RightToLeftRows {
                    ForEach(row, id: \.self) { id in editTile(id, size: buttonSize) }
                }
                .zIndex(row.contains { $0 == dragging } ? 1 : 0)
                VStack(spacing: 26) {
                    RoundCommandButton(title: "More", icon: .more, size: buttonSize, tint: .quiet) {}
                        .allowsHitTesting(false)
                        .opacity(0.5)
                    if let main { editTile(main, size: mainSize) }
                }
                .zIndex(main == dragging ? 1 : 0)
            }
            .padding(.leading, 14)
        }
    }

    /// A wiggling button that can be dragged; taps do nothing while rearranging.
    private func editTile(_ id: String, size: CGFloat) -> some View {
        let isDragged = dragging == id
        let center = frames[id].map { CGPoint(x: $0.midX, y: $0.midY) } ?? dragPoint
        return button(id, size: size)
            .allowsHitTesting(false)
            .modifier(Wiggle(active: !isDragged))
            .opacity(id == "capture" && !controller.canCapture ? 0.7 : 1)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[id] = $0 }
            .scaleEffect(isDragged ? 1.15 : 1)
            .offset(isDragged ? CGSize(width: dragPoint.x - center.x, height: dragPoint.y - center.y) : .zero)
            .zIndex(isDragged ? 1 : 0)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        if dragging != id {
                            dragging = id
                            lastTarget = nil
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        dragPoint = value.location
                        drag(id, over: value.location)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            dragging = nil
                            lastTarget = nil
                        }
                    }
            )
    }

    /// Moves the dragged button into the place of whatever it's over (iPhone home screen style), or to
    /// the end of the tray when it's dropped into the tray's empty space.
    private func drag(_ id: String, over point: CGPoint) {
        guard var order = editing, let from = order.firstIndex(of: id) else { return }
        if let target = frames.first(where: { $0.key != id && order.contains($0.key) && $0.value.contains(point) })?.key {
            guard target != lastTarget, let to = order.firstIndex(of: target) else { return }
            lastTarget = target
            order.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        } else if trayFrame.contains(point), let divider = order.firstIndex(of: GameSession.moreDivider), from < divider {
            lastTarget = nil
            order.remove(at: from)
            order.append(id)
        } else {
            lastTarget = nil
            return
        }
        // Something always has to be the big button.
        if order.first == GameSession.moreDivider, order.count > 1 { order.swapAt(0, 1) }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { editing = order }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// The standard order, keeping your pinned skills beside the big button.
    private func resetOrder(_ order: [String]) -> [String] {
        var standard = GameSession.defaultBattleButtons
        standard.insert(contentsOf: order.filter { $0.hasPrefix("skill:") },
                        at: standard.firstIndex(of: GameSession.moreDivider) ?? standard.endIndex)
        return standard
    }

    @ViewBuilder
    private func button(_ id: String, size: CGFloat) -> some View {
        let big = size == mainSize
        if id.hasPrefix("skill:"), let skill = controller.pinnedSkills.first(where: { "skill:\($0.id)" == id }) {
            QuickSkillButton(controller: controller, skill: skill, size: size, onHold: arrange)
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

/// The fight's pace: 2× plays it twice as fast (your time to choose stays the same), and Auto lets
/// the hero and companion fight on their own against monsters well below you. Both are kept for
/// the next fights. Auto shows only in wild fights, dimmed where the monsters are too strong for it.
private struct PaceControls: View {
    let controller: BattleController

    var body: some View {
        HStack(spacing: 8) {
            let fast = controller.speed > 1
            PaceButton(title: fast ? "2×" : "1×", lit: fast,
                       label: fast ? "Battle speed: double. Tap for normal." : "Battle speed: normal. Tap for double.") {
                controller.toggleSpeed()
            }
            if controller.isWild {
                PaceButton(title: "AUTO", lit: controller.isAuto, enabled: controller.isAuto || controller.canAuto,
                           label: controller.isAuto ? "Auto is on. Tap to choose yourself." : "Auto: fight on your own.") {
                    controller.toggleAuto()
                }
            }
        }
    }
}

/// A small lit-or-not switch for the pace controls.
private struct PaceButton: View {
    let title: String
    let lit: Bool
    var enabled = true
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            SoundEffects.shared.play(.tap, volume: 0.7)
            action()
        } label: {
            Text(title)
                .font(HUDStyle.font(12))
                .foregroundStyle(lit ? HUDStyle.ink : HUDStyle.cream)
                .frame(minWidth: 40, minHeight: 30)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(lit ? HUDStyle.gold : HUDStyle.ink.opacity(0.85))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(lit ? Color.white.opacity(0.9) : HUDStyle.cream.opacity(0.55), lineWidth: 2))
                )
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}

/// Your companion's turn, after the hero's choice: Attack in the big button's spot, its Skills,
/// Guard, and Auto to let it decide for itself. The chip on top shows whose turn it is. The hero's
/// choice is made by then, so there's no going back to it (that would start their clock over).
private struct CompanionPad: View {
    let controller: BattleController

    var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            if let companion = controller.companion {
                HStack(spacing: 8) {
                    SpriteImage(art: companion.art, size: 30)
                    Text("\(companion.name)'s turn")
                        .font(HUDStyle.font(13))
                        .foregroundStyle(HUDStyle.cream)
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(HUDStyle.ink.opacity(0.88)).overlay(Capsule().strokeBorder(HUDStyle.gold.opacity(0.7), lineWidth: 1.5)))
            }

            HStack(alignment: .bottom, spacing: 14) {
                HStack(alignment: .bottom, spacing: 10) {
                    RoundCommandButton(title: "Auto", icon: .paw, size: 56, tint: .quiet) { controller.letCompanionDecide() }
                    RoundCommandButton(title: "Guard", icon: .shield, size: 56, tint: .normal) { controller.defend() }
                    if !controller.companionSkills.isEmpty {
                        RoundCommandButton(title: "Skills", icon: .sparkles, size: 56, tint: .normal) { controller.openSkills() }
                    }
                }
                RoundCommandButton(title: "Attack", icon: .tooth, size: 88, tint: .primary) { controller.attack() }
            }
        }
        .padding(.leading, 14)
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

/// The home-screen wiggle for buttons being rearranged, each a little out of step with the others.
private struct Wiggle: ViewModifier {
    let active: Bool
    @State private var speed = Double.random(in: 0.11...0.15)

    // `Self.Content`: plain `Content` is the game's data store.
    func body(content: Self.Content) -> some View {
        content.phaseAnimator([false, true]) { view, tilted in
            view.rotationEffect(.degrees(active ? (tilted ? 2.5 : -2.5) : 0))
        } animation: { _ in
            .easeInOut(duration: speed)
        }
    }
}

/// Lays its views out in rows from the bottom-right corner: right to left, and when a row is full,
/// on up into the next one. Labels hang below the buttons, so rows leave room for them.
private struct RightToLeftRows: Layout {
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat = 26

    private func rows(_ sizes: [CGSize], maxWidth: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var width: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let row = rows[rows.count - 1]
            let needed = row.isEmpty ? size.width : width + spacing + size.width
            if !row.isEmpty, needed > maxWidth {
                rows.append([index])
                width = size.width
            } else {
                rows[rows.count - 1].append(index)
                width = needed
            }
        }
        return rows
    }

    private func measure(_ subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }

    /// Without a width on offer, four buttons to a row.
    private func maxWidth(_ proposal: ProposedViewSize, _ sizes: [CGSize]) -> CGFloat {
        if let width = proposal.width, width.isFinite { return width }
        return 4 * (sizes.first?.width ?? 56) + 3 * spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = measure(subviews)
        guard !sizes.isEmpty else { return .zero }
        let rows = rows(sizes, maxWidth: maxWidth(proposal, sizes))
        let widths = rows.map { row in row.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(max(0, row.count - 1)) }
        let heights = rows.map { row in row.map { sizes[$0].height }.max() ?? 0 }
        return CGSize(width: widths.max() ?? 0, height: heights.reduce(0, +) + rowSpacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measure(subviews)
        var y = bounds.maxY
        for row in rows(sizes, maxWidth: bounds.width) {
            var x = bounds.maxX
            for index in row {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .bottomTrailing, proposal: ProposedViewSize(sizes[index]))
                x -= sizes[index].width + spacing
            }
            y -= (row.map { sizes[$0].height }.max() ?? 0) + rowSpacing
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
    var size: CGFloat = 56
    var onHold: (() -> Void)? = nil

    var body: some View {
        let cost = controller.cost(of: skill)
        let affordable = (controller.hero?.mp ?? 0) >= cost
        let tint = Color(uiColor: skill.tileColor)
        PressButton(action: { controller.useSkill(skill) }, onHold: onHold) {
            // Round like the other battle buttons, in the skill's colour.
            Group {
                if let picture = skill.art.flatMap(ArtLibrary.shared.artImage) {
                    Image(uiImage: picture)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.62, height: size * 0.62)
                } else {
                    IconImage(skill.icon.flatMap(GameIcon.init) ?? .sparkles, size: size * 0.42)
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.75), tint], center: UnitPoint(x: 0.35, y: 0.3),
                                         startRadius: 1, endRadius: size * 0.75))
                    .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.3), .clear, .black.opacity(0.2)],
                                                          startPoint: .top, endPoint: .bottom)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.75), lineWidth: 2))
            )
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 4)
            .opacity(affordable ? 1 : 0.5)
        }
        .overlay(alignment: .bottom) {
            // The skill's name, like the other buttons' labels; long names end in "…".
            Text(skill.name)
                .font(HUDStyle.font(10))
                .foregroundStyle(affordable ? HUDStyle.cream : HUDStyle.dim)
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: size + 14)
                .offset(y: 15)
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

    /// A boss's story first (the first time you beat it), then the summary; then, if needed, who
    /// stays behind (full party) and skill choices.
    private enum Stage { case story, summary, release, levelUp }
    @State private var stage: Stage

    init(result: BattleResult, session: GameSession, onContinue: @escaping () -> Void) {
        self.result = result
        self.session = session
        self.onContinue = onContinue
        _stage = State(initialValue: result.story == nil ? .summary : .story)
    }

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
            case .story:
                if let story = result.story {
                    BossStoryCard(story: story, onDone: advance)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
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
        if stage == .story {
            stage = .summary
        } else if stage == .summary, session.pendingPet != nil {
            stage = .release
        } else if stage != .levelUp, result.newLevel != nil, session.canSpendSkillPoint {
            stage = .levelUp
        } else {
            onContinue()
        }
    }

    private var summary: some View {
        // A level-up trims the card in gold.
        let rim = result.newLevel != nil ? HUDStyle.gold : HUDStyle.cream
        return VStack(spacing: 10) {
            Text(title)
                .font(HUDStyle.font(26))
                .foregroundStyle(result.outcome == .victory ? HUDStyle.gold : HUDStyle.cream)
            // Scrolls only when it can't all fit (a phone on its side after a big win).
            ViewThatFits(in: .vertical) {
                details
                ScrollView { details }
                    .scrollBounceBehavior(.basedOnSize)
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
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(rim.opacity(0.85), lineWidth: 2))
        )
        .padding(20)
    }

    /// The pay, the level-up, what was found, and what else happened.
    private var details: some View {
        VStack(spacing: 10) {
            if result.exp > 0 || result.gold > 0 {
                HStack(spacing: 18) {
                    // None when you were out cold at the end (your friends won it).
                    if result.exp > 0 {
                        Label { Text("+\(result.exp) EXP") } icon: {
                            IconImage(.star, size: 18).foregroundStyle(HUDStyle.exp)
                        }
                    }
                    Label { Text("+\(result.gold)") } icon: {
                        IconImage(.coins, size: 18).foregroundStyle(HUDStyle.gold)
                    }
                }
                .font(HUDStyle.font(16))
                .foregroundStyle(HUDStyle.cream)
            }
            if let level = result.newLevel {
                LevelUpBanner(level: level, gains: session.heroClass.growth * result.levelsGained)
            }
            if !result.others.isEmpty {
                PartyLevelUps(others: result.others)
            }
            if !result.loot.isEmpty {
                LootGrid(loot: result.loot)
            }
            ForEach(Array(result.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(HUDStyle.font(13))
                    .foregroundStyle(HUDStyle.cream)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// A boss beaten for the first time: what the win means, told as a short story before the pay.
/// The boss in a ring of light over the title; the paragraphs come in one after another, at about
/// reading pace. A tap shows the rest at once; Continue goes on to the rewards.
private struct BossStoryCard: View {
    let story: BossStory
    let onDone: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How many paragraphs are showing.
    @State private var shown = 0

    private var told: Bool { shown >= story.paragraphs.count }

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                // Landscape: the boss beside the story, so it all fits.
                HStack(spacing: 18) {
                    portrait(size: 80)
                    VStack(spacing: 10) {
                        heading
                        ViewThatFits(in: .vertical) {
                            paragraphs
                            ScrollView { paragraphs }
                                .scrollBounceBehavior(.basedOnSize)
                        }
                        continueButton
                    }
                }
            } else {
                VStack(spacing: 12) {
                    portrait(size: 96)
                    heading
                    paragraphs
                    continueButton
                }
            }
        }
        .padding(22)
        .frame(maxWidth: verticalSizeClass == .compact ? 620 : 420)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(HUDStyle.ink.opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(HUDStyle.gold.opacity(0.85), lineWidth: 2))
        )
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture { revealAll() }
        .padding(20)
        .task { await tell() }
    }

    private func portrait(size: CGFloat) -> some View {
        SpriteImage(art: story.art, size: size)
            .frame(width: size + 16, height: size + 16)
            .background(
                Circle()
                    .fill(RadialGradient(colors: [HUDStyle.gold.opacity(0.3), HUDStyle.gold.opacity(0.04)],
                                         center: .center, startRadius: 0, endRadius: size * 0.6))
                    .overlay(Circle().strokeBorder(HUDStyle.gold.opacity(0.5), lineWidth: 1.5))
            )
            .accessibilityHidden(true)
    }

    /// The title, with a little star rule under it like a storybook chapter.
    private var heading: some View {
        VStack(spacing: 6) {
            Text(story.title)
                .font(HUDStyle.font(22))
                .foregroundStyle(HUDStyle.gold)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Capsule().fill(HUDStyle.gold.opacity(0.45)).frame(width: 44, height: 1.5)
                Text("✦").font(HUDStyle.font(11)).foregroundStyle(HUDStyle.gold.opacity(0.8))
                Capsule().fill(HUDStyle.gold.opacity(0.45)).frame(width: 44, height: 1.5)
            }
            .accessibilityHidden(true)
        }
    }

    /// Every paragraph takes its place from the start (unshown ones invisible), so nothing jumps.
    private var paragraphs: some View {
        VStack(spacing: 10) {
            ForEach(Array(story.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                Text(paragraph)
                    .font(HUDStyle.font(14))
                    .foregroundStyle(HUDStyle.cream)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(index < shown ? 1 : 0)
                    .offset(y: index < shown ? 0 : 8)
            }
        }
    }

    private var continueButton: some View {
        Button("Continue") {
            if told { onDone() } else { revealAll() }
        }
        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
        .opacity(told ? 1 : 0.5)
        .padding(.top, 4)
    }

    /// One paragraph after another, each given time to be read (all at once with Reduce Motion).
    private func tell() async {
        if reduceMotion {
            shown = story.paragraphs.count
            return
        }
        var pause = 0.5
        for (index, paragraph) in story.paragraphs.enumerated() {
            try? await Task.sleep(for: .seconds(pause))
            guard !Task.isCancelled else { return }
            if shown <= index {
                withAnimation(.easeOut(duration: 0.8)) { shown = index + 1 }
            }
            pause = min(3.5, max(1.5, Double(paragraph.count) * 0.022))
        }
    }

    private func revealAll() {
        guard !told else { return }
        withAnimation(.easeOut(duration: 0.3)) { shown = story.paragraphs.count }
    }
}

/// What a win (or a quest) turned up, as little item tiles with how many and the name underneath.
struct LootGrid: View {
    let loot: [(id: String, count: Int)]
    var title = "Found"

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.gold)
            CenteredRows(spacing: 8, rowSpacing: 8) {
                ForEach(Array(loot.enumerated()), id: \.offset) { _, entry in
                    if let item = Content.shared.item(entry.id) {
                        VStack(spacing: 3) {
                            ItemIcon(item: item, size: 40, count: entry.count)
                            Text(item.name)
                                .font(HUDStyle.font(10))
                                .foregroundStyle(HUDStyle.cream)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 78)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
    }
}

/// Friends and your companion who went up a level with the win, each with their new level, in a
/// gold box like the hero's banner.
private struct PartyLevelUps: View {
    let others: [LevelUp]

    var body: some View {
        VStack(spacing: 6) {
            Text(others.count == 1 ? "Level up!" : "Level ups!")
                .font(HUDStyle.font(14))
                .foregroundStyle(HUDStyle.gold)
            CenteredRows(spacing: 6, rowSpacing: 6) {
                ForEach(Array(others.enumerated()), id: \.offset) { _, other in
                    HStack(spacing: 4) {
                        IconImage(.arrowUp, size: 11)
                            .foregroundStyle(HUDStyle.gold)
                        Text(other.name)
                            .foregroundStyle(HUDStyle.cream)
                        Text("Lv \(other.level)")
                            .foregroundStyle(HUDStyle.gold)
                    }
                    .font(HUDStyle.font(12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(HUDStyle.gold.opacity(0.14)))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(HUDStyle.gold.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(HUDStyle.gold.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(others.map { "\($0.name) reached level \($0.level)" }.joined(separator: ". "))
    }
}

/// A level-up, made a fuss of on the victory and quest cards: the new level on a gold medal in a
/// slowly turning sunburst, stars flying off it, "LEVEL UP!", and what the new levels raised.
struct LevelUpBanner: View {
    let level: Int
    /// What the levels raised: the class's growth for each level gained.
    let gains: Stats
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var burst = false

    /// The stats that went up, in the Character tab's order.
    private var raised: [(label: String, value: Int)] {
        let all: [(label: String, value: Int)] = [
            ("HP", gains.hp), ("MP", gains.mp), ("ATK", gains.attack),
            ("DEF", gains.defense), ("MAG", gains.magic), ("SPD", gains.speed),
        ]
        return all.filter { $0.value > 0 }
    }

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                // Landscape: the medal beside the words, so the card still fits the screen.
                HStack(spacing: 16) {
                    medal(size: 50)
                    VStack(alignment: .leading, spacing: 4) {
                        title(size: 22)
                        Text(gains.bonusSummary)
                            .font(HUDStyle.font(11))
                            .foregroundStyle(HUDStyle.green)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    medal(size: 66)
                    title(size: 28)
                    CenteredRows(spacing: 5, rowSpacing: 5) {
                        ForEach(Array(raised.enumerated()), id: \.offset) { _, stat in
                            chip(stat.label, stat.value)
                        }
                    }
                    Text("HP and MP fully restored")
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.dim)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(HUDStyle.gold.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(HUDStyle.gold.opacity(0.55), lineWidth: 1.5))
        .scaleEffect(shown ? 1 : 0.6)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.15)) { shown = true }
            withAnimation(.easeOut(duration: 0.9).delay(0.3)) { burst = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level up! You're now level \(level). \(gains.bonusSummary)")
    }

    private func medal(size: CGFloat) -> some View {
        ZStack {
            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
                let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 20) / 20
                Sunburst(rays: 14)
                    .fill(RadialGradient(colors: [HUDStyle.gold.opacity(0.75), HUDStyle.gold.opacity(0)],
                                         center: .center, startRadius: size * 0.4, endRadius: size * 1.3))
                    .frame(width: size * 2.6, height: size * 2.6)
                    .rotationEffect(.degrees(turn * 360))
            }
            // Stars fly off from behind the medal as it lands.
            ForEach(0..<8, id: \.self) { index in
                IconImage(.star, size: size * 0.18)
                    .foregroundStyle(index % 2 == 0 ? HUDStyle.cream : HUDStyle.gold)
                    .offset(burst ? Self.flight(of: index, radius: size) : .zero)
                    .opacity(burst ? 0 : 1)
            }
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.97, blue: 0.75), HUDStyle.gold, HUDStyle.orange],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.75))
                .overlay(Circle().strokeBorder(HUDStyle.cream, lineWidth: 2.5))
                .shadow(color: HUDStyle.gold.opacity(0.9), radius: 10)
                .frame(width: size, height: size)
            VStack(spacing: -4) {
                Text("LV").font(HUDStyle.font(size * 0.19))
                Text("\(level)")
                    .font(HUDStyle.font(size * 0.42))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .foregroundStyle(HUDStyle.ink)
            .padding(.horizontal, size * 0.1)
        }
        .frame(width: size, height: size)
    }

    /// Where star `index` of eight ends up, all the way round the medal.
    private static func flight(of index: Int, radius: CGFloat) -> CGSize {
        let angle = CGFloat(index) / 8 * 2 * .pi
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius * 0.8)
    }

    private func title(size: CGFloat) -> some View {
        Text("LEVEL UP!")
            .font(HUDStyle.font(size))
            .foregroundStyle(HUDStyle.gold)
            .shadow(color: HUDStyle.orange.opacity(0.9), radius: 0, x: 2, y: 2)
    }

    /// "HP +12": one raised stat, in a little dark pill.
    private func chip(_ label: String, _ value: Int) -> some View {
        let text: Text = Text(label + " ").foregroundStyle(HUDStyle.cream) + Text("+\(value)").foregroundStyle(HUDStyle.green)
        return text
            .font(HUDStyle.font(11))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(HUDStyle.ink.opacity(0.7)))
    }
}

/// Wedges of light round the middle, like a sunburst.
private nonisolated struct Sunburst: Shape {
    var rays = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height) / 2
        let step = 2 * CGFloat.pi / CGFloat(rays)
        for index in 0..<rays {
            let angle = step * CGFloat(index)
            path.move(to: center)
            path.addArc(center: center, radius: radius, startAngle: Angle(radians: Double(angle - step / 4)),
                        endAngle: Angle(radians: Double(angle + step / 4)), clockwise: false)
            path.closeSubpath()
        }
        return path
    }
}

/// Wraps its views into rows like text, each row centred.
private struct CenteredRows: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    private func rows(_ sizes: [CGSize], maxWidth: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var width: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let row = rows[rows.count - 1]
            let needed = row.isEmpty ? size.width : width + spacing + size.width
            if !row.isEmpty, needed > maxWidth {
                rows.append([index])
                width = size.width
            } else {
                rows[rows.count - 1].append(index)
                width = needed
            }
        }
        return rows
    }

    private func rowWidth(_ row: [Int], _ sizes: [CGSize]) -> CGFloat {
        row.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard !sizes.isEmpty else { return .zero }
        let maxWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? .infinity
        let rows = rows(sizes, maxWidth: maxWidth)
        let heights = rows.map { row in row.map { sizes[$0].height }.max() ?? 0 }
        let widest = rows.map { rowWidth($0, sizes) }.max() ?? 0
        return CGSize(width: maxWidth.isFinite ? maxWidth : widest,
                      height: heights.reduce(0, +) + rowSpacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for row in rows(sizes, maxWidth: bounds.width) {
            let height = row.map { sizes[$0].height }.max() ?? 0
            var x = bounds.midX - rowWidth(row, sizes) / 2
            for index in row {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += height + rowSpacing
        }
    }
}

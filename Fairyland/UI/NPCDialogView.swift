import SwiftUI

/// Talking to someone: the healer, the shop, the quest giver, a guild master or a boss.
struct NPCDialogView: View {
    let npc: NPCDef
    let session: GameSession
    let onClose: () -> Void
    /// Bosses: start the fight.
    var onFight: (NPCDef) -> Void = { _ in }
    @State private var reply: String?

    var body: some View {
        GeometryReader { proxy in
            // Fairyland-style: the character stands big in the bottom-right corner, cut off by the
            // edge of the screen, and talks from a speech bubble on their left.
            let portrait = min(proxy.size.width * 0.5, proxy.size.height * 0.6, 300)
            ZStack(alignment: .bottomTrailing) {
                Color.black.opacity(0.35)
                    .onTapGesture(perform: onClose)

                SpriteImage(art: npc.art, size: portrait)
                    .offset(x: portrait * 0.22, y: portrait * 0.16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                bubble(maxHeight: proxy.size.height * 0.5)
                    .frame(maxWidth: 520)
                    .padding(.leading, 12)
                    .padding(.trailing, portrait * 0.62)
                    .padding(.bottom, max(16, proxy.safeAreaInsets.bottom))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }

    private func bubble(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FLTitleBar(title: npc.name, onClose: onClose)
            VStack(alignment: .leading, spacing: 10) {
                Text(reply ?? npc.greeting)
                    .font(HUDStyle.font(13))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ScrollView {
                    Group {
                        switch npc.role {
                        case .healer: HealerPanel(session: session, reply: $reply)
                        case .shop: ShopPanel(session: session, stock: npc.stock ?? [], reply: $reply)
                        case .quests: QuestGiverPanel(session: session, giver: npc.id, reply: $reply)
                        case .guild: GuildPanel(session: session, classID: npc.classId ?? "", reply: $reply)
                        case .chest: EmptyView()   // opened straight from the map (GameCoordinator.open)
                        case .boss: BossPanel(session: session, boss: npc, onFight: onFight)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: min(260, max(120, maxHeight - 110)))
            }
            .padding(12)
        }
        .foregroundStyle(HUDStyle.cream)
        .background(HUDStyle.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // The bubble's tail points at the speaker on the right.
        .overlay(alignment: .bottomTrailing) {
            BubbleTail()
                .fill(Color(red: 0.05, green: 0.17, blue: 0.35).opacity(0.95))
                .frame(width: 18, height: 22)
                .offset(x: 16, y: -28)
                .accessibilityHidden(true)
        }
    }
}

/// A small triangle pointing right, for the speech bubble.
private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct HealerPanel: View {
    let session: GameSession
    @Binding var reply: String?

    var body: some View {
        Button {
            session.restParty()
            session.post("Your party is fully rested.", .reward)
            session.save()
            reply = "There you go! Everyone is fully rested."
        } label: {
            Label("Rest and recover (free)", icon: .heartPlus)
        }
        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
    }
}

private struct ShopPanel: View {
    let session: GameSession
    let stock: [String]
    @Binding var reply: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(session.data.gold) gold", icon: .coins)
                .font(HUDStyle.font(12))
                .foregroundStyle(HUDStyle.gold)
            ForEach(stock.compactMap { session.content.item($0) }) { item in
                HStack(spacing: 10) {
                    ItemIcon(item: item, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                        let detail = item.type == .consumable ? (item.description ?? "") : "\(item.type.displayName) · \(item.stats?.bonusSummary ?? "")"
                        Text(detail).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.green)
                        if item.type != .consumable, let issue = session.equipIssue(item) {
                            Text(issue).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                        }
                    }
                    Spacer()
                    if session.count(of: item.id) > 0 {
                        Text("own \(session.count(of: item.id))").font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                    }
                    Button("\(item.price)g") {
                        if session.buy(item.id) {
                            session.post("Bought \(item.name).", .reward)
                            reply = "Thanks! Enjoy your \(item.name)."
                        } else {
                            reply = "Hmm, you're a bit short on gold."
                        }
                    }
                    .buttonStyle(PixelButtonStyle(tint: session.data.gold >= item.price ? HUDStyle.gold : HUDStyle.dim, compact: true))
                }
                .font(HUDStyle.font(12))
            }
        }
    }
}

private struct QuestGiverPanel: View {
    let session: GameSession
    let giver: String
    @Binding var reply: String?
    @State private var asking: String?

    var body: some View {
        let quests = session.quests(from: giver).filter { session.status(of: $0) != .completed }
        VStack(alignment: .leading, spacing: 8) {
            if quests.isEmpty {
                Text("Nothing for now. Come back when you're stronger!").font(HUDStyle.font(12)).foregroundStyle(HUDStyle.dim)
            }
            ForEach(quests) { quest in
                VStack(alignment: .leading, spacing: 6) {
                    QuestRow(session: session, quest: quest)
                    switch session.status(of: quest) {
                    case .available:
                        if asking == quest.id, let question = quest.question {
                            Text(question.text).font(HUDStyle.font(12)).foregroundStyle(HUDStyle.gold)
                            HStack {
                                ForEach(question.answers, id: \.text) { answer in
                                    Button(answer.text) {
                                        session.acceptQuest(quest.id, answer: answer)
                                        asking = nil
                                        reply = "\(answer.text)… a fine answer. Here are your gifts. Hatch that egg and come show me!"
                                    }
                                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                                }
                            }
                        } else {
                            Button("Accept") {
                                if quest.question != nil {
                                    asking = quest.id
                                    reply = quest.question?.text
                                } else {
                                    session.acceptQuest(quest.id)
                                    reply = "Wonderful! I knew I could count on you."
                                }
                            }
                            .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                        }
                    case .ready:
                        Button("Complete quest") {
                            let rewards = session.turnInQuest(quest.id)
                            session.save()
                            reply = "Thank you! Here's your reward: " + rewards.joined(separator: ", ")
                        }
                        .buttonStyle(PixelButtonStyle(tint: HUDStyle.green, compact: true))
                    default:
                        EmptyView()
                    }
                }
            }
        }
    }
}

private struct GuildPanel: View {
    let session: GameSession
    let classID: String
    @Binding var reply: String?
    @State private var confirming = false

    var body: some View {
        let path = session.content.classDef(classID)
        let hero = session.data.hero
        VStack(alignment: .leading, spacing: 8) {
            Text("\(path.guild ?? "Guild"): \(path.name)").font(HUDStyle.font(13)).foregroundStyle(HUDStyle.gold)
            Text(path.description).font(HUDStyle.font(11))
            Text("Skills: " + path.skills.compactMap { unlock in session.content.skill(unlock.skill).map { "\($0.name) (Lv \(unlock.level))" } }.joined(separator: ", "))
                .font(HUDStyle.font(10))
                .foregroundStyle(HUDStyle.dim)

            if hero.classID == path.id {
                Text("Welcome back, \(path.name)!").font(HUDStyle.font(12)).foregroundStyle(HUDStyle.green)
            } else if hero.classID != "novice" {
                Text("You've already chosen the path of the \(session.heroClass.name).").font(HUDStyle.font(12)).foregroundStyle(HUDStyle.dim)
            } else if !session.canChooseClass {
                Text("Come back when you reach level \(session.content.classChoiceLevel).").font(HUDStyle.font(12)).foregroundStyle(HUDStyle.dim)
            } else if confirming {
                HStack {
                    Text("This choice is permanent. Sure?").font(HUDStyle.font(12))
                    Button("Yes, become a \(path.name)") {
                        session.chooseClass(path.id)
                        session.save()
                        reply = "Welcome to the \(path.guild ?? "guild"), \(path.name)! Your new skills await."
                    }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                    Button("Not yet") { confirming = false }
                        .buttonStyle(PixelButtonStyle(compact: true))
                }
            } else {
                Button("Join and become a \(path.name)") { confirming = true }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
            }
        }
    }
}

/// A boss: how strong it is, and a button to take it on.
private struct BossPanel: View {
    let session: GameSession
    let boss: NPCDef
    let onFight: (NPCDef) -> Void

    var body: some View {
        let species = boss.monster.flatMap(session.content.monster)
        let level = boss.level ?? 10
        VStack(alignment: .leading, spacing: 8) {
            if let species {
                HStack(spacing: 8) {
                    Text("Lv \(level) \(species.name)").foregroundStyle(HUDStyle.gold)
                    ElementBadge(element: species.element)
                }
                .font(HUDStyle.font(13))
                if level > session.data.hero.level + 2 {
                    Text("This looks really dangerous at your level…").font(HUDStyle.font(11)).foregroundStyle(HUDStyle.orange)
                }
            }
            if session.isDefeated(boss) {
                EmptyNote("You've already beaten it.")
            } else {
                Button { onFight(boss) } label: { Label("Fight!", icon: .sword) }
                    .buttonStyle(PixelButtonStyle(tint: Color(red: 1, green: 0.55, blue: 0.5)))
            }
        }
    }
}

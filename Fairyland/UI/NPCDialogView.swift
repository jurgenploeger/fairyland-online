import SwiftUI

/// Talking to someone in town: the healer, the shop, the quest giver, a guild master — or opening a gift box.
struct NPCDialogView: View {
    let npc: NPCDef
    let session: GameSession
    let onClose: () -> Void
    /// Bosses: start the fight.
    var onFight: (NPCDef) -> Void = { _ in }
    @State private var reply: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 0) {
                FLTitleBar(title: npc.name, onClose: onClose)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        SpriteImage(art: npc.art, size: 60)
                            .background(Circle().fill(.white.opacity(0.08)))
                        Text(reply ?? npc.greeting)
                            .font(HUDStyle.font(13))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
                    }
                    ScrollView {
                        Group {
                            switch npc.role {
                            case .healer: HealerPanel(session: session, reply: $reply)
                            case .shop: ShopPanel(session: session, stock: npc.stock ?? [], reply: $reply)
                            case .quests: QuestGiverPanel(session: session, giver: npc.id, reply: $reply)
                            case .guild: GuildPanel(session: session, classID: npc.classId ?? "", reply: $reply)
                            case .chest: ChestPanel(session: session, chest: npc, reply: $reply)
                            case .boss: BossPanel(session: session, boss: npc, onFight: onFight)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 260)
                }
                .padding(12)
            }
            .foregroundStyle(HUDStyle.cream)
            .frame(maxWidth: 680)
            .background(HUDStyle.panel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(10)
        }
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

private struct ChestPanel: View {
    let session: GameSession
    let chest: NPCDef
    @Binding var reply: String?

    var body: some View {
        if session.isOpened(chest.id) {
            EmptyNote("It's empty now.")
        } else if session.canOpen(chest) {
            Button {
                if let item = session.openChest(chest) {
                    session.save()
                    reply = "You untie the ribbon… You found a \(item.name)!"
                }
            } label: {
                Label("Open the gift box", icon: .gift)
            }
            .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
        } else {
            Text("The ribbon is tied tight. Maybe Elder Oak knows who it's for.")
                .font(HUDStyle.font(12))
                .foregroundStyle(HUDStyle.dim)
        }
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
                                        reply = "\(answer.text)… a fine answer. Now, off you go — the gift boxes are hidden around town!"
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

import SwiftUI

/// Character, Companions, Bag and Quests in one tabbed panel.
struct MenuView: View {
    let session: GameSession
    let onClose: () -> Void
    var onQuitToTitle: (() -> Void)?
    @State private var tab: MenuTab

    init(session: GameSession, initialTab: MenuTab, onClose: @escaping () -> Void, onQuitToTitle: (() -> Void)? = nil) {
        self.session = session
        self.onClose = onClose
        self.onQuitToTitle = onQuitToTitle
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(MenuTab.allCases) { item in
                        Button {
                            if tab != item { SoundEffects.shared.play(.tap, volume: 0.7) }
                            tab = item
                        } label: {
                            Label(item.rawValue, icon: item.icon)
                                .labelStyle(TabLabelStyle(selected: item == tab))
                        }
                    }
                    Spacer(minLength: 4)
                    OrangeCloseButton(action: onClose)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(LinearGradient(colors: [HUDStyle.frameLight, HUDStyle.frameMid, HUDStyle.frameDark], startPoint: .top, endPoint: .bottom))

                ScrollView {
                    Group {
                        switch tab {
                        case .character: CharacterTab(session: session)
                        case .companions: CompanionsTab(session: session)
                        case .bag: BagTab(session: session)
                        case .quests: QuestsTab(session: session)
                        case .settings: SettingsView(session: session, onQuitToTitle: onQuitToTitle)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 760)
            .background(HUDStyle.panel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(10)
        }
        .foregroundStyle(HUDStyle.cream)
    }
}

private struct TabLabelStyle: LabelStyle {
    let selected: Bool
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            // Icons only in narrow portrait layouts.
            if verticalSizeClass == .compact || selected { configuration.title }
        }
        .font(HUDStyle.font(12))
        .foregroundStyle(selected ? HUDStyle.ink : HUDStyle.cream)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(selected ? HUDStyle.gold : .white.opacity(0.08)))
    }
}

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(HUDStyle.font(11))
            .foregroundStyle(HUDStyle.gold)
            .padding(.top, 4)
    }
}

// MARK: - Character

private struct CharacterTab: View {
    let session: GameSession
    @State private var changingSlot: ItemType?
    @State private var editing = false
    @State private var renaming = false
    @FocusState private var nameFocused: Bool
    @State private var draftName = ""
    @State private var draftLook = Look.standard

    var body: some View {
        let hero = session.data.hero
        let stats = session.heroStats
        if editing {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Customize your hero")
                LookEditor(name: $draftName, look: $draftLook, raceID: session.data.hero.raceID, isUnlocked: session.isUnlocked)
                HStack {
                    Button("Cancel") { editing = false }
                        .buttonStyle(PixelButtonStyle(compact: true))
                    Spacer()
                    Button {
                        session.customizeHero(name: draftName, look: draftLook)
                        editing = false
                    } label: {
                        Label("Save look", icon: .check)
                    }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                }
            }
        } else {
            overview(hero: hero, stats: stats)
        }
    }

    private func saveName() {
        session.customizeHero(name: draftName, look: session.data.hero.look ?? .standard)
        renaming = false
    }

    @ViewBuilder
    private func overview(hero: Hero, stats: Stats) -> some View {
        AdaptiveStack(spacing: 18) {
            VStack(spacing: 6) {
                SpriteImage(art: GameSession.heroArt, size: 156)
                    .background(Circle().fill(.white.opacity(0.06)))
                if renaming {
                    HStack(spacing: 6) {
                        TextField("Name", text: $draftName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .font(HUDStyle.font(16))
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .frame(width: 140)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.12)))
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(saveName)
                            .onChange(of: draftName) { _, value in
                                if value.count > 12 { draftName = String(value.prefix(12)) }
                            }
                        Button(action: saveName) {
                            IconImage(.check, size: 16)
                                .foregroundStyle(HUDStyle.ink)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(HUDStyle.gold))
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel("Save name")
                    }
                } else {
                    Button {
                        draftName = hero.name
                        renaming = true
                        nameFocused = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(hero.name).font(HUDStyle.font(18))
                            IconImage(.edit, size: 15).foregroundStyle(HUDStyle.gold)
                        }
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("Rename \(hero.name)")
                }
                Button {
                    draftName = hero.name
                    draftLook = hero.look ?? .standard
                    editing = true
                } label: {
                    Label("Customize", icon: .palette)
                }
                .buttonStyle(PixelButtonStyle(compact: true))
                Text("\(session.heroRace.name) · \(session.heroClass.name)")
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.gold)
                Text(session.rebirths > 0 ? "Level \(hero.level) · Reborn ×\(session.rebirths)" : "Level \(hero.level)").font(HUDStyle.font(12))
                StatBar(label: "EXP", value: hero.exp, maximum: GameSession.expToNext(level: hero.level), color: HUDStyle.exp)
                    .frame(width: 170)
                if session.canChooseClass {
                    Text("Ready to choose a path! Visit a guild master in Meadowbrook.")
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.green)
                        .multilineTextAlignment(.center)
                        .frame(width: 170)
                }
            }
            .frame(minWidth: 190)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Stats")
                StatBar(label: "HP", value: hero.hp, maximum: stats.hp, color: HUDStyle.hp)
                StatBar(label: "MP", value: hero.mp, maximum: stats.mp, color: HUDStyle.mp)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    StatCell(name: "Attack", value: stats.attack)
                    StatCell(name: "Defense", value: stats.defense)
                    StatCell(name: "Magic", value: stats.magic)
                    StatCell(name: "Speed", value: stats.speed)
                }

                SectionTitle(text: "Equipment")
                ForEach(ItemType.equipmentSlots, id: \.self) { slot in
                    EquipmentRow(session: session, slot: slot, isChanging: changingSlot == slot) {
                        changingSlot = changingSlot == slot ? nil : slot
                    }
                }

                HStack {
                    SectionTitle(text: "Skills")
                    Spacer()
                    if session.unspentSkillPoints > 0 {
                        Text("\(session.unspentSkillPoints) skill point\(session.unspentSkillPoints == 1 ? "" : "s") to spend")
                            .font(HUDStyle.font(11))
                            .foregroundStyle(HUDStyle.gold)
                    }
                }
                if session.heroSkills.isEmpty && session.learnableSkills.isEmpty {
                    EmptyNote(session.skillHint, size: 11)
                }
                SkillChoices(session: session)
                let upcoming = session.heroClass.skills.filter { $0.level > hero.level }
                ForEach(upcoming, id: \.skill) { unlock in
                    if let skill = session.content.skill(unlock.skill) {
                        // Still locked: a faded tile, with the level it unlocks at.
                        HStack(spacing: 8) {
                            SkillIcon(skill: skill, size: 28)
                                .saturation(0.2)
                                .opacity(0.55)
                            Text(skill.name)
                                .foregroundStyle(HUDStyle.dim)
                            Spacer()
                            Text("Lv \(unlock.level)")
                                .font(HUDStyle.font(10))
                                .foregroundStyle(HUDStyle.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(HUDStyle.dim))
                        }
                        .font(HUDStyle.font(11))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StatCell: View {
    let name: String
    let value: Int

    var body: some View {
        HStack {
            Text(name).foregroundStyle(HUDStyle.dim)
            Spacer()
            Text("\(value)")
        }
        .font(HUDStyle.font(12))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.06)))
    }
}

private struct EquipmentRow: View {
    let session: GameSession
    let slot: ItemType
    let isChanging: Bool
    let toggle: () -> Void

    var body: some View {
        let equipped = session.data.hero.equipment[slot].flatMap { session.content.item($0) }
        let options = session.bagEquipment.filter { $0.type == slot }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(slot.displayName)
                    .foregroundStyle(HUDStyle.dim)
                    .frame(width: 80, alignment: .leading)
                if let equipped {
                    ItemIcon(item: equipped, size: 30)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(equipped?.name ?? "—")
                    if let bonus = equipped?.stats?.bonusSummary, !bonus.isEmpty {
                        Text(bonus).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.green)
                    }
                }
                Spacer()
                if !options.isEmpty || equipped != nil {
                    Button(isChanging ? "Done" : "Change", action: toggle)
                        .buttonStyle(PixelButtonStyle(compact: true))
                }
            }
            .font(HUDStyle.font(12))

            if isChanging {
                ForEach(options) { item in
                    HStack(spacing: 8) {
                        ItemIcon(item: item, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                            Text(item.stats?.bonusSummary ?? "").font(HUDStyle.font(10)).foregroundStyle(HUDStyle.green)
                        }
                        Spacer()
                        if let issue = session.equipIssue(item) {
                            Text(issue).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                        } else {
                            Button("Equip") { session.equip(item.id) }
                                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                        }
                    }
                    .font(HUDStyle.font(12))
                    .padding(.leading, 80)
                }
                if equipped != nil {
                    Button("Unequip") { session.unequip(slot) }
                        .buttonStyle(PixelButtonStyle(compact: true))
                        .padding(.leading, 80)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.05)))
    }
}

struct ElementBadge: View {
    let element: Element

    var body: some View {
        Text(element.displayName)
            .font(HUDStyle.font(9))
            .foregroundStyle(HUDStyle.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color(uiColor: element.color)))
    }
}

// MARK: - Companions

private struct CompanionsTab: View {
    let session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Companions fight beside you and earn a share of battle EXP. Weaken a wild monster below half HP and use Capture to befriend it (up to \(GameSession.maxPets)).")
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.dim)
            if session.data.pets.isEmpty {
                EmptyNote("No companions yet.\nFinish the Hope of Meadowbrook quest for an egg.")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
                ForEach(session.data.pets) { pet in
                    CompanionCard(session: session, pet: pet)
                }
            }

            SectionTitle(text: "Party & friends")
            Text("Befriend adventurers you meet (walk up to one). Up to \(GameSession.maxAllies) friends can travel and fight with you.")
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.dim)
            if session.friends.isEmpty {
                EmptyNote("No friends yet.\nSay hi to the adventurers you meet!")
            }
            ForEach(session.friends) { friend in
                FriendRow(session: session, friend: friend)
            }
        }
    }
}

private struct FriendRow: View {
    let session: GameSession
    let friend: Adventurer

    var body: some View {
        let inParty = session.isInParty(friend)
        HStack(spacing: 10) {
            SpriteImage(art: session.artID(for: friend), size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(friend.name)
                    if inParty {
                        Text("IN PARTY")
                            .font(HUDStyle.font(9))
                            .foregroundStyle(HUDStyle.ink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(HUDStyle.green))
                    }
                }
                Text("Lv \(friend.level) \(session.content.race(friend.raceID).name) \(session.content.classDef(friend.classID).name)")
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
            }
            Spacer()
            if inParty {
                Button("Leave") { session.leaveParty(friend.id) }
                    .buttonStyle(PixelButtonStyle(compact: true))
            } else if !session.adventurersAround.contains(friend.id) {
                // Friends have to be here to join you.
                Text("Not around")
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
            } else if session.partyMembers.count < GameSession.maxAllies {
                Button("Invite") { session.invite(friend.id) }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
            }
        }
        .font(HUDStyle.font(12))
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
    }
}

private struct CompanionCard: View {
    let session: GameSession
    let pet: Pet
    @State private var editing = false

    var body: some View {
        let species = session.species(of: pet)
        let stats = session.stats(of: pet)
        let isActive = session.data.activePetID == pet.id
        if editing {
            CompanionEditor(session: session, pet: pet) { editing = false }
        } else {
            card(species: species, stats: stats, isActive: isActive)
        }
    }

    @ViewBuilder
    private func card(species: MonsterDef?, stats: Stats, isActive: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SpriteImage(art: session.artID(for: pet), size: 72)
                .background(Circle().fill(.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pet.name).font(HUDStyle.font(14))
                    if let element = species?.element { ElementBadge(element: element) }
                }
                Text("\(species?.name ?? pet.speciesID) · Lv \(pet.level)")
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.gold)
                StatBar(label: "HP", value: pet.hp, maximum: stats.hp, color: HUDStyle.hp)
                StatBar(label: "EXP", value: pet.exp, maximum: GameSession.expToNext(level: pet.level), color: HUDStyle.exp)
                Text("ATK \(stats.attack) · DEF \(stats.defense) · MAG \(stats.magic) · SPD \(stats.speed)")
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
                if let skills = species?.skills.compactMap({ session.content.skill($0) }), !skills.isEmpty {
                    // What it can do in a fight.
                    HStack(spacing: 6) {
                        ForEach(skills) { skill in
                            HStack(spacing: 3) {
                                SkillIcon(skill: skill, size: 22)
                                Text(skill.name)
                                    .font(HUDStyle.font(10))
                                    .foregroundStyle(HUDStyle.cream)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    if isActive {
                        Label("Following you", icon: .checkCircle)
                            .font(HUDStyle.font(11))
                            .foregroundStyle(HUDStyle.green)
                    } else {
                        Button("Bring along") { session.setActivePet(pet.id) }
                            .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                    }
                    Button {
                        editing = true
                    } label: {
                        Label("Rename", icon: .edit)
                    }
                    .buttonStyle(PixelButtonStyle(compact: true))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(isActive ? 0.1 : 0.05))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isActive ? HUDStyle.green.opacity(0.7) : .clear, lineWidth: 2))
        )
    }
}

// MARK: - Bag

private struct BagTab: View {
    let session: GameSession
    @State private var note: String?
    @State private var hatched: Pet?
    @State private var hatching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(session.data.gold) gold", icon: .coins)
                    .foregroundStyle(HUDStyle.gold)
                Spacer()
                if let note { Text(note).foregroundStyle(HUDStyle.green) }
            }
            .font(HUDStyle.font(12))

            SectionTitle(text: "Items")
            if session.consumables.isEmpty {
                Text("No potions. Trader Bo in Meadowbrook sells them.").font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            }
            ForEach(session.consumables) { item in
                HStack(spacing: 10) {
                    ItemIcon(item: item, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(item.name) ×\(session.count(of: item.id))")
                        Text(item.description ?? "").font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                    }
                    Spacer()
                    if item.hatches != nil {
                        Button {
                            hatching = true
                            hatched = session.hatch(item.id)
                            session.save()
                        } label: {
                            Label("Hatch", icon: .egg)
                        }
                        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                    } else {
                        Button("Hero") { note = session.use(item.id) }
                            .buttonStyle(PixelButtonStyle(compact: true))
                        if let pet = session.activePet {
                            Button(pet.name) { note = session.use(item.id, onPet: pet.id) }
                                .buttonStyle(PixelButtonStyle(compact: true))
                        }
                    }
                }
                .font(HUDStyle.font(12))
            }

            if hatching, let pet = hatched {
                HatchView(session: session, pet: pet) { hatching = false }
            }

            SectionTitle(text: "Equipment")
            if session.bagEquipment.isEmpty {
                Text("Nothing spare. Equipped gear is on the Character tab.").font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            }
            ForEach(session.bagEquipment) { item in
                HStack(spacing: 10) {
                    ItemIcon(item: item, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(item.name)  ·  \(item.type.displayName)")
                        Text(item.stats?.bonusSummary ?? "").font(HUDStyle.font(10)).foregroundStyle(HUDStyle.green)
                    }
                    Spacer()
                    if let issue = session.equipIssue(item) {
                        Text(issue).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                    } else {
                        Button("Equip") { session.equip(item.id) }
                            .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                    }
                }
                .font(HUDStyle.font(12))
            }

            SectionTitle(text: "Materials")
            if session.bagMaterials.isEmpty {
                Text("Monsters drop wood, metal, gems and hides. A town smith forges them into weapons.")
                    .font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            }
            ForEach(session.bagMaterials) { item in
                HStack(spacing: 10) {
                    ItemIcon(item: item, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(item.name) ×\(session.count(of: item.id))")
                        Text(item.description ?? "").font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                    }
                    Spacer()
                }
                .font(HUDStyle.font(12))
            }
        }
    }
}

/// The egg wobbles, cracks, and your first companion pops out.
private struct HatchView: View {
    let session: GameSession
    let pet: Pet
    let onDone: () -> Void
    @State private var stage = 0

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if stage < 2 {
                    SpriteImage(art: "pet_egg", size: 90)
                        .rotationEffect(.degrees(stage == 1 ? 12 : -12))
                        .animation(.easeInOut(duration: 0.12).repeatCount(8, autoreverses: true), value: stage)
                } else {
                    SpriteImage(art: session.artID(for: pet), size: 110)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                    IconImage(.sparkles, size: 40)
                        .foregroundStyle(HUDStyle.gold)
                        .offset(x: 44, y: -40)
                }
            }
            .frame(height: 120)
            Text(stage < 2 ? "Something is hatching…" : "\(pet.name) hatched! Your first companion.")
                .font(HUDStyle.font(14))
                .foregroundStyle(HUDStyle.gold)
            if stage >= 2 {
                Button("Hello, \(pet.name)!", action: onDone)
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
        .task {
            stage = 1
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { stage = 2 }
        }
    }
}

// MARK: - Quests

private struct QuestsTab: View {
    let session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Active")
            if session.activeQuests.isEmpty {
                Text("No active quests. Elder Oak in Meadowbrook always needs help.").font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            }
            ForEach(session.activeQuests) { quest in
                QuestRow(session: session, quest: quest)
            }
            if !session.completedQuests.isEmpty {
                SectionTitle(text: "Completed")
                ForEach(session.completedQuests) { quest in
                    Label(quest.title, icon: .badgeCheck)
                        .font(HUDStyle.font(12))
                        .foregroundStyle(HUDStyle.dim)
                }
            }
        }
    }
}

struct QuestRow: View {
    let session: GameSession
    let quest: QuestDef

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(quest.title).font(HUDStyle.font(13))
                Spacer()
                switch session.status(of: quest) {
                case .active(let progress, let goal): Text("\(progress)/\(goal)").foregroundStyle(HUDStyle.gold)
                case .ready: Text("Done! Report back").foregroundStyle(HUDStyle.green)
                default: EmptyView()
                }
            }
            .font(HUDStyle.font(12))
            Text(quest.description).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.05)))
    }
}

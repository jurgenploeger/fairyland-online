import CoreGraphics
import Foundation
import Observation

/// The player's progress: hero, companions, bag, quests. All rules for levelling,
/// equipment, class choice and quests live here; the scenes and UI just call in.
@Observable
final class GameSession {
    /// Like Fairyland, a handful of companions; catch a sixth and one has to stay behind.
    static let maxPets = 5
    /// A newly caught companion waiting for room in a full party.
    var pendingPet: Pet?
    /// The adventurer you're standing next to (the HUD shows their card).
    var nearbyAdventurer: Adventurer?
    /// Up to two friends can travel with you.
    static let maxAllies = 2

    var data: SaveData
    /// Name of the map the player is on, for the HUD.
    var mapName = ""
    /// NPC close enough to talk to, for the HUD's Talk button.
    var nearbyNPC: String?
    /// The tile the hero stands on, for the minimap.
    var mapCell = GridPoint(col: 0, row: 0)
    /// Recent system messages, shown Fairyland-style in the HUD.
    private(set) var log: [LogLine] = []
    /// When the game was last written to disk (the HUD flashes "Saved").
    private(set) var lastSaved: Date?

    struct LogLine: Identifiable {
        enum Kind { case system, quest, battle, reward }
        let id = UUID()
        let text: String
        let kind: Kind
        let time = Date()
    }

    /// What people on this map have said: the Chat window. Starts over on each map.
    struct ChatLine: Identifiable {
        enum Kind { case you, adventurer, villager, npc, system }
        let id = UUID()
        let speaker: String
        let text: String
        let kind: Kind
        let time = Date()
    }

    private(set) var chat: [ChatLine] = []
    var unreadChat = 0

    func postChat(_ text: String, from speaker: String, kind: ChatLine.Kind) {
        chat.append(ChatLine(speaker: speaker, text: text, kind: kind))
        if chat.count > 80 { chat.removeFirst(chat.count - 80) }
        if kind != .you { unreadChat += 1 }
    }

    func startChat(on mapName: String) {
        chat = [ChatLine(speaker: "", text: "You entered \(mapName).", kind: .system)]
        unreadChat = 0
    }

    func post(_ text: String, _ kind: LogLine.Kind = .system) {
        log.append(LogLine(text: text, kind: kind))
        if log.count > 12 { log.removeFirst(log.count - 12) }
    }
    /// Last known position on the current map (saved with the game).
    @ObservationIgnored var playerPosition: CGPoint?

    var content: Content { .shared }

    init(data: SaveData) {
        self.data = data
        if let position = data.position, position.count == 2 {
            playerPosition = CGPoint(x: position[0], y: position[1])
        }
        if self.data.hero.learnedSkills == nil {
            // Older saves learned skills automatically; keep them, and don't charge for them.
            let legacy = classSkills(upTo: data.hero.level).map(\.id)
            self.data.hero.learnedSkills = legacy
            self.data.hero.bonusSkillPoints = legacy.count
        }
        applyLook()
    }

    static func newGame(name: String, raceID: String, look: Look = .standard) -> GameSession {
        let content = Content.shared
        let hero = Hero(
            name: name, raceID: raceID, classID: "novice", level: 1, exp: 0, hp: 1, mp: 0,
            equipment: Equipment(armor: "cloth_tunic"), look: look
        )
        let data = SaveData(
            hero: hero, pets: [], activePetID: nil, gold: 30, inventory: ["potion": 3],
            quests: [:], mapID: content.startMap, position: nil, startedAt: Date()
        )
        let session = GameSession(data: data)
        session.restoreHero()
        // Like Fairyland, your first companion comes from an egg in the first quest.
        return session
    }

    func save() {
        data.position = playerPosition.map { [Double($0.x), Double($0.y)] }
        SaveStore.save(data)
        lastSaved = Date()
    }

    // MARK: - Looks

    /// Art id of the hero as customised: a recoloured copy of player_walk.
    static let heroArt = "hero"

    /// Worn armour takes over the outfit's colours (leather, steel, silk…).
    static func rules(for look: Look, armor: ItemDef? = nil) -> [RecolorRule] {
        let options = Content.shared.appearance
        let outfit = armor?.recolor.flatMap { $0.isEmpty ? nil : $0 } ?? options.outfits.first { $0.id == look.outfit }?.recolor ?? []
        // Skin first (pale), then hair (saturated), then outfit (green) — they never overlap.
        return (options.skin.first { $0.id == look.skin }?.recolor ?? [])
            + (options.hair.first { $0.id == look.hair }?.recolor ?? [])
            + outfit
    }

    func equipped(_ slot: ItemType) -> ItemDef? {
        data.hero.equipment[slot].flatMap(content.item)
    }

    /// Changes whenever the hero's sprite should be redrawn (look, race or gear).
    var heroLookKey: String {
        let gear = ItemType.equipmentSlots.map { data.hero.equipment[$0] ?? "-" }.joined(separator: ",")
        return "\(heroRace.sheet)/\((data.hero.look ?? .standard).key)/\(gear)"
    }

    func applyLook() {
        let look = data.hero.look ?? .standard
        ArtLibrary.shared.register(Self.heroArt, from: heroRace.sheet, recolor: Self.rules(for: look, armor: equipped(.armor)), key: heroLookKey)
    }

    func customizeHero(name: String, look: Look) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { data.hero.name = String(trimmed.prefix(12)) }
        data.hero.look = look
        applyLook()
        post("Looking good, \(data.hero.name)!", .reward)
        save()
    }

    /// A companion looks like its species; colourful ones are rarer variants you catch.
    func artID(for pet: Pet) -> String {
        species(of: pet)?.art ?? ""
    }

    func renamePet(_ id: UUID, to name: String) {
        guard let index = data.pets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        data.pets[index].name = String(trimmed.prefix(12))
        post("\(data.pets[index].name) loves the new name!", .reward)
        save()
    }

    // MARK: - Hero

    var heroRace: RaceDef { content.race(data.hero.raceID) }
    var heroClass: ClassDef { content.classDef(data.hero.classID) }

    var heroStats: Stats {
        heroRace.base + heroClass.growth * (data.hero.level - 1) + equipmentBonus
    }

    var equipmentBonus: Stats {
        ItemType.equipmentSlots
            .compactMap { data.hero.equipment[$0] }
            .compactMap { content.item($0)?.stats }
            .reduce(Stats.zero, +)
    }

    // MARK: - Skills
    //
    // Every level gives a skill point. Your class unlocks new skills at milestone levels;
    // a point either learns one of those or raises a skill you know (up to level 5).

    /// Skills you've learned that your current class uses.
    var heroSkills: [SkillDef] {
        let learned = Set(data.hero.learnedSkills ?? [])
        return classSkills(upTo: data.hero.level).filter { learned.contains($0.id) }
    }

    /// Skills your class offers at your level that you haven't learned yet.
    var learnableSkills: [SkillDef] {
        let learned = Set(data.hero.learnedSkills ?? [])
        return classSkills(upTo: data.hero.level).filter { !learned.contains($0.id) }
    }

    /// The next skill your class unlocks at a higher level.
    var nextSkillUnlock: (skill: SkillDef, level: Int)? {
        heroClass.skills.filter { $0.level > data.hero.level }.min { $0.level < $1.level }
            .flatMap { unlock in content.skill(unlock.skill).map { ($0, unlock.level) } }
    }

    private func classSkills(upTo level: Int) -> [SkillDef] {
        heroClass.skills.filter { $0.level <= level }.compactMap { content.skill($0.skill) }
    }

    /// "No skills yet" plus what to do about it.
    var skillHint: String {
        if let skill = learnableSkills.first { return "No skills yet.\nSpend your skill point to learn \(skill.name)." }
        if let next = nextSkillUnlock { return "No skills yet.\nYou can learn \(next.skill.name) at level \(next.level)." }
        return "No skills yet."
    }

    static let maxSkillLevel = 5

    func skillLevel(_ id: String) -> Int {
        max(1, data.hero.skillLevels?[id] ?? 1)
    }

    /// One point per level gained. Learning costs one and each upgrade one; points in skills
    /// your class no longer has come back.
    var unspentSkillPoints: Int {
        let spent = heroSkills.reduce(0) { $0 + skillLevel($1.id) }
        return max(0, data.hero.level - 1 + (data.hero.bonusSkillPoints ?? 0) - spent)
    }

    func learnSkill(_ id: String) {
        guard unspentSkillPoints > 0, let skill = learnableSkills.first(where: { $0.id == id }) else { return }
        SoundEffects.shared.play(.learn)
        data.hero.learnedSkills = (data.hero.learnedSkills ?? []) + [id]
        var levels = data.hero.skillLevels ?? [:]
        levels[id] = 1
        data.hero.skillLevels = levels
        post("You learned \(skill.name)!", .reward)
    }

    func upgradeSkill(_ id: String) {
        guard unspentSkillPoints > 0, heroSkills.contains(where: { $0.id == id }), skillLevel(id) < Self.maxSkillLevel else { return }
        var levels = data.hero.skillLevels ?? [:]
        levels[id] = skillLevel(id) + 1
        data.hero.skillLevels = levels
    }

    /// Higher skill levels hit harder and cost a little more.
    static func mpCost(of skill: SkillDef, level: Int) -> Int { skill.mp + (level - 1) }

    var canChooseClass: Bool {
        data.hero.classID == "novice" && data.hero.level >= content.classChoiceLevel
    }

    static func expToNext(level: Int) -> Int { 10 + level * level * 5 }

    func restoreHero() {
        let stats = heroStats
        data.hero.hp = stats.hp
        data.hero.mp = stats.mp
    }

    /// Adds EXP and returns how many levels the hero gained.
    @discardableResult
    func gainHeroEXP(_ amount: Int) -> Int {
        guard amount > 0 else { return 0 }
        data.hero.exp += amount
        var levels = 0
        while data.hero.exp >= Self.expToNext(level: data.hero.level) {
            data.hero.exp -= Self.expToNext(level: data.hero.level)
            data.hero.level += 1
            levels += 1
        }
        if levels > 0 { restoreHero() }
        return levels
    }

    func chooseClass(_ id: String) {
        guard canChooseClass, content.classes.contains(where: { $0.id == id }) else { return }
        data.hero.classID = id
        SoundEffects.shared.play(.levelUp)
        Haptics.success()
        post("You joined the \(content.classDef(id).guild ?? "guild") as a \(content.classDef(id).name)!", .reward)
        // Gear the new class can't use goes back into the bag.
        for slot in ItemType.equipmentSlots {
            if let itemID = data.hero.equipment[slot], let item = content.item(itemID), equipIssue(item) != nil {
                unequip(slot)
            }
        }
        restoreHero()
    }

    private func clampHero() {
        let stats = heroStats
        data.hero.hp = min(data.hero.hp, stats.hp)
        data.hero.mp = min(data.hero.mp, stats.mp)
    }

    // MARK: - Companions

    var activePet: Pet? { data.pets.first { $0.id == data.activePetID } }

    func species(of pet: Pet) -> MonsterDef? { content.monster(pet.speciesID) }

    func stats(of pet: Pet) -> Stats { species(of: pet)?.stats(at: pet.level) ?? .zero }

    func makePet(species id: String, level: Int, name: String? = nil) -> Pet? {
        guard let species = content.monster(id) else { return nil }
        let stats = species.stats(at: level)
        return Pet(id: UUID(), speciesID: id, name: name ?? species.name, level: level, exp: 0, hp: stats.hp, mp: stats.mp)
    }

    @discardableResult
    func addPet(_ pet: Pet, countsForQuests: Bool = true) -> Bool {
        guard data.pets.count < Self.maxPets else { return false }
        data.pets.append(pet)
        if data.activePetID == nil { data.activePetID = pet.id }
        if countsForQuests { record(.capture, target: pet.speciesID) }
        return true
    }

    // MARK: - Friends & party

    var friends: [Adventurer] { data.friends ?? [] }

    var partyMembers: [Adventurer] {
        (data.partyIDs ?? []).compactMap { id in friends.first { $0.id == id } }
    }

    func isFriend(_ adventurer: Adventurer) -> Bool { friends.contains { $0.id == adventurer.id } }
    func isInParty(_ adventurer: Adventurer) -> Bool { data.partyIDs?.contains(adventurer.id) == true }

    /// Most adventurers are happy to be friends; the grumpy red-named ones aren't.
    @discardableResult
    func befriend(_ adventurer: Adventurer) -> Bool {
        guard !isFriend(adventurer), !adventurer.hostile else { return false }
        var friend = adventurer
        friend.hostile = false
        data.friends = friends + [friend]
        post("\(adventurer.name) is now your friend!", .reward)
        save()
        return true
    }

    func invite(_ id: UUID) {
        guard let friend = friends.first(where: { $0.id == id }), !isInParty(friend), partyMembers.count < Self.maxAllies else { return }
        // Friends keep up with you.
        let level = max(friend.level, data.hero.level - 1)
        if let index = data.friends?.firstIndex(where: { $0.id == id }) {
            data.friends?[index].level = level
        }
        data.partyIDs = (data.partyIDs ?? []) + [id]
        post("\(friend.name) joined your party!", .reward)
        save()
    }

    func leaveParty(_ id: UUID) {
        guard let friend = friends.first(where: { $0.id == id }) else { return }
        data.partyIDs?.removeAll { $0 == id }
        post("\(friend.name) left the party. See you around!")
        save()
    }

    func unfriend(_ id: UUID) {
        leaveParty(id)
        data.friends?.removeAll { $0.id == id }
        save()
    }

    func stats(of adventurer: Adventurer) -> Stats {
        content.race(adventurer.raceID).base + content.classDef(adventurer.classID).growth * (adventurer.level - 1)
    }

    func skills(of adventurer: Adventurer) -> [SkillDef] {
        content.classDef(adventurer.classID).skills.filter { $0.level <= adventurer.level }.compactMap { content.skill($0.skill) }
    }

    /// Their walk sheet in their colours.
    func artID(for adventurer: Adventurer) -> String {
        let sheet = content.race(adventurer.raceID).sheet
        let id = "adv:\(adventurer.raceID):\(adventurer.look.key)"
        ArtLibrary.shared.register(id, from: sheet, recolor: Self.rules(for: adventurer.look), key: sheet + "/" + adventurer.look.key)
        return id
    }

    /// Party friends grow with you: a share of every win.
    func growParty() {
        let level = data.hero.level - 1
        let party = Set(data.partyIDs ?? [])
        guard var friends = data.friends else { return }
        for index in friends.indices where party.contains(friends[index].id) {
            friends[index].level = max(friends[index].level, level)
        }
        data.friends = friends
    }

    /// Full party: `id` stays behind (it may be the newcomer), and the newcomer takes its place.
    func leaveBehind(_ id: UUID) {
        guard let newcomer = pendingPet else { return }
        pendingPet = nil
        if id == newcomer.id {
            post("\(newcomer.name) waves goodbye and hops back to the wild.")
            return
        }
        guard let index = data.pets.firstIndex(where: { $0.id == id }) else { return }
        let parting = data.pets.remove(at: index)
        data.pets.append(newcomer)
        if data.activePetID == parting.id { data.activePetID = newcomer.id }
        post("\(parting.name) stays behind. \(newcomer.name) joined your party!", .reward)
        save()
    }

    func setActivePet(_ id: UUID) {
        guard data.pets.contains(where: { $0.id == id }) else { return }
        data.activePetID = id
    }

    /// Adds EXP to a companion and returns how many levels it gained.
    @discardableResult
    func gainPetEXP(_ id: UUID, _ amount: Int) -> Int {
        guard amount > 0, let index = data.pets.firstIndex(where: { $0.id == id }) else { return 0 }
        data.pets[index].exp += amount
        var levels = 0
        while data.pets[index].exp >= Self.expToNext(level: data.pets[index].level) {
            data.pets[index].exp -= Self.expToNext(level: data.pets[index].level)
            data.pets[index].level += 1
            levels += 1
        }
        if levels > 0 {
            let stats = stats(of: data.pets[index])
            data.pets[index].hp = stats.hp
            data.pets[index].mp = stats.mp
        }
        return levels
    }

    /// The healer: everyone back to full.
    func restParty() {
        SoundEffects.shared.play(.heal)
        restoreHero()
        for index in data.pets.indices {
            let stats = stats(of: data.pets[index])
            data.pets[index].hp = stats.hp
            data.pets[index].mp = stats.mp
        }
    }

    var checkpoint: Checkpoint {
        data.checkpoint ?? Checkpoint(mapID: content.startMap, entry: nil)
    }

    /// Walking into a map makes its entrance your checkpoint; towns revive you in the square.
    func reachCheckpoint(_ map: MapDef, entry: Edge?) {
        let point = Checkpoint(mapID: map.id, entry: map.fence == true ? nil : entry)
        guard point != data.checkpoint else { return }
        data.checkpoint = point
        post("Checkpoint saved at \(checkpointName(point)).", .quest)
    }

    func checkpointName(_ point: Checkpoint) -> String {
        let name = content.map(point.mapID)?.name ?? "town"
        return point.entry == nil ? name : "the \(name) entrance"
    }

    /// Lost a battle: wake up at the last checkpoint, bruised.
    func faint() {
        let stats = heroStats
        data.hero.hp = max(1, stats.hp / 2)
        data.hero.mp = stats.mp / 2
        for index in data.pets.indices where data.pets[index].hp <= 0 {
            data.pets[index].hp = 1
        }
        data.mapID = checkpoint.mapID
        playerPosition = nil
    }

    // MARK: - Eggs & gift boxes

    func isOpened(_ chestID: String) -> Bool {
        data.openedChests?.contains(chestID) == true
    }

    /// Whether a gift box can be opened yet (its quest has to be accepted first).
    func canOpen(_ chest: NPCDef) -> Bool {
        guard !isOpened(chest.id) else { return false }
        guard let questID = chest.quest else { return true }
        return data.quests[questID] != nil
    }

    /// Opens a gift box and returns the item inside.
    @discardableResult
    func openChest(_ chest: NPCDef) -> ItemDef? {
        guard canOpen(chest), let id = chest.gives, let item = content.item(id) else { return nil }
        data.openedChests = (data.openedChests ?? []) + [chest.id]
        SoundEffects.shared.play(.chest)
        addItem(id)
        record(.collect, target: "gift_box")
        post("Found \(item.name) in the gift box!", .reward)
        return item
    }

    /// Hatches an egg from the bag into a new companion.
    func hatch(_ eggID: String) -> Pet? {
        guard let egg = content.item(eggID), let pool = egg.hatches, !pool.isEmpty, count(of: eggID) > 0 else { return nil }
        let species = data.eggSpecies.flatMap { pool.contains($0) ? $0 : nil } ?? pool.randomElement()!
        guard let pet = makePet(species: species, level: 1), data.pets.count < Self.maxPets else { return nil }
        SoundEffects.shared.play(.hatch)
        Haptics.success()
        removeItem(eggID)
        addPet(pet, countsForQuests: false)
        data.activePetID = pet.id
        post("\(pet.name) hatched and joined you!", .reward)
        return pet
    }

    // MARK: - Items

    func count(of id: String) -> Int { data.inventory[id] ?? 0 }

    func addItem(_ id: String, _ amount: Int = 1) {
        data.inventory[id, default: 0] += amount
    }

    @discardableResult
    func removeItem(_ id: String) -> Bool {
        guard count(of: id) > 0 else { return false }
        data.inventory[id]! -= 1
        if data.inventory[id] == 0 { data.inventory[id] = nil }
        return true
    }

    var consumables: [ItemDef] {
        content.items.filter { $0.type == .consumable && count(of: $0.id) > 0 }
    }

    /// What you can drink or feed in battle (not eggs or Seal Stones).
    var battleItems: [ItemDef] {
        consumables.filter { ($0.heal ?? 0) > 0 || ($0.mp ?? 0) > 0 }
    }

    var sealStones: Int {
        content.items.filter { $0.capture == true }.reduce(0) { $0 + count(of: $1.id) }
    }

    var bagEquipment: [ItemDef] {
        content.items.filter { $0.type != .consumable && count(of: $0.id) > 0 }
    }

    /// Why the hero can't equip `item`, or nil if they can.
    func equipIssue(_ item: ItemDef) -> String? {
        if let classes = item.classes, !classes.contains(data.hero.classID) {
            let names = classes.map { content.classDef($0).name }.joined(separator: ", ")
            return "Only for \(names)"
        }
        if let level = item.level, data.hero.level < level {
            return "Needs level \(level)"
        }
        return nil
    }

    func equip(_ id: String) {
        guard let item = content.item(id), item.type != .consumable, equipIssue(item) == nil, removeItem(id) else { return }
        SoundEffects.shared.play(.equip)
        if let old = data.hero.equipment[item.type] { addItem(old) }
        data.hero.equipment[item.type] = id
        clampHero()
        applyLook()
    }

    func unequip(_ slot: ItemType) {
        guard let id = data.hero.equipment[slot] else { return }
        addItem(id)
        data.hero.equipment[slot] = nil
        clampHero()
        applyLook()
    }

    @discardableResult
    func buy(_ id: String) -> Bool {
        guard let item = content.item(id), data.gold >= item.price else { return false }
        data.gold -= item.price
        SoundEffects.shared.play(.coins)
        addItem(id)
        return true
    }

    /// Uses a potion or ether outside battle, on the hero or a companion. Returns a message.
    @discardableResult
    func use(_ id: String, onPet petID: UUID? = nil) -> String? {
        guard let item = content.item(id), item.type == .consumable, count(of: id) > 0 else { return nil }
        if let petID, let index = data.pets.firstIndex(where: { $0.id == petID }) {
            let stats = stats(of: data.pets[index])
            data.pets[index].hp = min(stats.hp, data.pets[index].hp + (item.heal ?? 0))
            data.pets[index].mp = min(stats.mp, data.pets[index].mp + (item.mp ?? 0))
            removeItem(id)
            return "\(data.pets[index].name) feels better."
        }
        let stats = heroStats
        data.hero.hp = min(stats.hp, data.hero.hp + (item.heal ?? 0))
        data.hero.mp = min(stats.mp, data.hero.mp + (item.mp ?? 0))
        removeItem(id)
        return "\(data.hero.name) feels better."
    }

    // MARK: - Quests

    enum QuestStatus: Equatable {
        case locked
        case available
        case active(progress: Int, goal: Int)
        case ready
        case completed
    }

    enum QuestNotice {
        case available, ready
    }

    func goal(of quest: QuestDef) -> Int {
        quest.objective.type == .chooseClass ? 1 : (quest.objective.count ?? 1)
    }

    func status(of quest: QuestDef) -> QuestStatus {
        if let progress = data.quests[quest.id] {
            if progress.state == .completed { return .completed }
            let goal = goal(of: quest)
            let current: Int = switch quest.objective.type {
            case .defeat, .capture, .collect: progress.count
            case .reachLevel: data.hero.level
            case .chooseClass: data.hero.classID == "novice" ? 0 : 1
            }
            return current >= goal ? .ready : .active(progress: current, goal: goal)
        }
        let prerequisitesDone = (quest.requires ?? []).allSatisfy { data.quests[$0]?.state == .completed }
        let levelOK = data.hero.level >= (quest.minLevel ?? 1)
        return prerequisitesDone && levelOK ? .available : .locked
    }

    func quests(from giver: String) -> [QuestDef] {
        content.quests.filter { $0.giver == giver && status(of: $0) != .locked }
    }

    var activeQuests: [QuestDef] {
        content.quests.filter { data.quests[$0.id]?.state == .active }
    }

    var completedQuests: [QuestDef] {
        content.quests.filter { data.quests[$0.id]?.state == .completed }
    }

    func notice(for giver: String) -> QuestNotice? {
        if let npc = content.npc(giver), npc.role == .chest {
            return canOpen(npc) ? .available : nil
        }
        let statuses = content.quests.filter { $0.giver == giver }.map { status(of: $0) }
        if statuses.contains(.ready) { return .ready }
        if statuses.contains(.available) { return .available }
        return nil
    }

    func acceptQuest(_ id: String, answer: QuestDef.Question.Answer? = nil) {
        guard let quest = content.quest(id), status(of: quest) == .available else { return }
        data.quests[id] = QuestProgress(state: .active, count: 0)
        SoundEffects.shared.play(.questAccept)
        if let answer { data.eggSpecies = answer.egg }
        post("Quest accepted: \(quest.title)", .quest)
        for item in quest.starterItems ?? [] { addItem(item) }
        if let first = quest.starterItems?.first, let item = content.item(first) {
            let count = quest.starterItems?.count ?? 1
            post("Received \(count > 1 ? "\(count) " : "")\(item.name)\(count > 1 ? "s" : "").", .reward)
        }
    }

    /// Counts a defeat or capture toward matching active quests.
    func record(_ type: QuestDef.ObjectiveType, target: String?) {
        for quest in activeQuests where quest.objective.type == type {
            if let wanted = quest.objective.target, wanted != target { continue }
            data.quests[quest.id]?.count += 1
        }
    }

    func isDefeated(_ boss: NPCDef) -> Bool {
        data.defeatedBosses?.contains(boss.id) == true
    }

    func defeatBoss(_ boss: NPCDef) {
        guard !isDefeated(boss) else { return }
        data.defeatedBosses = (data.defeatedBosses ?? []) + [boss.id]
        save()
    }

    func hasCompleted(_ questID: String) -> Bool {
        data.quests[questID]?.state == .completed
    }

    /// Quests unlock extra looks…
    func isUnlocked(_ preset: LookPreset) -> Bool {
        preset.unlock.map(hasCompleted) ?? true
    }

    /// …and open new roads.
    func canTravel(_ exit: MapDef.Exit) -> Bool {
        exit.requires.map(hasCompleted) ?? true
    }

    /// Hands in a finished quest and pays out. Returns what was earned.
    @discardableResult
    func turnInQuest(_ id: String) -> [String] {
        guard let quest = content.quest(id), status(of: quest) == .ready else { return [] }
        data.quests[id]?.state = .completed
        SoundEffects.shared.play(.questDone)
        Haptics.success()
        post("Quest complete: \(quest.title)", .quest)
        var lines: [String] = []
        if let gold = quest.reward.gold {
            data.gold += gold
            lines.append("+\(gold) gold")
        }
        if let exp = quest.reward.exp {
            lines.append("+\(exp) EXP")
            if gainHeroEXP(exp) > 0 { lines.append("Level up! You're now level \(data.hero.level).") }
        }
        for itemID in quest.reward.items ?? [] {
            addItem(itemID)
            lines.append("Got \(content.item(itemID)?.name ?? itemID)")
        }
        let looks = [("hair", content.appearance.hair), ("outfit", content.appearance.outfits)]
            .flatMap { kind, presets in presets.filter { $0.unlock == id }.map { "\($0.name) \(kind)" } }
        if !looks.isEmpty {
            lines.append("New look\(looks.count > 1 ? "s" : ""): \(looks.joined(separator: ", ")). Try it in Character → Customize!")
        }
        for map in content.maps {
            for exit in map.exits where exit.requires == id {
                lines.append("The road from \(map.name) to \(content.map(exit.to)?.name ?? exit.to) is open!")
            }
        }
        return lines
    }
}

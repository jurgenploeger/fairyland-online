import CoreGraphics
import Foundation
import Observation

/// The player's progress: hero, companions, bag, quests. All rules for levelling,
/// equipment, class choice and quests live here; the scenes and UI just call in.
@Observable
final class GameSession {
    static let maxPets = 6

    var data: SaveData
    /// Name of the map the player is on, for the HUD.
    var mapName = ""
    /// NPC close enough to talk to, for the HUD's Talk button.
    var nearbyNPC: String?
    /// The tile the hero stands on, for the minimap.
    var mapCell = GridPoint(col: 0, row: 0)
    /// Recent system messages, shown Fairyland-style in the HUD.
    private(set) var log: [LogLine] = []

    struct LogLine: Identifiable {
        enum Kind { case system, quest, battle, reward }
        let id = UUID()
        let text: String
        let kind: Kind
        let time = Date()
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
    }

    static func newGame(name: String, raceID: String) -> GameSession {
        let content = Content.shared
        let hero = Hero(
            name: name, raceID: raceID, classID: "novice", level: 1, exp: 0, hp: 1, mp: 0,
            equipment: Equipment(armor: "cloth_tunic")
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

    var heroSkills: [SkillDef] {
        heroClass.skills.filter { $0.level <= data.hero.level }.compactMap { content.skill($0.skill) }
    }

    static let maxSkillLevel = 5

    func skillLevel(_ id: String) -> Int {
        max(1, data.hero.skillLevels?[id] ?? 1)
    }

    /// One point per level gained; points in skills your class no longer has come back.
    var unspentSkillPoints: Int {
        let spent = heroSkills.reduce(0) { $0 + skillLevel($1.id) - 1 }
        return max(0, data.hero.level - 1 - spent)
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
        restoreHero()
        for index in data.pets.indices {
            let stats = stats(of: data.pets[index])
            data.pets[index].hp = stats.hp
            data.pets[index].mp = stats.mp
        }
    }

    /// Lost a battle: wake up in town, bruised.
    func faint() {
        let stats = heroStats
        data.hero.hp = max(1, stats.hp / 2)
        data.hero.mp = stats.mp / 2
        for index in data.pets.indices where data.pets[index].hp <= 0 {
            data.pets[index].hp = 1
        }
        data.mapID = content.startMap
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
        if let old = data.hero.equipment[item.type] { addItem(old) }
        data.hero.equipment[item.type] = id
        clampHero()
    }

    func unequip(_ slot: ItemType) {
        guard let id = data.hero.equipment[slot] else { return }
        addItem(id)
        data.hero.equipment[slot] = nil
        clampHero()
    }

    @discardableResult
    func buy(_ id: String) -> Bool {
        guard let item = content.item(id), data.gold >= item.price else { return false }
        data.gold -= item.price
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
        if let answer { data.eggSpecies = answer.egg }
        post("Quest accepted: \(quest.title)", .quest)
    }

    /// Counts a defeat or capture toward matching active quests.
    func record(_ type: QuestDef.ObjectiveType, target: String?) {
        for quest in activeQuests where quest.objective.type == type {
            if let wanted = quest.objective.target, wanted != target { continue }
            data.quests[quest.id]?.count += 1
        }
    }

    /// Hands in a finished quest and pays out. Returns what was earned.
    @discardableResult
    func turnInQuest(_ id: String) -> [String] {
        guard let quest = content.quest(id), status(of: quest) == .ready else { return [] }
        data.quests[id]?.state = .completed
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
        return lines
    }
}

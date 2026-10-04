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
    /// Adventurers walking around near you on this map: only they can be invited along.
    var adventurersAround: Set<UUID> = []
    /// Up to four friends can travel with you, a party of five, each with their companion. (In a
    /// battle, friends take ids 2…5 and their companions 6…9, below the monsters' 10 and up.)
    static let maxAllies = 4

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
    /// Set by the game while you're on a map: casts a field spell like Bridge of Light. Nil on the
    /// title screen and in tests, where there's nowhere to go.
    @ObservationIgnored var onCastField: ((SkillDef) -> Void)?

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
        var slotted = data
        slotted.slot = UUID().uuidString   // every new game gets its own save
        slotted.skillLevelsDoubled = true  // already on the 10-step skill scale
        slotted.levelsRescaled = true      // and on the 200-level scale (a debug level isn't stretched)
        let session = GameSession(data: slotted)
        session.restoreHero()
        // Like Fairyland, your first companion comes from an egg in the first quest.
        return session
    }

    func save() {
        guard !isDeleted else { return }
        data.position = playerPosition.map { [Double($0.x), Double($0.y)] }
        if !seen.isEmpty { data.explored = (data.explored ?? [:]).merging(seen) { $1 } }
        SaveStore.save(data)
        lastSaved = Date()
    }

    /// Set once the game is deleted, so a late autosave can't bring it back.
    private(set) var isDeleted = false

    /// Deletes this game's save for good (Settings → Danger zone).
    func deleteGame() {
        isDeleted = true
        if let slot = data.slot { SaveStore.delete(slot: slot) }
    }

    // MARK: - Looks

    /// Art id of the hero as customised: a recoloured copy of player_walk.
    static let heroArt = "hero"

    /// A whole sheet's colours (other adventurers; the hero's hood or helmet). Worn armour takes
    /// over the outfit's colours (leather, steel, silk…).
    static func rules(for look: Look, armor: ItemDef? = nil) -> [RecolorRule] {
        let options = Content.shared.appearance
        let skin: [RecolorRule] = options.skin.first { $0.id == look.skin }?.recolor ?? []
        let hair: [RecolorRule] = options.hair.first { $0.id == look.hair }?.recolor ?? []
        // Skin first (pale), then hair (saturated), then outfit (green): they never overlap.
        return skin + hair + outfitRules(for: look, armor: armor)
    }

    private static func outfitRules(for look: Look, armor: ItemDef?) -> [RecolorRule] {
        if let worn = armor?.recolor, !worn.isEmpty { return worn }
        return Content.shared.appearance.outfits.first { $0.id == look.outfit }?.recolor ?? []
    }

    /// The bald body's colours: skin and outfit. Its hair is on the hair and locks layers, so a dye
    /// leaves the rest alone (ginger boots and belts keep their colour).
    static func bodyRules(for look: Look, armor: ItemDef? = nil) -> [RecolorRule] {
        let skin: [RecolorRule] = Content.shared.appearance.skin.first { $0.id == look.skin }?.recolor ?? []
        return skin + outfitRules(for: look, armor: armor)
    }

    /// The hair and locks layers hold nothing but hair, so the hair colour's rules widen to the
    /// `hairLayer` window there: every shade of the ginger takes the colour, down to the deep red
    /// shadows and the pale tips. The outfit's rules follow for a collar showing through.
    static func hairLayerRules(for look: Look, armor: ItemDef? = nil) -> [RecolorRule] {
        let options = Content.shared.appearance
        var hair: [RecolorRule] = options.hair.first { $0.id == look.hair }?.recolor ?? []
        if let window = options.hairLayer {
            hair = hair.map { $0.within(window) }
        }
        return hair + outfitRules(for: look, armor: armor)
    }

    /// The hairstyle a hero wears: their pick if it suits their walk sheet, else the sheet's own hair
    /// (a gender's: a ponytail, braids), else their race's.
    static func style(for look: Look, race: RaceDef) -> String {
        let styles = Content.shared.appearance.styles(for: race.sheet(for: look.gender))
        if let picked = look.style, styles.contains(where: { $0.id == picked }) { return picked }
        if let own = styles.first(where: { $0.sheet != nil }) { return own.id }
        return race.hair ?? styles.first?.id ?? "spiky"
    }

    /// The hero as paper-doll layers (art/sprites, made by tools/hero_layers.py): the bald body, the
    /// locks it keeps (a beard), then the hairstyle, or a helmet or hood instead (so no hair pokes
    /// through). Locks and hair take the hair colour on every shade; the body only skin and outfit.
    /// Armour with its own walk sheet for the race (items.json `sheets`) replaces the lot.
    static func layers(race: RaceDef, look: Look, armor: ItemDef? = nil) -> [ArtLayer] {
        if let sheet = armor?.sheets?[race.id] { return [ArtLayer(id: sheet)] }
        let headgear: String? = switch armor?.wear ?? "" {
        case "plate": "helmet"
        case "cloak": "hood"
        default: nil
        }
        let style = Self.style(for: look, race: race)
        // Each gender's walk sheet has its own set; the race's default sheet keeps the plain names.
        let body = look.gender.flatMap { race.sheets?[$0] != nil ? "\(race.id)_\($0)" : nil } ?? race.id
        let hair = hairLayerRules(for: look, armor: armor)
        let bald = ArtLayer(id: "body_\(body)", recolor: bodyRules(for: look, armor: armor))
        return [bald, ArtLayer(id: "locks_\(body)", recolor: hair),
                headgear.map { ArtLayer(id: "\($0)_\(body)") } ?? ArtLayer(id: "hair_\(style)_\(body)", recolor: hair)]
    }

    func equipped(_ slot: ItemType) -> ItemDef? {
        data.hero.equipment[slot].flatMap(content.item)
    }

    /// Changes whenever the hero's sprite should be redrawn (look, race or gear).
    var heroLookKey: String { Self.lookKey(for: data.hero) }

    static func lookKey(for hero: Hero) -> String {
        let gear = ItemType.equipmentSlots.map { hero.equipment[$0] ?? "-" }.joined(separator: ",")
        let look = hero.look ?? .standard
        return "\(Content.shared.race(hero.raceID).sheet(for: look.gender))/\(look.key)/\(gear)"
    }

    func applyLook() {
        Self.registerHero(data.hero, as: Self.heroArt)
    }

    /// Draws a hero exactly as the game shows them (race, gender, hairstyle, colours, worn armour)
    /// under the art id `id`: the hero in play, or a saved hero on the title screen.
    static func registerHero(_ hero: Hero, as id: String) {
        let content = Content.shared
        let race = content.race(hero.raceID)
        let look = hero.look ?? .standard
        let armor = hero.equipment[.armor].flatMap(content.item)
        let boots = hero.equipment[.accessory].flatMap(content.item)?.wear == "boots"
        var gear = GearLook(wear: armor?.wear, accent: armor?.accent, boots: boots, pattern: armor?.pattern)
        var rules = Self.rules(for: look, armor: armor)
        if let armor, armor.sheets?[race.id] != nil {
            // The armour's own sheet is already drawn and coloured: only the skin tone applies, plus a
            // rare colour variant's tint.
            gear = GearLook(wear: nil, accent: nil, boots: boots)
            rules = (content.appearance.skin.first { $0.id == look.skin }?.recolor ?? []) + (armor.tint ?? [])
        }
        ArtLibrary.shared.register(id, from: race.sheet(for: look.gender), recolor: rules, key: Self.lookKey(for: hero),
                                   gear: gear, layers: Self.layers(race: race, look: look, armor: armor))
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
        heroRace.base + heroClass.growth * (data.hero.level - 1 + Self.rebirthLevelBonus * rebirths) + equipmentBonus
    }

    // MARK: - Levels & rebirth
    //
    // Like Fairyland Online: levels go to 200, and from level 101 you can be reborn at level 1,
    // keeping your skills and carrying some strength over. Each rebirth after the first needs
    // 5 more levels (and more gold).

    static let levelCap = 200
    /// Each rebirth keeps the stat growth of this many levels.
    static let rebirthLevelBonus = 8

    var rebirths: Int { data.hero.rebirths ?? 0 }
    var rebirthLevel: Int { 101 + 5 * rebirths }
    var rebirthCost: Int { 20_000 * (rebirths + 1) }
    var canRebirth: Bool { data.hero.level >= rebirthLevel && data.gold >= rebirthCost }

    /// Maps a level from before the stretch (monsters topped out at 32) onto today's 1–105.
    static func stretchedLevel(_ old: Int) -> Int {
        max(1, Int((1 + Double(old - 1) * 104 / 31).rounded()))
    }

    /// Skills used to master at level 5; now it takes 10. Older saves keep their progress: a skill
    /// at level L becomes 2L (level 1 stays 1), so a mastered skill is still mastered.
    func rescaleSkillLevelsIfNeeded() {
        guard data.skillLevelsDoubled != true else { return }
        data.skillLevelsDoubled = true
        guard var levels = data.hero.skillLevels else { return }
        for (id, level) in levels where level > 1 {
            levels[id] = min(Self.maxSkillLevel, level * 2)
        }
        data.hero.skillLevels = levels
    }

    func rescaleLevelsIfNeeded() {
        guard data.levelsRescaled != true else { return }
        data.levelsRescaled = true
        guard data.hero.level > 1 || data.pets.contains(where: { $0.level > 1 }) else { return }
        data.hero.level = Self.stretchedLevel(data.hero.level)
        data.hero.exp = 0
        for index in data.pets.indices {
            data.pets[index].level = Self.stretchedLevel(data.pets[index].level)
            data.pets[index].exp = 0
            let stats = stats(of: data.pets[index])
            data.pets[index].hp = stats.hp
            data.pets[index].mp = stats.mp
        }
        // Read first, then write: `data.friends?[i].level = f(data…)` reads `data` while the
        // optional-chained write already holds it, which Swift's exclusivity check aborts on.
        if var friends = data.friends {
            for index in friends.indices {
                friends[index].level = Self.stretchedLevel(friends[index].level)
            }
            data.friends = friends
        }
        restoreHero()
        post("The world grew bigger! You're now level \(data.hero.level).", .reward)
    }

    func rebirth() {
        guard canRebirth else { return }
        data.gold -= rebirthCost
        data.hero.rebirths = rebirths + 1
        data.hero.level = 1
        data.hero.exp = 0
        restoreHero()
        post("You were reborn! Rebirth \(rebirths): back to level 1, a little stronger than before.", .reward)
        save()
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
    // a point either learns one of those or raises a skill you know (up to level 10).

    /// Skills you've learned that your current class uses.
    var heroSkills: [SkillDef] {
        let learned = Set(data.hero.learnedSkills ?? [])
        // Reborn heroes keep every skill they learned, whatever their level now.
        return classSkills(upTo: rebirths > 0 ? Int.max : data.hero.level).filter { learned.contains($0.id) }
    }

    // MARK: - Pinned skills

    /// How many skills fit on the battle bar.
    static let maxPinnedSkills = 4

    /// Pinned skills the hero can use right now, in the order they were pinned.
    var pinnedSkills: [SkillDef] {
        let known = heroSkills
        return (data.pinnedSkills ?? []).compactMap { id in known.first { $0.id == id } }
    }

    func isPinned(_ id: String) -> Bool { data.pinnedSkills?.contains(id) == true }

    /// Pins or unpins a skill. Returns false when the bar is already full.
    @discardableResult
    func togglePin(_ id: String) -> Bool {
        let known = Set(heroSkills.map(\.id))
        var pins = (data.pinnedSkills ?? []).filter { known.contains($0) }
        if let index = pins.firstIndex(of: id) {
            pins.remove(at: index)
        } else {
            guard pins.count < Self.maxPinnedSkills, known.contains(id) else { return false }
            pins.append(id)
        }
        data.pinnedSkills = pins
        return true
    }

    // MARK: - Battle buttons

    /// In `battleButtons`, everything after this sits in the More menu.
    static let moreDivider = "more"
    static let defaultBattleButtons = ["attack", "skills", "capture", moreDivider, "items", "guard", "run"]

    /// The battle buttons in your order: the first is the big one, those after `moreDivider` wait
    /// in the More menu. Pinned skills appear as "skill:<id>"; newly pinned ones join before More.
    var battleButtons: [String] {
        let pins = pinnedSkills.map { "skill:\($0.id)" }
        var order = (data.battleButtons ?? Self.defaultBattleButtons).filter { !$0.hasPrefix("skill:") || pins.contains($0) }
        for command in Self.defaultBattleButtons where !order.contains(command) { order.append(command) }
        let divider = order.firstIndex(of: Self.moreDivider) ?? order.endIndex
        let newPins = pins.filter { !order.contains($0) }
        order.insert(contentsOf: newPins, at: divider)
        return order
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

    /// Ten steps from learning a skill to mastering it.
    static let maxSkillLevel = 10

    func skillLevel(_ id: String) -> Int {
        max(1, data.hero.skillLevels?[id] ?? 1)
    }

    /// A point to spend and something to spend it on: a skill to learn, or one not yet mastered.
    var canSpendSkillPoint: Bool {
        unspentSkillPoints > 0
            && (!learnableSkills.isEmpty || heroSkills.contains { skillLevel($0.id) < Self.maxSkillLevel })
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

    /// EXP for the next level. Past 100 it climbs faster, like Fairyland Online's slow late game:
    /// twice the old amount by level 140 and 3.5 times by 200.
    static func expToNext(level: Int) -> Int {
        let base = 10 + level * level * 5
        guard level > 100 else { return base }
        return Int((Double(base) * (1 + Double(level - 100) / 40)).rounded())
    }

    func restoreHero() {
        let stats = heroStats
        data.hero.hp = stats.hp
        data.hero.mp = stats.mp
    }

    /// Adds EXP and returns how many levels the hero gained.
    @discardableResult
    func gainHeroEXP(_ amount: Int) -> Int {
        guard amount > 0 else { return 0 }
        guard data.hero.level < Self.levelCap else { return 0 }
        data.hero.exp += amount
        var levels = 0
        while data.hero.level < Self.levelCap, data.hero.exp >= Self.expToNext(level: data.hero.level) {
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

    // MARK: - Exploring dark maps

    /// Cells seen on dark maps since the last save, kept out of `data` so exploring doesn't redraw
    /// everything that shows the save; `save()` writes them in.
    @ObservationIgnored private var seen: [String: Data] = [:]
    /// Goes up whenever you see somewhere new on a dark map, so the minimap redraws.
    private(set) var exploredVersion = 0

    /// The cells you've seen on a dark map, one bit each (`SaveData.explored`).
    func explored(_ mapID: String) -> Data? { seen[mapID] ?? data.explored?[mapID] }

    /// Marks cells of a dark map as seen. Returns true if any of them is new.
    @discardableResult
    func explore(_ cells: [GridPoint], on mapID: String, columns: Int, rows: Int) -> Bool {
        let size = (columns * rows + 7) / 8
        var bits = explored(mapID) ?? Data()
        // A map that changed size since: start afresh.
        if bits.count != size { bits = Data(count: size) }
        var fresh = false
        for cell in cells where cell.col >= 0 && cell.row >= 0 && cell.col < columns && cell.row < rows {
            let index = cell.row * columns + cell.col
            let mask = UInt8(1 << (index % 8))
            if bits[index / 8] & mask == 0 {
                bits[index / 8] |= mask
                fresh = true
            }
        }
        guard fresh else { return false }
        seen[mapID] = bits
        exploredVersion += 1
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
        guard let friend = friends.first(where: { $0.id == id }), !isInParty(friend), partyMembers.count < Self.maxAllies,
              adventurersAround.contains(id) else { return }
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
        let sheet = content.race(adventurer.raceID).sheet(for: adventurer.look.gender)
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
        guard data.pets[index].level < Self.levelCap else { return 0 }
        data.pets[index].exp += amount
        var levels = 0
        while data.pets[index].level < Self.levelCap, data.pets[index].exp >= Self.expToNext(level: data.pets[index].level) {
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
        record(.hatch, target: nil)
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
        content.items.filter { ItemType.equipmentSlots.contains($0.type) && count(of: $0.id) > 0 }
    }

    var bagMaterials: [ItemDef] {
        content.items.filter { $0.type == .material && count(of: $0.id) > 0 }
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
        guard let item = content.item(id), ItemType.equipmentSlots.contains(item.type), equipIssue(item) == nil, removeItem(id) else { return }
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

    // MARK: - Selling and trading

    /// Shops buy things back for half their price, like Fairyland's NPC shops.
    static func sellPrice(of item: ItemDef) -> Int { max(1, item.price / 2) }

    /// What a shop will take: anything in the bag with a price (eggs have none).
    var sellableItems: [ItemDef] {
        content.items.filter { $0.price > 0 && count(of: $0.id) > 0 }
    }

    /// Sells one to a shop. Returns the gold paid, or nil if there was nothing to sell.
    @discardableResult
    func sell(_ id: String) -> Int? {
        guard let item = content.item(id), item.price > 0, removeItem(id) else { return nil }
        let paid = Self.sellPrice(of: item)
        data.gold += paid
        SoundEffects.shared.play(.coins)
        return paid
    }

    /// One deal an adventurer offers: they buy something of yours (for more than a shop pays), or
    /// sell you something they carry (for a little over the shop price, but shops may not stock it).
    struct TradeOffer: Identifiable {
        enum Kind { case theyBuy, theySell }
        let kind: Kind
        let item: ItemDef
        let price: Int
        /// Who offered it, on which in-game day, for what: a deal is made once.
        let id: String
    }

    /// Today's offers from `adventurer`. They change with the in-game day, and stay put while
    /// you think it over.
    func tradeOffers(with adventurer: Adventurer, at date: Date = Date()) -> [TradeOffer] {
        let moment = GameClock.moment(at: date, since: data.startedAt)
        let day = "\(moment.year)/\(moment.month.displayName)/\(moment.day)"
        var rng = SeededRandom(text: "\(adventurer.id)|\(day)")
        let done = Set(data.tradesDone ?? [])
        func offer(_ kind: TradeOffer.Kind, _ item: ItemDef, _ price: Int) -> TradeOffer? {
            let id = "\(adventurer.id)|\(day)|\(kind == .theyBuy ? "buy" : "sell")|\(item.id)"
            return done.contains(id) ? nil : TradeOffer(kind: kind, item: item, price: price, id: id)
        }
        // They want a couple of your things, materials first, and pay half again what a shop would.
        let yours = sellableItems.filter { $0.type == .material } + sellableItems.filter { $0.type != .material }
        let wanted = Array(yours.prefix(6).shuffled(using: &rng).prefix(2))
        // And they carry a few things around their level.
        let level = adventurer.level
        let goods = content.items.filter { item in
            item.price > 0 && item.capture != true && item.hatches == nil
                && (item.type == .consumable || item.type == .material || abs((item.level ?? 1) - level) <= 12)
        }
        let carried = Array(goods.shuffled(using: &rng).prefix(3))
        return wanted.compactMap { offer(.theyBuy, $0, max(1, Self.sellPrice(of: $0) * 3 / 2)) }
            + carried.compactMap { offer(.theySell, $0, max(1, $0.price * 11 / 10)) }
    }

    /// Beat an adventurer and they drop everything they carry: today's goods (what they'd have sold
    /// you) go into your bag, and those deals are gone. Returns what you got.
    func takeSpoils(from adventurer: Adventurer) -> [ItemDef] {
        let goods = tradeOffers(with: adventurer).filter { $0.kind == .theySell }
        for offer in goods { addItem(offer.item.id) }
        data.tradesDone = Array((data.tradesDone ?? []).suffix(200)) + goods.map(\.id)
        return goods.map(\.item)
    }

    /// Makes a deal. Returns false if you can't (not enough gold, or the item's gone).
    @discardableResult
    func trade(_ offer: TradeOffer) -> Bool {
        guard !(data.tradesDone ?? []).contains(offer.id) else { return false }
        switch offer.kind {
        case .theyBuy:
            guard removeItem(offer.item.id) else { return false }
            data.gold += offer.price
        case .theySell:
            guard data.gold >= offer.price else { return false }
            data.gold -= offer.price
            addItem(offer.item.id)
        }
        data.tradesDone = Array((data.tradesDone ?? []).suffix(200)) + [offer.id]
        SoundEffects.shared.play(.coins)
        return true
    }

    // MARK: - Crafting
    // Fairyland Online's blacksmiths forged weapons from gathered wood, metal and gems. Here
    // monsters drop the materials, and a smith in each town turns a recipe into the weapon.

    /// Everything a smith can forge, lowest level first.
    var recipes: [ItemDef] {
        content.items.filter { $0.recipe != nil }.sorted { ($0.level ?? 1) < ($1.level ?? 1) }
    }

    struct Ingredient: Identifiable {
        let material: ItemDef
        let needed: Int
        let owned: Int
        var id: String { material.id }
    }

    /// The ingredients of `item`, in a stable order, with how many you have.
    func ingredients(of item: ItemDef) -> [Ingredient] {
        var parts: [Ingredient] = []
        for (id, needed) in (item.recipe ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard let material = content.item(id) else { continue }
            parts.append(Ingredient(material: material, needed: needed, owned: count(of: id)))
        }
        return parts
    }

    func canCraft(_ item: ItemDef) -> Bool {
        guard let recipe = item.recipe, !recipe.isEmpty else { return false }
        return recipe.allSatisfy { count(of: $0.key) >= $0.value }
    }

    @discardableResult
    func craft(_ id: String) -> Bool {
        guard let item = content.item(id), canCraft(item), let recipe = item.recipe else { return false }
        for (material, needed) in recipe {
            data.inventory[material, default: 0] -= needed
            if data.inventory[material] == 0 { data.inventory[material] = nil }
        }
        addItem(id)
        return true
    }

    /// A material a monster of `level` might drop: mostly the newest kind it can carry, now and
    /// then the one before. Gems are the rarest.
    func materialDrop(level: Int) -> ItemDef? {
        let kinds = ["wood", "wood", "wood", "metal", "metal", "metal", "hide", "hide", "gem"]
        guard let kind = kinds.randomElement() else { return nil }
        let options = content.items
            .filter { $0.type == .material && $0.material == kind && ($0.level ?? 1) <= level }
            .sorted { ($0.level ?? 1) > ($1.level ?? 1) }
        guard !options.isEmpty else { return nil }
        return Double.random(in: 0..<1) < 0.3 && options.count > 1 ? options[1] : options[0]
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
            case .defeat, .capture, .collect, .hatch: progress.count
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

    /// The elder's three gifts used to be gift boxes hidden around Meadowbrook. A save from then
    /// that took his quest without finding every box gets the missing gifts now, once.
    func handOutMissingStarterGifts() {
        guard data.version < 2 else { return }
        data.version = 2
        guard data.quests["hope_of_meadowbrook"]?.state == .active else { return }
        let boxes = [("gift_box_1", "wooden_sword"), ("gift_box_2", "novice_ring"), ("gift_box_3", "pet_egg")]
        for (box, item) in boxes where data.openedChests?.contains(box) != true {
            addItem(item)
            data.openedChests = (data.openedChests ?? []) + [box]
            if let name = content.item(item)?.name { post("Elder Oak left you a \(name).", .reward) }
        }
    }

    func acceptQuest(_ id: String, answer: QuestDef.Question.Answer? = nil) {
        guard let quest = content.quest(id), status(of: quest) == .available else { return }
        data.quests[id] = QuestProgress(state: .active, count: 0)
        SoundEffects.shared.play(.questAccept)
        if let answer { data.eggSpecies = answer.egg }
        post("Quest accepted: \(quest.title)", .quest)
        let starters = quest.starterItems ?? []
        for item in starters { addItem(item) }
        // "Received 3 Seal Stones." / "Received Wooden Sword, Novice Ring and Pet Egg."
        var unique: [String] = []
        for id in starters where !unique.contains(id) { unique.append(id) }
        let names = unique.map { id -> String in
            let name = content.item(id)?.name ?? id
            let count = starters.filter { $0 == id }.count
            return count > 1 ? "\(count) \(name)s" : name
        }
        if !names.isEmpty {
            let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : names[0]
            post("Received \(list).", .reward)
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

    /// Bosses beaten since arriving on this map. They're back for a rematch next visit.
    var bossesBeatenHere: Set<String> = []

    func isBeatenHere(_ boss: NPCDef) -> Bool {
        bossesBeatenHere.contains(boss.id)
    }

    /// Every win rolls the boss's rare drops (the colour variants of top armour).
    func defeatBoss(_ boss: NPCDef) {
        bossesBeatenHere.insert(boss.id)
        if !isDefeated(boss) {
            data.defeatedBosses = (data.defeatedBosses ?? []) + [boss.id]
        }
        let species = boss.monster.flatMap(content.monster)
        for drop in species?.drops ?? [] where Double.random(in: 0..<1) < drop.chance {
            guard let item = content.item(drop.item) else { continue }
            addItem(item.id)
            post("\(species?.name ?? boss.name) dropped \(item.name)!", .reward)
        }
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

    /// Whether you've been to a map (saves from before this was tracked know the start town,
    /// the current map and the last checkpoint).
    func hasVisited(_ mapID: String) -> Bool {
        data.visitedMaps?.contains(mapID) == true || mapID == data.mapID
            || mapID == content.startMap || mapID == data.checkpoint?.mapID
    }

    /// A species met in battle goes into the Monster Book (or widens the levels it was met at).
    func sawMonster(_ id: String, level: Int) {
        var book = data.monsterBook ?? [:]
        if var entry = book[id] {
            entry.lowestLevel = min(entry.lowestLevel, level)
            entry.highestLevel = max(entry.highestLevel, level)
            book[id] = entry
        } else {
            book[id] = MonsterSighting(lowestLevel: level, highestLevel: level)
        }
        data.monsterBook = book
    }

    func beatMonster(_ id: String, level: Int) {
        sawMonster(id, level: level)
        data.monsterBook?[id]?.defeated += 1
    }

    func sighting(of id: String) -> MonsterSighting? { data.monsterBook?[id] }

    func markVisited(_ mapID: String) {
        guard data.visitedMaps?.contains(mapID) != true else { return }
        data.visitedMaps = (data.visitedMaps ?? []) + [mapID]
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

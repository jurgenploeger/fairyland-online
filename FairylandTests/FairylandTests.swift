import Foundation
import Testing
import UIKit
@testable import Fairyland

/// Catches broken references when editing content/*.json or art/assets.json.
@MainActor
struct ContentTests {
    let content = Content.shared

    @Test func changelogMatchesAppVersion() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        #expect(content.releases.first?.version == version, "bump content/changelog.json with MARKETING_VERSION")
    }

    @Test func everyReferenceResolves() {
        for cls in content.classes {
            for unlock in cls.skills {
                #expect(content.skill(unlock.skill) != nil, "class \(cls.id) → unknown skill \(unlock.skill)")
            }
        }
        for monster in content.monsters {
            for skill in monster.skills {
                #expect(content.skill(skill) != nil, "monster \(monster.id) → unknown skill \(skill)")
            }
            #expect(ArtLibrary.shared.asset(monster.art) != nil, "monster \(monster.id) → unknown art \(monster.art)")
        }
        for quest in content.quests {
            #expect(content.npc(quest.giver) != nil, "quest \(quest.id) → unknown giver \(quest.giver)")
            if quest.objective.type == .defeat, let target = quest.objective.target {
                #expect(content.monster(target) != nil, "quest \(quest.id) → unknown monster \(target)")
            }
            if let question = quest.question {
                for answer in question.answers {
                    #expect(content.monster(answer.egg) != nil, "quest \(quest.id) → unknown egg \(answer.egg)")
                }
            }
            for item in quest.reward.items ?? [] {
                #expect(content.item(item) != nil, "quest \(quest.id) → unknown item \(item)")
            }
            for required in quest.requires ?? [] {
                #expect(content.quest(required) != nil, "quest \(quest.id) → unknown quest \(required)")
            }
        }
        #expect(content.map(content.startMap) != nil)
        for map in content.maps {
            for exit in map.exits {
                let destination = content.map(exit.to)
                #expect(destination != nil, "map \(map.id) → unknown map \(exit.to)")
                // Every exit needs a way back, or you'd get stuck.
                #expect(destination?.exits.contains { $0.to == map.id && $0.edge == exit.edge.opposite } == true,
                        "map \(exit.to) has no \(exit.edge.opposite) exit back to \(map.id)")
            }
            for id in map.encounters?.monsters.keys.sorted() ?? [] {
                #expect(content.monster(id) != nil, "map \(map.id) → unknown monster \(id)")
            }
            if let music = map.music {
                #expect(content.song(music) != nil, "map \(map.id) → unknown song \(music)")
            }
            if let music = map.battleMusic {
                #expect(content.song(music) != nil, "map \(map.id) → unknown battle song \(music)")
            }
            for npc in map.npcs ?? [] {
                #expect(ArtLibrary.shared.asset(npc.art) != nil, "npc \(npc.id) → unknown art \(npc.art)")
                for item in npc.stock ?? [] {
                    #expect(content.item(item) != nil, "shop \(npc.id) → unknown item \(item)")
                }
                if npc.role == .chest {
                    #expect(npc.gives.flatMap(content.item) != nil, "chest \(npc.id) → unknown item")
                }
                if npc.role == .guild {
                    #expect(content.classes.contains { $0.id == npc.classId }, "guild \(npc.id) → unknown class")
                }
                if npc.role == .boss {
                    #expect(npc.monster.flatMap(content.monster)?.boss == true, "boss \(npc.id) → unknown boss monster")
                }
            }
            for exit in map.exits {
                if let quest = exit.requires { #expect(content.quest(quest) != nil, "map \(map.id) road → unknown quest \(quest)") }
            }
            let art = map.theme.props.map(\.art) + (map.town?.lots ?? []) + (map.town?.streetDecor?.keys.sorted() ?? [])
                + (map.buildings ?? []).map(\.art) + (map.decor ?? []).map(\.art)
            for id in art {
                #expect(ArtLibrary.shared.asset(id) != nil, "map \(map.id) → unknown art \(id)")
            }
        }
        for preset in content.appearance.hair + content.appearance.outfits {
            if let quest = preset.unlock { #expect(content.quest(quest) != nil, "look \(preset.id) → unknown quest \(quest)") }
        }
        for item in content.items {
            #expect(item.icon.flatMap(GameIcon.init) != nil, "item \(item.id) → unknown icon \(item.icon ?? "nil")")
        }
        for skill in content.skills {
            #expect(skill.icon.flatMap(GameIcon.init) != nil, "skill \(skill.id) → unknown icon \(skill.icon ?? "nil")")
        }
    }

    @Test func songsParse() {
        for song in content.songs {
            let tune = Tune(song, instruments: content.instruments)
            #expect(!tune.isLegacy, "song \(song.id) still uses chiptune waves")
            for (index, voice) in tune.voices.enumerated() {
                #expect(!voice.notes.isEmpty, "song \(song.id) track \(index) has no notes")
                #expect(voice.instrument != nil, "song \(song.id) track \(index) → unknown instrument")
                if voice.isDrums {
                    #expect(voice.notes.contains { !$0.drums.isEmpty }, "song \(song.id) track \(index) has no drum hits")
                } else {
                    #expect(voice.notes.contains { !$0.frequencies.isEmpty }, "song \(song.id) track \(index) has no pitches")
                }
            }
        }
        #expect(abs((Tune.frequency(of: "A4") ?? 0) - 440) < 0.01)
        #expect(abs((Tune.frequency(of: "C4") ?? 0) - 261.63) < 0.01)
    }

    @Test func theLateGameClimbsSlower() {
        #expect(GameSession.expToNext(level: 100) == 10 + 100 * 100 * 5)
        #expect(GameSession.expToNext(level: 140) == 2 * (10 + 140 * 140 * 5))
        #expect(GameSession.expToNext(level: 199) > 3 * (10 + 199 * 199 * 5))
    }

    @Test func everyZoneLevelHasSomewhereToFight() {
        // From level 1 to 200 there is always a zone whose monsters are within 10 levels of you.
        let bands = content.maps.compactMap(\.encounters).map { ($0.levels.first ?? 1, $0.levels.last ?? 1) }
        for level in 1...200 {
            #expect(bands.contains { $0.0 <= level + 10 && $0.1 >= level - 10 }, "nowhere to fight at level \(level)")
        }
    }

    @Test func everyMapHasRoomToWalk() {
        for def in content.maps {
            let map = WorldMap(def: def)
            for exit in def.exits {
                #expect(map.isWalkable(map.entryCell(from: exit.edge)), "map \(def.id) entry from \(exit.edge) is blocked")
            }
        }
    }

    @Test func everyMapHasAPaletteThatGrades() throws {
        let url = try #require(Bundle.main.url(forResource: "tile_grass", withExtension: "png", subdirectory: "art/sprites"))
        let image = try #require(UIImage(contentsOfFile: url.path)?.cgImage)
        for def in content.maps {
            let palette = try #require(def.theme.palette, "map \(def.id) has no palette")
            let graded = try #require(Recolor.grade(palette, image: image), "map \(def.id) palette didn't grade")
            #expect(graded.width == image.width && graded.height == image.height)
        }
    }
}

@MainActor
struct LookTests {
    init() {
        // Belt and braces: never touch the real save from tests.
        SaveStore.fileName = "fairyland-tests-save.json"
    }

    @Test func derivedSpritesHaveABase() throws {
        let url = try #require(Bundle.main.url(forResource: "assets", withExtension: "json", subdirectory: "art"))
        let manifest = try JSONDecoder().decode(ArtManifest.self, from: Data(contentsOf: url))
        let ids = Set(manifest.assets.map(\.id))
        for asset in manifest.assets {
            if let base = asset.derive?.from {
                #expect(ids.contains(base), "\(asset.id) derives from unknown \(base)")
            }
        }
    }

    @Test func customisingTheHeroAndCompanion() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let options = Content.shared.appearance
        #expect(options.hair.first?.id == Look.standard.hair)
        let look = Look(hair: "pink", outfit: "blue", skin: "tan")
        session.customizeHero(name: "  Pip  ", look: look)
        #expect(session.data.hero.name == "Pip")
        #expect(session.data.hero.look == look)
        #expect(!GameSession.rules(for: look).isEmpty)
        #expect(session.lastSaved != nil)

        let pet = session.makePet(species: "jelly", level: 1)!
        session.addPet(pet, countsForQuests: false)
        #expect(session.artID(for: pet) == "monster_jelly")
        session.renamePet(pet.id, to: "Wobble")
        let updated = session.data.pets[0]
        #expect(updated.name == "Wobble")
        // Companions keep their species' colours.
        #expect(session.artID(for: updated) == "monster_jelly")
    }

    @Test func everyGenderHasASheetForEveryRace() {
        let content = Content.shared
        #expect(content.appearance.genders.map(\.id) == ["male", "female", "other"])
        for race in content.races {
            #expect(race.sheet(for: nil) == race.sheet)   // older saves keep their sheet
            for gender in content.appearance.genders {
                let sheet = race.sheet(for: gender.id)
                #expect(ArtLibrary.shared.asset(sheet) != nil, "\(race.id) \(gender.id) → unknown art \(sheet)")
            }
        }
        #expect(content.race("dwarf").sheet(for: "female") != content.race("dwarf").sheet(for: "male"))
        let look = Look(hair: "pink", outfit: "blue", skin: "tan", gender: "other")
        #expect(look.key != Look(hair: "pink", outfit: "blue", skin: "tan").key)
    }
}

@MainActor
struct RulesTests {
    init() {
        SaveStore.fileName = "fairyland-tests-save.json"
    }

    @Test func elementChart() {
        #expect(Element.water.multiplier(against: .fire) == 1.5)
        #expect(Element.fire.multiplier(against: .water) == 0.75)
        #expect(Element.earth.multiplier(against: .water) == 1.5)
        #expect(Element.wood.multiplier(against: .earth) == 1.5)
        #expect(Element.light.multiplier(against: .dark) == 1.5)
        #expect(Element.fire.multiplier(against: .fire) == 1)
    }

    @Test func levellingUpRestoresAndGrows() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let before = session.heroStats
        session.data.hero.hp = 1
        let levels = session.gainHeroEXP(GameSession.expToNext(level: 1))
        #expect(levels == 1)
        #expect(session.data.hero.level == 2)
        #expect(session.heroStats.hp > before.hp)
        #expect(session.data.hero.hp == session.heroStats.hp)
        // Reaching Bash's level unlocks it; learning it takes one skill point.
        let bashLevel = Content.shared.classDef("novice").skills.first { $0.skill == "bash" }!.level
        while session.data.hero.level < bashLevel {
            session.gainHeroEXP(GameSession.expToNext(level: session.data.hero.level))
        }
        #expect(session.heroSkills.isEmpty)
        #expect(session.learnableSkills.contains { $0.id == "bash" })
        let points = session.unspentSkillPoints
        session.learnSkill("bash")
        #expect(session.heroSkills.contains { $0.id == "bash" })
        #expect(session.unspentSkillPoints == points - 1)
    }

    @Test func classChoiceNeedsLevel() {
        let session = GameSession.newGame(name: "Test", raceID: "elf")
        session.addItem("wooden_sword")
        session.equip("wooden_sword")
        session.chooseClass("mage")
        #expect(session.data.hero.classID == "novice")
        session.data.hero.level = Content.shared.classChoiceLevel
        session.chooseClass("mage")
        #expect(session.data.hero.classID == "mage")
        // The wooden sword isn't for mages, so it goes back into the bag.
        #expect(session.data.hero.equipment.weapon == nil)
        #expect(session.count(of: "wooden_sword") == 1)
        #expect(session.learnableSkills.contains { $0.id == "fire_bolt" })
    }

    @Test func firstCompanionHatchesFromTheEldersEgg() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        #expect(session.data.pets.isEmpty)
        let quest = Content.shared.quest("hope_of_meadowbrook")!
        // No gift boxes lying around: the elder hands over the three gifts himself.
        #expect((Content.shared.map("meadowbrook")?.npcs ?? []).allSatisfy { $0.role != .chest })
        session.acceptQuest(quest.id, answer: quest.question?.answers.first { $0.egg == "jelly" })
        #expect(session.count(of: "wooden_sword") == 1)
        #expect(session.count(of: "novice_ring") == 1)
        #expect(session.count(of: "pet_egg") == 1)
        #expect(session.status(of: quest) != .ready)   // hatch the egg first
        let pet = session.hatch("pet_egg")
        #expect(pet?.speciesID == "jelly")
        #expect(session.activePet?.id == pet?.id)
        #expect(session.status(of: quest) == .ready)
        session.turnInQuest(quest.id)
        #expect(session.status(of: Content.shared.quest("jelly_trouble")!) == .available)
    }

    @Test func oldSavesGetTheGiftsTheyMissed() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.version = 1
        session.data.quests["hope_of_meadowbrook"] = QuestProgress(state: .active, count: 1)
        session.data.openedChests = ["gift_box_1"]   // found the sword box only
        session.handOutMissingStarterGifts()
        #expect(session.count(of: "novice_ring") == 1)
        #expect(session.count(of: "pet_egg") == 1)
        #expect(session.count(of: "wooden_sword") == 0)
        session.handOutMissingStarterGifts()   // only once
        #expect(session.count(of: "pet_egg") == 1)
    }

    @Test func skillPointsRaiseSkills() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let novice = Content.shared.classDef("novice").skills
        let bashLevel = novice.first { $0.skill == "bash" }!.level
        let aidLevel = novice.first { $0.skill == "first_aid" }!.level
        session.data.hero.level = bashLevel
        let points = bashLevel - 1
        #expect(session.unspentSkillPoints == points)
        session.upgradeSkill("bash")   // not learned yet
        #expect(session.unspentSkillPoints == points)
        session.learnSkill("bash")
        session.upgradeSkill("bash")
        #expect(session.skillLevel("bash") == 2)
        #expect(session.unspentSkillPoints == points - 2)
        session.data.hero.level = aidLevel
        #expect(session.learnableSkills.map(\.id) == ["first_aid"])
    }

    @Test func rebirthKeepsSkillsAndStrength() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let bashLevel = Content.shared.classDef("novice").skills.first { $0.skill == "bash" }!.level
        session.data.hero.level = bashLevel
        session.learnSkill("bash")
        session.data.hero.level = session.rebirthLevel
        #expect(!session.canRebirth)   // not enough gold yet
        session.data.gold = session.rebirthCost
        let strengthAtOne = GameSession.newGame(name: "Fresh", raceID: "human").heroStats.attack
        session.rebirth()
        #expect(session.data.hero.level == 1)
        #expect(session.rebirths == 1)
        #expect(session.data.gold == 0)
        #expect(session.heroSkills.contains { $0.id == "bash" })
        #expect(session.heroStats.attack > strengthAtOne)
        #expect(session.rebirthLevel == 106)
    }

    @Test func smithForgesFromMaterials() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let sword = try #require(Content.shared.item("novice_bronze_sword"))
        #expect(!session.canCraft(sword))
        #expect(!session.craft(sword.id))
        for (material, needed) in sword.recipe ?? [:] {
            session.addItem(material, needed + 1)
        }
        #expect(session.canCraft(sword))
        #expect(session.craft(sword.id))
        #expect(session.count(of: sword.id) == 1)
        for (material, _) in sword.recipe ?? [:] {
            #expect(session.count(of: material) == 1)   // one of each left over
        }
        #expect(!session.bagMaterials.isEmpty)
        #expect(!session.bagEquipment.contains { $0.type == .material })
    }

    @Test func recipesUseMaterialsMonstersDrop() {
        for item in Content.shared.items {
            for (id, _) in item.recipe ?? [:] {
                let material = Content.shared.item(id)
                #expect(material?.type == .material, "recipe for \(item.id) → \(id) isn't a material")
                #expect((material?.level ?? 1) <= max(item.level ?? 1, 1), "recipe for \(item.id) → \(id) drops too late")
            }
        }
        let session = GameSession.newGame(name: "Test", raceID: "human")
        for _ in 0..<50 {
            let drop = session.materialDrop(level: 1)
            #expect(drop == nil || (drop?.level ?? 1) <= 1)
        }
    }

    @Test func levelsStopAtTheCap() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.level = GameSession.levelCap
        #expect(session.gainHeroEXP(1_000_000_000) == 0)
        #expect(session.data.hero.level == GameSession.levelCap)
    }

    @Test func oldSavesGetStretchedLevels() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.levelsRescaled = nil
        session.data.hero.level = 10
        session.rescaleLevelsIfNeeded()
        #expect(session.data.hero.level == GameSession.stretchedLevel(10))
        #expect(session.data.hero.level == 31)
        session.rescaleLevelsIfNeeded()   // only once
        #expect(session.data.hero.level == 31)
    }

    @Test func skillsPinToTheQuickBar() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let bash = try #require(Content.shared.classDef("novice").skills.first { $0.skill == "bash" })
        session.data.hero.level = bash.level
        session.learnSkill("bash")
        let first = try #require(session.heroSkills.first)
        #expect(session.pinnedSkills.isEmpty)
        #expect(session.togglePin(first.id))
        #expect(session.isPinned(first.id))
        #expect(session.pinnedSkills.map(\.id) == [first.id])
        #expect(!session.togglePin("not_a_skill"))
        #expect(session.togglePin(first.id))   // unpin
        #expect(session.pinnedSkills.isEmpty)
        for skill in Content.shared.skills {
            #expect(skill.art.flatMap(ArtLibrary.shared.asset) != nil, "skill \(skill.id) has no icon art")
        }
    }

    @Test func questFlow() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.quests["hope_of_meadowbrook"] = QuestProgress(state: .completed, count: 3)
        let quest = Content.shared.quest("jelly_trouble")!
        #expect(session.status(of: quest) == .available)
        session.acceptQuest(quest.id)
        for _ in 0..<3 { session.record(.defeat, target: "jelly") }
        session.record(.defeat, target: "bunny")
        #expect(session.status(of: quest) == .ready)
        let gold = session.data.gold
        session.turnInQuest(quest.id)
        #expect(session.status(of: quest) == .completed)
        #expect(session.data.gold == gold + (quest.reward.gold ?? 0))
        // Completing it unlocks the follow-ups.
        #expect(session.status(of: Content.shared.quest("new_friend")!) == .available)
    }

    @Test func battleRunsToAnEnd() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let heroStats = Stats(hp: 200, mp: 20, attack: 30, defense: 10, magic: 10, speed: 20)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 5, element: .neutral,
                             stats: heroStats, hp: 200, mp: 20, skills: [], captureRate: 0)
        let stats = jelly.stats(at: 1)
        let enemy = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                              stats: stats, hp: stats.hp, mp: stats.mp, skills: jelly.skills, captureRate: jelly.captureRate)
        let engine = BattleEngine(party: [hero], enemies: [enemy], content: content, seed: 42)
        var rounds = 0
        while engine.outcome == .ongoing && rounds < 20 {
            _ = engine.resolveRound(heroAction: .attack(target: 10))
            rounds += 1
        }
        // A nearly beaten monster may run off instead of going down.
        #expect(engine.outcome == .victory || engine.outcome == .fled)
    }

    @Test func captureNeedsALoneWeakenedMonster() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = jelly.stats(at: 1)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 1, element: .neutral,
                             stats: Stats(hp: 60, attack: 10, defense: 8, speed: 10), hp: 60, mp: 0, skills: [], captureRate: 0)
        var enemy = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                              stats: stats, hp: stats.hp, mp: 0, skills: [], captureRate: jelly.captureRate)
        #expect(BattleEngine(party: [hero], enemies: [enemy], content: content).captureStatus(of: 10) == .tooHealthy)
        // Half HP isn't weak enough any more: Fairyland wanted them below 20%.
        enemy.hp = stats.hp / 2
        #expect(BattleEngine(party: [hero], enemies: [enemy], content: content).captureStatus(of: 10) == .tooHealthy)
        // And only the last one standing.
        enemy.hp = 1
        var friend = enemy
        friend = Combatant(id: 11, side: .enemies, source: .wild("jelly"), name: "Jelly B", art: jelly.art, level: 1, element: jelly.element,
                           stats: stats, hp: stats.hp, mp: 0, skills: [], captureRate: jelly.captureRate)
        #expect(BattleEngine(party: [hero], enemies: [enemy, friend], content: content).captureStatus(of: 10) == .notAlone)

        let engine = BattleEngine(party: [hero], enemies: [enemy], content: content)
        guard case .ready(let chance) = engine.captureStatus(of: 10) else {
            Issue.record("expected capture to be possible")
            return
        }
        // Not easy, even at 1 HP.
        #expect(chance > 0.2 && chance < 0.6)
    }

    @Test func fullPartyLeavesSomeoneBehind() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        for _ in 0..<GameSession.maxPets {
            #expect(session.addPet(session.makePet(species: "jelly", level: 1)!, countsForQuests: false))
        }
        let newcomer = session.makePet(species: "bunny", level: 3)!
        #expect(!session.addPet(newcomer, countsForQuests: false))
        session.pendingPet = newcomer
        let parting = session.data.pets[2]
        session.leaveBehind(parting.id)
        #expect(session.data.pets.count == GameSession.maxPets)
        #expect(session.data.pets.contains { $0.id == newcomer.id })
        #expect(!session.data.pets.contains { $0.id == parting.id })
        #expect(session.pendingPet == nil)
    }

    @Test func oldSavesWithFriendsRescale() {
        // 0.1.0 saves: levels from before the stretch, and friends to scale up too. This used to
        // trip Swift's exclusivity check and crash on Continue.
        var data = GameSession.newGame(name: "Test", raceID: "human").data
        data.hero.level = 10
        data.levelsRescaled = nil
        data.friends = [Adventurer(name: "Momo", raceID: "elf", classID: "mage", level: 8, look: .standard)]
        let session = GameSession(data: data)
        session.rescaleLevelsIfNeeded()
        #expect(session.data.hero.level == GameSession.stretchedLevel(10))
        #expect(session.friends.first?.level == GameSession.stretchedLevel(8))
        #expect(session.data.levelsRescaled == true)
    }

    @Test func friendsJoinTheParty() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.level = 6
        let momo = Adventurer(name: "Momo", raceID: "elf", classID: "mage", level: 4, look: .standard, petSpecies: "jelly")
        let grump = Adventurer(name: "Grump", raceID: "dwarf", classID: "fighter", level: 7, look: .standard, hostile: true)
        #expect(!session.befriend(grump))
        #expect(session.befriend(momo))
        // Only friends walking around nearby can join.
        session.invite(momo.id)
        #expect(session.partyMembers.isEmpty)
        session.adventurersAround = [momo.id]
        session.invite(momo.id)
        #expect(session.partyMembers.map(\.name) == ["Momo"])
        // Friends keep up with you.
        #expect(session.partyMembers[0].level == 5)
        let controller = BattleController.duel(with: grump, session: session)
        #expect(controller.party.contains { $0.name == "Momo" })
        #expect(controller.enemies.map(\.name) == ["Grump"])
        session.leaveParty(momo.id)
        #expect(session.partyMembers.isEmpty)
        #expect(session.friends.count == 1)
    }

    @Test func questsUnlockLooksAndRoads() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let pink = Content.shared.appearance.hair.first { $0.id == "pink" }!
        let road = Content.shared.map("sunny_meadow")!.exits.first { $0.to == "pineapple_shore" }!
        #expect(!session.isUnlocked(pink))
        #expect(!session.canTravel(road))
        session.data.quests["jelly_trouble"] = QuestProgress(state: .completed, count: 3)
        #expect(session.isUnlocked(pink))
        #expect(session.canTravel(road))
    }

    @Test func bigSpellsSplash() {
        let fire = Content.shared.skill("fire_bolt")!
        #expect(BattleEngine.splashFraction(of: fire, level: 2) == 0)
        #expect(BattleEngine.splashFraction(of: fire, level: 3) > 0)
        #expect(BattleEngine.splashFraction(of: fire, level: 5) > BattleEngine.splashFraction(of: fire, level: 3))
        #expect(BattleEngine.splashFraction(of: Content.shared.skill("bash")!, level: 5) == 0)
    }
}

@MainActor
struct PerformanceTests {
    /// Big maps must still load quickly; this prints how long each one takes to build.
    @Test func mapsBuildQuickly() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        for def in Content.shared.maps {
            let clock = ContinuousClock()
            var grid: WorldMap?
            let gridTime = clock.measure { grid = WorldMap(def: def) }
            let sceneTime = clock.measure { _ = WorldScene(map: def, session: session, input: InputState(), entry: nil) }
            print("⏱ \(def.id): grid \(gridTime), scene \(sceneTime), cells \(grid!.columns * grid!.rows)")
            #expect(sceneTime < .seconds(3), "\(def.id) took \(sceneTime) to build")
        }
    }
}

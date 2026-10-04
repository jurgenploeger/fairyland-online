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

    @Test func housesStandOffTheRoads() {
        for def in content.maps {
            let map = WorldMap(def: def)
            #expect(map.buildings.count == (def.buildings ?? []).count, "map \(def.id) lost a building")
            // The map's own buildings and the shops along the streets: on plain ground or a terrace's
            // paved top, never on a road, and never on each other.
            let houses = map.buildings.map { ($0.art, $0.anchor) } + map.lots.map { ($0.art, $0.anchor) }
            var taken: Set<GridPoint> = []
            for (art, anchor) in houses {
                for dc in -1...1 {
                    for dr in 0...1 {
                        let cell = GridPoint(col: anchor.col + dc, row: anchor.row + dr)
                        let ground = map.ground[cell.row][cell.col]
                        #expect(ground == .ground || ground == .accent, "map \(def.id): \(art) stands on \(ground) at \(cell)")
                        #expect(taken.insert(cell).inserted, "map \(def.id): \(art) overlaps another building at \(cell)")
                    }
                }
            }
        }
    }

    @Test func announcementsAndTradersHaveSomethingToSay() {
        let notices = content.announcements
        #expect(!notices.dawn.isEmpty && !notices.dusk.isEmpty && !notices.community.isEmpty)
        for id in notices.arrival.keys {
            #expect(content.map(id) != nil, "announcements arrival → unknown map \(id)")
        }
        let lines = content.crowd.traderLines ?? []
        #expect(lines.contains { $0.contains("{item}") } && lines.contains { $0.contains("{buy}") })
        #expect(!(content.crowd.modReplies ?? []).isEmpty)
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

    @Test func spreadMeasuresFromTheWindowsMiddle() throws {
        // A green ramp (highlights 70, shadows 150) turned brown keeps its shading's hue shift:
        // the middle lands on `to` and each hue stays its distance from the middle times `spread`.
        let green = try JSONDecoder().decode(RecolorRule.self, from: Data(#"{"hue": [70, 150], "to": 25, "spread": -0.3}"#.utf8))
        #expect(green.distanceFromMiddle(of: 110) == 0)
        #expect(green.distanceFromMiddle(of: 150) == 40)
        #expect(green.distanceFromMiddle(of: 70) == -40)
        // A window that wraps round red has its middle at 355.
        let pink = try JSONDecoder().decode(RecolorRule.self, from: Data(#"{"hue": [330, 20], "to": 200}"#.utf8))
        #expect(pink.distanceFromMiddle(of: 10) == 15)
        #expect(pink.distanceFromMiddle(of: 340) == -15)
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
        // Mage skills open up as you level.
        let fireBolt = Content.shared.classDef("mage").skills.first { $0.skill == "fire_bolt" }!
        #expect(!session.learnableSkills.contains { $0.id == "fire_bolt" } || fireBolt.level <= session.data.hero.level)
        session.data.hero.level = fireBolt.level
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

    @Test func monstersDropGearFromUpToTheirLevel() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.classID = "fighter"
        let bossDrops = Set(Content.shared.monsters.flatMap { $0.drops ?? [] }.map(\.item))
        var usable = 0
        for _ in 0..<400 {
            let gear = try #require(session.equipmentDrop(level: 40))
            #expect(ItemType.equipmentSlots.contains(gear.type))
            #expect((29...40).contains(gear.level ?? 1), "\(gear.id) is level \(gear.level ?? 1)")
            #expect(!bossDrops.contains(gear.id), "\(gear.id) is a boss's own drop")
            if gear.classes?.contains("fighter") ?? true { usable += 1 }
        }
        // Mostly gear your class can use (three in four, plus what the rest happens to hit).
        #expect(usable > 240)
        for _ in 0..<100 {
            let best = try #require(session.equipmentDrop(level: 40, best: true))
            #expect((35...40).contains(best.level ?? 1))
        }
        // Past the best gear there is, drops come from the top.
        let top = try #require(Content.shared.items.compactMap(\.level).max())
        #expect((session.equipmentDrop(level: top + 50)?.level ?? 0) > top - 12)
        // Stronger fights drop gear more often; a rare monster often, a boss always.
        let even = GameSession.equipmentDropChance(level: 30, heroLevel: 30, rare: false, boss: false)
        let above = GameSession.equipmentDropChance(level: 45, heroLevel: 30, rare: false, boss: false)
        let below = GameSession.equipmentDropChance(level: 10, heroLevel: 30, rare: false, boss: false)
        #expect(below < even && even < above)
        #expect(abs(above - 0.16) < 1e-9 && abs(below - 0.02) < 1e-9)
        #expect(GameSession.equipmentDropChance(level: 30, heroLevel: 30, rare: true, boss: false) > above)
        #expect(GameSession.equipmentDropChance(level: 30, heroLevel: 30, rare: false, boss: true) == 1)
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

    @Test func monsterBookRemembersWhatYouMeet() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        #expect(session.sighting(of: "rat_king") == nil)
        let npc = try #require(Content.shared.maps.flatMap { $0.npcs ?? [] }.first { $0.monster == "rat_king" })
        let level = try #require(npc.level)
        _ = try #require(BattleController.boss(npc, session: session))
        let met = try #require(session.sighting(of: "rat_king"))
        #expect(met.defeated == 0)
        #expect(met.lowestLevel == level && met.highestLevel == level)
        // Beaten below and above the level it was met at, the book widens both ways.
        session.beatMonster("rat_king", level: 2)
        session.beatMonster("rat_king", level: level + 10)
        let beaten = try #require(session.sighting(of: "rat_king"))
        #expect(beaten.defeated == 2)
        #expect(beaten.lowestLevel == 2 && beaten.highestLevel == level + 10)
        #expect(Element.water.strongAgainst == [.fire])
        #expect(Element.water.weakTo == [.earth])
        #expect(Content.shared.monsters.allSatisfy { !($0.lore ?? "").isEmpty })
    }

    @Test func bossesComeInWavesAndOutrankThem() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let map = try #require(Content.shared.maps.first { $0.npcs?.contains { $0.monster == "rat_king" } == true })
        let npc = try #require(map.npcs?.first { $0.monster == "rat_king" })
        let level = try #require(npc.level)
        let waves = try #require(BattleController.bossWaves(npc, encounters: map.encounters, session: session))
        // Two waves of two of the map's own monsters, then the boss in the middle of two more.
        #expect(waves.map(\.count) == [2, 2, 3])
        #expect(waves[2][1].speciesID == "rat_king" && waves[2][1].level == level)
        let monsters = waves.joined().filter { $0.speciesID != "rat_king" }
        #expect(monsters.allSatisfy { map.encounters?.monsters[$0.speciesID ?? ""] != nil })
        // The boss outranks them all, and each wave stands a little closer to its level.
        #expect(monsters.allSatisfy { $0.level < level })
        #expect(waves[0].allSatisfy { $0.level <= level - 7 } && waves[1].allSatisfy { $0.level <= level - 4 })
        for (index, wave) in waves.enumerated() { #expect(wave.allSatisfy { $0.wave == index + 1 }) }
        let ids = waves.joined().map(\.id)
        #expect(Set(ids).count == ids.count && ids.allSatisfy { $0 >= 10 })

        // The fight opens with the first wave and knows how many follow.
        let battle = try #require(BattleController.boss(npc, encounters: map.encounters, session: session))
        #expect(battle.enemies.count == 2 && battle.wave == 1 && battle.waveCount == 3)
        #expect(!battle.enemies.contains { $0.speciesID == "rat_king" })
        #if DEBUG
        // Debug wins (screenshots) take every wave down at once.
        battle.winForDebug()
        #expect(battle.result?.outcome == .victory)
        #endif
        // Without the map's monsters it fights alone, in one wave.
        let alone = try #require(BattleController.boss(npc, session: session))
        #expect(alone.enemies.count == 1 && alone.waveCount == 1)
    }

    @Test func theNextWaveStepsInWhenOneIsBeaten() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 30, element: .neutral,
                             stats: Stats(hp: 500, mp: 20, attack: 60, defense: 50, magic: 10, speed: 99), hp: 500, mp: 20,
                             skills: [], captureRate: 0)
        let foeStats = jelly.stats(at: 1)
        let first = Combatant(id: 11, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                              stats: foeStats, hp: 1, mp: 0, skills: [], captureRate: jelly.captureRate)
        var boss = Combatant(id: 20, side: .enemies, source: .wild("jelly"), name: "Boss", art: jelly.art, level: 5, element: jelly.element,
                             stats: foeStats, hp: foeStats.hp, mp: 0, skills: [], captureRate: 0)
        boss.wave = 2
        let engine = BattleEngine(party: [hero], enemies: [first], content: content, seed: 9, waves: [[boss]])
        #expect(engine.wave == 1 && engine.waveCount == 2)
        let events = engine.resolveRound(heroAction: .attack(target: 11))
        // Beating the first wave isn't a win yet: the boss steps in for the next round.
        #expect(engine.outcome == .ongoing)
        #expect(engine.wave == 2)
        #expect(engine.combatant(20)?.isAlive == true)
        let steppedIn = events.contains { event in
            if case .wave(let number, let total, let arrivals) = event { return number == 2 && total == 2 && arrivals.map(\.id) == [20] }
            return false
        }
        #expect(steppedIn)
    }

    #if DEBUG
    @Test func bossesTellTheirStoryTheFirstTimeOnly() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let npc = try #require(Content.shared.boss(fighting: "rat_king"))
        let victory = try #require(npc.victory)
        let first = try #require(BattleController.boss(npc, session: session))
        first.winForDebug()
        #expect(first.result?.outcome == .victory)
        #expect(first.result?.story?.title == victory.title)
        #expect(first.result?.story?.paragraphs == victory.story)
        // Beaten once, a rematch is just a fight (the story stays in the Monster Book).
        session.defeatBoss(npc)
        let rematch = try #require(BattleController.boss(npc, session: session))
        rematch.winForDebug()
        #expect(rematch.result?.outcome == .victory)
        #expect(rematch.result?.story == nil)
    }
    #endif

    @Test func shopsBuyBackAndAdventurersTrade() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let potion = try #require(Content.shared.item("potion"))
        let gold = session.data.gold
        let potions = session.count(of: "potion")
        #expect(session.sell("potion") == GameSession.sellPrice(of: potion))
        #expect(session.data.gold == gold + GameSession.sellPrice(of: potion))
        #expect(session.count(of: "potion") == potions - 1)
        #expect(session.sell("not_an_item") == nil)

        let friend = Adventurer(name: "Mimi", raceID: "elf", classID: "mage", level: 10, look: .standard)
        let offers = session.tradeOffers(with: friend)
        // The same day gives the same offers.
        #expect(offers.map(\.id) == session.tradeOffers(with: friend).map(\.id))
        session.data.gold = 100_000
        let deal = try #require(offers.first { $0.kind == .theySell })
        #expect(session.trade(deal))
        #expect(session.count(of: deal.item.id) >= 1)
        // Each deal is made once.
        #expect(!session.trade(deal))
        #expect(!session.tradeOffers(with: friend).contains { $0.id == deal.id })
        if let buy = offers.first(where: { $0.kind == .theyBuy }) {
            // Adventurers pay more than the shop does.
            #expect(buy.price > GameSession.sellPrice(of: buy.item))
        }
    }

    @Test func battleButtonsKeepYourOrder() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        #expect(session.battleButtons == GameSession.defaultBattleButtons)
        let bash = try #require(Content.shared.classDef("novice").skills.first { $0.skill == "bash" })
        session.data.hero.level = bash.level
        session.learnSkill("bash")
        let skill = try #require(session.heroSkills.first)
        session.togglePin(skill.id)
        // A newly pinned skill joins just before More.
        let divider = try #require(session.battleButtons.firstIndex(of: GameSession.moreDivider))
        #expect(session.battleButtons[divider - 1] == "skill:\(skill.id)")
        // Your own order sticks, even with the skill as the big button.
        session.data.battleButtons = ["skill:\(skill.id)", "skills", "more", "attack", "items", "guard", "run", "capture"]
        #expect(session.battleButtons == ["skill:\(skill.id)", "skills", "more", "attack", "items", "guard", "run", "capture"])
        // Unpinned skills drop out; nothing else is lost.
        session.togglePin(skill.id)
        #expect(session.battleButtons == ["skills", "more", "attack", "items", "guard", "run", "capture"])
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

    @Test func companionsFollowOrders() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 200, mp: 20, attack: 30, defense: 10, magic: 10, speed: 20)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 5, element: .neutral,
                             stats: stats, hp: 200, mp: 20, skills: [], captureRate: 0)
        let pet = Combatant(id: 1, side: .party, source: .pet(UUID()), name: "Pet", art: jelly.art, level: 5, element: jelly.element,
                            stats: stats, hp: 200, mp: 20, skills: jelly.skills, captureRate: 0)
        let foeStats = jelly.stats(at: 30)
        let foe = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 30, element: jelly.element,
                            stats: foeStats, hp: foeStats.hp, mp: foeStats.mp, skills: [], captureRate: 0)
        let engine = BattleEngine(party: [hero, pet], enemies: [foe], content: content, seed: 7)
        // Told to guard, it guards; left to itself, it would have gone for the monster.
        let events = engine.resolveRound(heroAction: .defend, orders: [1: .defend])
        let guards = events.filter { event in
            if case .defend(let actor) = event { return actor == 1 }
            return false
        }
        let attacks = events.filter { event in
            if case .attack(let actor, _) = event { return actor == 1 }
            return false
        }
        #expect(guards.count == 1)
        #expect(attacks.isEmpty)
    }

    @Test func poisonBitesEachRoundAndCursesWeaken() throws {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 500, mp: 200, attack: 30, defense: 10, magic: 40, speed: 50)
        var hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 20, element: .neutral,
                             stats: stats, hp: 500, mp: 200, skills: ["poison", "curse"], captureRate: 0)
        hero.skillLevels = ["poison": 1, "curse": 1]
        let foeStats = jelly.stats(at: 20)
        // Plenty of HP, so it lasts the whole test.
        let foe = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 20, element: jelly.element,
                            stats: foeStats, hp: foeStats.hp * 20, mp: 0, skills: [], captureRate: 0)
        let engine = BattleEngine(party: [hero], enemies: [foe], content: content, seed: 3)
        func bites(_ events: [BattleEvent]) -> [Int] {
            events.compactMap { event in
                if case .ailmentDamage(let target, _, let amount) = event, target == 10 { return amount }
                return nil
            }
        }

        // Poison takes hold and bites at the end of the round it lands in, then once a round: 3 bites.
        let first = engine.resolveRound(heroAction: .skill("poison", target: 10))
        let tookHold = first.contains { event in
            if case .afflicted(let target, let effect, _) = event { return target == 10 && effect == .poison }
            return false
        }
        #expect(tookHold)
        let bite = try #require(bites(first).first)
        #expect(bite > 0)
        #expect(bites(engine.resolveRound(heroAction: .defend)) == [bite])
        #expect(bites(engine.resolveRound(heroAction: .defend)) == [bite])
        #expect(bites(engine.resolveRound(heroAction: .defend)).isEmpty)

        // A curse lowers the stats behind its hits (attack and magic) by a fifth for the rest of the
        // round and 3 more, and says by how much.
        let cursing = engine.resolveRound(heroAction: .skill("curse", target: 10))
        let shown = cursing.contains { event in
            if case .statsChanged(10, let changes, 3) = event {
                return changes.map(\.stat) == [.attack, .magic] && changes.allSatisfy { abs($0.amount + 0.2) < 0.001 }
            }
            return false
        }
        #expect(shown)
        let cursed = try #require(engine.combatant(10))
        #expect(abs(cursed.factor(.attack) - 0.8) < 0.001 && abs(cursed.factor(.magic) - 0.8) < 0.001)
        for _ in 0..<3 { _ = engine.resolveRound(heroAction: .defend) }
        #expect(abs((engine.combatant(10)?.factor(.attack) ?? 0) - 0.8) < 0.001)
        _ = engine.resolveRound(heroAction: .defend)
        #expect(engine.combatant(10)?.factor(.attack) == 1)
        #expect(engine.combatant(10)?.lowered.isEmpty == true)
    }

    @Test func aBossesMinionsStandTheirGround() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 500, mp: 20, attack: 1, defense: 50, magic: 1, speed: 1)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 30, element: .neutral,
                             stats: stats, hp: 500, mp: 20, skills: [], captureRate: 0)
        // The boss is down and its last minion nearly beaten: it can't run off and turn the win into "It got away".
        let boss = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Boss", art: jelly.art, level: 30, element: jelly.element,
                             stats: stats, hp: 0, mp: 0, skills: [], captureRate: 0)
        let minionStats = jelly.stats(at: 5)
        let minion = Combatant(id: 11, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 5, element: jelly.element,
                               stats: minionStats, hp: 1, mp: 0, skills: [], captureRate: jelly.captureRate)
        let engine = BattleEngine(party: [hero], enemies: [boss, minion], content: content, seed: 11)
        for _ in 0..<20 { _ = engine.resolveRound(heroAction: .defend) }
        #expect(engine.outcome == .ongoing)
        #expect(engine.combatant(11)?.hasFled == false)
    }

    @Test func companionsHoldBackOnlyWhileYouSeal() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let foeStats = jelly.stats(at: 1)
        func play(_ heroAction: BattleAction) -> [BattleEvent] {
            let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 5, element: .neutral,
                                 stats: Stats(hp: 500, mp: 20, attack: 30, defense: 50, magic: 10, speed: 50), hp: 500, mp: 20,
                                 skills: [], captureRate: 0)
            // Faster than everyone, so it acts first.
            let pet = Combatant(id: 1, side: .party, source: .pet(UUID()), name: "Pet", art: jelly.art, level: 5, element: jelly.element,
                                stats: Stats(hp: 500, mp: 0, attack: 30, defense: 50, magic: 10, speed: 99), hp: 500, mp: 0,
                                skills: [], captureRate: 0)
            let foe = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                                stats: foeStats, hp: 1, mp: 0, skills: [], captureRate: jelly.captureRate)
            let engine = BattleEngine(party: [hero, pet], enemies: [foe], content: content, seed: 5)
            return engine.resolveRound(heroAction: heroAction)
        }
        // The monster could be sealed, but you're not throwing a stone: your companion goes for it.
        let attacked = play(.defend).contains { event in
            if case .attack(let actor, _) = event { return actor == 1 }
            return false
        }
        #expect(attacked)
        // You throw one: it holds back.
        let heldBack = play(.capture(target: 10)).contains { event in
            if case .defend(let actor) = event { return actor == 1 }
            return false
        }
        #expect(heldBack)
    }

    @Test func reviveWakesAFaintedCompanionAndBlessHelps() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let heroStats = Stats(hp: 200, mp: 100, attack: 30, defense: 10, magic: 20, speed: 99)
        var hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 40, element: .neutral,
                             stats: heroStats, hp: 200, mp: 100, skills: ["revive", "bless"], captureRate: 0)
        hero.skillLevels = ["revive": 1, "bless": 1]
        let petStats = Stats(hp: 100, mp: 0, attack: 10, defense: 10, magic: 0, speed: 1)
        let pet = Combatant(id: 1, side: .party, source: .pet(UUID()), name: "Pet", art: jelly.art, level: 10, element: .neutral,
                            stats: petStats, hp: 0, mp: 0, skills: [], captureRate: 0)
        let stats = jelly.stats(at: 1)
        let enemy = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                              stats: stats, hp: 9_999, mp: 0, skills: [], captureRate: 0)
        let engine = BattleEngine(party: [hero, pet], enemies: [enemy], content: content, seed: 7)
        _ = engine.resolveRound(heroAction: .skill("revive", target: 1))
        // Revive Lv1 brings them back with 30% of their HP; a level-1 jelly can't knock that out.
        #expect(engine.combatant(1)!.hp > 0)
        #expect(engine.combatant(0)!.mp < 100)
        _ = engine.resolveRound(heroAction: .skill("bless", target: 0))
        let blessed = engine.combatant(0)!
        #expect(blessed.raised[.attack]?.rounds == BattleEngine.buffLength + 1)
        #expect(blessed.raised[.defense]?.rounds == BattleEngine.buffLength + 1)
        #expect(blessed.attack > Double(heroStats.attack))
    }

    @Test func buffsRaiseStatsForAWhileAndSayByHowMuch() throws {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 500, mp: 200, attack: 30, defense: 40, magic: 20, speed: 50)
        var hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 40, element: .neutral,
                             stats: stats, hp: 500, mp: 200, skills: ["protection", "berserk", "guardianship"], captureRate: 0)
        hero.skillLevels = ["protection": 1, "berserk": 1, "guardianship": 1]
        let friend = Combatant(id: 2, side: .party, source: .ally(UUID()), name: "Momo", art: "player_walk", level: 40, element: .neutral,
                               stats: Stats(hp: 500, mp: 0, attack: 20, defense: 20, magic: 0, speed: 1), hp: 500, mp: 0,
                               skills: [], captureRate: 0)
        let foeStats = jelly.stats(at: 1)
        let foe = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                            stats: foeStats, hp: 9_999, mp: 0, skills: [], captureRate: 0)
        let engine = BattleEngine(party: [hero, friend], enemies: [foe], content: content, seed: 9)

        // Protection: DEF +40%, said with the amount, for this round and 3 more.
        let shielding = engine.resolveRound(heroAction: .skill("protection", target: 0))
        #expect(shielding.contains { event in
            if case .statsChanged(0, let changes, 3) = event { return changes == [StatChange(stat: .defense, amount: 0.4)] }
            return false
        })
        let shielded = try #require(engine.combatant(0))
        #expect(abs(shielded.defense - 56) < 0.001)
        for _ in 0..<3 { _ = engine.resolveRound(heroAction: .defend) }
        #expect(engine.combatant(0)?.raised[.defense] != nil)
        _ = engine.resolveRound(heroAction: .defend)
        #expect(engine.combatant(0)?.raised[.defense] == nil)

        // Berserk trades defense for attack.
        _ = engine.resolveRound(heroAction: .skill("berserk", target: 0))
        let raging = try #require(engine.combatant(0))
        #expect(abs(raging.factor(.attack) - 1.3) < 0.001)
        #expect(abs(raging.factor(.defense) - 0.75) < 0.001)

        // Guardianship wards everyone on your side.
        let ward = engine.resolveRound(heroAction: .skill("guardianship", target: 0))
        let warded = Set(ward.compactMap { event -> Int? in
            if case .statsChanged(let target, _, _) = event { return target }
            return nil
        })
        #expect(warded == [0, 2])
        #expect(engine.combatant(2)?.raised[.defense] != nil)
    }

    @Test func monstersPowerThemselvesUp() throws {
        let content = Content.shared
        let wolf = try #require(content.monster("werewolf"))
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 60, element: .neutral,
                             stats: Stats(hp: 99_999, mp: 0, attack: 1, defense: 999, magic: 1, speed: 1), hp: 99_999, mp: 0,
                             skills: [], captureRate: 0)
        let stats = wolf.stats(at: 20)
        let foe = Combatant(id: 10, side: .enemies, source: .wild("werewolf"), name: "Werewolf", art: wolf.art, level: 20, element: wolf.element,
                            stats: stats, hp: stats.hp, mp: stats.mp, skills: wolf.skills, captureRate: wolf.captureRate)
        let engine = BattleEngine(party: [hero], enemies: [foe], content: content, seed: 21)
        var raged = false
        for _ in 0..<30 where !raged {
            raged = engine.resolveRound(heroAction: .defend).contains { event in
                if case .statsChanged(10, let changes, _) = event { return changes.contains { $0.stat == .attack && $0.amount > 0 } }
                return false
            }
        }
        #expect(raged)
    }

    @Test func friendsFightOnAfterYouFallAndWakeYou() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 200, mp: 100, attack: 30, defense: 10, magic: 20, speed: 10)
        // You've fallen; a friend who knows Revive is still standing.
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 40, element: .neutral,
                             stats: stats, hp: 0, mp: 20, skills: [], captureRate: 0)
        var friend = Combatant(id: 2, side: .party, source: .ally(UUID()), name: "Maple", art: "player_walk", level: 40, element: .neutral,
                               stats: stats, hp: 200, mp: 100, skills: ["revive"], captureRate: 0)
        friend.skillLevels = ["revive": 1]
        let foe = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                            stats: jelly.stats(at: 1), hp: 9_999, mp: 0, skills: [], captureRate: 0)
        let engine = BattleEngine(party: [hero, friend], enemies: [foe], content: content, seed: 4)
        _ = engine.resolveRound(heroAction: .defend)
        // The fight goes on without you, and your friend wakes you.
        #expect(engine.outcome == .ongoing)
        #expect(engine.combatant(0)!.hp > 0)

        // With only your companion standing, a fall loses the fight: companions don't fight on alone.
        let pet = Combatant(id: 1, side: .party, source: .pet(UUID()), name: "Pet", art: jelly.art, level: 40, element: .neutral,
                            stats: stats, hp: 200, mp: 0, skills: [], captureRate: 0)
        let alone = BattleEngine(party: [hero, pet], enemies: [foe], content: content, seed: 4)
        _ = alone.resolveRound(heroAction: .defend)
        #expect(alone.outcome == .defeat)
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

    @Test func eachGameHasItsOwnSave() {
        let first = GameSession.newGame(name: "One", raceID: "human")
        let second = GameSession.newGame(name: "Two", raceID: "elf")
        #expect(first.data.slot != nil && first.data.slot != second.data.slot)
        first.save()
        second.save()
        let names = Set(SaveStore.all().map(\.hero.name))
        #expect(names.isSuperset(of: ["One", "Two"]))
        if let slot = first.data.slot { SaveStore.delete(slot: slot) }
        #expect(!SaveStore.all().contains { $0.slot == first.data.slot })
        #expect(SaveStore.all().contains { $0.slot == second.data.slot })
        if let slot = second.data.slot { SaveStore.delete(slot: slot) }
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
        // Momo's companion comes along, named for Momo, and stands behind Momo.
        #expect(controller.party.contains { $0.name == "Momo's Jelly Puff" && $0.petID != nil })
        let fighter = controller.party.first { $0.name == "Momo" }
        #expect(fighter != nil && controller.party.first { $0.name == "Momo's Jelly Puff" }?.ownerID == fighter?.id)
        #expect(controller.party.first { $0.name == "Momo" }?.classID == "mage")
        #expect(controller.enemies.map(\.name) == ["Grump"])
        session.leaveParty(momo.id)
        #expect(session.partyMembers.isEmpty)
        #expect(session.friends.count == 1)
    }

    @Test func friendsSayWhenTheyGoUpALevelWithYou() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.level = 30
        let momo = Adventurer(name: "Momo", raceID: "elf", classID: "mage", level: 27, look: .standard)
        let pip = Adventurer(name: "Pip", raceID: "human", classID: "fighter", level: 40, look: .standard)
        #expect(session.befriend(momo))
        #expect(session.befriend(pip))
        session.adventurersAround = [momo.id, pip.id]
        session.invite(momo.id)
        session.invite(pip.id)
        // You go up a level: Momo keeps a level behind you and says so; Pip, already past you, doesn't.
        session.data.hero.level = 31
        let grown = session.growParty()
        #expect(grown.map { $0.name } == ["Momo"])
        #expect(grown.first?.level == 30)
        #expect(session.growParty().isEmpty)
    }

    @Test func theOldSaveMovesInOnceAndCopiesCollapse() throws {
        let manager = FileManager.default
        try? manager.removeItem(at: SaveStore.folder)
        defer {
            try? manager.removeItem(at: SaveStore.folder)
            try? manager.removeItem(at: SaveStore.legacyURL)
        }
        // A save from before the folder (no slot), in Application Support: a path with a space.
        var old = GameSession.newGame(name: "Old", raceID: "human").data
        old.slot = nil
        try manager.createDirectory(at: SaveStore.legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(old).write(to: SaveStore.legacyURL)
        // However often the title screen looks, it moves in once, and the old file goes.
        for _ in 0..<3 { _ = SaveStore.all() }
        #expect(SaveStore.all().filter { $0.hero.name == "Old" }.count == 1)
        #expect(!manager.fileExists(atPath: SaveStore.legacyURL.path(percentEncoded: false)))
        // Copies that differ only in their slot (what the old bug left behind) collapse to one.
        var copy = old
        for _ in 0..<2 {
            copy.slot = UUID().uuidString
            SaveStore.save(copy)
        }
        #expect(SaveStore.all().filter { $0.hero.name == "Old" }.count == 1)
        // A copy you played on is a game of its own, and stays.
        copy.slot = UUID().uuidString
        copy.gold += 100
        SaveStore.save(copy)
        #expect(SaveStore.all().filter { $0.hero.name == "Old" }.count == 2)
    }

    @Test func aFullPartyBringsItsCompanions() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let friends = (0..<5).map { index in
            Adventurer(name: "Friend \(index)", raceID: "elf", classID: "mage", level: 4, look: .standard, petSpecies: "jelly")
        }
        for friend in friends { #expect(session.befriend(friend)) }
        session.adventurersAround = Set(friends.map(\.id))
        for friend in friends { session.invite(friend.id) }
        // Four friends travel with you; the fifth waits for a place.
        #expect(GameSession.maxAllies == 4)
        #expect(session.partyMembers.count == 4)
        let rival = Adventurer(name: "Grump", raceID: "dwarf", classID: "fighter", level: 7, look: .standard, hostile: true)
        let controller = BattleController.duel(with: rival, session: session)
        // Each brings their companion, and nobody on your side shares an id with the other (10 and up).
        #expect(controller.party.filter { $0.petID != nil }.count == 4)
        let ids = controller.party.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0 < 10 })
    }

    @Test func thePartySplitsWhenSomeoneFaints() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let maple = Adventurer(name: "Maple", raceID: "human", classID: "mage", level: 10, look: .standard)
        let kip = Adventurer(name: "Kip", raceID: "elf", classID: "fighter", level: 10, look: .standard)
        for friend in [maple, kip] { #expect(session.befriend(friend)) }
        session.adventurersAround = [maple.id, kip.id]
        session.invite(maple.id)
        session.invite(kip.id)
        // Out in Sunny Meadow, in from Meadowbrook on the west: everyone's checkpoint is that entrance.
        let meadow = try #require(Content.shared.map("sunny_meadow"))
        session.data.mapID = meadow.id
        session.reachCheckpoint(meadow, entry: .west)
        session.playerPosition = CGPoint(x: 100, y: 50)
        let entrance = Spot(mapID: meadow.id, entry: .west)

        // Kip faints, but the fight is won: Kip wakes up at the entrance and waits there.
        _ = session.partWays(fainted: [kip.id], heroFainted: false)
        #expect(session.friendsAtYourSide.map(\.name) == ["Maple"])
        #expect(session.friends.first { $0.id == kip.id }?.waitingAt == entrance)

        // You fall with Maple still standing: you wake up at your checkpoint, and Maple waits where you fell.
        let lines = session.partWays(fainted: [], heroFainted: true)
        #expect(lines == ["You wake up at the Sunny Meadow entrance, a little bruised.", "Maple waits for you where you fell."])
        #expect(session.friends.first { $0.id == maple.id }?.waitingAt == Spot(mapID: meadow.id, position: [100, 50]))
        // Both are still in your party, but they don't fight until you come back for them.
        #expect(session.partyMembers.count == 2 && session.friendsAtYourSide.isEmpty)
        let encounters = try #require(meadow.encounters)
        #expect(!BattleController.encounter(encounters, session: session).party.contains { $0.isAlly })
        session.rejoin(maple.id)
        #expect(session.friendsAtYourSide.map(\.name) == ["Maple"])

        // Falling together, a friend who saved where you did wakes up beside you.
        let together = session.partWays(fainted: [maple.id], heroFainted: true)
        #expect(together.first == "You and Maple wake up at the Sunny Meadow entrance, a little bruised.")
        #expect(session.friendsAtYourSide.map(\.name) == ["Maple"])
    }

    @Test func botsAndModeratorsAreTagged() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.postChat("hi!", from: "Momo", kind: .adventurer)
        #expect(session.chat.last?.badge == .bot)
        session.isModerator = false
        session.postChat("hello", from: "Test", kind: .you)
        #expect(session.chat.last?.badge == nil)
        session.isModerator = true
        session.postChat("hello", from: "Test", kind: .you)
        #expect(session.chat.last?.badge == .mod)
        session.postChat("Welcome!", from: "Elder Oak", kind: .npc)
        #expect(session.chat.last?.badge == nil)
        // Only the moderator code switches it on (its hash is in the source, never the code).
        #expect(!Moderation.unlock(with: "not the code"))
    }

    @Test func worldMessagesAndAnnouncementsFollowYouFromMapToMap() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.isModerator = true
        session.startChat(on: "Meadowbrook")
        session.postWorld("Welcome, everyone!")
        session.announce("Dawn breaks over Mysteria.")
        session.postChat("lol", from: "Momo", kind: .adventurer)
        session.startChat(on: "Goldburg")
        // What's said to everyone stays; the map's own chatter starts over.
        #expect(session.chat.map(\.kind) == [.world, .announcement, .system])
        #expect(session.chat.first?.badge == .mod)
        #expect(session.log.contains { $0.kind == .world } && session.log.contains { $0.kind == .announcement })
    }

    @Test func aRareSightingMakesItTurnUpMoreOften() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let meadow = try #require(Content.shared.map("sunny_meadow"))
        let encounters = try #require(meadow.encounters)
        let rare = try #require(encounters.monsters.keys.first { Content.shared.monster($0)?.rare == true })
        let base = try #require(encounters.monsters[rare])
        session.data.mapID = meadow.id
        #expect(BattleController.encounterWeights(encounters, session: session)[rare] == base)
        session.sighting = GameSession.Sighting(mapID: meadow.id, monsterID: rare, boost: 6, until: Date().addingTimeInterval(60))
        #expect(BattleController.encounterWeights(encounters, session: session)[rare] == base * 6)
        // Only on its own map, and only until it's over.
        session.data.mapID = "meadowbrook"
        #expect(BattleController.encounterWeights(encounters, session: session)[rare] == base)
        session.data.mapID = meadow.id
        session.sighting = GameSession.Sighting(mapID: meadow.id, monsterID: rare, boost: 6, until: Date().addingTimeInterval(-1))
        #expect(BattleController.encounterWeights(encounters, session: session)[rare] == base)
    }

    @Test func marketTradersCallOutTheirDeals() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let trader = Adventurer(name: "Momo", raceID: "dwarf", classID: "fighter", level: 30, look: .standard)
        let offers = session.tradeOffers(with: trader)
        // The sign shows something they really sell today, and what they call out is a real deal.
        let sign = try #require(session.marketSign(for: trader))
        #expect(offers.contains { $0.kind == .theySell && sign == "\($0.item.name) · \($0.price)g" })
        let shout = try #require(session.marketShout(for: trader))
        #expect(offers.contains { shout.contains($0.item.name) && shout.contains("\($0.price)") })
    }

    @Test func botsWearArmourForTheirClassAndLevel() {
        func bot(_ classID: String, _ level: Int) -> Adventurer {
            Adventurer(name: "Momo", raceID: "elf", classID: classID, level: level, look: .standard)
        }
        var worn: Set<String> = []
        for _ in 0..<60 {
            for (classID, level) in [("novice", 5), ("fighter", 45), ("mage", 45), ("tamer", 70), ("fighter", 90)] {
                let someone = bot(classID, level)
                let armor = GameSession.armor(for: someone)
                #expect(armor?.type == .armor)
                #expect((armor?.level ?? 1) <= level, "\(armor?.id ?? "-") is above level \(level)")
                #expect(armor?.classes?.contains(classID) ?? true, "a \(classID) can't wear \(armor?.id ?? "-")")
                // The same adventurer always wears the same.
                #expect(GameSession.armor(for: someone)?.id == armor?.id)
                if let armor { worn.insert(armor.id) }
            }
        }
        // ...but the crowd doesn't all wear the same, and past their first steps it isn't a tunic.
        #expect(worn.count >= 8)
        #expect((GameSession.armor(for: bot("fighter", 45))?.level ?? 1) >= 14)
        #expect(!GameSession.wearsBoots(bot("fighter", 30)))
    }

    @Test func botsFightWithAWeaponForTheirClassAndLevel() {
        var held: Set<String> = []
        for _ in 0..<60 {
            for (classID, level) in [("novice", 5), ("fighter", 45), ("mage", 45), ("tamer", 70), ("fighter", 90)] {
                let someone = Adventurer(name: "Momo", raceID: "elf", classID: classID, level: level, look: .standard)
                let weapon = GameSession.weapon(for: someone)
                #expect(weapon?.type == .weapon)
                #expect((weapon?.level ?? 1) <= level, "\(weapon?.id ?? "-") is above level \(level)")
                #expect(weapon?.classes?.contains(classID) ?? true, "a \(classID) can't hold \(weapon?.id ?? "-")")
                // The same adventurer always holds the same.
                #expect(GameSession.weapon(for: someone)?.id == weapon?.id)
                if let weapon { held.insert(weapon.id) }
            }
        }
        #expect(held.count >= 8)
    }

    @Test func aBackupComesBackAsAGameOfItsOwn() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.data.hero.level = 12
        let game = try SaveStore.imported(try JSONEncoder().encode(session.data))
        #expect(game.hero.name == "Test" && game.hero.level == 12)
        // A slot of its own, so it never overwrites the game it was made from.
        #expect(game.slot != nil && game.slot != session.data.slot)
        #expect(throws: (any Error).self) { try SaveStore.imported(Data("not a save".utf8)) }
    }

    @Test func autoFightsOnlyMonstersWellBelowYou() throws {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        let meadow = try #require(Content.shared.map("sunny_meadow")?.encounters)
        let lowest = meadow.levels.first ?? 1
        let highest = meadow.levels.last ?? lowest
        session.data.hero.level = highest + BattleController.autoLevelGap
        #expect(BattleController.encounter(meadow, session: session).canAuto)
        // Every monster here is within a few levels of you: you fight it yourself.
        session.data.hero.level = lowest + BattleController.autoLevelGap - 1
        #expect(!BattleController.encounter(meadow, session: session).canAuto)
        // Never in a duel.
        session.data.hero.level = 60
        let rival = Adventurer(name: "Grump", raceID: "dwarf", classID: "fighter", level: 1, look: .standard, hostile: true)
        #expect(!BattleController.duel(with: rival, session: session).canAuto)
    }

    @Test func theHeroOnAutoFightsLikeAFriend() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 200, mp: 100, attack: 30, defense: 10, magic: 20, speed: 10)
        var hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 40, element: .neutral,
                             stats: stats, hp: 200, mp: 100, skills: ["first_aid"], captureRate: 0)
        hero.skillLevels = ["first_aid": 1]
        let friend = Combatant(id: 2, side: .party, source: .ally(UUID()), name: "Maple", art: "player_walk", level: 40, element: .neutral,
                               stats: stats, hp: 30, mp: 0, skills: [], captureRate: 0)
        let foe = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                            stats: jelly.stats(at: 1), hp: 5, mp: 0, skills: [], captureRate: 0)
        let engine = BattleEngine(party: [hero, friend], enemies: [foe], content: content, seed: 2)
        // A friend in trouble is healed first, as a friend would; then it's the monster's turn to fall.
        guard case .skill(let skill, let target) = engine.autoAction(for: 0) else {
            Issue.record("expected First Aid on Maple")
            return
        }
        #expect(skill == "first_aid" && target == 2)
    }

    @Test func monstersBeatenTogetherFallTogether() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = Stats(hp: 200, mp: 100, attack: 60, defense: 10, magic: 20, speed: 999)
        var hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 40, element: .neutral,
                             stats: stats, hp: 200, mp: 100, skills: ["whirlwind"], captureRate: 0)
        hero.skillLevels = ["whirlwind": 1]
        let foes = (10..<13).map { id -> Combatant in
            Combatant(id: id, side: .enemies, source: .wild("jelly"), name: id == 11 ? "Fire Rat" : "Jelly", art: jelly.art, level: 1,
                      element: jelly.element, stats: jelly.stats(at: 1), hp: 1, mp: 0, skills: [], captureRate: 0)
        }
        let engine = BattleEngine(party: [hero], enemies: foes, content: content, seed: 5)
        let events = engine.resolveRound(heroAction: .skill("whirlwind", target: 10))
        let defeats = events.indices.filter { index in
            if case .defeated = events[index] { return true }
            return false
        }
        // The sweep's knock-outs come one after another, so the battle plays them as one.
        #expect(defeats.count == 3)
        #expect(defeats == Array((defeats.first ?? 0)..<((defeats.first ?? 0) + 3)))
        #expect(BattleController.tally(foes.map(\.name)) == "Jelly ×2 and Fire Rat")
        #expect(BattleController.tally(["Fire Rat"]) == "Fire Rat")
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
        #expect(BattleEngine.splashFraction(of: fire, level: 4) == 0)
        #expect(BattleEngine.splashFraction(of: fire, level: 5) > 0)
        #expect(BattleEngine.splashFraction(of: fire, level: 10) > BattleEngine.splashFraction(of: fire, level: 5))
        #expect(BattleEngine.splashFraction(of: Content.shared.skill("bash")!, level: 10) == 0)
    }
}

@MainActor
struct PerformanceTests {
    /// How long one map may take to build. An optimised build, like the App Store's, should do it in
    /// a few seconds. A debug build runs this code many times slower: in the CI tests job (a simulator
    /// on a shared runner) the biggest maps took up to 48 s, so there the bound only catches a map
    /// that's become pathologically slow, and the job's log lists every map's time (⏱) to watch.
    #if DEBUG
    static let mapBuildLimit: Duration = .seconds(90)
    #else
    static let mapBuildLimit: Duration = .seconds(3)
    #endif

    /// Every map must build, and quickly; this prints how long each one takes.
    @Test func mapsBuildQuickly() async {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        for def in Content.shared.maps {
            let clock = ContinuousClock()
            var grid: WorldMap?
            let gridTime = clock.measure { grid = WorldMap(def: def) }
            let start = clock.now
            let scene = WorldScene(map: def, session: session, input: InputState(), entry: nil)
            await scene.build { _ in }
            let sceneTime = clock.now - start
            #expect(scene.isBuilt)
            print("⏱ \(def.id): grid \(gridTime), scene \(sceneTime), cells \(grid!.columns * grid!.rows)")
            #expect(sceneTime < Self.mapBuildLimit, "\(def.id) took \(sceneTime) to build")
        }
    }
}

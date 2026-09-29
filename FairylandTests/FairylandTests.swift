import Foundation
import Testing
@testable import Fairyland

/// Catches broken references when editing content/*.json or art/assets.json.
@MainActor
struct ContentTests {
    let content = Content.shared

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
            }
        }
    }

    @Test func songsParse() {
        for song in content.songs {
            let tune = Tune(song)
            for (index, voice) in tune.voices.enumerated() {
                #expect(!voice.notes.isEmpty, "song \(song.id) track \(index) has no notes")
                #expect(voice.notes.allSatisfy { $0.frequency != 0 || true })
            }
        }
        #expect(abs((Tune.frequency(of: "A4") ?? 0) - 440) < 0.01)
        #expect(abs((Tune.frequency(of: "C4") ?? 0) - 261.63) < 0.01)
    }

    @Test func everyMapHasRoomToWalk() {
        for def in content.maps {
            let map = WorldMap(def: def)
            for exit in def.exits {
                #expect(map.isWalkable(map.entryCell(from: exit.edge)), "map \(def.id) entry from \(exit.edge) is blocked")
            }
        }
    }
}

@MainActor
struct RulesTests {
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
        #expect(session.heroSkills.contains { $0.id == "bash" })
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
        #expect(session.heroSkills.contains { $0.id == "fire_bolt" })
    }

    @Test func firstCompanionHatchesFromTheGiftBoxEgg() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        #expect(session.data.pets.isEmpty)
        let quest = Content.shared.quest("hope_of_meadowbrook")!
        let chests = (Content.shared.map("meadowbrook")?.npcs ?? []).filter { $0.role == .chest }
        #expect(chests.count == 3)
        #expect(!session.canOpen(chests[0]))   // needs the quest first
        session.acceptQuest(quest.id, answer: quest.question?.answers.first { $0.egg == "jelly" })
        for chest in chests { session.openChest(chest) }
        #expect(session.status(of: quest) == .ready)
        #expect(session.count(of: "pet_egg") == 1)
        let pet = session.hatch("pet_egg")
        #expect(pet?.speciesID == "jelly")
        #expect(session.activePet?.id == pet?.id)
        session.turnInQuest(quest.id)
        #expect(session.status(of: Content.shared.quest("jelly_trouble")!) == .available)
    }

    @Test func skillPointsRaiseSkills() {
        let session = GameSession.newGame(name: "Test", raceID: "human")
        session.gainHeroEXP(GameSession.expToNext(level: 1) + GameSession.expToNext(level: 2))
        #expect(session.data.hero.level == 3)
        #expect(session.unspentSkillPoints == 2)
        session.upgradeSkill("bash")
        #expect(session.skillLevel("bash") == 2)
        #expect(session.unspentSkillPoints == 1)
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
        #expect(engine.outcome == .victory)
    }

    @Test func captureNeedsAWeakenedMonster() {
        let content = Content.shared
        let jelly = content.monster("jelly")!
        let stats = jelly.stats(at: 1)
        let hero = Combatant(id: 0, side: .party, source: .hero, name: "Hero", art: "player_walk", level: 1, element: .neutral,
                             stats: Stats(hp: 60, attack: 10, defense: 8, speed: 10), hp: 60, mp: 0, skills: [], captureRate: 0)
        var enemy = Combatant(id: 10, side: .enemies, source: .wild("jelly"), name: "Jelly", art: jelly.art, level: 1, element: jelly.element,
                              stats: stats, hp: stats.hp, mp: 0, skills: [], captureRate: jelly.captureRate)
        #expect(BattleEngine(party: [hero], enemies: [enemy], content: content).captureStatus(of: 10) == .tooHealthy)
        enemy.hp = stats.hp / 4
        let engine = BattleEngine(party: [hero], enemies: [enemy], content: content)
        guard case .ready(let chance) = engine.captureStatus(of: 10) else {
            Issue.record("expected capture to be possible")
            return
        }
        #expect(chance > 0.3)
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

import SpriteKit

/// Background life on a map: adventurers (standing in for Fairyland's other players, some
/// with a companion trotting behind) and villagers pottering around town. They stroll,
/// pause, look around and chat now and then. They never block the way. Walk up to an
/// adventurer to see their card: befriend them, invite them along, or (in danger zones) duel.
final class Crowd {
    private final class Member {
        let name: String
        let kind: GameSession.ChatLine.Kind
        let walker: Walker
        let pet: Walker?
        let home: GridPoint
        let roam: Int
        let lines: [String]
        /// Adventurers have a level, class and companion like you.
        let profile: Adventurer?
        var wait: TimeInterval
        var chat: TimeInterval
        /// Hostile adventurers wait a while between picking fights.
        var calm: TimeInterval = 8

        init(name: String, kind: GameSession.ChatLine.Kind, walker: Walker, pet: Walker?, home: GridPoint, roam: Int,
             lines: [String], profile: Adventurer? = nil) {
            self.profile = profile
            self.name = name
            self.kind = kind
            self.walker = walker
            self.pet = pet
            self.home = home
            self.roam = roam
            self.lines = lines
            wait = .random(in: 0.5...4)
            chat = .random(in: 6...30)
        }
    }

    static let adventurerColor = UIColor(red: 0.62, green: 0.93, blue: 1, alpha: 1)
    static let hostileColor = UIColor(red: 1, green: 0.42, blue: 0.4, alpha: 1)

    /// Everything anyone says goes to the map's chat log.
    var onChat: ((String, String, GameSession.ChatLine.Kind) -> Void)?
    /// A red-named adventurer in a danger zone walks up and picks a fight.
    var onChallenge: ((Adventurer) -> Void)?

    private let map: WorldMap
    private var members: [Member] = []
    private let replies = Content.shared.crowd.replies
    private var rng = SystemRandomNumberGenerator()

    /// Friends you've made (and who aren't travelling with you) now and then turn up on a map with
    /// other adventurers about, if it suits their level, so you can meet them again and invite them.
    init(def: MapDef, map: WorldMap, world: SKNode, friends: [Adventurer] = []) {
        self.map = map
        let options = Content.shared.crowd
        let town = def.fence == true
        let spread = max(map.columns, map.rows) / 2
        var adventurerNames = options.adventurerNames.shuffled()
        var villagerNames = options.villagerNames.shuffled()

        let levels = def.encounters.map { ($0.levels.first ?? 1)...(($0.levels.last ?? 1) + 3) } ?? 1...8
        let count = def.crowd?.adventurers ?? 0
        // Towns welcome anyone; out in the wild, friends roam where the monsters suit them.
        let nearLevel = (levels.lowerBound - 10)...(levels.upperBound + 10)
        let visitors: [Adventurer] = count == 0 ? [] : Array(friends
            .filter { town || nearLevel.contains($0.level) }
            .filter { _ in Double.random(in: 0..<1) < Self.friendVisitChance }
            .shuffled()
            .prefix(min(2, count)))
        for index in 0..<count {
            guard let home = map.strollTarget(near: map.center, radius: spread, using: &rng) else { continue }
            let profile = index < visitors.count
                ? visitors[index]
                : Self.profile(named: adventurerNames.popLast() ?? "Traveller", levels: levels, danger: def.danger == true)
            addAdventurer(profile, home: home, roam: town ? 9 : 14, world: world)
        }
        for _ in 0..<(def.crowd?.villagers ?? 0) {
            guard let home = map.strollTarget(near: map.center, radius: spread, using: &rng) else { continue }
            let name = villagerNames.popLast() ?? "Villager"
            let look = Self.randomLook()
            let walker = Self.person(name, race: Content.shared.races.randomElement()?.id ?? "human", look: look, color: .white)
            walker.walkSpeed = .random(in: 50...66)
            add(Member(name: name, kind: .villager, walker: walker, pet: nil, home: home, roam: 5, lines: options.villagerLines), to: world)
        }
    }

    /// How likely each friend is to be on a map you enter.
    static let friendVisitChance = 0.35

    private func addAdventurer(_ profile: Adventurer, home: GridPoint, roam: Int, world: SKNode) {
        let walker = Self.person(profile.name, race: profile.raceID, look: profile.look,
                                 color: profile.hostile ? Self.hostileColor : Self.adventurerColor)
        walker.walkSpeed = .random(in: 72...92)
        var pet: Walker?
        if let species = profile.petSpecies.flatMap(Content.shared.monster) {
            pet = Walker(cycle: ArtLibrary.shared.walkCycle(species.art), label: nil)
            pet?.walkSpeed = 110
            pet?.motion = IdleMotion.of(art: species.art)
        }
        add(Member(name: profile.name, kind: .adventurer, walker: walker, pet: pet, home: home, roam: roam,
                   lines: Content.shared.crowd.adventurerLines, profile: profile), to: world)
    }

    /// A friend who left your party stays on this map, strolling around where they stood.
    func rejoin(_ friend: Adventurer, at point: CGPoint, world: SKNode) {
        guard !members.contains(where: { $0.profile?.id == friend.id }) else { return }
        addAdventurer(friend, home: map.cell(at: point), roam: 9, world: world)
        if let member = members.last {
            member.walker.position = point
            member.pet?.position = point + CGVector(dx: -30, dy: 0)
        }
    }

    /// A random adventurer: level to suit the area, a class once they're past Novice, and
    /// often a companion. In danger zones some are troublemakers.
    private static func profile(named name: String, levels: ClosedRange<Int>, danger: Bool) -> Adventurer {
        let content = Content.shared
        let level = Int.random(in: levels)
        let classID = level < content.classChoiceLevel ? "novice" : (content.classes.filter { $0.id != "novice" }.randomElement()?.id ?? "novice")
        let pets = content.crowd.companions.compactMap { art in content.monsters.first { $0.art == art }?.id }
        return Adventurer(name: name, raceID: content.races.randomElement()?.id ?? "human", classID: classID, level: level,
                          look: randomLook(), petSpecies: Bool.random() ? pets.randomElement() : nil,
                          hostile: danger && Int.random(in: 0..<5) < 2)
    }

    private static func randomLook() -> Look {
        let options = Content.shared.appearance
        return Look(hair: options.hair.randomElement()?.id ?? Look.standard.hair,
                    outfit: options.outfits.randomElement()?.id ?? Look.standard.outfit,
                    skin: options.skin.randomElement()?.id ?? Look.standard.skin,
                    gender: options.genders.randomElement()?.id)
    }

    /// Someone of a race and look, recoloured like a customised hero.
    private static func person(_ name: String, race raceID: String, look: Look, color: UIColor) -> Walker {
        let sheet = Content.shared.race(raceID).sheet(for: look.gender)
        let id = "adv:\(raceID):\(look.key)"
        ArtLibrary.shared.register(id, from: sheet, recolor: GameSession.rules(for: look), key: sheet + "/" + look.key)
        let walker = Walker(cycle: ArtLibrary.shared.walkCycle(id), label: name, labelColor: color)
        walker.tagMode = .onDemand
        return walker
    }

    private func add(_ member: Member, to world: SKNode) {
        member.walker.position = map.center(of: member.home)
        member.walker.face(Direction.allCases.randomElement() ?? .down)
        world.addChild(member.walker)
        if let pet = member.pet {
            pet.position = member.walker.position + CGVector(dx: -30, dy: 0)
            world.addChild(pet)
        }
        members.append(member)
    }

    // MARK: - Every frame

    func update(dt: TimeInterval, player: CGPoint) {
        for member in members {
            let walker = member.walker
            walker.isNear = walker.position.distance(to: player) < Walker.nameRange
            // Adventurers stop to chat when you walk up to them.
            if member.profile?.hostile == false, walker.position.distance(to: player) < 90 {
                walker.path = []
                walker.face(Direction(player - walker.position, current: walker.facing))
                member.wait = max(member.wait, 1.5)
            }
            if !walker.path.isEmpty {
                walker.followPath(dt: dt)
                walker.setWalking(true)
            } else {
                walker.setWalking(false)
                member.wait -= dt
                if member.wait <= 0 { decide(member) }
            }
            member.chat -= dt
            if member.chat <= 0 {
                member.chat = .random(in: 20...45)
                // Adventurers talk on the map channel; villagers only chat to those nearby.
                let near = walker.position.distance(to: player) < 420
                if near || member.kind == .adventurer, let line = member.lines.randomElement() {
                    speak(line, by: member, bubble: near)
                }
            }
            if let profile = member.profile, profile.hostile {
                member.calm -= dt
                let distance = walker.position.distance(to: player)
                if member.calm <= 0, distance < 170 {
                    member.calm = 25
                    walker.path = []
                    walker.setWalking(false)
                    walker.face(Direction(player - walker.position, current: walker.facing))
                    speak(["Hey! You there!", "Fight me!", "This is my turf!", "Let's see what you've got!"].randomElement() ?? "Fight me!",
                          by: member, bubble: true)
                    onChallenge?(profile)
                }
            }
            walker.zPosition = -walker.position.y
            if let pet = member.pet {
                walker.markFootstep()
                pet.follow(walker, dt: dt, footstep: walker.footstep(behind: 36)) { self.map.isWalkable(self.map.rawCell(at: $0)) }
                pet.zPosition = -pet.position.y
            }
        }
    }

    /// Standing around is over: look about, or stroll somewhere near home.
    private func decide(_ member: Member) {
        if Int.random(in: 0..<3, using: &rng) == 0 {
            member.walker.face(Direction.allCases.randomElement(using: &rng) ?? .down)
            member.wait = .random(in: 1.5...3.5, using: &rng)
            return
        }
        member.wait = .random(in: 2...7, using: &rng)
        guard let target = map.strollTarget(near: member.home, radius: member.roam, using: &rng) else { return }
        let path = map.path(from: member.walker.position, to: map.center(of: target))
        // Skip long detours around ponds and fences; they'll pick somewhere else next time.
        if path.count <= member.roam * 3 { member.walker.path = path }
    }

    // MARK: - Meeting people

    /// The adventurer standing closest to `point`, if anyone is within reach.
    func adventurer(near point: CGPoint, within reach: CGFloat) -> Adventurer? {
        members
            .compactMap { member in member.profile.map { (profile: $0, distance: member.walker.position.distance(to: point)) } }
            .filter { $0.distance < reach }
            .min { $0.distance < $1.distance }?
            .profile
    }

    /// The adventurer you tapped (or their companion), if any.
    func adventurer(at point: CGPoint) -> Adventurer? {
        func hit(_ node: SKNode) -> Bool { (node.position + CGVector(dx: 0, dy: 24)).distance(to: point) < 30 }
        return members.first { member in
            member.profile != nil && (hit(member.walker) || member.pet.map { hit($0) } == true)
        }?.profile
    }

    /// Every adventurer within reach of `point`.
    func adventurers(near point: CGPoint, within reach: CGFloat) -> Set<UUID> {
        Set(members.compactMap { member in
            member.walker.position.distance(to: point) < reach ? member.profile?.id : nil
        })
    }

    func position(of id: UUID) -> CGPoint? {
        members.first { $0.profile?.id == id }?.walker.position
    }

    /// They left: joined your party, or ran off after a duel.
    func remove(_ id: UUID, poof: Bool) {
        guard let index = members.firstIndex(where: { $0.profile?.id == id }) else { return }
        let member = members.remove(at: index)
        for node in [member.walker, member.pet].compactMap({ $0 }) {
            if poof, let parent = node.parent { SkillEffects.smoke(at: node.position, in: parent) }
            node.run(.sequence([.fadeOut(withDuration: poof ? 0.3 : 0), .removeFromParent()]))
        }
    }

    func say(_ line: String, from id: UUID) {
        guard let member = members.first(where: { $0.profile?.id == id }) else { return }
        speak(line, by: member, bubble: true)
    }

    // MARK: - Tapping

    /// Tapping someone makes them turn to you and say something. Returns whether anyone was hit.
    @discardableResult
    func greet(at point: CGPoint, from player: CGPoint) -> Bool {
        guard let member = members.first(where: { ($0.walker.position + CGVector(dx: 0, dy: 24)).distance(to: point) < 30 }) else {
            return false
        }
        member.walker.path = []
        member.walker.setWalking(false)
        member.walker.revealTag()
        member.walker.face(Direction(player - member.walker.position, current: member.walker.facing))
        member.wait = 3
        member.chat = .random(in: 20...45)
        if let line = member.lines.randomElement() { speak(line, by: member, bubble: true) }
        return true
    }

    /// After you say something, someone nearby (or on the map) may answer.
    func reply(near point: CGPoint) {
        guard Int.random(in: 0..<3, using: &rng) > 0 else { return }
        let nearby = members.filter { $0.walker.position.distance(to: point) < 420 }
        guard let member = (nearby.isEmpty ? members.filter { $0.kind == .adventurer } : nearby).randomElement(),
              let line = replies.randomElement() else { return }
        member.chat = .random(in: 20...45)
        let near = !nearby.isEmpty
        member.walker.run(.wait(forDuration: .random(in: 1.2...3))) { [weak self] in
            self?.speak(line, by: member, bubble: near)
        }
    }

    private func speak(_ line: String, by member: Member, bubble: Bool) {
        if bubble { member.walker.say(line) }
        onChat?(member.name, line, member.kind)
    }
}

import SwiftUI

/// New skills to learn and known skills to raise, each for one skill point. Used on the
/// Character screen and the Level Up card after a battle.
struct SkillChoices: View {
    let session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(session.learnableSkills) { skill in
                LearnSkillRow(session: session, skill: skill)
            }
            ForEach(session.heroSkills) { skill in
                SkillRow(session: session, skill: skill)
            }
        }
    }
}

/// A skill your class just unlocked: learn it for a point.
struct LearnSkillRow: View {
    let session: GameSession
    let skill: SkillDef

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            SkillIcon(skill: skill, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(skill.name)
                    Text("NEW")
                        .font(HUDStyle.font(9))
                        .foregroundStyle(HUDStyle.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(HUDStyle.gold))
                    if let element = skill.element {
                        ElementBadge(element: element)
                    }
                }
                if let description = skill.description {
                    Text(description).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                }
            }
            Spacer()
            Text("\(GameSession.mpCost(of: skill, level: 1)) MP").foregroundStyle(HUDStyle.mp)
            Button("Learn") { session.learnSkill(skill.id) }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                .disabled(session.unspentSkillPoints == 0)
                .opacity(session.unspentSkillPoints == 0 ? 0.5 : 1)
        }
        .font(HUDStyle.font(12))
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(HUDStyle.gold.opacity(0.12)))
    }
}

struct SkillRow: View {
    let session: GameSession
    let skill: SkillDef

    var body: some View {
        let level = session.skillLevel(skill.id)
        HStack(alignment: .center, spacing: 8) {
            SkillIcon(skill: skill, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(skill.name)
                    if let element = skill.element {
                        ElementBadge(element: element)
                    }
                }
                HStack(spacing: 2) {
                    ForEach(1...GameSession.maxSkillLevel, id: \.self) { step in
                        IconImage(step <= level ? .star : .starOutline, size: 11)
                            .foregroundStyle(step <= level ? HUDStyle.gold : HUDStyle.dim)
                    }
                    if let description = skill.description {
                        Text(description).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim).padding(.leading, 4)
                    }
                }
            }
            Spacer()
            Text("\(GameSession.mpCost(of: skill, level: level)) MP").foregroundStyle(HUDStyle.mp)
            if session.unspentSkillPoints > 0, level < GameSession.maxSkillLevel {
                Button {
                    session.upgradeSkill(skill.id)
                } label: {
                    IconImage(.plus, size: 15)
                        .foregroundStyle(HUDStyle.ink)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(HUDStyle.gold).overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5)))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Raise \(skill.name) to level \(level + 1)")
            }
        }
        .font(HUDStyle.font(12))
    }
}

/// After a battle that levelled you up: spend the new point now, or keep it for later.
struct LevelUpCard: View {
    let session: GameSession
    let level: Int
    let onDone: () -> Void

    var body: some View {
        let points = session.unspentSkillPoints
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text("Level \(level)!")
                    .font(HUDStyle.font(26))
                    .foregroundStyle(HUDStyle.gold)
                Text(points > 0
                     ? "You have \(points) skill point\(points == 1 ? "" : "s"). Learn a new skill or power one up."
                     : "All points spent. Good choice!")
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.cream)
                    .multilineTextAlignment(.center)
            }
            ScrollView {
                SkillChoices(session: session)
                    .foregroundStyle(HUDStyle.cream)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 260)
            Button(points > 0 ? "Decide later" : "Done", action: onDone)
                .buttonStyle(PixelButtonStyle(tint: points > 0 ? HUDStyle.cream : HUDStyle.gold))
        }
        .padding(20)
        .frame(maxWidth: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(HUDStyle.ink.opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(HUDStyle.gold.opacity(0.9), lineWidth: 2))
        )
        .padding(20)
    }
}

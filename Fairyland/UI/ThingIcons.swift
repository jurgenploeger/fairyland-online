import SwiftUI

/// A little square badge with an icon on a tinted tile, like an inventory slot.
struct IconTile: View {
    let icon: GameIcon
    let tint: Color
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26)
            .fill(tint)
            .overlay(RoundedRectangle(cornerRadius: size * 0.26)
                .fill(LinearGradient(colors: [.white.opacity(0.35), .clear, .black.opacity(0.22)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: size * 0.26).strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
            .overlay(alignment: .top) {
                // Glossy top, like Fairyland's inventory icons.
                Capsule().fill(.white.opacity(0.28)).frame(height: size * 0.22).padding(.horizontal, size * 0.14).padding(.top, size * 0.08)
            }
            .overlay {
                IconImage(icon, size: size * 0.6)
                    .foregroundStyle(.white)
                    .shadow(color: HUDStyle.ink.opacity(0.7), radius: 0, x: 0, y: 1)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct ItemIcon: View {
    let item: ItemDef
    var size: CGFloat = 32

    var body: some View {
        IconTile(icon: item.icon.flatMap(GameIcon.init) ?? .gift, tint: tint, size: size)
    }

    private var tint: Color {
        switch item.type {
        case .consumable: item.mp != nil ? Color(red: 0.3, green: 0.55, blue: 0.95) : item.hatches != nil ? Color(red: 0.95, green: 0.7, blue: 0.3) : Color(red: 0.92, green: 0.35, blue: 0.45)
        case .weapon: Color(red: 0.5, green: 0.56, blue: 0.68)
        case .armor: Color(red: 0.62, green: 0.45, blue: 0.3)
        case .accessory: Color(red: 0.62, green: 0.4, blue: 0.85)
        }
    }
}

struct SkillIcon: View {
    let skill: SkillDef
    var size: CGFloat = 32

    var body: some View {
        IconTile(icon: skill.icon.flatMap(GameIcon.init) ?? .sparkles, tint: tint, size: size)
    }

    private var tint: Color {
        if let element = skill.element { return Color(uiColor: element.color) }
        return switch skill.kind {
        case .heal: Color(red: 0.3, green: 0.72, blue: 0.45)
        case .magic: Color(red: 0.55, green: 0.42, blue: 0.9)
        case .physical: Color(red: 0.85, green: 0.42, blue: 0.32)
        }
    }
}

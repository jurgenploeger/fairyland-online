import SwiftUI

/// A little square badge with an icon on a tinted tile, like an inventory slot.
struct IconTile: View {
    let icon: GameIcon
    let tint: Color
    var size: CGFloat = 32
    /// Pixel art shown instead of the icon when there is some.
    var picture: UIImage? = nil

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
                if let picture {
                    Image(uiImage: picture)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.84, height: size * 0.84)
                } else {
                    IconImage(icon, size: size * 0.6)
                        .foregroundStyle(.white)
                        .shadow(color: HUDStyle.ink.opacity(0.7), radius: 0, x: 0, y: 1)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct ItemIcon: View {
    let item: ItemDef
    var size: CGFloat = 32

    var body: some View {
        IconTile(icon: item.icon.flatMap(GameIcon.init) ?? .gift, tint: tint, size: size,
                 picture: item.art.flatMap(ArtLibrary.shared.artImage))
    }

    private var tint: Color {
        switch item.type {
        case .consumable: item.mp != nil ? Color(red: 0.3, green: 0.55, blue: 0.95) : item.hatches != nil ? Color(red: 0.95, green: 0.7, blue: 0.3) : Color(red: 0.92, green: 0.35, blue: 0.45)
        case .weapon: Color(red: 0.5, green: 0.56, blue: 0.68)
        case .armor: Color(red: 0.62, green: 0.45, blue: 0.3)
        case .accessory: Color(red: 0.62, green: 0.4, blue: 0.85)
        case .material: Color(red: 0.55, green: 0.6, blue: 0.4)
        }
    }
}

struct SkillIcon: View {
    let skill: SkillDef
    var size: CGFloat = 32

    var body: some View {
        IconTile(icon: skill.icon.flatMap(GameIcon.init) ?? .sparkles, tint: tint, size: size,
                 picture: skill.art.flatMap(ArtLibrary.shared.artImage))
    }

    private var tint: Color { Color(uiColor: skill.tileColor) }
}

extension SkillDef {
    /// The colour behind a skill's icon: its element's, else its kind's.
    var tileColor: UIColor {
        if let element { return element.color }
        return switch kind {
        case .heal, .revive: UIColor(red: 0.3, green: 0.72, blue: 0.45, alpha: 1)
        case .buff: UIColor(red: 0.3, green: 0.55, blue: 0.85, alpha: 1)
        case .curse: UIColor(red: 0.45, green: 0.28, blue: 0.62, alpha: 1)
        case .field: UIColor(red: 0.85, green: 0.65, blue: 0.25, alpha: 1)
        case .magic: UIColor(red: 0.55, green: 0.42, blue: 0.9, alpha: 1)
        case .physical: UIColor(red: 0.85, green: 0.42, blue: 0.32, alpha: 1)
        }
    }
}

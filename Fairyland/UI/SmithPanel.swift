import SwiftUI

/// A town blacksmith: pick a weapon line, see what each recipe needs, and forge it.
struct SmithPanel: View {
    let session: GameSession
    @Binding var reply: String?
    @State private var line: String?

    private struct WeaponLine: Identifiable {
        /// Weapons are drawn in the hero's hand by their icon, so it also names the line.
        let icon: String
        let name: String
        var id: String { icon }
    }

    private static let lines = [
        WeaponLine(icon: "sword", name: "Swords"), WeaponLine(icon: "axe", name: "Axes"),
        WeaponLine(icon: "wand", name: "Staffs"), WeaponLine(icon: "paw", name: "Whips"),
    ]

    /// Starts on the line the hero's class fights with.
    private var defaultLine: String {
        switch session.data.hero.classID {
        case "mage": "wand"
        case "tamer": "paw"
        default: "sword"
        }
    }

    var body: some View {
        let chosen = line ?? defaultLine
        let level = session.data.hero.level
        // Around the hero's level: a little behind (to catch up) and a little ahead (to aim for).
        let shown = session.recipes.filter { $0.icon == chosen && ($0.level ?? 1) >= level - 15 && ($0.level ?? 1) <= level + 10 }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Self.lines) { option in
                    Button(option.name) { line = option.icon }
                        .buttonStyle(PixelButtonStyle(tint: option.icon == chosen ? HUDStyle.gold : HUDStyle.dim, compact: true))
                }
            }
            if shown.isEmpty {
                EmptyNote("Nothing to forge in this line at your level.")
            }
            ForEach(shown) { item in
                SmithRecipeRow(session: session, item: item, reply: $reply)
            }
        }
    }
}

private struct SmithRecipeRow: View {
    let session: GameSession
    let item: ItemDef
    @Binding var reply: String?

    var body: some View {
        let ready = session.canCraft(item)
        HStack(alignment: .top, spacing: 10) {
            ItemIcon(item: item, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.name)  ·  Lv \(item.level ?? 1)")
                Text(item.stats?.bonusSummary ?? "").font(HUDStyle.font(10)).foregroundStyle(HUDStyle.green)
                HStack(spacing: 8) {
                    ForEach(session.ingredients(of: item)) { part in
                        HStack(spacing: 3) {
                            ItemIcon(item: part.material, size: 16)
                            Text("\(part.material.name) \(part.owned)/\(part.needed)")
                                .foregroundStyle(part.owned >= part.needed ? HUDStyle.green : HUDStyle.dim)
                        }
                    }
                }
                .font(HUDStyle.font(10))
                if let issue = session.equipIssue(item) {
                    Text(issue).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                }
            }
            Spacer()
            Button("Forge") {
                if session.craft(item.id) {
                    session.post("Forged a \(item.name)!", .reward)
                    session.save()
                    reply = "Clang, clang… done! One \(item.name), fresh from the anvil."
                } else {
                    reply = "You're missing some materials. Monsters out in the wilds drop them."
                }
            }
            .buttonStyle(PixelButtonStyle(tint: ready ? HUDStyle.gold : HUDStyle.dim, compact: true))
        }
        .font(HUDStyle.font(12))
    }
}

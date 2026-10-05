import SwiftUI

/// Name, gender, hairstyle, and hair, outfit and skin colours, with a turning live preview. Used when
/// creating a hero and from the Character screen, where name and gender are fixed.
struct LookEditor: View {
    @Binding var name: String
    @Binding var look: Look
    /// Which race's walk sheet to preview.
    var raceID = "human"
    /// Looks you've unlocked through quests (new heroes start with the basics).
    var isUnlocked: (LookPreset) -> Bool = { $0.unlock == nil }
    /// After creation the hero keeps their name and gender: only their looks change.
    var identityLocked = false
    /// Worn armour: its own colours replace the outfit's, so there's nothing to dye while it's on.
    var armor: ItemDef? = nil

    private var options: AppearanceOptions { Content.shared.appearance }
    private var race: RaceDef { Content.shared.race(raceID) }

    var body: some View {
        AdaptiveStack(spacing: 16) {
            VStack(spacing: 6) {
                TurntablePreview(look: look, race: race)
                Button {
                    look = Look(
                        hair: options.hair.filter(isUnlocked).randomElement()?.id ?? look.hair,
                        outfit: options.outfits.filter(isUnlocked).randomElement()?.id ?? look.outfit,
                        skin: options.skin.filter(isUnlocked).randomElement()?.id ?? look.skin,
                        gender: look.gender,
                        style: options.styles(for: race.sheet(for: look.gender)).randomElement()?.id ?? look.style
                    )
                } label: {
                    Label(L("Surprise me"), icon: .dice)
                }
                .buttonStyle(PixelButtonStyle(compact: true))
            }
            .frame(minWidth: 170)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                if !identityLocked {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Name")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                        TextField(L("Name"), text: $name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .font(HUDStyle.font(15))
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.12)))
                            .onChange(of: name) { _, value in
                                if value.count > 12 { name = String(value.prefix(12)) }
                            }
                    }
                    GenderPicker(genders: options.genders, selection: $look.gender)
                }
                StylePicker(look: $look, race: race)
                SwatchPicker(title: L("Hair"), presets: options.hair, selection: $look.hair, isUnlocked: isUnlocked)
                if armor == nil {
                    SwatchPicker(title: L("Outfit"), presets: options.outfits, selection: $look.outfit, isUnlocked: isUnlocked)
                }
                SwatchPicker(title: L("Skin"), presets: options.skin, selection: $look.skin, isUnlocked: isUnlocked)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The hero slowly turning on the spot, so you see the look from every side.
private struct TurntablePreview: View {
    let look: Look
    let race: RaceDef
    private let order: [Direction] = [.down, .right, .up, .left]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.9)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.9) % order.count
            Image(uiImage: ArtLibrary.shared.preview(from: race.sheet(for: look.gender), recolor: GameSession.rules(for: look), key: look.key,
                                                     facing: order[step], layers: GameSession.layers(race: race, look: look)))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 164, height: 164)
                .background(Circle().fill(.white.opacity(0.08)))
                .overlay(alignment: .bottom) {
                    Ellipse().fill(.black.opacity(0.2)).frame(width: 60, height: 12).offset(y: -8)
                }
        }
        .accessibilityLabel(L("Preview of your hero"))
    }
}

/// Male, female or other: which of the race's walk sheets the hero uses.
private struct GenderPicker: View {
    let genders: [GenderOption]
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L("Gender")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            HStack(spacing: 8) {
                ForEach(genders) { gender in
                    let selected = gender.id == (selection ?? genders.first?.id)
                    Button(gender.name) { selection = gender.id }
                        .buttonStyle(PixelButtonStyle(tint: selected ? HUDStyle.gold : HUDStyle.dim, compact: true))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

/// Hairstyles, each shown on your hero as they look right now: the walk sheet's own hair first (a
/// gender's ponytail or braids), then the ones that suit any race.
private struct StylePicker: View {
    @Binding var look: Look
    let race: RaceDef

    private var styles: [HairStyle] { Content.shared.appearance.styles(for: race.sheet(for: look.gender)) }
    private var current: String { GameSession.style(for: look, race: race) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(L("Hairstyle")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                Text(styles.first { $0.id == current }?.name ?? "").font(HUDStyle.font(11)).foregroundStyle(HUDStyle.gold)
            }
            HStack(spacing: 8) {
                ForEach(styles) { style in
                    let selected = style.id == current
                    Button {
                        look.style = style.id
                    } label: {
                        Image(uiImage: portrait(style))
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(selected ? HUDStyle.gold : .white.opacity(0.4), lineWidth: selected ? 3 : 1.5))
                            .padding(2)
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(L("Hairstyle {style}", ["style": style.name]))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func portrait(_ style: HairStyle) -> UIImage {
        var styled = look
        styled.style = style.id
        return ArtLibrary.shared.preview(from: race.sheet(for: look.gender), recolor: GameSession.rules(for: styled), key: styled.key,
                                         layers: GameSession.layers(race: race, look: styled))
    }
}

struct SwatchPicker: View {
    let title: String
    let presets: [LookPreset]
    @Binding var selection: String
    var isUnlocked: (LookPreset) -> Bool = { _ in true }
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                Text(presets.first { $0.id == selection }?.name ?? "").font(HUDStyle.font(11)).foregroundStyle(HUDStyle.gold)
                if let hint {
                    Text(hint).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.orange).lineLimit(1)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets) { preset in
                        let selected = preset.id == selection
                        let open = isUnlocked(preset)
                        Button {
                            if open {
                                selection = preset.id
                                hint = nil
                            } else {
                                let quest = preset.unlock.flatMap { Content.shared.quest($0)?.title } ?? L("a quest")
                                hint = L("{look}: finish “{quest}”", ["look": preset.name, "quest": quest])
                            }
                        } label: {
                            Circle()
                                .fill(Color(uiColor: UIColor(hex: preset.swatch) ?? .white))
                                .frame(width: 30, height: 30)
                                .opacity(open ? 1 : 0.35)
                                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                                .overlay(Circle().strokeBorder(selected ? HUDStyle.gold : .clear, lineWidth: 3).padding(-4))
                                .overlay {
                                    if selected {
                                        IconImage(.check, size: 13).foregroundStyle(HUDStyle.ink)
                                    } else if !open {
                                        IconImage(.lock, size: 13).foregroundStyle(.white)
                                    }
                                }
                                .padding(4)
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel(open ? "\(title) \(preset.name)" : L("{title} {look}, locked", ["title": title, "look": preset.name]))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }
}

/// Rename a companion. (Its colours come from its species: rarer variants look different.)
struct CompanionEditor: View {
    let session: GameSession
    let pet: Pet
    let onDone: () -> Void
    @State private var name: String

    init(session: GameSession, pet: Pet, onDone: @escaping () -> Void) {
        self.session = session
        self.pet = pet
        self.onDone = onDone
        _name = State(initialValue: pet.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SpriteImage(art: session.artID(for: pet), size: 80)
                    .background(Circle().fill(.white.opacity(0.08)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Name")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                    TextField(L("Name"), text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(HUDStyle.font(14))
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.12)))
                        .submitLabel(.done)
                        .onSubmit(save)
                }
            }
            HStack {
                Button(L("Cancel"), action: onDone)
                    .buttonStyle(PixelButtonStyle(compact: true))
                Spacer()
                Button(action: save) {
                    Label(L("Save"), icon: .check)
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
    }

    private func save() {
        session.renamePet(pet.id, to: name)
        onDone()
    }
}

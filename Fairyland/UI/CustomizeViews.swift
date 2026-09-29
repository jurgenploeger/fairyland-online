import SwiftUI

/// Name + hair, outfit and skin colours, with a turning live preview. Used when creating a
/// hero and from the Character screen.
struct LookEditor: View {
    @Binding var name: String
    @Binding var look: Look
    /// Which race's walk sheet to preview.
    var raceID = "human"
    /// Looks you've unlocked through quests (new heroes start with the basics).
    var isUnlocked: (LookPreset) -> Bool = { $0.unlock == nil }

    private var options: AppearanceOptions { Content.shared.appearance }

    var body: some View {
        AdaptiveStack(spacing: 16) {
            VStack(spacing: 6) {
                TurntablePreview(look: look, sheet: Content.shared.race(raceID).sheet)
                Button {
                    look = Look(
                        hair: options.hair.filter(isUnlocked).randomElement()?.id ?? look.hair,
                        outfit: options.outfits.filter(isUnlocked).randomElement()?.id ?? look.outfit,
                        skin: options.skin.filter(isUnlocked).randomElement()?.id ?? look.skin
                    )
                } label: {
                    Label("Surprise me", icon: .dice)
                }
                .buttonStyle(PixelButtonStyle(compact: true))
            }
            .frame(minWidth: 170)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name").font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(HUDStyle.font(15))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.12)))
                        .onChange(of: name) { _, value in
                            if value.count > 12 { name = String(value.prefix(12)) }
                        }
                }
                SwatchPicker(title: "Hair", presets: options.hair, selection: $look.hair, isUnlocked: isUnlocked)
                SwatchPicker(title: "Outfit", presets: options.outfits, selection: $look.outfit, isUnlocked: isUnlocked)
                SwatchPicker(title: "Skin", presets: options.skin, selection: $look.skin, isUnlocked: isUnlocked)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The hero slowly turning on the spot, so you see the look from every side.
private struct TurntablePreview: View {
    let look: Look
    let sheet: String
    private let order: [Direction] = [.down, .right, .up, .left]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.9)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.9) % order.count
            Image(uiImage: ArtLibrary.shared.preview(from: sheet, recolor: GameSession.rules(for: look), key: look.key, facing: order[step]))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 164, height: 164)
                .background(Circle().fill(.white.opacity(0.08)))
                .overlay(alignment: .bottom) {
                    Ellipse().fill(.black.opacity(0.2)).frame(width: 60, height: 12).offset(y: -8)
                }
        }
        .accessibilityLabel("Preview of your hero")
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
                                let quest = preset.unlock.flatMap { Content.shared.quest($0)?.title } ?? "a quest"
                                hint = "\(preset.name): finish “\(quest)”"
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
                        .accessibilityLabel(open ? "\(title) \(preset.name)" : "\(title) \(preset.name), locked")
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
                    Text("Name").font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                    TextField("Name", text: $name)
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
                Button("Cancel", action: onDone)
                    .buttonStyle(PixelButtonStyle(compact: true))
                Spacer()
                Button(action: save) {
                    Label("Save", icon: .check)
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

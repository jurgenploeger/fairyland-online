import SwiftUI

/// Fairyland Online's look: glossy light-blue bevelled frames, deep-blue glass windows,
/// tan info plates, yellow outlined names and orange close buttons.
enum HUDStyle {
    static let cream = Color(red: 1, green: 0.97, blue: 0.88)
    static let gold = Color(red: 1, green: 0.84, blue: 0.28)
    static let nameYellow = Color(red: 1, green: 0.95, blue: 0.35)
    static let hp = Color(red: 0.93, green: 0.22, blue: 0.2)
    static let mp = Color(red: 0.24, green: 0.52, blue: 0.95)
    static let exp = Color(red: 0.55, green: 0.88, blue: 0.3)
    static let pet = Color(red: 0.98, green: 0.72, blue: 0.2)
    static let green = Color(red: 0.6, green: 0.97, blue: 0.62)
    static let dim = Color(red: 0.86, green: 0.92, blue: 1).opacity(0.7)
    /// Deep navy: window glass and dark text on light buttons.
    static let ink = Color(red: 0.06, green: 0.15, blue: 0.3)
    static let orange = Color(red: 0.98, green: 0.52, blue: 0.16)

    static let frameLight = Color(red: 0.86, green: 0.96, blue: 1)
    static let frameMid = Color(red: 0.5, green: 0.77, blue: 0.95)
    static let frameDark = Color(red: 0.15, green: 0.35, blue: 0.62)
    static let plate = Color(red: 0.97, green: 0.88, blue: 0.64)
    static let plateDark = Color(red: 0.55, green: 0.41, blue: 0.18)

    static func font(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Fairyland's chat/name lettering.
    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    static let bevel = LinearGradient(colors: [frameLight, frameMid, frameDark], startPoint: .top, endPoint: .bottom)

    /// A deep-blue glass window with a glossy light-blue bevel.
    static var panel: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(LinearGradient(
                colors: [Color(red: 0.13, green: 0.32, blue: 0.56).opacity(0.93), Color(red: 0.05, green: 0.17, blue: 0.35).opacity(0.95)],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(bevel, lineWidth: 3))
            .overlay(RoundedRectangle(cornerRadius: 7).inset(by: 3).strokeBorder(.white.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
    }

    /// Tan info plate (like Fairyland's calendar and coordinates boxes).
    static var plateBackground: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.78), plate, Color(red: 0.86, green: 0.72, blue: 0.44)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(plateDark, lineWidth: 1.5))
    }
}

/// Glossy Fairyland-style bar: coloured fill with a white shine, dark inset track.
struct StatBar: View {
    let label: String
    let value: Int
    let maximum: Int
    let color: Color
    var labelWidth: CGFloat = 28
    var height: CGFloat = 11
    var showsNumbers = true

    private var fraction: CGFloat {
        maximum > 0 ? min(1, max(0, CGFloat(value) / CGFloat(maximum))) : 0
    }

    var body: some View {
        HStack(spacing: 6) {
            if !label.isEmpty {
                Text(label)
                    .frame(width: labelWidth, alignment: .leading)
            }
            GlossyBar(fraction: fraction, color: color, height: height)
                .overlay {
                    if showsNumbers {
                        Text("\(value)/\(maximum)")
                            .font(HUDStyle.mono(8))
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 0, x: 1, y: 1)
                    }
                }
        }
        .font(HUDStyle.font(10))
        .foregroundStyle(HUDStyle.cream)
        .animation(.easeOut(duration: 0.25), value: value)
    }
}

struct GlossyBar: View {
    let fraction: CGFloat
    let color: Color
    var height: CGFloat = 11

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 0.05, green: 0.1, blue: 0.2).opacity(0.85))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.75), color, color.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    .frame(width: max(height, proxy.size.width * fraction))
                    .opacity(fraction > 0 ? 1 : 0)
                    .overlay(alignment: .top) {
                        Capsule().fill(.white.opacity(0.45)).frame(height: height * 0.35).padding(.horizontal, 3).padding(.top, 1)
                    }
            }
        }
        .frame(height: height)
        .overlay(Capsule().strokeBorder(HUDStyle.frameDark.opacity(0.9), lineWidth: 1))
    }
}

/// A window title bar with an orange close button, like Fairyland's panels.
struct FLTitleBar: View {
    let title: String
    var icon: GameIcon?
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let icon { IconImage(icon, size: 16) }
            Text(title).lineLimit(1)
            Spacer(minLength: 4)
            OrangeCloseButton(action: onClose)
        }
        .font(HUDStyle.font(14))
        .foregroundStyle(.white)
        .shadow(color: HUDStyle.frameDark, radius: 0, x: 1, y: 1)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 8)
                .fill(LinearGradient(colors: [HUDStyle.frameLight, HUDStyle.frameMid, HUDStyle.frameDark], startPoint: .top, endPoint: .bottom))
        )
    }
}

struct OrangeCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconImage(.close, size: 13)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 1, green: 0.75, blue: 0.4), HUDStyle.orange, Color(red: 0.75, green: 0.3, blue: 0.05)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 16))
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                )
        }
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
        .accessibilityLabel("Close")
    }
}

/// Glossy square toolbar button (Fairyland's top-right / hotbar icons).
struct FLIconButton: View {
    let icon: GameIcon
    let label: String
    var size: CGFloat = 46
    var badge: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            SoundEffects.shared.play(.tap, volume: 0.7)
            action()
        } label: {
            IconImage(icon, size: size * 0.5)
                .foregroundStyle(.white)
                .shadow(color: HUDStyle.frameDark, radius: 0, x: 1, y: 1)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient(colors: [Color(red: 0.6, green: 0.85, blue: 1), Color(red: 0.25, green: 0.55, blue: 0.9), Color(red: 0.12, green: 0.33, blue: 0.66)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(HUDStyle.bevel, lineWidth: 2.5))
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.35)).frame(height: size * 0.3).padding(4)
                        }
                )
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(HUDStyle.gold).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
                            .offset(x: 3, y: -3)
                    }
                }
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 2)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Pixel art from ArtLibrary, scaled up with crisp square pixels.
struct SpriteImage: View {
    let art: String
    var size: CGFloat = 64

    var body: some View {
        Image(uiImage: ArtLibrary.shared.image(art))
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// Glossy pill button (light, with dark text).
extension HUDStyle {
    /// Name colour for friends travelling in your party.
    static let partyGreen = UIColor(red: 0.55, green: 1, blue: 0.55, alpha: 1)
}

struct PixelButtonStyle: ButtonStyle {
    var tint: Color = HUDStyle.cream
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HUDStyle.font(compact ? 11 : 13))
            .foregroundStyle(HUDStyle.ink)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 6 : 9)
            .background(
                Capsule()
                    .fill(LinearGradient(colors: [.white, tint, tint.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(HUDStyle.frameDark.opacity(0.7), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: configuration.isPressed ? 0 : 3)
            )
            .offset(y: configuration.isPressed ? 2 : 0)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { SoundEffects.shared.play(.tap, volume: 0.7) }
            }
    }
}

/// HStack in landscape, VStack in portrait.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        if verticalSizeClass == .compact {
            HStack(alignment: .top, spacing: spacing, content: content)
        } else {
            VStack(alignment: .leading, spacing: spacing, content: content)
        }
    }
}

extension Stats {
    /// "ATK +4 · DEF +2" for item descriptions.
    var bonusSummary: String {
        [("HP", hp), ("MP", mp), ("ATK", attack), ("DEF", defense), ("MAG", magic), ("SPD", speed)]
            .filter { $0.1 != 0 }
            .map { "\($0.0) +\($0.1)" }
            .joined(separator: " · ")
    }
}

/// A friendly "nothing here yet" line, centred in the space it's given. Use "\n" to pick
/// where it breaks so it wraps into even lines.
struct EmptyNote: View {
    let text: String
    var size: CGFloat = 12

    init(_ text: String, size: CGFloat = 12) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(HUDStyle.font(size))
            .foregroundStyle(HUDStyle.dim)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
    }
}

import SwiftUI

/// Storyleaf's own colours, the logo's and the app icon's exactly (the Figma brand guidelines list
/// them, page 03 Colour). The title and loading screens wear them; the game's windows keep
/// Fairyland's look (`HUDStyle`).
enum Brand {
    /// The wordmark's letters, top to bottom.
    static let leafLight = Color(red: 0.929, green: 1, blue: 0.659)    // #EDFFA8
    static let leaf = Color(red: 0.549, green: 0.898, blue: 0.42)      // #8CE56B
    static let leafDeep = Color(red: 0.161, green: 0.659, blue: 0.451) // #29A873
    /// Every outline: the letters', the leaf's and the tagline pill's.
    static let forest = Color(red: 0.09, green: 0.302, blue: 0.231)    // #174D3B
    /// The thicker edge under the letters and the pill.
    static let depth = Color(red: 0.039, green: 0.188, blue: 0.141)    // #0A3024
    /// The sticker border round the letters, and the book's pages.
    static let cream = Color(red: 1, green: 0.969, blue: 0.878)        // #FFF7E0

    /// The icon's sky, top to bottom.
    static let lavender = Color(red: 0.8, green: 0.722, blue: 1)       // #CCB8FF
    static let sky = Color(red: 0.659, green: 0.859, blue: 1)          // #A8DBFF
    static let mint = Color(red: 0.722, green: 0.961, blue: 0.839)     // #B8F5D6
}

/// The sky the app icon's leaf floats in, behind the title and loading screens: lavender at the
/// top through sky blue to mint, soft sun rays fanning out from behind the logo, and clouds
/// along the bottom.
struct StoryleafSky: View {
    /// Where the rays fan out from, as a share of the screen: behind the logo.
    var raysFrom = UnitPoint(x: 0.5, y: 0.3)

    /// The clouds along the bottom, a bank in each corner like the icon's: where across the
    /// screen, and how big, as shares of its shorter side.
    private static let puffs: [(x: CGFloat, size: CGFloat)] = [
        (0.02, 0.56), (0.2, 0.4), (0.36, 0.24),
        (0.98, 0.6), (0.8, 0.42), (0.64, 0.26),
    ]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                LinearGradient(colors: [Brand.lavender, Brand.sky, Brand.mint], startPoint: .top, endPoint: .bottom)

                SunRays(center: raysFrom)
                    .fill(RadialGradient(colors: [.white.opacity(0.3), .white.opacity(0)], center: raysFrom,
                                         startRadius: 0, endRadius: max(proxy.size.width, proxy.size.height) * 0.7))

                ForEach(Self.puffs.indices, id: \.self) { index in
                    let puff = Self.puffs[index]
                    Circle()
                        .fill(.white.opacity(0.88))
                        .frame(width: side * puff.size, height: side * puff.size)
                        .position(x: proxy.size.width * puff.x, y: proxy.size.height + side * puff.size * 0.12)
                }
                .blur(radius: 1.5)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Rays fanning out from `center` (a share of the rect) past its corners: every other wedge of
/// `count`, like the sun behind the icon's leaf.
nonisolated struct SunRays: Shape {
    var center: UnitPoint
    var count = 16

    func path(in rect: CGRect) -> Path {
        let origin = CGPoint(x: rect.minX + rect.width * center.x, y: rect.minY + rect.height * center.y)
        let reach = hypot(rect.width, rect.height)
        let step = 2 * Double.pi / Double(count)
        var path = Path()
        for index in 0..<count {
            let start = Double(index) * step
            let end = start + step / 2
            path.move(to: origin)
            path.addLine(to: CGPoint(x: origin.x + cos(start) * reach, y: origin.y + sin(start) * reach))
            path.addLine(to: CGPoint(x: origin.x + cos(end) * reach, y: origin.y + sin(end) * reach))
            path.closeSubpath()
        }
        return path
    }
}

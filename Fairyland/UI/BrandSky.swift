import SwiftUI

/// Storyleaf's own colours, from the logo and the app icon (and the App Store slides, which
/// tools/store_slides.py letters in the same ones). The title and loading screens wear them; the
/// game's windows keep Fairyland's look (`HUDStyle`).
enum Brand {
    /// The wordmark's letters, light at the top to the leaf green at the bottom.
    static let leafLight = Color(red: 0.867, green: 0.973, blue: 0.745)  // #DDF8BE
    static let leaf = Color(red: 0.263, green: 0.639, blue: 0.365)       // #43A35D
    /// Every outline: the letters', the leaf's and the tagline pill's.
    static let forest = Color(red: 0.09, green: 0.298, blue: 0.231)      // #174C3B
    /// The thicker edge under the letters.
    static let depth = Color(red: 0.035, green: 0.173, blue: 0.133)      // #092C22
    /// The tagline pill, the leaf's pages and the sparkles.
    static let cream = Color(red: 0.996, green: 0.929, blue: 0.812)      // #FEEDCF

    /// The icon's sky, top to bottom.
    static let lavender = Color(red: 0.812, green: 0.741, blue: 0.996)   // #CFBDFE
    static let periwinkle = Color(red: 0.741, green: 0.784, blue: 0.996) // #BDC8FE
    static let sky = Color(red: 0.659, green: 0.855, blue: 0.992)        // #A8DAFD
    static let aqua = Color(red: 0.682, green: 0.894, blue: 0.933)       // #AEE4EE
    static let mint = Color(red: 0.737, green: 0.945, blue: 0.875)       // #BCF1DF
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
                LinearGradient(stops: [
                    .init(color: Brand.lavender, location: 0),
                    .init(color: Brand.periwinkle, location: 0.28),
                    .init(color: Brand.sky, location: 0.55),
                    .init(color: Brand.aqua, location: 0.78),
                    .init(color: Brand.mint, location: 1),
                ], startPoint: .top, endPoint: .bottom)

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

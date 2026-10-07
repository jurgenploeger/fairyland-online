import SwiftUI

/// Shown while a map is being built: the logo over the title's sky, and a leaf-green bar filling up.
struct LoadingCurtain: View {
    /// 0...1: how far the map build has got.
    var progress: Double = 0
    @State private var spin = false

    var body: some View {
        ZStack {
            StoryleafSky(raysFrom: UnitPoint(x: 0.5, y: 0.44))
            // The bar keeps a little apart from the logo, and narrower than it.
            VStack(spacing: 30) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300)
                    .scaleEffect(spin ? 1.03 : 0.97)
                // In the logo's colours: its leaf green, outlined like its letters, on its cream.
                LoadingBar(progress: progress, label: L("Loading"), textColor: Brand.forest,
                           fill: [Brand.leafLight, Brand.leaf, Brand.leafDeep], track: Brand.cream, rim: Brand.forest,
                           width: 200)
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { spin = true }
        }
    }
}

/// Shown briefly when travelling to another map: the destination's name over a spinning swirl,
/// and the loading bar.
struct MapLoadingCard: View {
    let mapName: String
    var progress: Double = 0
    @State private var spin = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.15, blue: 0.32), Color(red: 0.13, green: 0.3, blue: 0.55)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                SwirlShape()
                    .stroke(Color(red: 0.75, green: 0.35, blue: 0.95), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .shadow(color: Color(red: 0.75, green: 0.35, blue: 0.95).opacity(0.7), radius: 10)
                Text(mapName)
                    .font(HUDStyle.font(26))
                    .foregroundStyle(HUDStyle.nameYellow)
                    .shadow(color: .black, radius: 0, x: 2, y: 2)
                LoadingBar(progress: progress, label: L("Travelling"), textColor: HUDStyle.cream)
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

/// A bar that fills as loading goes (blue, unless told otherwise), with the percentage beside the label.
struct LoadingBar: View {
    let progress: Double
    let label: String
    let textColor: Color
    /// The fill, top to bottom, the empty part, and the rim round it.
    var fill: [Color] = [Color(red: 0.45, green: 0.78, blue: 1), Color(red: 0.13, green: 0.47, blue: 0.95)]
    var track: Color = HUDStyle.ink.opacity(0.35)
    var rim: Color = .white.opacity(0.8)
    /// How wide the bar grows at most.
    var width: CGFloat = 280

    private var percent: Int { Int((min(max(progress, 0), 1) * 100).rounded()) }

    var body: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(track)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(LinearGradient(colors: fill, startPoint: .top, endPoint: .bottom))
                            .overlay(alignment: .top) {
                                Capsule().fill(.white.opacity(0.35)).frame(height: 4).padding(.horizontal, 6).padding(.top, 2)
                            }
                            .frame(width: max(14, proxy.size.width * min(max(progress, 0), 1)))
                    }
                }
                .overlay(Capsule().strokeBorder(rim, lineWidth: 2))
                .frame(maxWidth: width)
                .frame(height: 16)
                // No animation: the map build holds the screen between steps, so an animated bar
                // would lag behind its own number.
            Text("\(label)… \(percent)%")
                .font(HUDStyle.font(14))
                .monospacedDigit()
                .foregroundStyle(textColor.opacity(0.85))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(L("{percent} percent", ["percent": percent]))
    }
}

/// An Archimedean spiral, like Fairyland's swirl.
nonisolated struct SwirlShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let turns = 2.6
        let steps = 90
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let angle = t * turns * 2 * .pi
            let radius = t * min(rect.width, rect.height) / 2
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}

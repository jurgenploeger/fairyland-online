import SwiftUI

/// Shown while a map is being built: the logo over the title's sky, and a blue bar filling up.
struct LoadingCurtain: View {
    /// 0...1: how far the map build has got.
    var progress: Double = 0
    @State private var spin = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 1, green: 0.84, blue: 0.42), Color(red: 1, green: 0.66, blue: 0.78), Color(red: 0.5, green: 0.81, blue: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 14) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300)
                    .scaleEffect(spin ? 1.03 : 0.97)
                LoadingBar(progress: progress, label: "Loading", textColor: HUDStyle.ink)
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
                LoadingBar(progress: progress, label: "Travelling", textColor: HUDStyle.cream)
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

/// A blue bar that fills as loading goes, with the percentage beside the label.
struct LoadingBar: View {
    let progress: Double
    let label: String
    let textColor: Color

    private var percent: Int { Int((min(max(progress, 0), 1) * 100).rounded()) }

    var body: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(HUDStyle.ink.opacity(0.35))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.78, blue: 1), Color(red: 0.13, green: 0.47, blue: 0.95)],
                                                 startPoint: .top, endPoint: .bottom))
                            .overlay(alignment: .top) {
                                Capsule().fill(.white.opacity(0.35)).frame(height: 4).padding(.horizontal, 6).padding(.top, 2)
                            }
                            .frame(width: max(14, proxy.size.width * min(max(progress, 0), 1)))
                    }
                }
                .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 2))
                .frame(maxWidth: 280)
                .frame(height: 16)
                .animation(.easeOut(duration: 0.25), value: progress)
            Text("\(label)… \(percent)%")
                .font(HUDStyle.font(14))
                .monospacedDigit()
                .foregroundStyle(textColor.opacity(0.85))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(percent) percent")
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

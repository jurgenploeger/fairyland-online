import SwiftUI

/// Shown while a map is being built: the star emblem spinning over the title's sky.
struct LoadingCurtain: View {
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
                ProgressView()
                    .tint(HUDStyle.ink)
                Text("Loading…")
                    .font(HUDStyle.font(15))
                    .foregroundStyle(HUDStyle.ink.opacity(0.8))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { spin = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading")
    }
}

/// Shown briefly when travelling to another map: the destination's name over a spinning swirl.
struct MapLoadingCard: View {
    let mapName: String
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
                Text("Travelling…")
                    .font(HUDStyle.mono(12))
                    .foregroundStyle(HUDStyle.dim)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Travelling to \(mapName)")
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

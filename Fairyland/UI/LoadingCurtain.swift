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

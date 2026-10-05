import SwiftUI

/// Tapping the minimap: the world map, with where you are. The whole map of the area you're in
/// stays hidden, so caves and forests are still yours to explore; the minimap shows what's near.
struct MapOverlay: View {
    let session: GameSession
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 10) {
                FLTitleBar(title: L("World map"), icon: .map, onClose: onClose)
                WorldAtlas(session: session)
            }
            .padding(16)
            .frame(maxWidth: 720, maxHeight: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(HUDStyle.ink.opacity(0.94))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(HUDStyle.cream.opacity(0.8), lineWidth: 2))
            )
            .padding(14)
        }
    }
}

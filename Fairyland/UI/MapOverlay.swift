import SwiftUI

/// The whole current map at a glance: where you are, your companion, and where the roads lead.
struct MapOverlay: View {
    let overview: (image: UIImage, player: CGPoint, companion: CGPoint?, name: String, exits: [MapDef.Exit])
    let onClose: () -> Void
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 10) {
                FLTitleBar(title: overview.name, icon: "map.fill", onClose: onClose)

                Image(uiImage: overview.image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay {
                        GeometryReader { proxy in
                            ZStack {
                                ForEach(overview.exits, id: \.to) { exit in
                                    ExitTag(exit: exit)
                                        .position(position(of: exit.edge, in: proxy.size))
                                }
                                if let companion = overview.companion {
                                    Circle()
                                        .fill(HUDStyle.green)
                                        .frame(width: 8, height: 8)
                                        .position(x: companion.x * proxy.size.width, y: companion.y * proxy.size.height)
                                }
                                ZStack {
                                    Circle().fill(HUDStyle.gold.opacity(0.35)).frame(width: pulse ? 30 : 14, height: pulse ? 30 : 14)
                                    Circle().fill(HUDStyle.gold).frame(width: 12, height: 12)
                                        .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 2))
                                }
                                .position(x: overview.player.x * proxy.size.width, y: overview.player.y * proxy.size.height)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HUDStyle.cream.opacity(0.6), lineWidth: 2))

                HStack(spacing: 14) {
                    Label("You", systemImage: "circle.fill").foregroundStyle(HUDStyle.gold)
                    Label("Companion", systemImage: "circle.fill").foregroundStyle(HUDStyle.green)
                    Label("Water", systemImage: "circle.fill").foregroundStyle(Color(red: 0.31, green: 0.64, blue: 0.88))
                }
                .font(HUDStyle.font(11))
                .labelStyle(CompactLabelStyle())
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
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private func position(of edge: Edge, in size: CGSize) -> CGPoint {
        switch edge {
        case .north: CGPoint(x: size.width / 2, y: 14)
        case .south: CGPoint(x: size.width / 2, y: size.height - 14)
        case .east: CGPoint(x: size.width - 60, y: size.height / 2)
        case .west: CGPoint(x: 60, y: size.height / 2)
        }
    }
}

private struct ExitTag: View {
    let exit: MapDef.Exit

    var body: some View {
        let name = Content.shared.map(exit.to)?.name ?? exit.to
        let arrow = switch exit.edge {
        case .north: "arrow.up"
        case .south: "arrow.down"
        case .east: "arrow.right"
        case .west: "arrow.left"
        }
        Label(name, systemImage: arrow)
            .font(HUDStyle.font(10))
            .foregroundStyle(HUDStyle.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(HUDStyle.gold))
            .fixedSize()
    }
}

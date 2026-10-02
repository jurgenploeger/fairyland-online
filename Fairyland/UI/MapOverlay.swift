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
                FLTitleBar(title: overview.name, icon: .map, onClose: onClose)

                // Turned and squashed like the world and the minimap, so north (up-left), east
                // (up-right) and the roads point the same way here as on screen while walking.
                GeometryReader { proxy in
                    let layout = DiamondLayout(size: proxy.size, tiles: overview.image.size)
                    ZStack {
                        Image(uiImage: overview.image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: layout.imageSize.width, height: layout.imageSize.height)
                            .rotationEffect(.degrees(-45))
                            .scaleEffect(x: 1, y: 0.5)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        ForEach(overview.exits, id: \.to) { exit in
                            ExitTag(exit: exit)
                                .position(layout.point(Self.unit(of: exit.edge)))
                        }
                        if let companion = overview.companion {
                            Circle()
                                .fill(HUDStyle.green)
                                .frame(width: 8, height: 8)
                                .position(layout.point(companion))
                        }
                        ZStack {
                            Circle().fill(HUDStyle.gold.opacity(0.35)).frame(width: pulse ? 30 : 14, height: pulse ? 30 : 14)
                            Circle().fill(HUDStyle.gold).frame(width: 12, height: 12)
                                .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 2))
                        }
                        .position(layout.point(overview.player))
                    }
                }
                .aspectRatio(2, contentMode: .fit)
                .background(Color(red: 0.05, green: 0.12, blue: 0.22))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HUDStyle.cream.opacity(0.6), lineWidth: 2))

                HStack(spacing: 14) {
                    Label { Text("You") } icon: { Circle().frame(width: 9, height: 9) }.foregroundStyle(HUDStyle.gold)
                    Label { Text("Companion") } icon: { Circle().frame(width: 9, height: 9) }.foregroundStyle(HUDStyle.green)
                    Label { Text("Water") } icon: { Circle().frame(width: 9, height: 9) }.foregroundStyle(Color(red: 0.31, green: 0.64, blue: 0.88))
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

    /// Where a road leaves the map, on the top-down overview (0...1, top-left origin).
    private static func unit(of edge: Edge) -> CGPoint {
        switch edge {
        case .north: CGPoint(x: 0.5, y: 0.06)
        case .south: CGPoint(x: 0.5, y: 0.94)
        case .east: CGPoint(x: 0.94, y: 0.5)
        case .west: CGPoint(x: 0.06, y: 0.5)
        }
    }
}

/// Fits the top-down overview, turned 45° and squashed to half height like the world, into
/// `size`, and says where a spot on the overview ends up.
private struct DiamondLayout {
    let size: CGSize
    let imageSize: CGSize

    init(size: CGSize, tiles: CGSize) {
        self.size = size
        // Turned, a w×h map spans (w + h)/√2 across and half that down; leave a little margin.
        let span = max(tiles.width + tiles.height, 1)
        let scale = min(size.width, size.height * 2) * CGFloat(2).squareRoot() / span * 0.94
        imageSize = CGSize(width: tiles.width * scale, height: tiles.height * scale)
    }

    /// `unit` is 0...1 on the overview image (top-left origin, north up).
    func point(_ unit: CGPoint) -> CGPoint {
        let x = (unit.x - 0.5) * imageSize.width
        let y = (unit.y - 0.5) * imageSize.height
        let c = CGFloat(0.5).squareRoot()
        // Same turn as `.rotationEffect(.degrees(-45))`, then the half-height squash.
        return CGPoint(x: size.width / 2 + (x + y) * c, y: size.height / 2 + (y - x) * c * 0.5)
    }
}

private struct ExitTag: View {
    let exit: MapDef.Exit

    var body: some View {
        let name = Content.shared.map(exit.to)?.name ?? exit.to
        let arrow: GameIcon = switch exit.edge {
        case .north: .arrowUp
        case .south: .arrowDown
        case .east: .arrowRight
        case .west: .arrowLeft
        }
        // Turned like the map: north points up-left, east up-right.
        Label {
            Text(name)
        } icon: {
            IconImage(arrow, size: 11).rotationEffect(.degrees(-45))
        }
            .font(HUDStyle.font(10))
            .foregroundStyle(HUDStyle.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(HUDStyle.gold))
            .fixedSize()
    }
}

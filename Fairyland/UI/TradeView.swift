import SwiftUI

/// Trading with an adventurer you're standing next to: what they'd buy from you (better than a
/// shop pays) and what they carry (things shops in this town might not stock). Offers change each
/// in-game day; each deal is made once.
struct TradeView: View {
    let session: GameSession
    let adventurer: Adventurer
    let onClose: () -> Void
    @State private var reply: String?

    var body: some View {
        let offers = session.tradeOffers(with: adventurer)
        let buying = offers.filter { $0.kind == .theyBuy }
        let selling = offers.filter { $0.kind == .theySell }
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                FLTitleBar(title: "Trade with \(adventurer.name)", icon: .coins, onClose: onClose)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            SpriteImage(art: session.artID(for: adventurer), size: 40)
                            Text(reply ?? "Got anything good? I've got a few things too.")
                                .font(HUDStyle.font(12))
                                .foregroundStyle(HUDStyle.cream)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Label("\(session.data.gold) gold", icon: .coins)
                            .font(HUDStyle.font(12))
                            .foregroundStyle(HUDStyle.gold)

                        Text("They'd buy").font(HUDStyle.font(13)).foregroundStyle(HUDStyle.gold)
                        if buying.isEmpty {
                            Text("Nothing of yours catches their eye today.").font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                        }
                        ForEach(buying) { offer in
                            row(offer, button: "Sell \(offer.price)g", enabled: session.count(of: offer.item.id) > 0,
                                note: "Shop pays \(GameSession.sellPrice(of: offer.item))g · you have \(session.count(of: offer.item.id))")
                        }

                        Text("They're selling").font(HUDStyle.font(13)).foregroundStyle(HUDStyle.gold)
                        if selling.isEmpty {
                            Text("They've traded everything away for today.").font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                        }
                        ForEach(selling) { offer in
                            row(offer, button: "Buy \(offer.price)g", enabled: session.data.gold >= offer.price,
                                note: offer.item.type == .consumable || offer.item.type == .material
                                    ? (offer.item.description ?? offer.item.type.displayName)
                                    : "\(offer.item.type.displayName) · \(offer.item.stats?.bonusSummary ?? "")")
                        }
                        Text("Offers change every in-game day.")
                            .font(HUDStyle.font(10))
                            .foregroundStyle(HUDStyle.dim)
                    }
                    .padding(14)
                }
            }
            .frame(maxWidth: 520, maxHeight: 560)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(HUDStyle.ink.opacity(0.94))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(HUDStyle.cream.opacity(0.8), lineWidth: 2))
            )
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .padding(14)
        }
    }

    private func row(_ offer: GameSession.TradeOffer, button: String, enabled: Bool, note: String) -> some View {
        HStack(spacing: 10) {
            ItemIcon(item: offer.item, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(offer.item.name).font(HUDStyle.font(12)).foregroundStyle(HUDStyle.cream)
                Text(note).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
            }
            Spacer()
            Button(button) {
                if session.trade(offer) {
                    session.post(offer.kind == .theyBuy
                                 ? "Sold \(offer.item.name) to \(adventurer.name) for \(offer.price) gold."
                                 : "Bought \(offer.item.name) from \(adventurer.name) for \(offer.price) gold.", .reward)
                    reply = offer.kind == .theyBuy ? "Just what I needed, thanks!" : "Pleasure doing business!"
                    session.save()
                } else {
                    reply = offer.kind == .theyBuy ? "Looks like you don't have that any more." : "Come back when you've got the gold."
                }
            }
            .buttonStyle(PixelButtonStyle(tint: enabled ? HUDStyle.gold : HUDStyle.dim, compact: true))
        }
    }
}

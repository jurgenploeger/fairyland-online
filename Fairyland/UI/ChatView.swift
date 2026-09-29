import SwiftUI

/// The map's chat window: everything adventurers, villagers and NPCs have said here, and a
/// box to say something yourself (someone might answer).
struct ChatView: View {
    let session: GameSession
    let onSay: (String) -> Void
    let onClose: () -> Void
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                FLTitleBar(title: "Chat · \(session.mapName)", icon: .talk, onClose: onClose)
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(session.chat) { line in
                                ChatLineView(line: line)
                                    .id(line.id)
                            }
                        }
                        .padding(12)
                    }
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: session.chat.last?.id) {
                        guard let last = session.chat.last?.id else { return }
                        withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo(last, anchor: .bottom) }
                        session.unreadChat = 0
                    }
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 8) {
                    TextField("Say something…", text: $draft)
                        .font(HUDStyle.font(13))
                        .foregroundStyle(HUDStyle.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(HUDStyle.cream))
                        .focused($typing)
                        .submitLabel(.send)
                        .onSubmit(send)
                    Button(action: send) {
                        IconImage(.arrowRight, size: 18)
                            .foregroundStyle(HUDStyle.ink)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(HUDStyle.gold).overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5)))
                    }
                    .buttonStyle(PressScaleStyle())
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Send")
                }
                .padding(10)
                .background(HUDStyle.ink.opacity(0.6))
            }
            .frame(maxWidth: 520, maxHeight: 460)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(HUDStyle.ink.opacity(0.94))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HUDStyle.frameLight.opacity(0.8), lineWidth: 2))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(16)
        }
        .onAppear { session.unreadChat = 0 }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSay(String(text.prefix(80)))
        draft = ""
    }
}

private struct ChatLineView: View {
    let line: GameSession.ChatLine

    private var color: Color {
        switch line.kind {
        case .you: HUDStyle.gold
        case .adventurer: Color(uiColor: Crowd.adventurerColor)
        case .villager: HUDStyle.cream
        case .npc: HUDStyle.green
        case .system: HUDStyle.dim
        }
    }

    var body: some View {
        if line.kind == .system {
            Text(line.text)
                .font(HUDStyle.font(11))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
        } else {
            (Text("[\(line.speaker)] ").foregroundStyle(color) + Text(line.text).foregroundStyle(HUDStyle.cream))
                .font(HUDStyle.font(12))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

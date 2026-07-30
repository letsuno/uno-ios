import SwiftUI

/// In-game chat: message list plus input field. Own messages align right.
struct ChatSheet: View {
    let game: GameStore

    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            Text("Chat")
                .font(.headline)
                .padding(.top, 16)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(game.room.chat) { message in
                            bubble(message)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: game.room.chat.count) {
                    scrollToBottom(proxy, animated: true)
                }
                .onAppear {
                    scrollToBottom(proxy, animated: false)
                }
            }
            inputBar
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = game.room.chat.last else { return }
        if animated {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    // MARK: - Message bubble

    private func bubble(_ message: ChatMessage) -> some View {
        let mine = message.userId == game.myId
        return VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(message.nickname)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if message.isSpectator == true {
                    Text("spectator")
                        .font(.system(size: 9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                }
            }
            Text(message.text)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(
                    mine ? .regular.tint(.blue.opacity(0.45)) : .regular,
                    in: .rect(cornerRadius: 16)
                )
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .id(message.id)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $draft)
                .textFieldStyle(.plain)
                .glassChip(horizontal: 14, vertical: 9)
                .onSubmit(send)
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
            }
            .buttonStyle(.glassProminent)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
    }

    private func send() {
        let text = draft
        draft = ""
        game.room.sendChat(text)
    }
}

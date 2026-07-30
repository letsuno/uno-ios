import SwiftUI

/// Live chat scrolling right-to-left across the table in 5 lanes
/// (web DanmakuLayer: 8 s linear, 28 px lane pitch). Driven by `room.chat`
/// rather than the game FX stream, so it lives apart from `FxLayer`.
struct DanmakuLayer: View {
    let room: RoomStore
    let size: CGSize

    struct Item: Identifiable, Equatable {
        let id: String
        let nickname: String
        let text: String
        let lane: Int
        let spectator: Bool
    }

    @State private var items: [Item] = []
    @State private var laneCounter = 0
    @State private var mountedAt = Date()

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                DanmakuItemView(item: item, travelWidth: size.width)
                    .offset(y: CGFloat(item.lane) * 26 + 44)
            }
        }
        .task(id: room.chat.last?.id) {
            guard let message = room.chat.last,
                message.timestamp / 1000 > mountedAt.timeIntervalSince1970 - 1,
                !items.contains(where: { $0.id == message.id })
            else { return }
            let item = Item(
                id: message.id,
                nickname: message.nickname,
                text: message.text,
                lane: laneCounter % 5,
                spectator: message.isSpectator == true
            )
            laneCounter += 1
            items.append(item)
            try? await Task.sleep(for: .seconds(8))
            items.removeAll { $0.id == item.id }
        }
    }
}

private struct DanmakuItemView: View {
    let item: DanmakuLayer.Item
    let travelWidth: CGFloat

    @State private var offsetX: CGFloat

    init(item: DanmakuLayer.Item, travelWidth: CGFloat) {
        self.item = item
        self.travelWidth = travelWidth
        _offsetX = State(initialValue: travelWidth + 20)
    }

    var body: some View {
        HStack(spacing: 5) {
            if item.spectator {
                Text("SPEC")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.white.opacity(0.2), in: .capsule)
            }
            Text(item.nickname)
                .foregroundStyle(.white.opacity(0.6))
            Text(item.text)
                .foregroundStyle(.white)
        }
        .font(.footnote.weight(.bold))
        .lineLimit(1)
        .fixedSize()
        .shadow(color: .black.opacity(0.8), radius: 2)
        .offset(x: offsetX)
        .onAppear {
            withAnimation(.linear(duration: 8)) {
                offsetX = -travelWidth
            }
        }
    }
}

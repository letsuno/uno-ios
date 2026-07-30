import SwiftUI

/// All 10 seats of the room in a two-column glass grid.
struct SeatGridView: View {
    let room: RoomStore

    @State private var swapTarget: RoomSeatPlayer?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<unoSeatCount, id: \.self) { index in
                if let player = seat(at: index) {
                    occupiedCell(player: player, index: index)
                } else {
                    emptyCell(index: index)
                }
            }
        }
        .confirmationDialog(
            "Request seat swap?",
            isPresented: Binding(
                get: { swapTarget != nil },
                set: { if !$0 { swapTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: swapTarget
        ) { target in
            Button("Swap with \(target.nickname)") {
                Task { await room.requestSwap(with: target.userId) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func seat(at index: Int) -> RoomSeatPlayer? {
        room.seats.indices.contains(index) ? room.seats[index] : nil
    }

    // MARK: - Occupied seat

    private func occupiedCell(player: RoomSeatPlayer, index: Int) -> some View {
        let isMe = player.userId == room.myUserId
        let isRoomOwner = player.userId == room.room?.ownerId

        return VStack(spacing: 8) {
            AvatarView(
                url: room.session.endpoint?.resolveAvatar(player.avatarUrl),
                name: player.nickname,
                size: 44
            )
            HStack(spacing: 4) {
                if isRoomOwner {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Text(player.nickname)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                if player.isBot {
                    chip(
                        text: player.botConfig?.difficulty.localizedName ?? "Bot",
                        icon: "cpu",
                        color: .purple
                    )
                }
                if player.ready {
                    chip(text: "READY", icon: "checkmark", color: .green)
                }
                if !player.connected {
                    Image(systemName: "wifi.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .frame(minHeight: 18)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 108)
        .modifier(SeatGlass(isMine: isMe))
        .opacity(player.connected ? 1 : 0.5)
        .contentShape(.rect(cornerRadius: 20))
        .onTapGesture {
            // Seated players can ask another human for a seat swap.
            if room.mySeat != nil, !isMe, !player.isBot {
                swapTarget = player
            }
        }
        .contextMenu {
            if room.isOwner {
                if player.isBot {
                    Menu("Change difficulty") {
                        ForEach(BotDifficulty.allCases, id: \.self) { difficulty in
                            Button(difficulty.localizedName) {
                                Task {
                                    await room.setBotDifficulty(
                                        botId: player.userId,
                                        difficulty: difficulty
                                    )
                                }
                            }
                        }
                    }
                    Button("Remove bot", role: .destructive) {
                        Task { await room.removeBot(botId: player.userId) }
                    }
                } else if !isMe {
                    Button("Transfer ownership") {
                        Task { await room.transferOwner(to: player.userId) }
                    }
                    Button("Kick", role: .destructive) {
                        Task { await room.kick(targetId: player.userId) }
                    }
                }
            }
        }
    }

    private func chip(text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .glassEffect(.regular.tint(color.opacity(0.25)), in: .capsule)
    }

    // MARK: - Empty seat

    private func emptyCell(index: Int) -> some View {
        Button {
            Task { await room.takeSeat(index) }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Seat \(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 108)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        .secondary.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if room.isOwner {
                Menu("Add bot here") {
                    ForEach(BotDifficulty.allCases, id: \.self) { difficulty in
                        Button(difficulty.localizedName) {
                            Task { await room.addBot(difficulty: difficulty, seatIndex: index) }
                        }
                    }
                }
            }
        }
    }
}

/// The viewer's own seat gets a tinted glass slab; everyone else stays neutral.
private struct SeatGlass: ViewModifier {
    let isMine: Bool

    func body(content: Content) -> some View {
        if isMine {
            content.glassEffect(.regular.tint(.blue.opacity(0.35)), in: .rect(cornerRadius: 20))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
    }
}

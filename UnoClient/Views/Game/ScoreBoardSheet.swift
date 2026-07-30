import SwiftUI

/// Non-dismissable terminal scoreboard shown after the 10 s reveal window for
/// round_end and game_over phases.
struct ScoreBoardSheet: View {
    let game: GameStore

    var body: some View {
        if let view = game.view {
            content(view)
        }
    }

    @ViewBuilder
    private func content(_ view: PlayerView) -> some View {
        let ranked = view.players.sorted { $0.score > $1.score }
        let winnerId =
            view.winnerId
            ?? game.gameOverPayload?.winnerId
            ?? game.roundEnd?.winnerId
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(view.phase == .gameOver ? "Game over" : "Round \(view.roundNumber) finished")
                    .font(.title2.weight(.bold))
                if view.phase == .gameOver, let reason = game.gameOverPayload?.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(ranked.enumerated()), id: \.element.id) { index, player in
                            row(player, rank: index, winnerId: winnerId)
                        }
                    }
                }
                .frame(maxHeight: 320)
                controls(view)
            }
            .padding(24)
            .frame(maxWidth: 420)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .padding(20)
        }
    }

    // MARK: - Rows

    private func row(_ player: PlayerViewPlayer, rank: Int, winnerId: String?) -> some View {
        HStack(spacing: 10) {
            rankBadge(rank)
            AvatarView(
                url: game.session.endpoint?.resolveAvatar(player.avatarUrl),
                name: player.name,
                size: 32
            )
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(player.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if player.id == winnerId {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                Text("^[\(player.roundWins ?? 0) round win](inflect: true)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(player.score)")
                .font(.headline.monospacedDigit())
            if game.room.isOwner && player.id != game.myId {
                Button {
                    Task { await game.kickPlayer(player.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .opacity(player.eliminated == true ? 0.4 : 1)
    }

    @ViewBuilder
    private func rankBadge(_ rank: Int) -> some View {
        if rank < 3 {
            Image(systemName: "medal.fill")
                .foregroundStyle([Color.yellow, Color(white: 0.75), Color.orange][rank])
                .frame(width: 22)
        } else {
            Text("\(rank + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22)
        }
    }

    // MARK: - Controls

    /// The server enforces a 10 s cooldown after the terminal transition before
    /// next-round votes / back-to-room are accepted.
    @ViewBuilder
    private func controls(_ view: PlayerView) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let cooldownEndsAt = (game.terminalAt ?? .distantPast).addingTimeInterval(10)
            let coolingDown = context.date < cooldownEndsAt
            VStack(spacing: 10) {
                if view.phase == .roundEnd {
                    roundEndControls(coolingDown: coolingDown)
                } else {
                    gameOverControls(coolingDown: coolingDown)
                }
            }
        }
    }

    @ViewBuilder
    private func roundEndControls(coolingDown: Bool) -> some View {
        if game.isSpectator {
            spectatorControls
        } else {
            HStack(spacing: 10) {
                Button(voteLabel) {
                    Task { await game.voteNextRound() }
                }
                .buttonStyle(.glassProminent)
                .disabled(coolingDown)
                Button("Move to spectators") {
                    Task { await game.leaveToSpectate() }
                }
                .buttonStyle(.glass)
            }
            if game.room.isOwner, let vote = game.room.nextRoundVote, vote.votes >= vote.required {
                Text("Everyone agreed — press again to start")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func gameOverControls(coolingDown: Bool) -> some View {
        if game.room.isOwner {
            Button("Back to room") {
                Task { await game.backToRoom() }
            }
            .buttonStyle(.glassProminent)
            .disabled(coolingDown)
        } else {
            Text("Waiting for the host…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Leave game", role: .destructive) {
                Task { await game.room.leaveRoom() }
            }
            .buttonStyle(.glass)
        }
    }

    @ViewBuilder
    private var spectatorControls: some View {
        if game.room.amQueuedForNextRound {
            Label("Queued for next round", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            Button("Cancel queue") {
                Task { await game.room.joinNextRoundAsSpectator() }
            }
            .buttonStyle(.glass)
        } else {
            Button("Join next round") {
                Task { await game.room.joinNextRoundAsSpectator() }
            }
            .buttonStyle(.glassProminent)
        }
        if !game.room.spectatorQueue.isEmpty {
            Text("In queue: \(game.room.spectatorQueue.joined(separator: ", "))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        Button("Leave game", role: .destructive) {
            Task { await game.room.leaveRoom() }
        }
        .buttonStyle(.glass)
    }

    private var voteLabel: String {
        if let vote = game.room.nextRoundVote {
            return "Next round (\(vote.votes)/\(vote.required))"
        }
        return "Next round"
    }
}

import SwiftUI

/// Thin top HUD bar for the landscape table: room info on the left, game
/// status pill in the middle, timer and actions on the right.
struct GameHUDBar: View {
    let game: GameStore
    @Binding var confirmLeave: Bool

    var body: some View {
        if let view = game.view {
            HStack(alignment: .top, spacing: 8) {
                leftCluster(view)
                Spacer()
                rightCluster(view)
            }
            // Center hint overlaid so it stays screen-centered regardless of how
            // wide the side clusters grow (e.g. the autopilot pill on the left).
            .overlay(alignment: .top) { statusPill(view) }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Top-left meta stack

    @ViewBuilder
    private func leftCluster(_ view: PlayerView) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(game.room.roomCode)
                    .font(.caption2.weight(.semibold).monospaced())
                    .glassChip(horizontal: 8, vertical: 4)
                if game.me?.autopilot == true {
                    Label("Autopilot", systemImage: "cpu.fill")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(.regular.tint(.green.opacity(0.3)), in: .capsule)
                }
            }
            Text("R\(view.roundNumber)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if game.isSpectator {
                Label("Spectating", systemImage: "eye.fill")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(.regular.tint(.blue.opacity(0.3)), in: .capsule)
            }
        }
    }

    // MARK: - Top-right system stack

    @ViewBuilder
    private func rightCluster(_ view: PlayerView) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            blitzPill(view)
            menuButton
        }
    }

    // MARK: - Center status pill

    @ViewBuilder
    private func statusPill(_ view: PlayerView) -> some View {
        if let color = view.currentColor {
            HStack(spacing: 6) {
                Circle()
                    .fill(color.tint)
                    .frame(width: 10, height: 10)
                Text(color.localizedName)
                    .font(.caption2.weight(.bold))
                if let top = view.topDiscard {
                    Text(top.symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(color.tint.opacity(0.25)), in: .capsule)
        }
    }

    // MARK: - Right cluster

    @ViewBuilder
    private func blitzPill(_ view: PlayerView) -> some View {
        let terminal = view.phase == .roundEnd || view.phase == .gameOver
        if let limit = game.houseRules.blitzTimeLimit,
            let startedAt = view.gameStartedAt, !terminal
        {
            let deadline = Date(timeIntervalSince1970: startedAt / 1000 + Double(limit))
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, deadline.timeIntervalSince(context.date))
                Label(
                    String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60),
                    systemImage: "bolt.fill"
                )
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(remaining < 30 ? .red : .primary)
                .glassChip(horizontal: 8, vertical: 4)
            }
        }
    }

    private var menuButton: some View {
        Menu {
            // Autopilot delegates *your* turns, so it only exists for a seated player.
            if game.isSeatedPlayer {
                Button("Autopilot once", systemImage: "wand.and.stars") {
                    Task { await game.autopilotOnce() }
                }
                Button(
                    game.me?.autopilot == true ? "Disable autopilot" : "Enable autopilot",
                    systemImage: "cpu"
                ) {
                    Task { await game.toggleAutopilot() }
                }
                Button("Move to spectators", systemImage: "eye") {
                    Task { await game.leaveToSpectate() }
                }
            }
            Divider()
            Button("Leave room", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                confirmLeave = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption)
        }
        .buttonStyle(.glass)
    }
}

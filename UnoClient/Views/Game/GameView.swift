import SwiftUI

/// Landscape in-game screen: thin HUD on top, the elliptic table filling the
/// middle, floating action row and the hand fan at the bottom. A full-screen
/// FX layer above everything plays the ported web-client animations.
struct GameView: View {
    let game: GameStore

    @State private var showChat = false
    @State private var confirmLeave = false
    @State private var scoreboardVisible = false

    var body: some View {
        Group {
            if game.view != nil {
                content
            } else {
                loadingPlaceholder
            }
        }
        .overlay {
            if let view = game.view, isTerminal(view.phase), scoreboardVisible {
                ScoreBoardSheet(game: game)
                    .transition(.opacity)
            }
        }
        .overlay { GameOverlays(game: game) }
        .task(id: revealKey) { await updateScoreboardVisibility() }
        .sheet(isPresented: $showChat) { ChatSheet(game: game) }
        .confirmationDialog(
            "Leave the room?",
            isPresented: $confirmLeave,
            titleVisibility: .visible
        ) {
            Button("Leave room", role: .destructive) {
                Task { await game.room.leaveRoom() }
            }
        }
    }

    // MARK: - Layout

    private var content: some View {
        // The hand fan is a fixed 116pt band and the action row a fixed 44pt row,
        // so their heights never depend on autopilot; the veil offset only slides
        // the render, not the layout. That keeps the table's height constant across
        // autopilot toggles (no seat recompute) while leaving it in the upper region
        // rather than centered over the whole screen.
        let auto = game.me?.autopilot == true
        let isPlayer = game.isSeatedPlayer
        return VStack(spacing: 0) {
            GameHUDBar(game: game, confirmLeave: $confirmLeave)
            TableView(game: game)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Chat shares the action row's horizontal line, sitting to the right
            // of the autopilot toggle that terminates the ActionBar.
            HStack(alignment: .center, spacing: 8) {
                if isPlayer {
                    ActionBar(game: game)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
                chatButton
            }
            if isPlayer {
                HandFanView(game: game)
                    .overlay { if auto { autopilotVeil } }
                    .offset(y: auto ? HandFanView.bandHeight / 2 : 0)
                    .allowsHitTesting(!auto)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: auto)
            }
        }
        .padding(.horizontal, 6)
        .overlayPreferenceValue(TableAnchorPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                FxLayer(
                    game: game,
                    points: anchors.mapValues { proxy[$0] },
                    size: proxy.size
                )
            }
        }
    }

    /// In-game chat launcher pinned to the bottom-right corner of the table.
    private var chatButton: some View {
        Button {
            showChat = true
        } label: {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.headline)
                .overlay(alignment: .topTrailing) {
                    if !game.room.chat.isEmpty {
                        Text("\(min(game.room.chat.count, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(.red, in: .circle)
                            .offset(x: 8, y: -8)
                    }
                }
        }
        .buttonStyle(.glass)
        .padding(.trailing, 4)
    }

    /// Dim, non-interactive cover over the hand while autopilot drives play.
    private var autopilotVeil: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.black.opacity(0.4))
            .overlay {
                Label("Autopilot", systemImage: "cpu.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Waiting for game state…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Terminal reveal window

    private func isTerminal(_ phase: GamePhase) -> Bool {
        phase == .roundEnd || phase == .gameOver
    }

    private var revealKey: String {
        let phase = game.view?.phase.rawValue ?? "none"
        let stamp = game.terminalAt?.timeIntervalSince1970 ?? 0
        return "\(phase)-\(stamp)"
    }

    /// Keep the table visible for a 10 s reveal after the round/game ends,
    /// then bring up the scoreboard. A stale or missing `terminalAt` skips the wait.
    private func updateScoreboardVisibility() async {
        guard let view = game.view, isTerminal(view.phase) else {
            scoreboardVisible = false
            return
        }
        if let terminalAt = game.terminalAt {
            let wait = terminalAt.addingTimeInterval(10).timeIntervalSinceNow
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
                if Task.isCancelled { return }
            }
        }
        withAnimation(.spring(duration: 0.4)) { scoreboardVisible = true }
    }
}

// MARK: - Shared helpers for the game views

extension GameStore {
    /// Full duration of the current turn timer (mirrors the deadline set in `apply`).
    var turnLimitSeconds: TimeInterval {
        guard let view else { return 30 }
        let limit = view.settings.turnTimeLimit
        return TimeInterval(houseRules.fastMode ? max(1, limit / 2) : limit)
    }

    func playerName(_ id: String?) -> String {
        guard let id, let view else { return "?" }
        return view.player(id: id)?.name ?? "?"
    }
}

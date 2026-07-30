import SwiftUI

/// The landscape table canvas: seats on an ellipse, center piles with the
/// spinning direction ring, turn caption and the critical countdown.
struct TableView: View {
    let game: GameStore

    var body: some View {
        if let view = game.view {
            GeometryReader { geo in
                let size = geo.size
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                ZStack {
                    tableSurface(size)
                    DirectionRingView(
                        clockwise: view.direction == .clockwise,
                        spinning: view.phase != .roundEnd && view.phase != .gameOver
                    )
                    .position(center)
                    pilesRow
                        .position(center)
                    seats(view, size: size)
                    if game.remainingPenaltyDraws > 0 {
                        penaltyPill
                            .position(x: center.x, y: 20)
                    }
                    criticalCountdown(size: size)
                    turnCaption(view)
                        .position(x: center.x, y: center.y + size.height * 0.30)
                }
            }
        }
    }

    // MARK: - Surface

    private func tableSurface(_ size: CGSize) -> some View {
        Ellipse()
            .stroke(
                UnoPalette.amber.opacity(0.15),
                style: StrokeStyle(lineWidth: 2, dash: [8, 6])
            )
            .frame(width: size.width * 0.76, height: size.height * 0.76)
            .position(x: size.width / 2, y: size.height / 2)
    }

    // MARK: - Center piles

    private var pilesRow: some View {
        HStack(alignment: .center, spacing: 20) {
            DrawPileView(game: game, side: .left)
            DiscardPileView(game: game)
            DrawPileView(game: game, side: .right)
        }
    }

    // MARK: - Seats

    @ViewBuilder
    private func seats(_ view: PlayerView, size: CGSize) -> some View {
        let players = view.players
        let viewerIndex = players.firstIndex { $0.id == game.myId } ?? 0
        ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
            if game.isSpectator || player.id != game.myId {
                PlayerSeatNode(game: game, player: player)
                    .position(
                        TableGeometry.seatPosition(
                            playerIndex: index,
                            viewerIndex: viewerIndex,
                            playerCount: players.count,
                            in: size
                        )
                    )
            }
        }
    }

    // MARK: - Captions

    private var penaltyPill: some View {
        Label(
            "\(game.playerName(game.actingPlayerId)) must draw \(game.remainingPenaltyDraws)",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .glassEffect(.regular.tint(.red.opacity(0.35)), in: .capsule)
    }

    /// Only phases that need a textual instruction the seat highlight can't
    /// convey render here; a plain turn is already signalled by the acting
    /// seat's pulse, ring and gold name.
    private func needsInstruction(_ phase: GamePhase) -> Bool {
        phase == .choosingColor || phase == .challenging || phase == .choosingSwapTarget
    }

    @ViewBuilder
    private func turnCaption(_ view: PlayerView) -> some View {
        if needsInstruction(view.phase), let actorId = game.actingPlayerId, let endsAt = game.turnEndsAt {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let remaining = max(0, endsAt.timeIntervalSince(context.date))
                let seconds = Int(remaining.rounded())
                HStack(spacing: 6) {
                    Text(captionText(view, actorId: actorId))
                        .font(.footnote.weight(.bold))
                    Text("\(seconds)s")
                        .font(.footnote.weight(.bold).monospacedDigit())
                        .foregroundStyle(seconds <= 5 ? .red : .secondary)
                        .opacity(seconds <= 5 ? flashOpacity(context.date) : 1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .glassEffect(
                    actorId == game.myId
                        ? .regular.tint(.yellow.opacity(0.3)) : .regular,
                    in: .capsule
                )
            }
            .id(actorId)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func captionText(_ view: PlayerView, actorId: String) -> String {
        let mine = actorId == game.myId
        let name = game.playerName(actorId)
        switch view.phase {
        case .choosingColor:
            return mine
                ? String(localized: "Choose a color")
                : String(localized: "\(name) is choosing a color")
        case .challenging:
            return mine
                ? String(localized: "Respond to +4")
                : String(localized: "\(name) is deciding on +4")
        case .choosingSwapTarget:
            return mine
                ? String(localized: "Pick a swap target")
                : String(localized: "\(name) is picking a swap target")
        default:
            return mine ? String(localized: "Your turn") : String(localized: "\(name)'s turn")
        }
    }

    /// Web timerFlash: opacity 1 <-> 0.3, 0.5 s alternate.
    private func flashOpacity(_ date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
        return phase < 0.5 ? 1 : 0.3
    }

    /// Big flashing number for the last 5 seconds of the acting turn.
    @ViewBuilder
    private func criticalCountdown(size: CGSize) -> some View {
        if let endsAt = game.turnEndsAt, game.view?.phase == .playing {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let remaining = endsAt.timeIntervalSince(context.date)
                if remaining > 0 && remaining <= 5 {
                    Text("\(Int(remaining.rounded(.up)))")
                        .font(.system(size: 54, weight: .black, design: .rounded))
                        .foregroundStyle(UnoPalette.rose)
                        .shadow(color: .black.opacity(0.3), radius: 0, x: 3, y: 4)
                        .opacity(0.8 * flashOpacity(context.date))
                        .position(x: size.width / 2, y: size.height * 0.20)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

/// Spinning dashed direction ring with a counter-rotating (i.e. upright)
/// glyph, mirroring the web client's 3 s linear spin.
struct DirectionRingView: View {
    let clockwise: Bool
    /// Paused during terminal phases so the ring stops driving redraws once the
    /// round/game is over and nothing else on the table is moving.
    var spinning: Bool = true
    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    UnoPalette.amber.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [7, 7])
                )
                .frame(width: 128, height: 128)
                .rotationEffect(.degrees(clockwise ? angle : -angle))
                .animation(
                    spinning
                        ? .linear(duration: 3).repeatForever(autoreverses: false)
                        : .default,
                    value: angle
                )
            Image(systemName: clockwise ? "arrow.clockwise" : "arrow.counterclockwise")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(UnoPalette.amber.opacity(0.5))
                .offset(y: -84)
                .transition(.scale(scale: 1.6).combined(with: .opacity))
                .id(clockwise)
        }
        .allowsHitTesting(false)
        .task(id: spinning) { angle = spinning ? 360 : 0 }
    }
}

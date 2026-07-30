import SwiftUI

/// One seat on the table ellipse: avatar with countdown ring and turn pulse,
/// name, mini hand and status chips. Mirrors the web client's PlayerNode.
struct PlayerSeatNode: View {
    let game: GameStore
    let player: PlayerViewPlayer

    private var isActing: Bool { player.id == game.actingPlayerId }
    private var isRevealed: Bool {
        !player.hand.isEmpty && player.hand.count == player.handCount
    }
    private var skipStamped: Bool {
        game.fx.skipStampedPlayerIds.contains(player.id)
    }

    var body: some View {
        HStack(spacing: 6) {
            leftIdentity
            rightStatus
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .grayscale(player.eliminated == true ? 0.8 : 0)
        .opacity(player.eliminated == true ? 0.35 : 1)
        .contextMenu {
            Menu("Throw item") {
                ForEach(unoThrowItems, id: \.self) { item in
                    Button(item) {
                        Task { await game.room.throwItem(item, at: player.id) }
                    }
                }
            }
        }
    }

    // MARK: - Left third: avatar + name

    private var leftIdentity: some View {
        VStack(spacing: 2) {
            avatar
            Text(player.name)
                .font(.system(size: 9, weight: isActing ? .bold : .semibold))
                .foregroundStyle(isActing ? UnoPalette.amber : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 44)
        }
    }

    private var avatar: some View {
        ZStack {
            if isActing {
                TurnPulseGlow(size: 42)
            }
            AvatarView(
                url: game.session.endpoint?.resolveAvatar(player.avatarUrl),
                name: player.name,
                size: 38
            )
            if isActing, let endsAt = game.turnEndsAt {
                CountdownRing(endsAt: endsAt, total: game.turnLimitSeconds, size: 42)
            }
            if !player.connected {
                Image(systemName: "wifi.slash")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(.black.opacity(0.65), in: .circle)
            }
            if skipStamped {
                Text("⊘")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.5), in: .circle)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if player.autopilot {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                    .padding(2)
                    .background(.black.opacity(0.7), in: .circle)
            }
        }
        .frame(width: 44, height: 44)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: skipStamped)
        .tableAnchor(.seat(playerId: player.id))
    }

    // MARK: - Right two-thirds: hand + score

    private var rightStatus: some View {
        VStack(alignment: .leading, spacing: 3) {
            miniHand
            scoreRow
        }
    }

    /// Only 1–3 cards are ever drawn; anything larger collapses to `×N` so the
    /// module keeps a fixed footprint regardless of hand size.
    @ViewBuilder
    private var miniHand: some View {
        if player.handCount > 0 {
            HStack(spacing: 4) {
                HStack(spacing: -8) {
                    if isRevealed {
                        ForEach(player.hand.prefix(3)) { card in
                            CardView(card: card, width: 16)
                        }
                    } else {
                        ForEach(0..<min(player.handCount, 3), id: \.self) { _ in
                            CardBackView(width: 16)
                        }
                    }
                }
                if player.handCount > 3 {
                    Text("×\(player.handCount)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                }
            }
        }
    }

    private var scoreRow: some View {
        HStack(spacing: 4) {
            Text("\(player.score) pts")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
            if let teamId = player.teamId {
                Text("T\(teamId + 1)")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.blue.opacity(0.5), in: .capsule)
            }
            if player.calledUno {
                Text("UNO!")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.yellow, in: .capsule)
            }
        }
    }
}

/// Gold breathing glow behind the acting player's avatar
/// (web: drawReadyPulse, opacity 0.25 -> 1, 1 s alternate).
struct TurnPulseGlow: View {
    var size: CGFloat = 52
    @State private var bright = false

    var body: some View {
        Circle()
            .fill(UnoPalette.gold.opacity(0.5))
            .frame(width: size, height: size)
            .blur(radius: 10)
            .opacity(bright ? 1 : 0.25)
            .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    bright = true
                }
            }
    }
}

/// Countdown ring around the acting player's avatar. Green above 50 %,
/// yellow above 25 %, red below (web: CountdownRing).
struct CountdownRing: View {
    let endsAt: Date
    let total: TimeInterval
    var size: CGFloat = 50
    var lineWidth: CGFloat = 3

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = max(0, endsAt.timeIntervalSince(context.date))
            let fraction = total > 0 ? remaining / total : 0
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color(for: fraction), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
                .animation(.linear(duration: 0.25), value: fraction)
        }
    }

    private func color(for fraction: Double) -> Color {
        if fraction > 0.5 { return UnoPalette.emerald }
        if fraction > 0.25 { return UnoPalette.gold }
        return UnoPalette.rose
    }
}

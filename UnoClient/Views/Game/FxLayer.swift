import SwiftUI

/// Full-screen effect layer above the table. Resolves the table anchors and
/// renders every transient `GameFxDirector.FxEvent`: card flights, effect banners,
/// color waves, thrown items and confetti. The `DanmakuLayer` chat overlay is
/// composed in on top but lives in its own file (it's driven by chat, not FX).
struct FxLayer: View {
    let game: GameStore
    let points: [TableAnchorKind: CGPoint]
    let size: CGSize

    private var hasBanner: Bool {
        game.fx.events.contains {
            if case .banner = $0.kind { return true }
            return false
        }
    }

    var body: some View {
        ZStack {
            DanmakuLayer(room: game.room, size: size)

            if hasBanner {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            ForEach(game.fx.events) { event in
                eventView(event)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: game.fx.events)
        .animation(.easeOut(duration: 0.2), value: hasBanner)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func eventView(_ event: GameFxDirector.FxEvent) -> some View {
        switch event.kind {
        case .playFlight(let card, let fromPlayerId):
            PlayFlightView(
                game: game,
                card: card,
                from: point(forPlayer: fromPlayerId),
                to: points[.discard] ?? center,
                isSelf: fromPlayerId == game.myId
            )
        case .drawFlight(let toPlayerId, let side, let count):
            DrawFlightView(
                from: points[.deck(side)] ?? center,
                to: point(forPlayer: toPlayerId),
                count: count,
                isSelf: toPlayerId == game.myId
            )
        case .banner(let banner):
            EffectBannerView(banner: banner)
                .position(x: size.width / 2, y: size.height / 2)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.75).combined(with: .opacity)
                            .combined(with: .offset(y: 20)),
                        removal: .scale(scale: 1.15).combined(with: .opacity)
                            .combined(with: .offset(y: -30))
                    )
                )
        case .colorWave(let color):
            ColorWaveView(color: color, size: size)
        case .myTurnBanner:
            Text("Your turn!")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 0, x: 3, y: 4)
                .position(x: size.width / 2, y: size.height * 0.35)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
        case .throwItem(let fromId, let targetId, let item):
            ThrowFlightView(
                item: item,
                seed: event.id.hashValue,
                from: point(forPlayer: fromId),
                to: point(forPlayer: targetId)
            )
        case .confetti:
            ConfettiView(seed: event.id.hashValue, size: size)
                .transition(.identity)
        }
    }

    private var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    private func point(forPlayer id: String) -> CGPoint {
        if id == game.myId, let hand = points[.myHand] { return hand }
        return points[.seat(playerId: id)] ?? center
    }
}

// MARK: - Card flights

/// Played card flying from a seat (or the hand) onto the discard pile.
/// Web: 0.38 s easeOut, 3-point arc through an apex, rotate to ∓4/6°.
struct PlayFlightView: View {
    let game: GameStore
    let card: UnoCard
    let from: CGPoint
    let to: CGPoint
    let isSelf: Bool

    @State private var progress: CGFloat = 0

    var body: some View {
        // Land on the card's final pile transform (same offset + tilt it keeps for
        // life), so the flight -> pile hand-off is a straight swap with no shift.
        let rest = DiscardPileView.rest(card.id)
        let to = CGPoint(x: to.x + rest.offset.width, y: to.y + rest.offset.height)
        let apex = CGPoint(
            x: (from.x + to.x) / 2,
            y: min(from.y, to.y) - (isSelf ? 90 : 40)
        )
        // Quadratic control point that makes the curve pass through the apex at t = 0.5.
        let control = CGPoint(
            x: 2 * apex.x - (from.x + to.x) / 2,
            y: 2 * apex.y - (from.y + to.y) / 2
        )
        CardView(card: card, width: 64)
            .modifier(
                PlayFlightModifier(
                    progress: progress,
                    from: from,
                    control: control,
                    to: to,
                    startScale: isSelf ? 0.9 : 0.5,
                    peakRotation: isSelf ? -4 : 6,
                    endRotation: rest.rotation
                )
            )
            .onAppear {
                withAnimation(.easeOut(duration: 0.38)) { progress = 1 }
            }
            .task {
                // Reveal exactly as the flight settles onto the pile at the same
                // tilt/scale, so the hand-off is a straight swap, not a jump.
                try? await Task.sleep(for: .seconds(0.38))
                game.fx.revealDiscard(card.id)
            }
    }
}

private struct PlayFlightModifier: ViewModifier, Animatable {
    var progress: CGFloat
    let from: CGPoint
    let control: CGPoint
    let to: CGPoint
    let startScale: CGFloat
    let peakRotation: Double
    /// Tilt the card settles at on landing — matches the pile's top-card rest tilt.
    let endRotation: Double

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = progress
        let inverse = 1 - t
        let x = inverse * inverse * from.x + 2 * inverse * t * control.x + t * t * to.x
        let y = inverse * inverse * from.y + 2 * inverse * t * control.y + t * t * to.y
        // scale: start -> 1 by mid-flight, then hold 1 so the landed card matches
        // the pile top card exactly (no shrink at hand-off).
        let scale =
            t < 0.5
            ? startScale + (1 - startScale) * t * 2
            : 1
        // rotation: arc up to the apex peak, then settle onto the pile's rest tilt.
        let rotation = peakRotation * Double(1 - abs(t - 0.5) * 2) + endRotation * Double(t)
        return
            content
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
            .opacity(Double(min(1, 0.4 + t * 1.5)))
            .position(x: x, y: y)
    }
}

/// Card backs flying from a draw deck to a seat or the viewer's hand.
/// Web: 500 ms easeOutCubic, -36 pt hop, 0.15 s stagger.
struct DrawFlightView: View {
    let from: CGPoint
    let to: CGPoint
    let count: Int
    let isSelf: Bool

    var body: some View {
        ForEach(0..<count, id: \.self) { index in
            SingleDrawFlight(
                from: from,
                to: to,
                endScale: isSelf ? 1.3 : 0.45,
                delay: 0.05 + Double(index) * 0.15
            )
        }
    }
}

private struct SingleDrawFlight: View {
    let from: CGPoint
    let to: CGPoint
    let endScale: CGFloat
    let delay: Double

    @State private var progress: CGFloat = 0
    @State private var landed = false

    var body: some View {
        CardBackView(width: 46)
            .modifier(
                DrawFlightModifier(
                    progress: progress, from: from, to: to, endScale: endScale
                )
            )
            .opacity(landed ? 0 : 1)
            .onAppear {
                // easeOutCubic ~= timingCurve(0.33, 1, 0.68, 1)
                withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.5).delay(delay)) {
                    progress = 1
                }
                Task {
                    try? await Task.sleep(for: .seconds(delay + 0.5))
                    withAnimation(.easeOut(duration: 0.12)) { landed = true }
                }
            }
    }
}

private struct DrawFlightModifier: ViewModifier, Animatable {
    var progress: CGFloat
    let from: CGPoint
    let to: CGPoint
    let endScale: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = progress
        let x = from.x + (to.x - from.x) * t
        let y = from.y + (to.y - from.y) * t + sin(Double(t) * .pi) * -36
        return
            content
            .scaleEffect(0.55 + (endScale - 0.55) * t)
            .opacity(Double(min(1, t * 6)))
            .position(x: x, y: CGFloat(y))
    }
}

// MARK: - Effect banners

/// Center-screen banner mirroring the web GameEffects component: big icon,
/// heavy text, optional sub-line and a card-back fan for draw penalties.
struct EffectBannerView: View {
    let banner: GameFxDirector.EffectBanner

    var body: some View {
        VStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 0, x: 3, y: 4)
            }
            Text(text)
                .font(.system(size: isVictory ? 52 : 46, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 0, x: 3, y: 4)
            if let subline {
                Text(subline)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            if cardFanCount > 0 {
                cardFan
            }
        }
        .scaleEffect(1.2)
    }

    private var isVictory: Bool {
        if case .victory = banner { return true }
        return false
    }

    private var icon: String? {
        switch banner {
        case .skip: return "nosign"
        case .reverse: return "arrow.triangle.2.circlepath"
        case .drawPenalty: return nil
        case .unoCall: return "megaphone.fill"
        case .catchUno: return "hand.raised.fill"
        case .challenge(let succeeded, _, _):
            return succeeded ? "checkmark.shield.fill" : "xmark.shield.fill"
        case .victory: return "trophy.fill"
        }
    }

    private var text: String {
        switch banner {
        case .skip: return String(localized: "SKIP!")
        case .reverse: return String(localized: "REVERSE!")
        case .drawPenalty(let count, _): return "+\(count)!"
        case .unoCall: return String(localized: "UNO!")
        case .catchUno: return String(localized: "CAUGHT!")
        case .challenge(let succeeded, _, _):
            return succeeded ? String(localized: "CHALLENGE WON!") : String(localized: "CHALLENGE FAILED!")
        case .victory(let winner, let isMe):
            if isMe { return String(localized: "YOU WIN!") }
            return winner.map { String(localized: "\($0) WINS!") } ?? String(localized: "ROUND OVER")
        }
    }

    private var subline: String? {
        switch banner {
        case .skip(let victim): return victim.map { String(localized: "\($0) is skipped") }
        case .reverse: return nil
        case .drawPenalty(_, let victim): return victim.map { String(localized: "\($0) draws") }
        case .unoCall(let caller): return caller
        case .catchUno(let catcher, let target): return String(localized: "\(catcher) caught \(target)")
        case .challenge(_, let penalized, let count): return String(localized: "\(penalized) draws \(count)")
        case .victory: return nil
        }
    }

    private var cardFanCount: Int {
        switch banner {
        case .drawPenalty(let count, _): return min(count, 6)
        case .challenge(_, _, let count): return min(count, 3)
        default: return 0
        }
    }

    private var fanTotal: Int {
        switch banner {
        case .drawPenalty(let count, _): return count
        case .challenge(_, _, let count): return count
        default: return 0
        }
    }

    private var cardFan: some View {
        HStack(spacing: 4) {
            HStack(spacing: -12) {
                ForEach(0..<cardFanCount, id: \.self) { index in
                    CardBackView(width: 26)
                        .rotationEffect(.degrees(Double(index) * 4 - 8))
                }
            }
            if fanTotal > cardFanCount {
                Text("×\(fanTotal)")
                    .font(.headline.weight(.black))
                    .foregroundStyle(UnoPalette.rose)
            }
        }
    }
}

// MARK: - Color wave

/// Expanding ring when the active color changes (web ColorWave: gradient
/// layer 1 s + border layer 1.1 s, both scale 0 -> 1, easeOut).
struct ColorWaveView: View {
    let color: CardColor
    let size: CGSize

    @State private var expanded = false

    private var diameter: CGFloat {
        (size.width * size.width + size.height * size.height).squareRoot().rounded(.up)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.tint.opacity(0.27), color.tint.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter / 2 * 0.7
                    )
                )
                .frame(width: diameter, height: diameter)
                .scaleEffect(expanded ? 1 : 0.001)
                .opacity(expanded ? 0 : 0.9)
                .animation(.easeOut(duration: 1.0), value: expanded)
            Circle()
                .stroke(color.tint, lineWidth: diameter * 0.125)
                .frame(width: diameter, height: diameter)
                .scaleEffect(expanded ? 1 : 0.001)
                .opacity(expanded ? 0 : 1)
                .animation(.easeOut(duration: 1.1), value: expanded)
        }
        .position(x: size.width / 2, y: size.height / 2)
        .onAppear { expanded = true }
    }
}

// MARK: - Thrown items

/// Emoji flying along a quadratic Bezier (0.6 s easeIn), then a splash with
/// six colored particles at the target (web ThrowAnimation).
struct ThrowFlightView: View {
    let item: String
    let seed: Int
    let from: CGPoint
    let to: CGPoint

    @State private var progress: CGFloat = 0
    @State private var impact = false

    private static let rotatingItems: Set<String> = ["🥚", "🍅", "🐷"]

    private static let palettes: [String: [Color]] = [
        "🥚": [Color(hex: 0xFFF9C4), Color(hex: 0xFFF176), Color(hex: 0xF9E08A)],
        "🍅": [Color(hex: 0xEF4444), Color(hex: 0xF87171), Color(hex: 0xDC2626)],
        "🌹": [Color(hex: 0xEC4899), Color(hex: 0xF472B6), Color(hex: 0xBE185D)],
        "💩": [Color(hex: 0x92400E), Color(hex: 0xA16207), Color(hex: 0x78350F)],
        "🐷": [Color(hex: 0xF9A8D4), Color(hex: 0xF472B6), Color(hex: 0xFDA4AF)],
        "👍": [Color(hex: 0xFBBF24), Color(hex: 0xF59E0B), Color(hex: 0xD97706)],
        "💖": [Color(hex: 0xEC4899), Color(hex: 0xF472B6), Color(hex: 0xF9A8D4)],
    ]

    private var control: CGPoint {
        CGPoint(
            x: (from.x + to.x) / 2,
            y: min(from.y, to.y) - abs(to.x - from.x) * 0.4
        )
    }

    var body: some View {
        ZStack {
            if impact {
                splash
            } else {
                Text(item)
                    .font(.system(size: 44))
                    .scaleEffect(1 + 0.3 * progress)
                    .rotationEffect(
                        .degrees(Self.rotatingItems.contains(item) ? 360 * progress : 0)
                    )
                    .modifier(
                        BezierPositionModifier(
                            progress: progress, from: from, control: control, to: to
                        )
                    )
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.6)) { progress = 1 }
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                impact = true
            }
        }
    }

    private var splash: some View {
        let palette = Self.palettes[item] ?? Self.palettes["👍"]!
        return ZStack {
            SplashEmoji(item: item)
            ForEach(0..<6, id: \.self) { index in
                SplashParticle(
                    color: palette[index % palette.count],
                    angle: Double(index) * .pi / 3
                        + Double((seed >> (index * 3)) & 7) / 14.0,
                    distance: 30 + CGFloat((seed >> (index * 2)) & 15) * 4 / 3
                )
            }
        }
        .position(to)
    }
}

private struct BezierPositionModifier: ViewModifier, Animatable {
    var progress: CGFloat
    let from: CGPoint
    let control: CGPoint
    let to: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = progress
        let inverse = 1 - t
        let x = inverse * inverse * from.x + 2 * inverse * t * control.x + t * t * to.x
        let y = inverse * inverse * from.y + 2 * inverse * t * control.y + t * t * to.y
        return content.position(x: x, y: y)
    }
}

private struct SplashEmoji: View {
    let item: String
    @State private var phase = 0

    var body: some View {
        Text(item)
            .font(.system(size: 44))
            .scaleEffect(phase == 0 ? 1 : phase == 1 ? 2 : 0.1)
            .opacity(phase == 2 ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { phase = 1 }
                Task {
                    try? await Task.sleep(for: .seconds(0.25))
                    withAnimation(.easeOut(duration: 0.25)) { phase = 2 }
                }
            }
    }
}

private struct SplashParticle: View {
    let color: Color
    let angle: Double
    let distance: CGFloat

    @State private var flung = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .offset(
                x: flung ? cos(angle) * distance * 1.5 : 0,
                y: flung ? sin(angle) * distance * 1.5 : 0
            )
            .scaleEffect(flung ? 0.1 : 1)
            .opacity(flung ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) { flung = true }
            }
    }
}

// MARK: - Confetti

/// One-shot celebration: 40 pieces falling with 720° rotation
/// (web Confetti: 2.5-3.5 s linear, 0-0.5 s delay).
struct ConfettiView: View {
    let seed: Int
    let size: CGSize

    private static let palette: [Color] = [
        Color(hex: 0xFF3366), Color(hex: 0x4488FF), Color(hex: 0x33CC66),
        Color(hex: 0xFBBF24), Color(hex: 0xA855F7), Color(hex: 0xEC4899),
    ]

    var body: some View {
        ForEach(0..<40, id: \.self) { index in
            ConfettiPiece(
                color: Self.palette[(seed &+ index) %% Self.palette.count],
                x: CGFloat((seed &+ index &* 2_654_435_761) %% 1000) / 1000 * size.width,
                pieceSize: 6 + CGFloat((seed >> (index % 16)) & 7),
                isCircle: (seed &+ index) % 2 == 0,
                duration: 2.5 + Double((seed &+ index &* 7) %% 100) / 100,
                delay: Double((seed &+ index &* 13) %% 50) / 100,
                fallHeight: size.height + 60
            )
        }
    }
}

private struct ConfettiPiece: View {
    let color: Color
    let x: CGFloat
    let pieceSize: CGFloat
    let isCircle: Bool
    let duration: Double
    let delay: Double
    let fallHeight: CGFloat

    @State private var fallen = false

    var body: some View {
        Group {
            if isCircle {
                Circle().fill(color)
            } else {
                RoundedRectangle(cornerRadius: 2).fill(color)
            }
        }
        .frame(width: pieceSize, height: pieceSize)
        .rotationEffect(.degrees(fallen ? 720 : 0))
        .opacity(fallen ? 0 : 1)
        .position(x: x, y: fallen ? fallHeight : -20)
        .onAppear {
            withAnimation(.linear(duration: duration).delay(delay)) { fallen = true }
        }
    }
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Positive modulo for seeded pseudo-random placement.
infix operator %% : MultiplicationPrecedence

func %% (lhs: Int, rhs: Int) -> Int {
    let raw = lhs % rhs
    return raw < 0 ? raw + rhs : raw
}

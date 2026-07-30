import SwiftUI

/// Discard pile with the web client's deterministic scatter: up to 8 cards, each
/// resting at a fixed transform decided once from its id — a card never moves
/// after it lands, so becoming an under-card when the next play arrives is a no-op.
struct DiscardPileView: View {
    let game: GameStore
    var cardWidth: CGFloat = 64

    private static let visibleStack = 8

    /// A card's final resting transform in the pile, derived once from its id.
    /// The play-flight lands at exactly this transform and the card keeps it for
    /// life, so a new play never recomputes where the previous card sits.
    static func rest(_ cardId: String) -> (offset: CGSize, rotation: Double) {
        let seed = djb2(cardId)
        return (
            CGSize(
                width: CGFloat((seed >> 4) % 40) - 20,
                height: CGFloat((seed >> 8) % 30) - 15
            ),
            Double(seed % 360) * 0.1 - 18
        )
    }

    var body: some View {
        if let view = game.view {
            content(view)
        }
    }

    private func content(_ view: PlayerView) -> some View {
        let pile = view.discardPile
        let stack = Array(pile.suffix(Self.visibleStack))
        let flightHidesTop =
            game.fx.hiddenDiscardCardId != nil
            && stack.last?.id == game.fx.hiddenDiscardCardId

        return ZStack {
            ForEach(Array(stack.enumerated()), id: \.element.id) { index, card in
                let isTop = index == stack.count - 1
                let rest = Self.rest(card.id)
                if isTop {
                    topCard(card, view: view, rest: rest)
                        .opacity(flightHidesTop ? 0 : 1)
                } else {
                    CardView(card: card, width: cardWidth)
                        .rotationEffect(.degrees(rest.rotation))
                        .offset(rest.offset)
                        .opacity(max(0.4, 0.85 - Double(stack.count - 1 - index) * 0.06))
                }
            }
            if pile.isEmpty {
                RoundedRectangle(cornerRadius: cardWidth * 0.14)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(width: cardWidth, height: cardWidth * 1.5)
            }
        }
        .frame(width: cardWidth + 44, height: cardWidth * 1.5 + 34)
        .overlay(alignment: .topTrailing) {
            if view.drawStack > 0 {
                drawStackBadge(view)
            }
        }
        .tableAnchor(.discard)
    }

    @ViewBuilder
    private func topCard(
        _ card: UnoCard, view: PlayerView, rest: (offset: CGSize, rotation: Double)
    ) -> some View {
        let awaitingColor = view.phase == .choosingColor && card.isWild && card.chosenColor == nil
        let glowColor = view.currentColor?.tint

        CardView(card: card, width: cardWidth)
            .shadow(color: (glowColor ?? .white).opacity(glowColor == nil ? 0.22 : 0.6), radius: 14)
            .overlay {
                if awaitingColor {
                    PendingColorOutline(cornerRadius: cardWidth * 0.14)
                } else if let glowColor, card.isWild {
                    RoundedRectangle(cornerRadius: cardWidth * 0.14)
                        .stroke(glowColor, lineWidth: 2.5)
                        .padding(-2)
                }
            }
            // Same resting transform it will keep as an under-card, so the next
            // play demotes it in place — no jump, no recompute.
            .rotationEffect(.degrees(rest.rotation))
            .offset(rest.offset)
            // Opacity-only: the flight already delivered the card to this exact
            // transform, so revealing it must not re-animate a pop.
            .transition(.opacity)
            .id(card.id)
    }

    private func drawStackBadge(_ view: PlayerView) -> some View {
        Text("+\(view.drawStack)")
            .font(.caption.weight(.black).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background((view.currentColor?.tint ?? .red).gradient, in: .circle)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .transition(.scale(scale: 0.5).combined(with: .opacity))
    }

    private static func djb2(_ text: String) -> Int {
        var hash = 5381
        for byte in text.utf8 {
            hash = ((hash << 5) &+ hash &+ Int(byte)) & 0xFFFFFF
        }
        return hash
    }
}

/// Dashed outline + pulse while a played wild waits for its color
/// (web: pendingPulse 1.1 s, opacity .6 -> 1, scale .96 -> 1).
struct PendingColorOutline: View {
    let cornerRadius: CGFloat
    @State private var up = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
            .foregroundStyle(.white.opacity(0.55))
            .padding(-3)
            .opacity(up ? 1 : 0.6)
            .scaleEffect(up ? 1 : 0.96)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    up = true
                }
            }
    }
}

/// One of the two draw decks. When drawable it gets the web client's gold
/// "draw ready" pulse; tapping draws from that side.
struct DrawPileView: View {
    let game: GameStore
    let side: DrawSide
    var cardWidth: CGFloat = 50

    @State private var pulse = false

    var body: some View {
        if let view = game.view {
            let count = side == .left ? view.deckLeftCount : view.deckRightCount
            let drawable = game.canDraw && count > 0 && !game.isSpectator
            Button {
                Task { await game.draw(side: side) }
            } label: {
                VStack(spacing: 4) {
                    ZStack {
                        if count > 1 {
                            CardBackView(width: cardWidth).offset(x: 3, y: 3)
                        }
                        CardBackView(width: cardWidth)
                            .overlay {
                                if drawable {
                                    RoundedRectangle(cornerRadius: cardWidth * 0.14)
                                        .stroke(
                                            UnoPalette.amber,
                                            lineWidth: 2.5
                                        )
                                }
                            }
                            .shadow(
                                color: drawable
                                    ? UnoPalette.gold
                                        .opacity(pulse ? 0.85 : 0.3)
                                    : .clear,
                                radius: drawable ? 13 : 0
                            )
                    }
                    .opacity(count == 0 ? 0.25 : drawable ? 1 : 0.6)
                    Text("\(count)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(count > 0 && count <= 10 ? .red : .secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!drawable)
            .scaleEffect(drawable && pulse ? 1.03 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .tableAnchor(.deck(side))
        }
    }
}

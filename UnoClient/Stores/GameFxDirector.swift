import Foundation
import Observation

/// Ephemeral animation events derived from consecutive server states. Kept apart
/// from `GameStore` so its high-churn timers (banners appearing/expiring, card
/// flights) don't sit on the authoritative game state, and so seats can depend on
/// `skipStampedPlayerIds` alone instead of scanning every live event.
@MainActor
@Observable
final class GameFxDirector {
    /// Transient animation events consumed by the FX layer. Each event carries
    /// its own lifetime and is removed automatically.
    private(set) var events: [FxEvent] = []
    /// Discard top hidden while its play-flight copy is in the air.
    private(set) var hiddenDiscardCardId: String?
    /// Own freshly drawn card hidden while the draw-flight copy is in the air.
    private(set) var hiddenHandCardId: String?
    /// Players currently wearing a skip "⊘" stamp. Seats read this set rather than
    /// scanning `events`, so an unrelated banner/flight no longer re-renders them.
    private(set) var skipStampedPlayerIds: Set<String> = []

    struct FxEvent: Identifiable, Equatable {
        enum Kind: Equatable {
            case playFlight(card: UnoCard, fromPlayerId: String)
            case drawFlight(toPlayerId: String, side: DrawSide, count: Int)
            case banner(EffectBanner)
            case colorWave(CardColor)
            case myTurnBanner
            case throwItem(fromId: String, targetId: String, item: String)
            case confetti
        }

        let id = UUID()
        let kind: Kind
    }

    /// Center-screen effect banners, mirroring the web client's GameEffects.
    enum EffectBanner: Equatable {
        case skip(victim: String?)
        case reverse
        case drawPenalty(count: Int, victim: String?)
        case unoCall(caller: String)
        case catchUno(catcher: String, target: String)
        case challenge(succeeded: Bool, penalized: String, count: Int)
        case victory(winner: String?, isMe: Bool)
    }

    // MARK: - Hidden-card lifetimes

    /// Hide the freshly drawn card until its draw-flight copy lands (~1.2 s).
    func hideDrawnCard(_ cardId: String) {
        hiddenHandCardId = cardId
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            if self?.hiddenHandCardId == cardId { self?.hiddenHandCardId = nil }
        }
    }

    func revealDiscard(_ cardId: String) {
        if hiddenDiscardCardId == cardId { hiddenDiscardCardId = nil }
    }

    func itemThrown(from: String, to target: String, item: String) {
        emit(.throwItem(fromId: from, targetId: target, item: item), lifetime: 1.6)
    }

    // MARK: - Emission

    private func emit(_ kind: FxEvent.Kind, lifetime: TimeInterval) {
        let event = FxEvent(kind: kind)
        events.append(event)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(lifetime))
            self?.events.removeAll { $0.id == event.id }
        }
    }

    private func stampSkip(playerId: String) {
        skipStampedPlayerIds.insert(playerId)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.0))
            self?.skipStampedPlayerIds.remove(playerId)
        }
    }

    // MARK: - Derivation

    /// Diff two consecutive server states into transient animation events,
    /// mirroring the web client's GameEffects/ViewportFxLayer triggers.
    func derive(old: PlayerView, next: PlayerView, myId: String?) {
        let action = next.lastAction

        // Card flights from per-player hand-count deltas (robust against
        // missed pushes; swaps and round resets are excluded).
        let roundReset = next.roundNumber != old.roundNumber
        let isSwap = action?.type == .chooseSwapTarget
        if !roundReset && !isSwap {
            for player in next.players {
                guard let before = old.players.first(where: { $0.id == player.id }) else {
                    continue
                }
                let delta = player.handCount - before.handCount
                if delta > 0 {
                    let side: DrawSide =
                        next.deckLeftCount < old.deckLeftCount ? .left : .right
                    let count = min(delta, 6)
                    emit(
                        .drawFlight(toPlayerId: player.id, side: side, count: count),
                        lifetime: 0.55 + Double(count - 1) * 0.15 + 0.4
                    )
                } else if delta < 0, action?.type == .playCard, action?.playerId == player.id,
                    let top = next.topDiscard, top.id != old.topDiscard?.id
                {
                    hiddenDiscardCardId = top.id
                    emit(.playFlight(card: top, fromPlayerId: player.id), lifetime: 0.55)
                    let topId = top.id
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(1.2))
                        self?.revealDiscard(topId)
                    }
                }
            }
        }

        // Center banners keyed on the action transition.
        if let action, action != old.lastAction {
            switch action.type {
            case .playCard where next.topDiscard?.id != old.topDiscard?.id:
                bannerForPlayedCard(action: action, next: next)
            case .callUno:
                emit(
                    .banner(.unoCall(caller: name(action.actorId, in: next))),
                    lifetime: 1.35
                )
            case .catchUno:
                emit(
                    .banner(
                        .catchUno(
                            catcher: action.catcherName ?? name(action.actorId, in: next),
                            target: name(action.targetId, in: next)
                        )
                    ),
                    lifetime: 1.35
                )
            case .challenge:
                let succeeded = action.succeeded == true
                emit(
                    .banner(
                        .challenge(
                            succeeded: succeeded,
                            penalized: name(action.penaltyPlayerId ?? action.targetId, in: next),
                            count: action.penaltyCount ?? (succeeded ? 4 : 6)
                        )
                    ),
                    lifetime: 1.35
                )
            default:
                break
            }
        }

        // Color wave whenever the active color changes through a play/choice.
        if next.currentColor != old.currentColor, let color = next.currentColor,
            action?.type == .playCard || action?.type == .chooseColor
        {
            emit(.colorWave(color), lifetime: 1.2)
        }

        // "Your turn" banner.
        let terminal: Set<GamePhase> = [.roundEnd, .gameOver]
        if !terminal.contains(next.phase), let myId,
            actingId(of: next) == myId, actingId(of: old) != myId
        {
            emit(.myTurnBanner, lifetime: 1.6)
        }

        // Round/game end: victory banner + confetti.
        if next.phase != old.phase, terminal.contains(next.phase) {
            let winner = next.players.first { $0.handCount == 0 && $0.eliminated != true }
            emit(
                .banner(.victory(winner: winner?.name, isMe: winner?.id == myId)),
                lifetime: 1.6
            )
            emit(.confetti, lifetime: 4)
        }
    }

    private func bannerForPlayedCard(action: GameAction, next: PlayerView) {
        guard let top = next.topDiscard else { return }
        switch top.type {
        case .skip:
            let victim = victimAfter(actorId: action.playerId, in: next)
            emit(.banner(.skip(victim: victim?.name)), lifetime: 1.35)
            if let victim { stampSkip(playerId: victim.id) }
        case .reverse:
            if next.players.count == 2 {
                let victim = victimAfter(actorId: action.playerId, in: next)
                emit(.banner(.skip(victim: victim?.name)), lifetime: 1.35)
            } else {
                emit(.banner(.reverse), lifetime: 1.35)
            }
        case .drawTwo:
            emit(
                .banner(
                    .drawPenalty(
                        count: max(next.drawStack, 2),
                        victim: next.pendingDrawPlayerId.map { name($0, in: next) }
                    )
                ),
                lifetime: 1.35
            )
        case .wildDrawFour:
            emit(
                .banner(
                    .drawPenalty(
                        count: max(next.drawStack, 4),
                        victim: next.pendingDrawPlayerId.map { name($0, in: next) }
                    )
                ),
                lifetime: 1.35
            )
        default:
            break
        }
    }

    private func actingId(of view: PlayerView) -> String? {
        if view.phase == .challenging { return view.pendingDrawPlayerId }
        return view.currentPlayer?.id
    }

    private func name(_ id: String?, in view: PlayerView) -> String {
        guard let id else { return "?" }
        return view.player(id: id)?.name ?? "?"
    }

    /// The player seated right after `actorId` in play direction, skipping
    /// eliminated players — i.e. the victim of a skip.
    private func victimAfter(actorId: String?, in view: PlayerView) -> PlayerViewPlayer? {
        guard let actorId,
            let start = view.players.firstIndex(where: { $0.id == actorId })
        else { return nil }
        let count = view.players.count
        let step = view.direction == .clockwise ? 1 : -1
        var index = start
        for _ in 0..<count {
            index = ((index + step) % count + count) % count
            let candidate = view.players[index]
            if candidate.eliminated != true { return candidate }
        }
        return nil
    }
}

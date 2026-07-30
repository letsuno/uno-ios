import Foundation
import Observation

@MainActor
@Observable
final class GameStore {
    unowned let session: SessionStore
    unowned let room: RoomStore

    private(set) var view: PlayerView?
    private(set) var lastDrawnCard: UnoCard?
    private(set) var roundEnd: RoundEndPayload?
    private(set) var gameOverPayload: GameOverPayload?
    private(set) var turnEndsAt: Date?
    private(set) var terminalAt: Date?

    /// Derived state cached once per `apply`. Hand rendering reads these O(hand)
    /// times per body pass, so recomputing them lazily made playability O(n²).
    private(set) var me: PlayerViewPlayer?
    private(set) var myHand: [UnoCard] = []
    private(set) var playableCardIds: Set<String> = []

    /// Ephemeral animation events derived from state transitions. Split off so its
    /// timer-driven churn doesn't invalidate views that only read authoritative state.
    let fx = GameFxDirector()

    /// A wild_draw_four that needs its color picked before the play is sent
    /// (stacking onto an existing attack card).
    var pendingColorPick: UnoCard?

    init(session: SessionStore, room: RoomStore) {
        self.session = session
        self.room = room
    }

    // MARK: - State ingestion

    func apply(_ next: PlayerView) {
        let previous = view
        view = next
        // Refresh cached derived state before anything reads it.
        me = resolveMe(in: next)
        myHand = reconcileHand(
            server: me?.hand ?? [],
            roundChanged: previous?.roundNumber != next.roundNumber
        )
        playableCardIds = computePlayableCardIds()

        let terminal: Set<GamePhase> = [.roundEnd, .gameOver]
        if !terminal.contains(next.phase) {
            roundEnd = nil
            gameOverPayload = nil
            terminalAt = nil
            let limit =
                next.settings.houseRules.fastMode
                ? next.settings.turnTimeLimit / 2
                : next.settings.turnTimeLimit
            turnEndsAt = Date().addingTimeInterval(TimeInterval(limit))
        } else {
            turnEndsAt = nil
            if previous.map({ terminal.contains($0.phase) }) != true { terminalAt = Date() }
        }
        if next.phase != .playing || !isMyTurn {
            if lastAction?.type != .drawCard { lastDrawnCard = nil }
        }
        if let previous { fx.derive(old: previous, next: next, myId: myId) }
    }

    func cardDrawn(_ card: UnoCard) {
        lastDrawnCard = card
        fx.hideDrawnCard(card.id)
    }

    func roundEnded(_ payload: RoundEndPayload) {
        roundEnd = payload
    }

    func gameOver(_ payload: GameOverPayload) {
        gameOverPayload = payload
    }

    func autopilotChanged(playerId: String, enabled: Bool) {
        if playerId == myId, enabled {
            session.showToast(String(localized: "Autopilot enabled"), isError: false)
        }
    }

    // MARK: - Identity / turn

    var myId: String? { session.user?.id }

    var isSpectator: Bool { view?.viewerId == "__spectator__" || room.isSpectator }

    private func resolveMe(in view: PlayerView) -> PlayerViewPlayer? {
        guard !isSpectator else { return nil }
        return view.players.first { $0.id == view.viewerId }
    }

    // MARK: - Hand ordering (client-owned)

    /// Hand order is display-only state the client owns, so a manual reorder
    /// survives server updates. Seed from `sortedForHand()` on a fresh round (or
    /// first sight), then keep the existing order for surviving cards and append
    /// newly drawn cards at the end (highlighted by their `NEW` badge).
    private func reconcileHand(server: [UnoCard], roundChanged: Bool) -> [UnoCard] {
        guard !roundChanged, !myHand.isEmpty else { return server.sortedForHand() }
        let byId = Dictionary(server.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [UnoCard] = []
        var seen = Set<String>()
        for card in myHand {
            if let fresh = byId[card.id] {
                result.append(fresh)
                seen.insert(card.id)
            }
        }
        result.append(contentsOf: server.filter { !seen.contains($0.id) }.sortedForHand())
        return result
    }

    /// Move a held card to a new slot, inserting after removal (so `to` is the
    /// final index). No-op if the card is gone or the index is unchanged.
    func reorderHand(_ cardId: String, to target: Int) {
        guard let from = myHand.firstIndex(where: { $0.id == cardId }) else { return }
        var arr = myHand
        let card = arr.remove(at: from)
        arr.insert(card, at: min(max(target, 0), arr.count))
        myHand = arr
    }

    var isMyTurn: Bool {
        guard let view, let me else { return false }
        return view.currentPlayer?.id == me.id
    }

    /// During `challenging` the acting player is the wild-draw-four victim,
    /// not `currentPlayerIndex`.
    var actingPlayerId: String? {
        guard let view else { return nil }
        if view.phase == .challenging { return view.pendingDrawPlayerId }
        return view.currentPlayer?.id
    }

    var houseRules: HouseRules { view?.settings.houseRules ?? .default }

    var hasDrawnThisTurn: Bool {
        guard let view, view.phase == .playing,
            let last = view.lastAction, last.type == .drawCard
        else { return false }
        return last.playerId == view.currentPlayer?.id && isMyTurn
    }

    var lastAction: GameAction? { view?.lastAction }

    /// Cards the penalty payer still owes (stack shown until converted).
    var remainingPenaltyDraws: Int {
        guard let view else { return 0 }
        let pending = view.pendingPenaltyDraws ?? 0
        return pending > 0 ? pending : view.drawStack
    }

    // MARK: - Playability

    private func computePlayableCardIds() -> Set<String> {
        guard let view, let me else { return [] }
        let hand = me.hand
        let top = view.topDiscard
        let rules = houseRules

        if view.phase == .challenging {
            guard view.pendingDrawPlayerId == me.id, let top else { return [] }
            return Set(hand.filter { canRespondToDrawStack($0, top: top, rules: rules) }.map(\.id))
        }
        guard view.phase == .playing else { return [] }

        if !isMyTurn {
            guard rules.jumpIn, (view.pendingPenaltyDraws ?? 0) == 0, view.drawStack == 0, let top
            else { return [] }
            return Set(hand.filter { isExactJumpInMatch($0, top: top) }.map(\.id))
        }
        if (view.pendingPenaltyDraws ?? 0) > 0 { return [] }
        if view.drawStack > 0 {
            guard let top else { return [] }
            return Set(hand.filter { canRespondToDrawStack($0, top: top, rules: rules) }.map(\.id))
        }
        return Set(hand.filter { canPlayCard($0, top: top, currentColor: view.currentColor) }.map(\.id))
    }

    /// noHints hides affordances without changing what is actually playable.
    var hintedCardIds: Set<String> {
        houseRules.noHints ? [] : playableCardIds
    }

    var canDraw: Bool {
        guard let view, isMyTurn, view.phase == .playing else { return false }
        let hasCards = view.deckLeftCount > 0 || view.deckRightCount > 0 || view.discardPile.count > 1
        guard hasCards else { return false }
        let penaltyDrawing = remainingPenaltyDraws > 0
        if penaltyDrawing { return true }
        if houseRules.forcedPlay && !playableCardIds.isEmpty { return false }
        if let me, let limit = houseRules.handLimit, me.hand.count >= limit { return false }
        let canStart = !houseRules.drawUntilPlayable || playableCardIds.isEmpty
        let canContinue = houseRules.drawUntilPlayable && hasDrawnThisTurn && playableCardIds.isEmpty
        return (!hasDrawnThisTurn && canStart) || canContinue
    }

    var canPass: Bool {
        guard let view, isMyTurn, view.phase == .playing else { return false }
        let noCardsAvailable =
            view.deckLeftCount == 0 && view.deckRightCount == 0 && view.discardPile.count <= 1
        if noCardsAvailable { return true }
        let afterDraw =
            (view.pendingPenaltyDraws ?? 0) == 0 && view.drawStack == 0 && hasDrawnThisTurn
            && (!houseRules.drawUntilPlayable || !playableCardIds.isEmpty)
        return afterDraw || canEndMultiPlay
    }

    /// multi-play keeps the turn after a number card; PASS ends the chain.
    /// The web client has no button for this — we surface an explicit "End turn".
    var canEndMultiPlay: Bool {
        guard let view, isMyTurn, view.phase == .playing,
            houseRules.multiplePlaySameNumber || houseRules.bombCard,
            let last = view.lastAction, last.type == .playCard, last.playerId == myId,
            view.topDiscard?.type == .number
        else { return false }
        return true
    }

    var canCallUno: Bool {
        guard let view, let me, !me.calledUno, me.unoCaught != true,
            (view.pendingPenaltyDraws ?? 0) == 0
        else { return false }
        if me.hand.count == 1 { return true }
        return !houseRules.strictUnoCall && me.hand.count == 2 && isMyTurn && !playableCardIds.isEmpty
    }

    /// silentUno swallows catches server-side, so hide the buttons entirely.
    var catchTargets: [PlayerViewPlayer] {
        guard let view, !houseRules.silentUno else { return [] }
        return view.players.filter {
            $0.id != myId && $0.handCount == 1 && !$0.calledUno && $0.unoCaught != true
        }
    }

    var showChallengeControls: Bool {
        guard let view, view.phase == .challenging else { return false }
        return view.pendingDrawPlayerId == me?.id
    }

    var showColorPicker: Bool {
        guard let view else { return false }
        return view.phase == .choosingColor && isMyTurn && me?.autopilot != true
    }

    var swapTargets: [PlayerViewPlayer] {
        guard let view, view.phase == .choosingSwapTarget, isMyTurn else { return [] }
        return view.players.filter { $0.id != myId && $0.eliminated != true }
    }

    /// A stacked wild_draw_four must carry its color inline or the server rejects it.
    func mustPickColorBeforePlay(_ card: UnoCard) -> Bool {
        guard let view, card.type == .wildDrawFour,
            view.phase == .challenging || view.drawStack > 0,
            let top = view.topDiscard
        else { return false }
        let rules = houseRules
        if rules.stackDrawFour && top.type == .wildDrawFour { return true }
        if rules.crossStack && (top.type == .drawTwo || top.type == .wildDrawFour) { return true }
        return false
    }

    // MARK: - Actions

    func play(_ card: UnoCard) async {
        if mustPickColorBeforePlay(card) {
            pendingColorPick = card
            return
        }
        await session.perform("game:play_card", .object(["cardId": .string(card.id)]))
    }

    func play(_ card: UnoCard, color: CardColor) async {
        pendingColorPick = nil
        await session.perform(
            "game:play_card",
            .object(["cardId": .string(card.id), "chosenColor": .string(color.rawValue)])
        )
    }

    func draw(side: DrawSide) async {
        await session.perform("game:draw_card", .object(["side": .string(side.rawValue)]))
    }

    func pass() async {
        await session.perform("game:pass")
    }

    func callUno() async {
        await session.perform("game:call_uno")
    }

    func catchUno(target: PlayerViewPlayer) async {
        await session.perform("game:catch_uno", .object(["targetPlayerId": .string(target.id)]))
    }

    func challenge() async {
        await session.perform("game:challenge")
    }

    func accept() async {
        await session.perform("game:accept")
    }

    func chooseColor(_ color: CardColor) async {
        await session.perform("game:choose_color", .object(["color": .string(color.rawValue)]))
    }

    func chooseSwapTarget(_ targetId: String) async {
        await session.perform("game:choose_swap_target", .object(["targetId": .string(targetId)]))
    }

    func voteNextRound() async {
        await session.perform("game:next_round")
    }

    func backToRoom() async {
        await session.perform("game:back_to_room")
    }

    func kickPlayer(_ targetId: String) async {
        await session.perform("game:kick_player", .object(["targetId": .string(targetId)]))
    }

    func leaveToSpectate() async {
        await session.perform("game:leave_to_spectate")
    }

    func toggleAutopilot() async {
        await session.perform("player:toggle-autopilot")
    }

    func autopilotOnce() async {
        await session.perform("game:autopilot_once")
    }
}

// MARK: - Rule predicates (mirror shared/src/rules/validation.ts)

func canPlayCard(_ card: UnoCard, top: UnoCard?, currentColor: CardColor?) -> Bool {
    if card.isWild { return true }
    if let currentColor, card.color == currentColor { return true }
    guard let top, !top.isWild else { return false }
    if card.type == .number {
        return top.type == .number && card.value == top.value
    }
    return card.type == top.type
}

func isExactJumpInMatch(_ card: UnoCard, top: UnoCard) -> Bool {
    guard card.type == top.type, card.color == top.color else { return false }
    return card.type != .number || card.value == top.value
}

func canRespondToDrawStack(_ card: UnoCard, top: UnoCard, rules: HouseRules) -> Bool {
    if rules.stackDrawTwo, card.type == .drawTwo, top.type == .drawTwo { return true }
    if rules.stackDrawFour, card.type == .wildDrawFour, top.type == .wildDrawFour { return true }
    if rules.crossStack,
        (card.type == .drawTwo && top.type == .wildDrawFour)
            || (card.type == .wildDrawFour && top.type == .drawTwo)
    {
        return true
    }
    if rules.reverseDeflectDrawTwo, card.type == .reverse, top.type == .drawTwo { return true }
    if rules.reverseDeflectDrawFour, card.type == .reverse, top.type == .wildDrawFour { return true }
    if rules.skipDeflect, card.type == .skip { return true }
    return false
}

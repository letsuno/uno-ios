import Foundation
import Observation
import os

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "UnoClient",
    category: "room"
)

@MainActor
@Observable
final class RoomStore {
    unowned let session: SessionStore
    let roomCode: String

    private(set) var room: RoomData?
    private(set) var seats: [RoomSeatPlayer?]
    private(set) var spectators: [Spectator]
    private(set) var isSpectator: Bool
    private(set) var chat: [ChatMessage] = []
    private(set) var game: GameStore?
    private(set) var nextRoundVote: NextRoundVote?
    private(set) var incomingSwapRequest: SwapRequest?
    private(set) var spectatorQueue: [String] = []
    /// Whether *this* client is queued for the next round. Authoritative from the
    /// `game:spectator_join` ack, since the broadcast `spectatorQueue` carries
    /// nicknames (not user ids) and cannot identify the local user reliably.
    private(set) var amQueuedForNextRound = false
    private(set) var ownerTransferAt: Double?
    private(set) var cheatDetected = false

    struct SwapRequest: Equatable {
        let requesterId: String
        let requesterName: String
        let requesterSeatIndex: Int
        let targetSeatIndex: Int?
    }

    init(
        session: SessionStore,
        roomCode: String,
        room: RoomData?,
        seats: [RoomSeatPlayer?],
        spectators: [Spectator],
        isSpectator: Bool
    ) {
        self.session = session
        self.roomCode = roomCode
        self.room = room
        self.seats = seats
        self.spectators = spectators
        self.isSpectator = isSpectator
    }

    // MARK: - Derived

    var myUserId: String? { session.user?.id }
    var isOwner: Bool { room?.ownerId == myUserId }

    var mySeatIndex: Int? {
        guard let myUserId else { return nil }
        return seats.firstIndex { $0?.userId == myUserId }
    }

    var mySeat: RoomSeatPlayer? { mySeatIndex.flatMap { seats[$0] } }

    var seatedPlayers: [RoomSeatPlayer] { seats.compactMap(\.self) }

    var canStartGame: Bool {
        guard isOwner else { return false }
        let players = seatedPlayers
        return players.count >= unoMinPlayers
            && players.allSatisfy { $0.ready || $0.isBot || $0.userId == room?.ownerId }
    }

    func applySnapshot(
        room: RoomData?,
        seats: [RoomSeatPlayer?]?,
        spectators: [Spectator]?,
        isSpectator: Bool
    ) {
        if let room { self.room = room }
        if let seats { self.seats = seats }
        if let spectators { self.spectators = spectators }
        self.isSpectator = isSpectator
    }

    func gameStateReceived(_ view: PlayerView) {
        // A live round means any prior next-round queueing has been resolved.
        if view.phase == .playing { amQueuedForNextRound = false }
        if let game {
            game.apply(view)
        } else {
            let store = GameStore(session: session, room: self)
            game = store
            store.apply(view)
        }
    }

    // MARK: - Room actions

    func setReady(_ ready: Bool) async {
        await session.perform("room:ready", .bool(ready))
    }

    func takeSeat(_ index: Int) async {
        await session.perform("seat:take", .number(Double(index)))
    }

    func leaveSeat() async {
        await session.perform("seat:leave")
    }

    func requestSwap(with targetUserId: String) async {
        await session.perform("seat:swap_request", .string(targetUserId))
    }

    func respondSwap(requesterId: String, accept: Bool) async {
        incomingSwapRequest = nil
        await session.perform(
            "seat:swap_respond",
            .object(["requesterId": .string(requesterId), "accept": .bool(accept)])
        )
    }

    func updateSettings(_ settings: RoomSettings) async {
        do {
            await session.perform("room:update_settings", try .from(settings))
        } catch {
            session.showToast(error.localizedDescription)
        }
    }

    func addBot(difficulty: BotDifficulty, seatIndex: Int?) async {
        var payload: [String: JSONValue] = ["difficulty": .string(difficulty.rawValue)]
        if let seatIndex { payload["seatIndex"] = .number(Double(seatIndex)) }
        await session.perform("room:add_bot", .object(payload))
    }

    /// An AI bot is added through the same event, but the server rejects the payload
    /// unless `rl` comes with an engine and the rule difficulties come without one.
    func addAiBot(providerId: String, seatIndex: Int?) async {
        var payload: [String: JSONValue] = [
            "difficulty": .string(BotDifficulty.rl.rawValue),
            "aiProviderId": .string(providerId),
        ]
        if let seatIndex { payload["seatIndex"] = .number(Double(seatIndex)) }
        await session.perform("room:add_bot", .object(payload))
    }

    func removeBot(botId: String) async {
        await session.perform("room:remove_bot", .object(["botId": .string(botId)]))
    }

    func setBotDifficulty(botId: String, difficulty: BotDifficulty) async {
        await session.perform(
            "room:set_bot_difficulty",
            .object(["botId": .string(botId), "difficulty": .string(difficulty.rawValue)])
        )
    }

    func setBotAi(botId: String, providerId: String) async {
        await session.perform(
            "room:set_bot_ai",
            .object(["botId": .string(botId), "providerId": .string(providerId)])
        )
    }

    /// Fetched per use rather than cached: the server filters by the seat count the
    /// action would produce, so a stale list stops matching after anyone sits down.
    func aiProviders(intent: AiProviderIntent) async -> [AiProvider] {
        do {
            let ack: AiProviderListAck = try await session.ack(
                "room:list_ai_providers", .object(["intent": .string(intent.rawValue)])
            )
            guard ack.success else {
                if let error = ack.error { session.showToast(error) }
                return []
            }
            return ack.providers ?? []
        } catch {
            session.showToast(error.localizedDescription)
            return []
        }
    }

    func startGame() async {
        await session.perform("game:start")
    }

    func leaveRoom() async {
        await session.perform("room:leave")
        session.leftRoom()
    }

    func dissolveRoom() async {
        await session.perform("room:dissolve")
        session.leftRoom()
    }

    func transferOwner(to targetId: String) async {
        await session.perform("room:transfer_owner", .object(["targetId": .string(targetId)]))
    }

    func kick(targetId: String) async {
        await session.perform("room:kick", .object(["targetId": .string(targetId)]))
    }

    /// Server drops chat silently unless a game session exists for the room.
    func sendChat(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.fire("chat:message", .object(["text": .string(String(trimmed.prefix(500)))]))
    }

    func throwItem(_ item: String, at targetId: String) async {
        await session.perform(
            "throw:item",
            .object(["targetId": .string(targetId), "item": .string(item)])
        )
    }

    /// Toggles the local user in/out of the next-round queue. The server ack
    /// reports the resulting `queued` state directly.
    func joinNextRoundAsSpectator() async {
        do {
            let ack: SpectatorJoinAck = try await session.ack("game:spectator_join")
            if ack.success == true {
                amQueuedForNextRound = ack.queued == true
            } else if let error = ack.error {
                session.showToast(error)
            }
        } catch {
            session.showToast(error.localizedDescription)
        }
    }

    // MARK: - Event handling

    func handle(event: String, args: [JSONValue]) {
        let payload = args.first ?? .null
        do {
            switch event {
            case "room:updated":
                // One server code path sends { players } without a room key.
                if let room = payload["room"] {
                    self.room = try room.decoded(as: RoomData.self)
                }
            case "seat:updated":
                let update = try payload.decoded(as: SeatUpdate.self)
                seats = update.seats
                spectators = update.spectators
            case "room:ready_changed":
                break  // seat:updated carries the same information
            case "room:dissolved":
                let reason = payload["reason"]?.stringValue
                session.showToast(dissolveDescription(reason), isError: false)
                session.leftRoom()
            case "room:rejoin_redirect":
                if let code = payload["roomCode"]?.stringValue {
                    Task { await session.rejoin(roomCode: code) }
                }
            case "seat:swap_requested":
                incomingSwapRequest = SwapRequest(
                    requesterId: payload["requesterId"]?.stringValue ?? "",
                    requesterName: payload["requesterName"]?.stringValue ?? "?",
                    requesterSeatIndex: payload["requesterSeatIndex"]?.intValue ?? 0,
                    targetSeatIndex: payload["targetSeatIndex"]?.intValue
                )
            case "seat:swap_resolved":
                incomingSwapRequest = nil
                if payload["accepted"]?.boolValue == false,
                    payload["requesterId"]?.stringValue == myUserId,
                    let reason = payload["reason"]?.stringValue
                {
                    session.showToast(String(localized: "Swap declined (\(reason))"))
                }
            case "room:spectator_joined", "room:spectator_left", "room:spectator_list":
                spectators = try payload["spectators"]?.decoded(as: [Spectator].self) ?? []
            case "room:bot_added":
                if let name = payload["name"]?.stringValue {
                    session.showToast(String(localized: "Bot \(name) joined"), isError: false)
                }
            case "room:bot_removed", "room:bot_updated":
                break  // seat:updated follows
            case "room:owner_transfer_pending":
                ownerTransferAt = payload["transferAt"]?.doubleValue
            case "room:owner_transfer_cancelled":
                ownerTransferAt = nil
            case "chat:message":
                chat.append(try payload.decoded(as: ChatMessage.self))
                if chat.count > 200 { chat.removeFirst(chat.count - 200) }
            case "chat:history":
                chat = try payload.decoded(as: [ChatMessage].self)
            case "chat:cleared":
                chat = []
            case "chat:rate_limited":
                session.showToast(payload["message"]?.stringValue ?? String(localized: "Sending too fast"))
            case "game:state", "game:update":
                gameStateReceived(try payload.decoded(as: PlayerView.self))
            case "game:card_drawn":
                if let card = try payload["card"]?.decoded(as: UnoCard.self) {
                    game?.cardDrawn(card)
                }
            case "game:action_rejected":
                session.showToast(payload["reason"]?.stringValue ?? String(localized: "Action rejected"))
            case "game:next_round_vote":
                nextRoundVote = try payload.decoded(as: NextRoundVote.self)
            case "game:round_end":
                game?.roundEnded(try payload.decoded(as: RoundEndPayload.self))
            case "game:over":
                game?.gameOver(try payload.decoded(as: GameOverPayload.self))
            case "game:back_to_room":
                game = nil
                nextRoundVote = nil
                spectatorQueue = []
                amQueuedForNextRound = false
                applySnapshot(
                    room: try payload["room"]?.decoded(as: RoomData.self),
                    seats: try payload["seats"]?.decoded(as: [RoomSeatPlayer?].self),
                    spectators: try payload["spectators"]?.decoded(as: [Spectator].self),
                    isSpectator: isSpectator
                )
            case "game:kicked":
                if payload["toSpectator"]?.boolValue == true {
                    isSpectator = true
                    session.showToast(String(localized: "Moved to spectators"), isError: false)
                } else {
                    session.showToast(payload["reason"]?.stringValue ?? String(localized: "Removed from room"))
                    session.leftRoom()
                }
            case "game:spectator_queue":
                spectatorQueue = payload["queue"]?.arrayValue?.compactMap(\.stringValue) ?? []
            case "game:cheat_detected":
                cheatDetected = true
            case "throw:item":
                if let from = payload["fromId"]?.stringValue,
                    let target = payload["targetId"]?.stringValue,
                    let item = payload["item"]?.stringValue
                {
                    game?.fx.itemThrown(from: from, to: target, item: item)
                }
            case "player:autopilot":
                if let playerId = payload["playerId"]?.stringValue,
                    let enabled = payload["enabled"]?.boolValue
                {
                    game?.autopilotChanged(playerId: playerId, enabled: enabled)
                }
            case "player:timeout", "player:disconnected", "player:reconnected":
                break  // reflected in the next game:update
            case "voice:presence":
                break  // voice chat is out of scope for this client
            default:
                logger.debug("unhandled event \(event)")
            }
        } catch {
            logger.error("failed to handle \(event): \(error)")
        }
    }

    private func dissolveDescription(_ reason: String?) -> String {
        switch reason {
        case "host_closed": return String(localized: "The host closed the room")
        case "idle_timeout": return String(localized: "Room closed after inactivity")
        case "empty": return String(localized: "Room closed because it was empty")
        default: return String(localized: "Room was closed")
        }
    }

    private struct SeatUpdate: Decodable {
        let seats: [RoomSeatPlayer?]
        let spectators: [Spectator]
    }

    private struct SpectatorJoinAck: Decodable {
        let success: Bool?
        let queued: Bool?
        let error: String?
    }

    private struct AiProviderListAck: Decodable {
        let success: Bool
        let providers: [AiProvider]?
        let error: String?
    }
}

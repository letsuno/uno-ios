import Foundation

enum GamePhase: String, Codable, Sendable {
    case waiting, dealing, playing
    case choosingColor = "choosing_color"
    case challenging
    case choosingSwapTarget = "choosing_swap_target"
    case roundEnd = "round_end"
    case gameOver = "game_over"
}

enum PlayDirection: String, Codable, Sendable {
    case clockwise
    case counterClockwise = "counter_clockwise"
}

enum DrawSide: String, Codable, Sendable {
    case left, right
}

/// `rl` is not a rung on the rule-bot ladder — it marks a bot driven by an AI engine,
/// named by `BotConfig.aiProviderId`. It still arrives through the same wire field, so
/// leaving it out breaks decoding of every seat in a room that has one.
enum BotDifficulty: String, Codable, Sendable {
    case novice, easy, normal, hard, rl

    /// The difficulties a rule bot can be set to.
    static let ruleCases: [BotDifficulty] = [.novice, .easy, .normal, .hard]

    var localizedName: String {
        switch self {
        case .novice: return String(localized: "Novice")
        case .easy: return String(localized: "Easy")
        case .normal: return String(localized: "Normal")
        case .hard: return String(localized: "Hard")
        case .rl: return String(localized: "AI")
        }
    }
}

enum BotPersonality: String, Codable, Sendable {
    case aggressive, defensive, chaotic, strategic, balanced
}

struct BotConfig: Codable, Equatable, Sendable {
    var difficulty: BotDifficulty
    var personality: BotPersonality?
    var aiProviderId: String?
}

/// One entry of `room:list_ai_providers`. The server filters the list by seat count and
/// house rules, so it is only valid for the intent it was fetched with.
struct AiProvider: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let fairness: Fairness

    /// How much of the hidden state the engine is allowed to see.
    enum Fairness: String, Decodable, Sendable {
        case fair, privileged, cheat

        var localizedName: String {
            switch self {
            case .fair: return String(localized: "Fair")
            case .privileged: return String(localized: "Privileged")
            case .cheat: return String(localized: "Sees all cards")
            }
        }
    }
}

/// The provider list is filtered against the resulting player count, which differs
/// between adding a new bot and re-engining one that is already seated.
enum AiProviderIntent: String, Sendable {
    case add, `switch`
}

/// Wire `GameAction` is a union with per-variant fields; decoded flat and leniently.
struct GameAction: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case playCard = "PLAY_CARD"
        case drawCard = "DRAW_CARD"
        case pass = "PASS"
        case callUno = "CALL_UNO"
        case catchUno = "CATCH_UNO"
        case challenge = "CHALLENGE"
        case accept = "ACCEPT"
        case chooseColor = "CHOOSE_COLOR"
        case chooseSwapTarget = "CHOOSE_SWAP_TARGET"
    }

    let type: Kind
    let playerId: String?
    let cardId: String?
    let chosenColor: CardColor?
    let isJumpIn: Bool?
    let side: DrawSide?
    let catcherId: String?
    let catcherName: String?
    let targetId: String?
    let succeeded: Bool?
    let penaltyPlayerId: String?
    let penaltyCount: Int?
    let color: CardColor?

    /// The acting player regardless of variant shape (CATCH_UNO uses catcherId).
    var actorId: String? { playerId ?? catcherId }
}

struct PlayerViewPlayer: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let hand: [UnoCard]
    let handCount: Int
    let score: Int
    let roundWins: Int?
    let connected: Bool
    let autopilot: Bool
    let calledUno: Bool
    let unoCaught: Bool?
    let eliminated: Bool?
    let teamId: Int?
    let avatarUrl: String?
    let role: String?
    let isBot: Bool
    let botConfig: BotConfig?
}

struct PlayerView: Codable, Equatable, Sendable {
    let viewerId: String
    let phase: GamePhase
    let players: [PlayerViewPlayer]
    let currentPlayerIndex: Int
    let direction: PlayDirection
    let discardPile: [UnoCard]
    let currentColor: CardColor?
    let drawStack: Int
    let pendingPenaltyDraws: Int?
    let deckLeftCount: Int
    let deckRightCount: Int
    let roundNumber: Int
    let winnerId: String?
    let settings: RoomSettings
    let pendingDrawPlayerId: String?
    let lastAction: GameAction?
    let discardPileCount: Int?
    let gameStartedAt: Double?
    let turnStartedAt: Double?

    var currentPlayer: PlayerViewPlayer? {
        players.indices.contains(currentPlayerIndex) ? players[currentPlayerIndex] : nil
    }

    var viewer: PlayerViewPlayer? { players.first { $0.id == viewerId } }

    var topDiscard: UnoCard? { discardPile.last }

    func player(id: String) -> PlayerViewPlayer? { players.first { $0.id == id } }
}

struct RoundEndPayload: Codable, Equatable, Sendable {
    let winnerId: String?
    let scores: [String: Int]
    let roundEndAt: Double?
}

struct GameOverPayload: Codable, Equatable, Sendable {
    let winnerId: String?
    let scores: [String: Int]
    let reason: String?
    let gameOverAt: Double?
}

struct NextRoundVote: Codable, Equatable, Sendable {
    let votes: Int
    let required: Int
    let voters: [String]
}

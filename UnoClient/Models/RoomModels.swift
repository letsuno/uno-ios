import Foundation

struct HouseRules: Codable, Equatable, Sendable {
    var stackDrawTwo = false
    var stackDrawFour = false
    var crossStack = false
    var reverseDeflectDrawTwo = false
    var reverseDeflectDrawFour = false
    var skipDeflect = false
    var zeroRotateHands = false
    var sevenSwapHands = false
    var jumpIn = false
    var multiplePlaySameNumber = false
    var wildFirstTurn = false
    var drawUntilPlayable = false
    var forcedPlayAfterDraw = false
    var handLimit: Int?
    var forcedPlay = false
    var handRevealThreshold: Int?
    var unoPenaltyCount = 2
    var strictUnoCall = false
    var misplayPenalty = false
    var fastMode = false
    var noHints = false
    var elimination = false
    var blitzTimeLimit: Int?
    var revengeMode = false
    var silentUno = false
    var teamMode = false
    var noFunctionCardFinish = false
    var noWildFinish = false
    var doubleScore = false
    var noChallengeWildFour = false
    var blindDraw = false
    var bombCard = false
    var shuffleSeats = false

    static let `default` = HouseRules()

    /// Presets are partial overlays over the defaults, mirroring HOUSE_RULES_PRESETS.
    static let party: HouseRules = {
        var rules = HouseRules()
        rules.stackDrawTwo = true
        rules.stackDrawFour = true
        rules.zeroRotateHands = true
        rules.sevenSwapHands = true
        rules.jumpIn = true
        rules.drawUntilPlayable = true
        return rules
    }()

    static let crazy: HouseRules = {
        var rules = party
        rules.crossStack = true
        rules.reverseDeflectDrawTwo = true
        rules.reverseDeflectDrawFour = true
        rules.skipDeflect = true
        rules.multiplePlaySameNumber = true
        rules.forcedPlayAfterDraw = true
        rules.doubleScore = true
        rules.noChallengeWildFour = true
        return rules
    }()
}

struct RoomSettings: Codable, Equatable, Sendable {
    var turnTimeLimit = 30
    var targetScore = 1000
    var houseRules = HouseRules.default
    var allowSpectators = true
    var spectatorMode = SpectatorMode.hidden

    static let turnTimeLimitOptions = [15, 30, 60]
    static let targetScoreOptions = [200, 300, 500, 1000]
}

enum SpectatorMode: String, Codable, Sendable {
    case full, hidden
}

enum RoomStatus: String, Codable, Sendable {
    case waiting, playing, finished
}

struct RoomData: Codable, Equatable, Sendable {
    let ownerId: String
    let status: RoomStatus
    let settings: RoomSettings
    let createdAt: String?
    let lastActivityAt: String?
}

struct RoomSeatPlayer: Codable, Identifiable, Equatable, Sendable {
    let userId: String
    let nickname: String
    let avatarUrl: String?
    let ready: Bool
    let connected: Bool
    let role: String?
    let isBot: Bool
    let botConfig: BotConfig?

    var id: String { userId }
}

/// A single spectator. The server has two payload shapes for the same set:
/// `seat:updated` carries `userId`, while `room:spectator_*` does not — so
/// `userId` is optional and identity falls back to the nickname.
struct Spectator: Codable, Identifiable, Equatable, Sendable {
    let userId: String?
    let nickname: String
    let avatarUrl: String?
    let connected: Bool

    var id: String { userId ?? nickname }
}

struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let userId: String
    let nickname: String
    let text: String
    let timestamp: Double
    let role: String?
    let isSpectator: Bool?
}

struct ActiveRoomInfo: Codable, Identifiable, Equatable, Sendable {
    struct PlayerInfo: Codable, Equatable, Sendable {
        let nickname: String
        let avatarUrl: String?
    }

    let roomCode: String
    let players: [PlayerInfo]
    let playerCount: Int
    let gameStartedAt: Double?
    let spectatorCount: Int
    let spectatorMode: SpectatorMode?

    var id: String { roomCode }
}

let unoMinPlayers = 2
let unoSeatCount = 10
let unoThrowItems = ["🥚", "🍅", "🌹", "💩", "🐷", "👍", "💖"]

import Foundation

struct User: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let username: String
    let nickname: String
    let avatarUrl: String?
    let role: String?
}

struct AuthConfig: Codable, Equatable, Sendable {
    let devMode: Bool
    let githubClientId: String?
    let turnstileSiteKey: String?
    let passkeyEnabled: Bool?
}

struct AuthResponse: Codable, Sendable {
    let token: String
    let user: User
}

struct ServerInfo: Codable, Equatable, Sendable {
    let name: String
    let version: String
    let motd: String
    let onlinePlayers: Int
    let activeRooms: Int
    let uptime: Double
}

struct ApiKeyIdentity: Codable, Sendable {
    let userId: String
    let username: String
    let nickname: String
    let avatarUrl: String?
    let role: String?
}

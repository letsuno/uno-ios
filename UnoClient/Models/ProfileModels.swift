import Foundation

/// `GET /api/profile` — the database-backed account view. Richer than the JWT-derived
/// `User`: it carries the GitHub binding, and its nickname/avatar are current rather
/// than whatever was minted into the token.
struct ProfileResponse: Decodable, Sendable {
    let user: Profile
}

struct Profile: Codable, Equatable, Sendable {
    let id: String
    let username: String
    let nickname: String
    let avatarUrl: String?
    let githubId: String?
    let role: String?
}

struct AvatarUpdate: Decodable, Sendable {
    let avatarUrl: String?
}

struct PasskeyInfo: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let createdAt: String?
}

struct ApiKeyInfo: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let keyPreview: String
    let createdAt: String?
    let lastUsedAt: String?
}

/// The plaintext key exists only in the create response — the server keeps a hash.
struct CreatedApiKey: Decodable, Identifiable, Sendable {
    let id: String
    let key: String
    let name: String
}

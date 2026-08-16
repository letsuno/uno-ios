import Foundation
import Observation
import UIKit

/// Account self-service: profile, passkeys and API keys. Kept out of `SessionStore`,
/// which owns the connection lifecycle and has no business holding credential lists.
@MainActor
@Observable
final class ProfileStore {
    private let session: SessionStore
    private let client: RestClient
    private let token: String

    private(set) var profile: Profile?
    private(set) var passkeys: [PasskeyInfo] = []
    private(set) var apiKeys: [ApiKeyInfo] = []
    /// Plaintext key from the last create call; the server never returns it again.
    var revealedKey: CreatedApiKey?
    private(set) var isLoading = false
    private(set) var isBusy = false

    init?(session: SessionStore) {
        guard let endpoint = session.endpoint, let token = session.authToken else { return nil }
        self.session = session
        self.client = RestClient(endpoint: endpoint)
        self.token = token
    }

    /// Dev servers expose a read-only `/profile` and register no write routes at all,
    /// so editing has to disappear rather than fail at the network.
    var isEditable: Bool { session.authConfig?.devMode != true }

    var passkeysEnabled: Bool { session.authConfig?.passkeyEnabled == true }

    var avatarURL: URL? { client.endpoint.resolveAvatar(profile?.avatarUrl) }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        profile = try? await client.profile(token: token)
        if passkeysEnabled {
            passkeys = (try? await client.passkeys(token: token)) ?? []
        }
        apiKeys = (try? await client.apiKeys(token: token)) ?? []
    }

    // MARK: - Identity

    func save(nickname rawNickname: String, username rawUsername: String) async {
        let nickname = rawNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let profile else { return }

        if let complaint = Self.nicknameComplaint(nickname) ?? Self.usernameComplaint(username) {
            session.showToast(complaint)
            return
        }

        let newNickname = nickname == profile.nickname ? nil : nickname
        let newUsername = username == profile.username ? nil : username
        guard newNickname != nil || newUsername != nil else { return }

        await mutate {
            try await self.client.updateProfile(
                nickname: newNickname, username: newUsername, token: self.token
            )
            self.session.showToast(String(localized: "Profile updated"), isError: false)
        }
    }

    /// Mirrors the server's rules so a typo costs no round trip.
    static func nicknameComplaint(_ nickname: String) -> String? {
        let cleaned = nickname.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        guard !cleaned.isEmpty, cleaned.count <= 20 else {
            return String(localized: "Nickname must be 1–20 characters")
        }
        guard cleaned.contains(where: { CharacterSet.alphanumerics.contains($0) }) else {
            return String(localized: "Nickname needs at least one letter or digit")
        }
        return nil
    }

    static func usernameComplaint(_ username: String) -> String? {
        guard (3...20).contains(username.count) else {
            return String(localized: "Username must be 3–20 characters")
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard username.unicodeScalars.allSatisfy(allowed.contains) else {
            return String(localized: "Username may only use letters, digits and underscore")
        }
        return nil
    }

    // MARK: - Password

    func setPassword(_ password: String, confirmation: String) async {
        if let complaint = Self.passwordComplaint(password) {
            session.showToast(complaint)
            return
        }
        guard password == confirmation else {
            session.showToast(String(localized: "The two passwords do not match"))
            return
        }
        await mutate {
            try await self.client.setPassword(password, token: self.token)
            self.session.showToast(String(localized: "Password updated"), isError: false)
        }
    }

    static func passwordComplaint(_ password: String) -> String? {
        guard (8...128).contains(password.count) else {
            return String(localized: "Password must be 8–128 characters")
        }
        guard password.contains(where: \.isLetter), password.contains(where: \.isNumber) else {
            return String(localized: "Password needs both letters and digits")
        }
        return nil
    }

    // MARK: - Avatar

    func setAvatar(imageData: Data) async {
        let encoded = await Task.detached(priority: .userInitiated) {
            Self.dataURI(from: imageData)
        }.value
        guard let dataURI = encoded else {
            session.showToast(String(localized: "That image could not be read"))
            return
        }
        await changeAvatar(to: dataURI)
    }

    func removeAvatar() async {
        await changeAvatar(to: "")
    }

    /// No cache eviction needed: the server stamps the avatar URL with the row's
    /// `updatedAt`, so every upload produces a URL nothing has fetched before.
    private func changeAvatar(to dataURI: String) async {
        await mutate { try await self.client.setAvatar(dataURI, token: self.token) }
    }

    /// The server re-crops to 256px, so uploading more than a screen-sized JPEG is
    /// wasted bandwidth against a 10 MB body limit.
    private nonisolated static func dataURI(from data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, 512 / max(longestSide, 1))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rendered = UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.85) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }

    // MARK: - Credentials

    func deletePasskey(id: String) async {
        await mutate { try await self.client.deletePasskey(id: id, token: self.token) }
    }

    func createApiKey(name rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 50 else {
            session.showToast(String(localized: "Key name must be 1–50 characters"))
            return
        }
        await mutate { self.revealedKey = try await self.client.createApiKey(name: name, token: self.token) }
    }

    func deleteApiKey(id: String) async {
        await mutate { try await self.client.deleteApiKey(id: id, token: self.token) }
    }

    /// Every mutation ends the same way: surface the failure, then re-read the server's
    /// state rather than patching the local copy and hoping it matches.
    private func mutate(_ perform: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await perform()
        } catch {
            session.showToast(error.localizedDescription)
            return
        }
        await load()
        await session.refreshUser()
    }
}

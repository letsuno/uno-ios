import Foundation

struct ApiError: Error, LocalizedError {
    let message: String
    let status: Int

    var errorDescription: String? { message }
    var isUnauthorized: Bool { status == 401 }
}

/// `POST /auth/passkey/login-options` — the assertion options plus a server-side
/// challenge handle. Only the fields the native request needs are decoded.
struct PasskeyLoginOptions: Decodable {
    let options: Assertion
    let challengeId: String

    struct Assertion: Decodable {
        let challenge: String  // base64url
        let rpId: String?
    }
}

/// `POST /auth/passkey/register-options` — the raw WebAuthn registration options.
struct PasskeyRegisterOptions: Decodable {
    let challenge: String  // base64url
    let rp: Rp
    let user: RpUser

    struct Rp: Decodable { let id: String? }
    struct RpUser: Decodable {
        let id: String  // base64url user handle
        let name: String
    }
}

struct RestClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let endpoint: ServerEndpoint
    private let transport: Transport

    init(
        endpoint: ServerEndpoint,
        transport: @escaping Transport = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.endpoint = endpoint
        self.transport = transport
    }

    private static let getTimeout: TimeInterval = 10
    private static let postTimeout: TimeInterval = 15

    private struct ErrorBody: Decodable { let error: String? }

    func serverInfo() async throws -> ServerInfo {
        try await get("/server/info")
    }

    /// Ask a candidate server who it is, retrying its plain-http variant when the user
    /// typed no scheme: bare-host input defaults to https, but LAN/dev servers speak http.
    /// Returns the endpoint that actually answered, which may be the insecure one.
    static func reach(
        _ endpoint: ServerEndpoint,
        allowingInsecureFallback: Bool
    ) async throws -> (endpoint: ServerEndpoint, info: ServerInfo) {
        do {
            return (endpoint, try await RestClient(endpoint: endpoint).serverInfo())
        } catch {
            guard allowingInsecureFallback, let insecure = endpoint.insecureVariant,
                let info = try? await RestClient(endpoint: insecure).serverInfo()
            else { throw error }
            return (insecure, info)
        }
    }

    func authConfig() async throws -> AuthConfig {
        try await get("/auth/config")
    }

    func devLogin(username: String) async throws -> AuthResponse {
        try await post("/auth/dev-login", body: ["username": username])
    }

    func login(username: String, password: String) async throws -> AuthResponse {
        try await post("/auth/login", body: ["username": username, "password": password])
    }

    func register(username: String, password: String, nickname: String) async throws -> AuthResponse {
        try await post(
            "/auth/register",
            body: ["username": username, "password": password, "nickname": nickname]
        )
    }

    func me(token: String) async throws -> User {
        try await get("/auth/me", token: token)
    }

    func verifyApiKey(_ key: String) async throws -> ApiKeyIdentity {
        try await post("/api-keys/verify", body: ["key": key])
    }

    // MARK: - Passkey

    func passkeyLoginOptions() async throws -> PasskeyLoginOptions {
        try await post("/auth/passkey/login-options", body: JSONValue.object([:]))
    }

    func passkeyLoginVerify(credential: JSONValue, challengeId: String) async throws -> AuthResponse {
        try await post(
            "/auth/passkey/login-verify",
            body: JSONValue.object(["credential": credential, "challengeId": .string(challengeId)])
        )
    }

    func passkeyRegisterOptions(token: String) async throws -> PasskeyRegisterOptions {
        try await post("/auth/passkey/register-options", body: JSONValue.object([:]), token: token)
    }

    func passkeyRegisterVerify(credential: JSONValue, name: String, token: String) async throws {
        let _: MutationResult = try await post(
            "/auth/passkey/register-verify",
            body: JSONValue.object(["credential": credential, "name": .string(name)]),
            token: token
        )
    }

    private struct MutationResult: Decodable { let success: Bool }

    // MARK: - Profile

    /// Production servers back this with the database; a dev server answers from the
    /// token and registers no write routes at all.
    func profile(token: String) async throws -> Profile {
        let response: ProfileResponse = try await get("/profile", token: token)
        return response.user
    }

    func updateProfile(nickname: String?, username: String?, token: String) async throws {
        var body: [String: String] = [:]
        if let nickname { body["nickname"] = nickname }
        if let username { body["username"] = username }
        let _: MutationResult = try await send("PATCH", "/profile", body: body, token: token)
    }

    /// An empty string clears the avatar; anything else must be a `data:image/…;base64,…`
    /// URI, which the server re-encodes to a 256px WebP.
    @discardableResult
    func setAvatar(_ dataURI: String, token: String) async throws -> String? {
        let result: AvatarUpdate = try await post(
            "/profile/avatar", body: ["avatar": dataURI], token: token
        )
        return result.avatarUrl
    }

    /// Sets or replaces the account password. GitHub-created accounts start without
    /// one, so this is also how they gain a password login.
    func setPassword(_ password: String, token: String) async throws {
        let _: MutationResult = try await post(
            "/auth/set-password", body: ["password": password], token: token
        )
    }

    // MARK: - Credential management

    func passkeys(token: String) async throws -> [PasskeyInfo] {
        try await get("/auth/passkey/list", token: token)
    }

    func deletePasskey(id: String, token: String) async throws {
        let _: MutationResult = try await send("DELETE", "/auth/passkey/\(id)", token: token)
    }

    func apiKeys(token: String) async throws -> [ApiKeyInfo] {
        try await get("/api-keys", token: token)
    }

    func createApiKey(name: String, token: String) async throws -> CreatedApiKey {
        try await post("/api-keys", body: ["name": name], token: token)
    }

    func deleteApiKey(id: String, token: String) async throws {
        let _: MutationResult = try await send("DELETE", "/api-keys/\(id)", token: token)
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String, token: String? = nil) async throws -> T {
        var request = URLRequest(url: endpoint.api(path))
        request.timeoutInterval = Self.getTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return try await run(request)
    }

    /// POST any `Encodable` body — plain `[String: String]` form payloads and the
    /// nested `JSONValue` WebAuthn credential objects share this one path.
    private func post<Body: Encodable, T: Decodable>(
        _ path: String, body: Body, token: String? = nil
    ) async throws -> T {
        try await send("POST", path, body: body, token: token)
    }

    private func send<Body: Encodable, T: Decodable>(
        _ method: String, _ path: String, body: Body, token: String? = nil
    ) async throws -> T {
        var request = mutation(method, path, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await run(request)
    }

    private func send<T: Decodable>(
        _ method: String, _ path: String, token: String? = nil
    ) async throws -> T {
        try await run(mutation(method, path, token: token))
    }

    private func mutation(_ method: String, _ path: String, token: String?) -> URLRequest {
        var request = URLRequest(url: endpoint.api(path))
        request.httpMethod = method
        request.timeoutInterval = Self.postTimeout
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func run<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else {
            throw ApiError(message: "Invalid server response", status: 0)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw ApiError(
                message: message ?? "Server error (\(http.statusCode))",
                status: http.statusCode
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

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
    let endpoint: ServerEndpoint

    private static let getTimeout: TimeInterval = 10
    private static let postTimeout: TimeInterval = 15

    private struct ErrorBody: Decodable { let error: String? }

    func serverInfo() async throws -> ServerInfo {
        try await get("/server/info")
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
        let _: PasskeyMutationResult = try await post(
            "/auth/passkey/register-verify",
            body: JSONValue.object(["credential": credential, "name": .string(name)]),
            token: token
        )
    }

    private struct PasskeyMutationResult: Decodable { let success: Bool }

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
        var request = URLRequest(url: endpoint.api(path))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.postTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        return try await run(request)
    }

    private func run<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
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

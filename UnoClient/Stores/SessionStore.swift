import Foundation
import Observation
import os

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "UnoClient",
    category: "session"
)

/// Connection + auth lifecycle. Owns the socket; room/game events are forwarded
/// to the active `RoomStore`.
@MainActor
@Observable
final class SessionStore {
    enum Stage: Equatable {
        case landing
        case login
        case connecting
        case online
    }

    enum ConnectionStatus: Equatable {
        case connected
        case reconnecting(attempt: Int)
        case offline
    }

    // MARK: - Observable state

    private(set) var stage: Stage = .landing
    private(set) var connectionStatus: ConnectionStatus = .offline
    private(set) var endpoint: ServerEndpoint?
    private(set) var serverInfo: ServerInfo?
    private(set) var authConfig: AuthConfig?
    private(set) var user: User?
    private(set) var lobbyRooms: [ActiveRoomInfo] = []
    private(set) var latencyMs: Int?
    private(set) var room: RoomStore?
    var isBusy = false
    var toast: ToastMessage?

    var savedAddress: String {
        get { UserDefaults.standard.string(forKey: "serverAddress") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "serverAddress") }
    }

    var recentServers: [String] {
        get { UserDefaults.standard.stringArray(forKey: "recentServers") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "recentServers") }
    }

    // MARK: - Private

    private var token: String?
    private var socket: SocketIOClient?
    private var reconnectTask: Task<Void, Never>?
    private var latencyTask: Task<Void, Never>?
    private var intentionalDisconnect = false

    struct ToastMessage: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    init() {
        if !savedAddress.isEmpty,
            let endpoint = ServerEndpoint(userInput: savedAddress),
            Keychain.token(for: endpoint.storageKey) != nil
        {
            Task { await connect(address: savedAddress) }
        }
    }

    func showToast(_ text: String, isError: Bool = true) {
        toast = ToastMessage(text: text, isError: isError)
    }

    // MARK: - Server selection

    /// Validate the link, fetch server info/auth config, then either resume the
    /// stored session or drop into the login stage.
    func connect(address: String) async {
        isBusy = true
        defer { isBusy = false }
        guard let candidate = ServerEndpoint(userInput: address) else {
            showToast(String(localized: "Enter a valid server link"))
            return
        }

        var resolved = candidate
        var info: ServerInfo
        do {
            info = try await RestClient(endpoint: candidate).serverInfo()
        } catch {
            // Bare-host input defaults to https; LAN/dev servers are often plain http.
            let hasExplicitScheme = address.contains("://")
            if !hasExplicitScheme, let insecure = candidate.insecureVariant,
                let fallback = try? await RestClient(endpoint: insecure).serverInfo()
            {
                resolved = insecure
                info = fallback
            } else {
                showToast(String(localized: "Cannot reach server: \(error.localizedDescription)"))
                return
            }
        }

        do {
            let config = try await RestClient(endpoint: resolved).authConfig()
            endpoint = resolved
            serverInfo = info
            authConfig = config
            savedAddress = address
            rememberServer(address)
        } catch {
            showToast(String(localized: "Server rejected auth config request: \(error.localizedDescription)"))
            return
        }

        if let stored = Keychain.token(for: resolved.storageKey) {
            do {
                user = try await RestClient(endpoint: resolved).me(token: stored)
                token = stored
                await openSocket()
                return
            } catch let error as ApiError where error.isUnauthorized {
                Keychain.setToken(nil, for: resolved.storageKey)
            } catch {
                showToast(String(localized: "Sign-in check failed: \(error.localizedDescription)"))
            }
        }
        stage = .login
    }

    private func rememberServer(_ address: String) {
        var list = recentServers.filter { $0 != address }
        list.insert(address, at: 0)
        recentServers = Array(list.prefix(8))
    }

    func backToLanding() {
        disconnectSocket()
        stage = .landing
        user = nil
        token = nil
        authConfig = nil
        serverInfo = nil
        room = nil
    }

    // MARK: - Auth

    func loginDev(username: String) async {
        await authenticate { try await $0.devLogin(username: username) }
    }

    func login(username: String, password: String) async {
        await authenticate { try await $0.login(username: username, password: password) }
    }

    func register(username: String, password: String, nickname: String) async {
        await authenticate {
            try await $0.register(username: username, password: password, nickname: nickname)
        }
    }

    /// `uno_ak_` API keys skip the JWT flow entirely — the key itself is the socket credential.
    func loginApiKey(_ key: String) async {
        guard let endpoint else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let identity = try await RestClient(endpoint: endpoint).verifyApiKey(key)
            user = User(
                id: identity.userId,
                username: identity.username,
                nickname: identity.nickname,
                avatarUrl: identity.avatarUrl,
                role: identity.role
            )
            token = key
            Keychain.setToken(key, for: endpoint.storageKey)
            await openSocket()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    /// Usernameless passkey sign-in: fetch a challenge, satisfy it with a
    /// platform authenticator, then verify server-side for a JWT.
    func loginWithPasskey() async {
        guard let endpoint else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let client = RestClient(endpoint: endpoint)
            let options = try await client.passkeyLoginOptions()
            guard let challenge = Data(base64URLEncoded: options.options.challenge) else {
                throw PasskeyError.malformedChallenge
            }
            let rpId = options.options.rpId ?? endpoint.baseURL.host() ?? ""
            let assertion = try await PasskeyCoordinator.shared.assertion(
                rpId: rpId, challenge: challenge
            )
            let response = try await client.passkeyLoginVerify(
                credential: PasskeyCoordinator.assertionJSON(assertion),
                challengeId: options.challengeId
            )
            user = response.user
            token = response.token
            Keychain.setToken(response.token, for: endpoint.storageKey)
            await openSocket()
        } catch PasskeyError.canceled {
            // User dismissed the sheet — no error surface.
        } catch {
            showToast(error.localizedDescription)
        }
    }

    /// Register a new platform passkey for the signed-in user (requires a token).
    func registerPasskey(name: String) async {
        guard let endpoint, let token else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let client = RestClient(endpoint: endpoint)
            let options = try await client.passkeyRegisterOptions(token: token)
            guard let challenge = Data(base64URLEncoded: options.challenge),
                let userID = Data(base64URLEncoded: options.user.id)
            else { throw PasskeyError.malformedChallenge }
            let rpId = options.rp.id ?? endpoint.baseURL.host() ?? ""
            let registration = try await PasskeyCoordinator.shared.registration(
                rpId: rpId, name: options.user.name, userID: userID, challenge: challenge
            )
            try await client.passkeyRegisterVerify(
                credential: PasskeyCoordinator.registrationJSON(registration),
                name: name, token: token
            )
            showToast(String(localized: "Passkey created"), isError: false)
        } catch PasskeyError.canceled {
            // User dismissed the sheet — no error surface.
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func authenticate(_ perform: (RestClient) async throws -> AuthResponse) async {
        guard let endpoint else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let response = try await perform(RestClient(endpoint: endpoint))
            user = response.user
            token = response.token
            Keychain.setToken(response.token, for: endpoint.storageKey)
            await openSocket()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func logout() {
        if let endpoint { Keychain.setToken(nil, for: endpoint.storageKey) }
        disconnectSocket()
        token = nil
        user = nil
        room = nil
        stage = .login
    }

    // MARK: - Socket lifecycle

    private func openSocket() async {
        guard let endpoint, let token else { return }
        stage = .connecting
        intentionalDisconnect = false

        let client = SocketIOClient(
            onEvent: { [weak self] event, args in
                Task { @MainActor in self?.handle(event: event, args: args) }
            },
            onClose: { [weak self] error in
                Task { @MainActor in self?.socketClosed(error: error) }
            }
        )
        socket = client

        do {
            try await client.connect(base: endpoint.baseURL, authToken: token)
        } catch {
            stage = .login
            if "\(error)".contains("Authentication failed") {
                Keychain.setToken(nil, for: endpoint.storageKey)
                showToast(String(localized: "Session expired, sign in again"))
            } else {
                showToast(String(localized: "Connection failed: \(error.localizedDescription)"))
            }
            return
        }

        connectionStatus = .connected
        stage = .online
        startLatencyProbe()
        await bootstrap()
    }

    /// connect → user:current_room → room:rejoin, mirroring the web client.
    private func bootstrap() async {
        do {
            let current: CurrentRoomAck = try await ack("user:current_room")
            if let code = current.roomCode {
                await rejoin(roomCode: code)
            } else {
                room = nil
            }
        } catch {
            logger.error("bootstrap failed: \(error)")
        }
    }

    private func socketClosed(error: Error?) {
        guard !intentionalDisconnect else { return }
        connectionStatus = .offline
        latencyTask?.cancel()
        latencyMs = nil
        guard stage == .online || stage == .connecting else { return }

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            for attempt in 1...5 {
                guard let self, !Task.isCancelled else { return }
                self.connectionStatus = .reconnecting(attempt: attempt)
                try? await Task.sleep(for: .seconds(min(10, Double(attempt) * 1.5)))
                guard let endpoint = self.endpoint, let token = self.token, let socket = self.socket else { return }
                do {
                    try await socket.connect(base: endpoint.baseURL, authToken: token)
                    self.connectionStatus = .connected
                    self.startLatencyProbe()
                    await self.rebootstrapAfterReconnect()
                    return
                } catch {
                    logger.warning("reconnect attempt \(attempt) failed: \(error)")
                    if "\(error)".contains("Authentication failed") {
                        self.showToast(String(localized: "Session expired, sign in again"))
                        self.logout()
                        return
                    }
                }
            }
            self?.connectionStatus = .offline
            self?.showToast(String(localized: "Lost connection to server"))
        }
    }

    private func rebootstrapAfterReconnect() async {
        if let code = room?.roomCode {
            await rejoin(roomCode: code)
        } else {
            await bootstrap()
        }
    }

    private func disconnectSocket() {
        intentionalDisconnect = true
        reconnectTask?.cancel()
        latencyTask?.cancel()
        latencyMs = nil
        let socket = socket
        Task { await socket?.disconnect() }
        self.socket = nil
        connectionStatus = .offline
    }

    private func startLatencyProbe() {
        latencyTask?.cancel()
        latencyTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let start = ContinuousClock.now
                if let socket = self.socket,
                    (try? await socket.emitWithAck("ping:latency", [], timeout: 8)) != nil
                {
                    self.latencyMs = (ContinuousClock.now - start).milliseconds
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: - Rooms

    func createRoom(settings: RoomSettings) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let response: RoomCreateAck = try await ack("room:create", .from(settings))
            guard response.success, let code = response.roomCode else {
                showToast(response.error ?? String(localized: "Could not create room"))
                return
            }
            // The create ack carries no seat table; a follow-up rejoin returns the
            // authoritative seats/spectators snapshot.
            await rejoin(roomCode: code)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func joinRoom(code rawCode: String) async {
        // Accept pasted web links like https://host/room/ABC123.
        var code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let match = code.firstMatch(of: /\/(?:ROOM|GAME)\/([A-Z0-9]{6})/) {
            code = String(match.1)
        }
        guard code.count == 6 else {
            showToast(String(localized: "Room code is 6 characters"))
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let response: RoomJoinAck = try await ack("room:join", .string(code))
            guard response.success else {
                showToast(response.error ?? String(localized: "Could not join room"))
                return
            }
            enterRoom(
                code: code,
                room: response.room,
                seats: response.seats,
                spectators: response.spectators,
                isSpectator: false
            )
            if response.rejoin == true {
                await rejoin(roomCode: code)
            }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    /// Spectate a live room from the lobby list, or resume after reconnect.
    func rejoin(roomCode: String) async {
        do {
            let response: RoomRejoinAck = try await ack("room:rejoin", .string(roomCode))
            guard response.success else {
                showToast(response.error ?? String(localized: "Could not rejoin room"))
                room = nil
                return
            }
            enterRoom(
                code: roomCode,
                room: response.room,
                seats: response.seats,
                spectators: response.spectators,
                isSpectator: response.isSpectator ?? false
            )
            if let view = response.gameState {
                room?.gameStateReceived(view)
            }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func enterRoom(
        code: String,
        room roomData: RoomData?,
        seats: [RoomSeatPlayer?]?,
        spectators: [Spectator]?,
        isSpectator: Bool
    ) {
        if let existing = room, existing.roomCode == code {
            existing.applySnapshot(room: roomData, seats: seats, spectators: spectators, isSpectator: isSpectator)
        } else {
            room = RoomStore(
                session: self,
                roomCode: code,
                room: roomData,
                seats: seats ?? Array(repeating: nil, count: unoSeatCount),
                spectators: spectators ?? [],
                isSpectator: isSpectator
            )
        }
    }

    func leftRoom() {
        room = nil
    }

    // MARK: - Emit plumbing

    func ack<T: Decodable>(_ event: String, _ args: JSONValue..., timeout: TimeInterval = 10) async throws -> T {
        guard let socket else { throw ApiError(message: "Not connected", status: 0) }
        let response = try await socket.emitWithAck(event, args, timeout: timeout)
        return try (response.first ?? .object([:])).decoded()
    }

    /// Emit expecting a `{ success, error? }` ack; surfaces failure as a toast and returns it.
    @discardableResult
    func perform(_ event: String, _ args: JSONValue...) async -> Bool {
        guard let socket else { return false }
        do {
            let response = try await socket.emitWithAck(event, args, timeout: 10)
            let result: ActionAck = try (response.first ?? .object([:])).decoded()
            if result.success != true, let error = result.error {
                showToast(error)
            }
            return result.success == true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    /// Fire-and-forget — only for events whose server handler has no callback (chat).
    func fire(_ event: String, _ args: JSONValue...) {
        let socket = socket
        Task { try? await socket?.emit(event, args) }
    }

    // MARK: - Event routing

    private func handle(event: String, args: [JSONValue]) {
        switch event {
        case "server:version":
            break
        case "lobby:rooms":
            lobbyRooms = (try? args.first?.decoded(as: [ActiveRoomInfo].self)) ?? lobbyRooms
        case "auth:kicked":
            showToast(String(localized: "Signed in from another device"))
            intentionalDisconnect = true
            logout()
        default:
            room?.handle(event: event, args: args)
        }
    }
}

// MARK: - Ack payloads

struct ActionAck: Decodable {
    let success: Bool?
    let error: String?
}

private struct CurrentRoomAck: Decodable {
    let roomCode: String?
}

private struct RoomCreateAck: Decodable {
    let success: Bool
    let error: String?
    let roomCode: String?
}

private struct RoomJoinAck: Decodable {
    let success: Bool
    let error: String?
    let room: RoomData?
    let seats: [RoomSeatPlayer?]?
    let spectators: [Spectator]?
    let rejoin: Bool?
}

private struct RoomRejoinAck: Decodable {
    let success: Bool
    let error: String?
    let gameState: PlayerView?
    let seats: [RoomSeatPlayer?]?
    let spectators: [Spectator]?
    let room: RoomData?
    let isSpectator: Bool?
}

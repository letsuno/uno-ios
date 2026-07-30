import Foundation

/// Minimal Socket.IO v4 client: Engine.IO v4 over a single WebSocket transport,
/// default namespace, text frames only. Just enough protocol for this app —
/// upgrade dance, binary attachments and multiple namespaces are intentionally absent.
actor SocketIOClient {
    enum SocketError: Error, LocalizedError {
        case invalidURL
        case handshakeFailed(String)
        case connectRejected(String)
        case notConnected
        case ackTimeout(event: String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid server URL"
            case .handshakeFailed(let reason): return "Handshake failed: \(reason)"
            case .connectRejected(let reason): return reason
            case .notConnected: return "Not connected to server"
            case .ackTimeout(let event): return "Server did not respond to \(event)"
            }
        }
    }

    /// Delivered on no particular actor; the owner is expected to hop to MainActor.
    private let onEvent: @Sendable (String, [JSONValue]) -> Void
    private let onClose: @Sendable (Error?) -> Void

    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var ackContinuations: [Int: CheckedContinuation<[JSONValue], Error>] = [:]
    private var nextAckID = 0
    private var connected = false
    private var lastActivity = Date()
    private var pingInterval: TimeInterval = 25
    private var pingTimeout: TimeInterval = 20

    init(
        onEvent: @escaping @Sendable (String, [JSONValue]) -> Void,
        onClose: @escaping @Sendable (Error?) -> Void
    ) {
        self.onEvent = onEvent
        self.onClose = onClose
    }

    // MARK: - Lifecycle

    /// `base` is the http(s) server root; `authToken` becomes the Socket.IO `auth.token`.
    func connect(base: URL, authToken: String) async throws {
        disconnectInternal(error: nil, notify: false)
        var didConnect = false
        defer {
            if !didConnect {
                disconnectInternal(error: nil, notify: false)
            }
        }

        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw SocketError.invalidURL
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + "/socket.io/"
        components.queryItems = [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket"),
        ]
        guard let url = components.url else { throw SocketError.invalidURL }

        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 8 * 1024 * 1024
        self.task = task
        task.resume()

        // Engine.IO open packet: "0{...}"
        let open = try await receiveText()
        guard open.hasPrefix("0"), let openData = open.dropFirst().data(using: .utf8),
            let handshake = try? JSONDecoder().decode(EngineHandshake.self, from: openData)
        else {
            throw SocketError.handshakeFailed("unexpected open packet")
        }
        pingInterval = TimeInterval(handshake.pingInterval) / 1000
        pingTimeout = TimeInterval(handshake.pingTimeout) / 1000

        // Socket.IO CONNECT with auth payload: "40{"token":"..."}"
        let auth = try String(data: JSONEncoder().encode(["token": authToken]), encoding: .utf8) ?? "{}"
        try await send(text: "40" + auth)

        // Wait for CONNECT ack "40{sid}" — the server may interleave engine pings.
        while true {
            let message = try await receiveText()
            if message == "2" {
                try await send(text: "3")
                continue
            }
            if message.hasPrefix("40") { break }
            if message.hasPrefix("44") {
                let body = String(message.dropFirst(2))
                let reason =
                    (try? JSONDecoder().decode([String: JSONValue].self, from: Data(body.utf8)))?["message"]?
                    .stringValue ?? body
                throw SocketError.connectRejected(reason)
            }
            // Anything else pre-connect is unexpected but non-fatal; keep waiting.
        }

        connected = true
        didConnect = true
        lastActivity = Date()
        startReceiveLoop()
        startWatchdog()
    }

    func disconnect() {
        if connected, let task { task.send(.string("41"), completionHandler: { _ in }) }
        disconnectInternal(error: nil, notify: false)
    }

    var isConnected: Bool { connected }

    // MARK: - Emit

    func emit(_ event: String, _ args: [JSONValue] = []) async throws {
        guard connected else { throw SocketError.notConnected }
        try await send(text: "42" + encodePayload(event: event, args: args))
    }

    func emitWithAck(_ event: String, _ args: [JSONValue] = [], timeout: TimeInterval = 10) async throws -> [JSONValue]
    {
        guard connected else { throw SocketError.notConnected }
        let ackID = nextAckID
        nextAckID += 1
        let packet = try "42\(ackID)" + encodePayload(event: event, args: args)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Register before sending: a fast server may acknowledge as soon as
                // URLSession resumes this actor after `send`.
                ackContinuations[ackID] = continuation
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.send(text: packet)
                        try await Task.sleep(for: .seconds(timeout))
                        await self.failAck(id: ackID, error: SocketError.ackTimeout(event: event))
                    } catch is CancellationError {
                        // The caller cancellation handler owns this completion path.
                    } catch {
                        await self.failAck(id: ackID, error: error)
                    }
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.failAck(id: ackID, error: CancellationError())
            }
        }
    }

    // MARK: - Internals

    private struct EngineHandshake: Decodable {
        let sid: String
        let pingInterval: Int
        let pingTimeout: Int
    }

    private func encodePayload(event: String, args: [JSONValue]) throws -> String {
        let payload = [JSONValue.string(event)] + args
        let data = try JSONEncoder().encode(payload)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func send(text: String) async throws {
        guard let task else { throw SocketError.notConnected }
        try await task.send(.string(text))
    }

    private func receiveText() async throws -> String {
        guard let task else { throw SocketError.notConnected }
        switch try await task.receive() {
        case .string(let text): return text
        case .data(let data): return String(data: data, encoding: .utf8) ?? ""
        @unknown default: return ""
        }
    }

    private func startReceiveLoop() {
        receiveLoop = Task { [weak self] in
            while let self {
                do {
                    let text = try await self.receiveText()
                    await self.handle(text: text)
                } catch {
                    await self.disconnectInternal(error: error, notify: true)
                    return
                }
                if await !self.connected { return }
            }
        }
    }

    private func startWatchdog() {
        let limit = pingInterval + pingTimeout + 5
        watchdog = Task { [weak self] in
            while let self, await self.connected {
                try? await Task.sleep(for: .seconds(limit / 2))
                let last = await self.lastActivityDate()
                if Date().timeIntervalSince(last) > limit {
                    await self.disconnectInternal(
                        error: SocketError.handshakeFailed("connection timed out"), notify: true)
                    return
                }
            }
        }
    }

    private func lastActivityDate() -> Date { lastActivity }

    private func handle(text: String) async {
        lastActivity = Date()
        guard let first = text.first else { return }
        switch first {
        case "2":  // engine ping
            try? await send(text: "3")
        case "1":  // engine close
            disconnectInternal(error: nil, notify: true)
        case "4":  // socket.io packet
            handleSocketPacket(String(text.dropFirst()))
        default:
            break
        }
    }

    private func handleSocketPacket(_ packet: String) {
        guard let type = packet.first else { return }
        let rest = String(packet.dropFirst())
        switch type {
        case "2": dispatch(body: rest, isAck: false)
        case "3": dispatch(body: rest, isAck: true)
        case "1":  // server-initiated namespace disconnect
            disconnectInternal(error: nil, notify: true)
        default:
            break
        }
    }

    private func dispatch(body: String, isAck: Bool) {
        // Optional leading ack id digits, then a JSON array.
        var ackID: Int?
        var jsonPart = Substring(body)
        let digits = jsonPart.prefix(while: \.isNumber)
        if !digits.isEmpty, let value = Int(digits) {
            ackID = value
            jsonPart = jsonPart.dropFirst(digits.count)
        }
        guard let args = try? JSONDecoder().decode([JSONValue].self, from: Data(jsonPart.utf8)) else { return }

        if isAck {
            guard let ackID, let continuation = ackContinuations.removeValue(forKey: ackID) else { return }
            continuation.resume(returning: args)
        } else {
            guard case .string(let event)? = args.first else { return }
            // Events with server-requested acks are acknowledged with an empty payload.
            if let ackID, connected, let task {
                task.send(.string("43\(ackID)[]"), completionHandler: { _ in })
            }
            onEvent(event, Array(args.dropFirst()))
        }
    }

    private func failAck(id: Int, error: Error) {
        if let continuation = ackContinuations.removeValue(forKey: id) {
            continuation.resume(throwing: error)
        }
    }

    private func disconnectInternal(error: Error?, notify: Bool) {
        let wasConnected = connected || task != nil
        connected = false
        receiveLoop?.cancel()
        receiveLoop = nil
        watchdog?.cancel()
        watchdog = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        for continuation in ackContinuations.values {
            continuation.resume(throwing: error ?? SocketError.notConnected)
        }
        ackContinuations.removeAll()
        if notify, wasConnected { onClose(error) }
    }
}

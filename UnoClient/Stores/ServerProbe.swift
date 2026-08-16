import Foundation
import Observation

/// Landing-screen reachability: no socket exists yet, so liveness and round-trip time
/// come from timing `GET /api/server/info` per candidate address.
@MainActor
@Observable
final class ServerProbe {
    enum Reading: Equatable {
        case probing
        case reachable(latencyMs: Int)
        case unreachable
    }

    private(set) var readings: [String: Reading] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    func reading(for address: String) -> Reading? {
        readings[address]
    }

    /// Idempotent per address: a row that reappears keeps its last result instead of
    /// flashing back to `.probing`.
    func measure(_ address: String) {
        guard tasks[address] == nil else { return }
        guard let endpoint = ServerEndpoint(userInput: address) else {
            readings[address] = .unreachable
            return
        }
        if readings[address] == nil { readings[address] = .probing }

        tasks[address] = Task { [weak self] in
            let reading = await Self.measure(endpoint, allowingInsecureFallback: !address.contains("://"))
            guard let self, !Task.isCancelled else { return }
            readings[address] = reading
            tasks[address] = nil
        }
    }

    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }

    /// The first request pays DNS and TLS setup, so it only resolves the endpoint and
    /// warms the connection; the second one is the number worth showing.
    private static func measure(
        _ endpoint: ServerEndpoint,
        allowingInsecureFallback: Bool
    ) async -> Reading {
        guard
            let resolved = try? await RestClient.reach(
                endpoint, allowingInsecureFallback: allowingInsecureFallback
            ).endpoint
        else { return .unreachable }

        let start = ContinuousClock.now
        guard (try? await RestClient(endpoint: resolved).serverInfo()) != nil else {
            return .unreachable
        }
        return .reachable(latencyMs: (ContinuousClock.now - start).milliseconds)
    }
}

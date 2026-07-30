#if DEBUG
    import Foundation

    /// Debug-build automation seam for simulator verification. Driven purely by
    /// environment variables (passed via `simctl launch` SIMCTL_CHILD_*):
    ///
    /// - UNO_TEST_SERVER + UNO_TEST_TOKEN: seed the saved address and keychain
    ///   token so the app auto-connects and signs in on launch.
    /// - UNO_TEST_FLOW=quickgame: once online, create a room, add three bots,
    ///   start the game and enable autopilot so the match plays itself.
    @MainActor
    enum TestDrive {
        static func seedIfRequested() {
            let env = ProcessInfo.processInfo.environment
            guard let server = env["UNO_TEST_SERVER"], let token = env["UNO_TEST_TOKEN"],
                let endpoint = ServerEndpoint(userInput: server)
            else { return }
            UserDefaults.standard.set(server, forKey: "serverAddress")
            Keychain.setToken(token, for: endpoint.storageKey)
        }

        static func driveIfRequested(_ session: SessionStore) {
            guard ProcessInfo.processInfo.environment["UNO_TEST_FLOW"] == "quickgame" else {
                return
            }
            Task {
                while session.stage != .online {
                    try? await Task.sleep(for: .seconds(0.5))
                }
                // Drop any auto-rejoined stale room so each launch starts clean.
                if session.room != nil {
                    await session.room?.leaveRoom()
                    try? await Task.sleep(for: .seconds(0.8))
                }
                await session.createRoom(settings: RoomSettings())
                guard let room = session.room else { return }
                for _ in 0..<3 {
                    await room.addBot(difficulty: .normal, seatIndex: nil)
                    try? await Task.sleep(for: .seconds(0.5))
                }
                try? await Task.sleep(for: .seconds(0.6))
                // Server's game:start requires every seated player ready (owner included).
                await room.setReady(true)
                try? await Task.sleep(for: .seconds(0.4))
                var attempts = 0
                while room.game == nil && attempts < 20 {
                    await room.startGame()
                    try? await Task.sleep(for: .seconds(1.0))
                    attempts += 1
                }
            }
        }
    }
#endif

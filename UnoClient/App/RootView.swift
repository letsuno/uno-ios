import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    /// Which screen the session state adds up to. Named separately from `Stage` because
    /// one stage — `.online` — covers three of them, and because the transition needs a
    /// single value to animate against.
    private enum Destination: Hashable {
        case landing
        case login
        case lobby
        case room(String)
        case game(String)
    }

    /// An occurrence of a screen, not just the screen's semantic destination. Reusing
    /// `.login` as a SwiftUI identity lets a recently removed login view be reinserted
    /// by reversing its removal transition, which makes it return from the leading edge.
    private struct Presentation: Identifiable {
        let id = UUID()
        let destination: Destination
    }

    /// Where to keep showing while the socket comes up. Connecting is not a screen of
    /// its own — making it one split "join a server" into two pushes, where entering a
    /// room or a game is a single one.
    @State private var settledDestination = Destination.landing

    /// Screen presentation is deliberately separate from session state. A second
    /// destination can arrive while the first transition is still moving (most easily
    /// by tapping Connect and Back quickly); changing the rendered destination again
    /// would make SwiftUI reverse the in-flight animation from its presentation state.
    @State private var presentation = Presentation(destination: .landing)
    @State private var pendingDestination: Destination?
    @State private var isScreenTransitioning = false

    private static let screenAnimation = Animation.smooth(duration: 0.4)

    var body: some View {
        // The safe area is left to the system. Trimming it was tried and reverted: in
        // landscape the ~59pt inset is the sensor housing physically covering the
        // display, and the remaining edges reserve at most the home indicator's ~21pt,
        // so there is nothing worth reclaiming. Screens keep their margins modest
        // through `screenInsets()` instead.
        let destination = destination
        ZStack {
            UnoBackground()

            screen(presentation.destination)
                // The identity boundary must sit inside the transition modifier.
                // Replacing the outer `_IDView` then inserts/removes exactly the node
                // carrying this transition, independent of each screen's root type.
                .id(presentation.id)
                // Spelled out rather than `.push(from:)`: that transition pairs its
                // own insertion and removal internally, and across two different
                // screen types the pairing was not stable — the same change slid in
                // from either side run to run. Both halves are pinned here.
                //
                // One direction for every change, forward and back alike. A
                // depth-aware version is not expressible this way: the outgoing
                // screen animates with the transition it declared on its own last
                // render, so going back slid both screens the same way.
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
        }
        .onChange(of: destination) { _, new in
            settledDestination = new
            present(new)
        }
        .overlay { connectingVeil }
        .overlay(alignment: .top) { connectionBanner }
        .toastOverlay(session)
        .preferredColorScheme(.dark)
    }

    private var destination: Destination {
        switch session.stage {
        case .landing: return .landing
        case .login: return .login
        case .connecting: return settledDestination
        case .online:
            guard let room = session.room else { return .lobby }
            return room.game == nil ? .room(room.roomCode) : .game(room.roomCode)
        }
    }

    /// Serializes root-screen changes. State may still advance for non-UI reasons while
    /// a transition is running, so retain the latest target and present it afterwards.
    private func present(_ destination: Destination) {
        guard !isScreenTransitioning else {
            pendingDestination = destination == presentation.destination ? nil : destination
            return
        }
        guard presentation.destination != destination else { return }

        isScreenTransitioning = true
        withAnimation(Self.screenAnimation, completionCriteria: .removed) {
            presentation = Presentation(destination: destination)
        } completion: {
            isScreenTransitioning = false
            guard let queuedDestination = pendingDestination else { return }
            pendingDestination = nil
            present(queuedDestination)
        }
    }

    @ViewBuilder
    private func screen(_ destination: Destination) -> some View {
        switch destination {
        case .landing:
            ConnectView()
        case .login:
            LoginView()
        case .lobby:
            LobbyView()
        case .room:
            if let room = session.room {
                RoomView(room: room)
            }
        case .game:
            if let game = session.room?.game {
                GameView(game: game)
            }
        }
    }

    /// Scoped to its own overlay so its fade never becomes the animation the screen
    /// transition inherits.
    private var connectingVeil: some View {
        ZStack {
            if session.stage == .connecting {
                Rectangle()
                    .fill(.black.opacity(0.4))
                    .ignoresSafeArea()
                ProgressView("Connecting…")
                    .controlSize(.large)
                    .padding(24)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: session.stage)
    }

    @ViewBuilder
    private var connectionBanner: some View {
        if session.stage == .online, case .reconnecting(let attempt) = session.connectionStatus {
            Label("Reconnecting (\(attempt)/5)…", systemImage: "wifi.exclamationmark")
                .font(.footnote.weight(.medium))
                .glassChip(horizontal: 14, vertical: 8)
                .padding(.top, 54)
        }
    }
}

import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        ZStack {
            UnoBackground()

            switch session.stage {
            case .landing:
                ConnectView()
            case .login:
                LoginView()
            case .connecting:
                ProgressView("Connecting…")
                    .controlSize(.large)
            case .online:
                if let room = session.room {
                    if let game = room.game {
                        GameView(game: game)
                    } else {
                        RoomView(room: room)
                    }
                } else {
                    LobbyView()
                }
            }
        }
        .overlay(alignment: .top) { connectionBanner }
        .toastOverlay(session)
        .preferredColorScheme(.dark)
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

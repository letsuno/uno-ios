import SwiftUI
import UIKit

/// Post-login home screen: player header, room creation / joining, live games list.
struct LobbyView: View {
    @Environment(SessionStore.self) private var session

    @State private var joinCode = ""
    @State private var showCreateSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(session.serverInfo?.name ?? "Lobby")
                        .font(.largeTitle.weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    HStack(alignment: .top, spacing: 24) {
                        VStack(spacing: 16) {
                            header
                            actions
                        }
                        .frame(maxWidth: .infinity)
                        liveGames
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.clear)
            .overlay(alignment: .topTrailing) {
                Menu {
                    if session.authConfig?.passkeyEnabled == true {
                        Button {
                            Task { await session.registerPasskey(name: UIDevice.current.name) }
                        } label: {
                            Label("Create Passkey", systemImage: "person.badge.key.fill")
                        }
                        .disabled(session.isBusy)
                        Divider()
                    }
                    Button(role: .destructive) {
                        session.logout()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    Button {
                        session.backToLanding()
                    } label: {
                        Label("Switch server", systemImage: "server.rack")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .buttonStyle(.glass)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCreateSheet) {
                CreateRoomSheet()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    AvatarView(
                        url: session.endpoint?.resolveAvatar(session.user?.avatarUrl),
                        name: session.user?.nickname ?? "?",
                        size: 52
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.user?.nickname ?? "Player")
                            .font(.title3.weight(.semibold))
                        if let motd = session.serverInfo?.motd, !motd.isEmpty {
                            Text(motd)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    latencyChip
                }
                if let info = session.serverInfo {
                    HStack(spacing: 14) {
                        Label("\(info.onlinePlayers) online", systemImage: "person.2.fill")
                        Label("\(info.activeRooms) rooms", systemImage: "square.grid.2x2.fill")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var latencyChip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(latencyColor)
                .frame(width: 7, height: 7)
            Text(session.latencyMs.map { "\($0) ms" } ?? "-- ms")
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
        }
        .glassChip(horizontal: 9, vertical: 5)
    }

    private var latencyColor: Color {
        guard let ms = session.latencyMs else { return .gray }
        if ms < 50 { return .green }
        if ms <= 150 { return .yellow }
        return .red
    }

    // MARK: - Primary actions

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                showCreateSheet = true
            } label: {
                Label("Create Room", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)

            HStack(spacing: 10) {
                TextField("Room code or link", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .glassChip(horizontal: 14, vertical: 12)
                    .onSubmit(join)

                Button(action: join) {
                    Label("Join", systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .disabled(joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isBusy)
            }
        }
    }

    private func join() {
        let raw = joinCode
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // `joinRoom` handles uppercasing and pasted room links itself.
        Task { await session.joinRoom(code: raw) }
    }

    // MARK: - Live games

    private var liveGames: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Live games")
                .font(.headline)
                .padding(.horizontal, 4)

            if session.lobbyRooms.isEmpty {
                GlassPanel {
                    Text("No games in progress. Create a room to get one going.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                ForEach(session.lobbyRooms) { info in
                    LiveGameCard(info: info)
                }
            }
        }
    }
}

private struct LiveGameCard: View {
    @Environment(SessionStore.self) private var session
    let info: ActiveRoomInfo

    var body: some View {
        GlassPanel(cornerRadius: 20) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(info.roomCode)
                        .font(.headline.monospaced())
                    Text(playerLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 12) {
                        Label("\(info.playerCount)", systemImage: "person.2")
                        Label("\(info.spectatorCount)", systemImage: "eye")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Button {
                    Task { await session.rejoin(roomCode: info.roomCode) }
                } label: {
                    Label("Spectate", systemImage: "eye.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var playerLine: String {
        let names = info.players.prefix(4).map(\.nickname)
        guard !names.isEmpty else { return String(localized: "No players") }
        let joined = names.joined(separator: ", ")
        return info.playerCount > names.count ? joined + ", …" : joined
    }
}

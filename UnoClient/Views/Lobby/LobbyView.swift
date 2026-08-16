import SwiftUI

/// Post-login home screen: player header, room creation / joining, live games list.
struct LobbyView: View {
    @Environment(SessionStore.self) private var session

    @State private var joinCode = ""
    @State private var showCreateSheet = false
    @State private var showProfileSheet = false

    var body: some View {
        NavigationStack {
            // The page itself does not scroll: the account column is fixed and only the
            // live-games list, whose length is unbounded, scrolls inside its own column.
            VStack(alignment: .leading, spacing: 12) {
                Text(session.serverInfo?.name ?? "Lobby")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .padding(.trailing, 44)

                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 14) {
                        header
                        actions
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    liveGames
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: UnoLayout.contentWidth)
            .screenInsets()
            .frame(maxWidth: .infinity)
            .scrollDismissesKeyboard(.interactively)
            .unoBackdrop()
            .overlay(alignment: .topTrailing) {
                Menu {
                    Button {
                        showProfileSheet = true
                    } label: {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                    Divider()
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
                .screenInsets()
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCreateSheet) {
                CreateRoomSheet()
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileView()
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
                    LatencyLabel(milliseconds: session.latencyMs)
                        .glassChip(horizontal: 9, vertical: 5)
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
            .actionWidth()
            .frame(maxWidth: .infinity, alignment: .leading)

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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if session.lobbyRooms.isEmpty {
                GlassPanel {
                    Text("No games in progress. Create a room to get one going.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(session.lobbyRooms) { info in
                            LiveGameCard(info: info)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            Spacer(minLength: 0)
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

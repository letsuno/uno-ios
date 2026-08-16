import SwiftUI

/// Landing screen: pick a server and connect.
struct ConnectView: View {
    @Environment(SessionStore.self) private var session
    @State private var address = ""
    @State private var didPrefill = false
    @State private var isCustomServer = false
    @State private var probe = ServerProbe()
    @FocusState private var isAddressFieldFocused: Bool

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The default server needs no input, so only the custom branch can be empty.
    private var connectTarget: String {
        isCustomServer ? trimmedAddress : ServerEndpoint.defaultAddress
    }

    var body: some View {
        // Centred with spacers rather than a `GeometryReader`-driven `minHeight`. The
        // geometry reader anchored its content to the top-left and reported a size that
        // is not settled on the first frame, which made this screen enter and leave a
        // transition from an inconsistent position. Every other screen is a fixed layout
        // with scrolling confined to the one list that can outgrow it; this matches.
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 32) {
                hero
                    .frame(maxWidth: .infinity)
                connectPanel
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: UnoLayout.contentWidth)
            .screenInsets()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !didPrefill else { return }
            didPrefill = true
            let saved = session.savedAddress
            guard ServerEndpoint(userInput: saved)?.isDefault != true else { return }
            address = saved
            isCustomServer = true
        }
        .onChange(of: isCustomServer) { _, isCustom in
            if isCustom {
                isAddressFieldFocused = true
            }
        }
        .onDisappear { probe.cancelAll() }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(Self.wordmark, id: \.letter) { card in
                    wordmarkLetter(card.letter, color: card.color)
                }
            }
            Text("Online multiplayer client")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private static let wordmark: [(letter: String, color: Color)] = [
        ("U", Color(red: 0.90, green: 0.22, blue: 0.27)),
        ("N", Color(red: 0.98, green: 0.75, blue: 0.14)),
        ("O", Color(red: 0.22, green: 0.70, blue: 0.40)),
        ("!", Color(red: 0.20, green: 0.45, blue: 0.95)),
    ]

    /// `Text` cannot take `glassEffect` — that API needs a `Shape`. So the glass is a
    /// tinted slab masked down to the glyph: the letter itself refracts the backdrop
    /// instead of sitting on a card.
    private func wordmarkLetter(_ letter: String, color: Color) -> some View {
        let glyph = Text(letter)
            .font(.system(size: 76, weight: .black, design: .rounded))

        return Color.clear
            .frame(width: letter == "!" ? 34 : 62, height: 92)
            .glassEffect(.regular.tint(color.opacity(0.75)), in: .rect)
            .mask { glyph }
            .shadow(color: color.opacity(0.45), radius: 14, y: 4)
    }

    // MARK: - Connect form

    private var connectPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label("Server", systemImage: "server.rack")
                    .font(.headline)

                if isCustomServer {
                    customServerControls
                } else {
                    defaultServerRow
                }

                // Connect and its escape hatch share one row: two capped buttons read as
                // controls, where one full-width button per line reads as a banner.
                HStack(spacing: 10) {
                    Button(action: connect) {
                        HStack(spacing: 8) {
                            if session.isBusy {
                                ProgressView()
                            } else {
                                Image(systemName: "bolt.horizontal.fill")
                            }
                            Text("Connect")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(connectTarget.isEmpty || session.isBusy)

                    Button {
                        withAnimation(.snappy) { isCustomServer.toggle() }
                    } label: {
                        Label(
                            isCustomServer ? "Default" : "Other server",
                            systemImage: isCustomServer ? "arrow.uturn.backward" : "chevron.down"
                        )
                        .font(.subheadline)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .disabled(session.isBusy)
                }
            }
        }
    }

    private var defaultServerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.tint)
            Text("Official server")
                .lineLimit(1)
            Spacer(minLength: 0)
            probeReadout(for: ServerEndpoint.defaultAddress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Server")
        .accessibilityValue("Official server")
        .task { probe.measure(ServerEndpoint.defaultAddress) }
    }

    /// Liveness for one candidate server, measured before any socket exists.
    @ViewBuilder
    private func probeReadout(for address: String) -> some View {
        switch probe.reading(for: address) {
        case .reachable(let latencyMs):
            LatencyLabel(milliseconds: latencyMs)
        case .unreachable:
            Label("Offline", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
        case .probing, nil:
            ProgressView()
                .controlSize(.mini)
        }
    }

    private var customServerControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("play.example.com or http://192.168.1.10:3001", text: $address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .submitLabel(.go)
                .focused($isAddressFieldFocused)
                .onSubmit(connect)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))

            Text("Bare hosts default to https. Plain-http LAN servers are detected automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !session.recentServers.isEmpty {
                recentPanel
            }
        }
    }

    private func connect() {
        let target = connectTarget
        guard !target.isEmpty, !session.isBusy else { return }
        isAddressFieldFocused = false
        Task { await session.connect(address: target) }
    }

    // MARK: - Recent servers

    private var recentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent servers")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            // The only part of this screen whose height is unbounded, so it is the only
            // part that scrolls.
            ScrollView {
                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        ForEach(session.recentServers, id: \.self) { server in
                            recentRow(server)
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 160)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentRow(_ server: String) -> some View {
        HStack(spacing: 12) {
            Button {
                address = server
                Task { await session.connect(address: server) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                    Text(server)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    probeReadout(for: server)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy)
            .task { probe.measure(server) }

            Button {
                session.recentServers = session.recentServers.filter { $0 != server }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(server)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

import SwiftUI

/// Landing screen: pick a server and connect.
struct ConnectView: View {
    @Environment(SessionStore.self) private var session
    @State private var address = ""
    @State private var didPrefill = false

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 32) {
                hero
                    .frame(maxWidth: .infinity)
                VStack(spacing: 20) {
                    connectPanel
                    if !session.recentServers.isEmpty {
                        recentPanel
                    }
                    Text("Bare hosts default to https. Plain-http LAN servers are detected automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 860)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            guard !didPrefill else { return }
            didPrefill = true
            address = session.savedAddress
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 10) {
            HStack(spacing: 2) {
                wordmarkLetter("U", color: Color(red: 0.90, green: 0.22, blue: 0.27))
                wordmarkLetter("N", color: Color(red: 0.98, green: 0.75, blue: 0.14))
                wordmarkLetter("O", color: Color(red: 0.22, green: 0.70, blue: 0.40))
                wordmarkLetter("!", color: Color(red: 0.20, green: 0.45, blue: 0.95))
            }
            Text("Online multiplayer client")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    private func wordmarkLetter(_ letter: String, color: Color) -> some View {
        Text(letter)
            .font(.system(size: 72, weight: .black, design: .rounded))
            .foregroundStyle(color.gradient)
            .shadow(color: color.opacity(0.45), radius: 14, y: 4)
    }

    // MARK: - Connect form

    private var connectPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label("Server", systemImage: "server.rack")
                    .font(.headline)

                TextField("play.example.com or http://192.168.1.10:3001", text: $address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .submitLabel(.go)
                    .onSubmit(connect)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))

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
                .disabled(trimmedAddress.isEmpty || session.isBusy)
            }
        }
    }

    private func connect() {
        let target = trimmedAddress
        guard !target.isEmpty, !session.isBusy else { return }
        Task { await session.connect(address: target) }
    }

    // MARK: - Recent servers

    private var recentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent servers")
                .font(.headline)
                .padding(.horizontal, 6)

            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    ForEach(session.recentServers, id: \.self) { server in
                        recentRow(server)
                    }
                }
            }
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy)

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

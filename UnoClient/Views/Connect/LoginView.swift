import SwiftUI

/// Sign-in screen shown after a server has been reached: dev login, password
/// auth with registration, or a raw API key.
struct LoginView: View {
    private enum AuthTab: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case register = "Register"
        var id: String { rawValue }
    }

    @Environment(SessionStore.self) private var session

    @State private var tab: AuthTab = .signIn
    @State private var username = ""
    @State private var password = ""
    @State private var nickname = ""
    @State private var apiKey = ""
    @State private var apiKeyExpanded = false

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 32) {
                VStack(spacing: 16) {
                    header
                    serverCard
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 20) {
                    if session.authConfig?.devMode == true {
                        devPanel
                    } else {
                        credentialsPanel
                        apiKeyPanel
                        if session.authConfig?.turnstileSiteKey != nil {
                            turnstileWarning
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 860)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                session.backToLanding()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.glass)
            Spacer()
        }
        .padding(.top, 8)
    }

    private var serverCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.serverInfo?.name ?? "Server")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if let info = session.serverInfo {
                        Label("\(info.onlinePlayers)", systemImage: "person.2.fill")
                        Label("\(info.activeRooms)", systemImage: "square.grid.2x2.fill")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                if let motd = session.serverInfo?.motd, !motd.isEmpty {
                    Text(motd)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Label(session.savedAddress, systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Dev mode

    private var devPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label("Quick sign-in", systemImage: "hammer.fill")
                    .font(.headline)

                inputField {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(submitDev)
                }

                submitButton("Enter", enabled: !trimmedUsername.isEmpty, action: submitDev)

                Text("Development server — any username signs in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func submitDev() {
        let name = trimmedUsername
        guard !name.isEmpty, !session.isBusy else { return }
        Task { await session.loginDev(username: name) }
    }

    // MARK: - Password auth

    private var credentialsPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Mode", selection: $tab) {
                    ForEach(AuthTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                inputField {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                }

                if tab == .register {
                    inputField {
                        TextField("Nickname", text: $nickname)
                    }
                }

                inputField {
                    SecureField("Password", text: $password)
                        .textContentType(tab == .register ? .newPassword : .password)
                        .submitLabel(.go)
                        .onSubmit(submitCredentials)
                }

                if tab == .register {
                    Text("Password needs at least 8 characters with letters and digits. Nickname 1–20 characters.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                submitButton(
                    tab == .signIn ? "Sign in" : "Create account",
                    enabled: credentialsValid,
                    action: submitCredentials
                )

                if tab == .signIn, session.authConfig?.passkeyEnabled == true {
                    Button {
                        Task { await session.loginWithPasskey() }
                    } label: {
                        Label("Sign in with Passkey", systemImage: "person.badge.key.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .disabled(session.isBusy)
                }
            }
        }
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var registerPasswordValid: Bool {
        password.count >= 8
            && password.contains(where: \.isLetter)
            && password.contains(where: \.isNumber)
    }

    private var credentialsValid: Bool {
        switch tab {
        case .signIn:
            return !trimmedUsername.isEmpty && !password.isEmpty
        case .register:
            return !trimmedUsername.isEmpty
                && (1...20).contains(trimmedNickname.count)
                && registerPasswordValid
        }
    }

    private func submitCredentials() {
        guard credentialsValid, !session.isBusy else { return }
        let name = trimmedUsername
        let pass = password
        switch tab {
        case .signIn:
            Task { await session.login(username: name, password: pass) }
        case .register:
            let nick = trimmedNickname
            Task { await session.register(username: name, password: pass, nickname: nick) }
        }
    }

    // MARK: - API key

    private var apiKeyPanel: some View {
        GlassPanel {
            DisclosureGroup(isExpanded: $apiKeyExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    inputField {
                        SecureField("uno_ak_…", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit(submitApiKey)
                    }
                    submitButton("Sign in with key", enabled: apiKeyValid, action: submitApiKey)
                }
                .padding(.top, 12)
            } label: {
                Label("Use API key", systemImage: "key.fill")
                    .font(.headline)
            }
            .tint(.primary)
        }
    }

    private var apiKeyValid: Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("uno_ak_")
    }

    private func submitApiKey() {
        guard apiKeyValid, !session.isBusy else { return }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await session.loginApiKey(key) }
    }

    // MARK: - Turnstile notice

    private var turnstileWarning: some View {
        Label(
            "This server has browser human-verification (Turnstile) enabled — password sign-in may be rejected from a native client.",
            systemImage: "exclamationmark.shield"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    // MARK: - Building blocks

    private func inputField<Field: View>(@ViewBuilder field: () -> Field) -> some View {
        field()
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func submitButton(_ title: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if session.isBusy {
                    ProgressView()
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .disabled(!enabled || session.isBusy)
    }
}

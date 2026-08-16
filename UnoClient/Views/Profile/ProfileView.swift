import PhotosUI
import SwiftUI
import UIKit

/// Account self-service sheet: avatar, display identity, passkeys and API keys.
/// Everything here needs a signed-in session; the lobby is its only entry point.
struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var store: ProfileStore?
    @State private var nickname = ""
    @State private var username = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var newKeyName = ""
    @State private var newPassword = ""
    @State private var passwordConfirmation = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                if let store {
                    // Two columns: the account itself on the left, the credentials that
                    // reach it on the right. One column would scroll past the screen.
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) {
                            avatarPanel(store)
                            identityPanel(store)
                            if store.isEditable {
                                passwordPanel(store)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 16) {
                            if store.passkeysEnabled {
                                passkeyPanel(store)
                            }
                            apiKeyPanel(store)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: UnoLayout.contentWidth)
                    .screenInsets()
                    .frame(maxWidth: .infinity)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .padding(40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .unoBackdrop()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            guard store == nil, let created = ProfileStore(session: session) else { return }
            store = created
            await created.load()
            nickname = created.profile?.nickname ?? session.user?.nickname ?? ""
            username = created.profile?.username ?? session.user?.username ?? ""
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item, let store else { return }
            Task {
                defer { pickedPhoto = nil }
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    session.showToast(String(localized: "That image could not be read"))
                    return
                }
                await store.setAvatar(imageData: data)
            }
        }
    }

    // MARK: - Avatar

    private func avatarPanel(_ store: ProfileStore) -> some View {
        GlassPanel {
            HStack(spacing: 16) {
                AvatarView(
                    url: store.avatarURL,
                    name: store.profile?.nickname ?? session.user?.nickname ?? "?",
                    size: 76
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.profile?.nickname ?? "—")
                        .font(.title3.weight(.semibold))
                    if store.isEditable {
                        HStack(spacing: 10) {
                            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                                Label("Change", systemImage: "photo")
                                    .font(.subheadline.weight(.medium))
                            }
                            .buttonStyle(.glass)
                            .disabled(store.isBusy)

                            if store.profile?.avatarUrl != nil {
                                Button(role: .destructive) {
                                    Task { await store.removeAvatar() }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                        .font(.subheadline.weight(.medium))
                                }
                                .buttonStyle(.glass)
                                .disabled(store.isBusy)
                            }
                        }
                    } else {
                        Text("This server runs in development mode — profile changes are disabled.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Identity

    private func identityPanel(_ store: ProfileStore) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label("Identity", systemImage: "person.text.rectangle")
                    .font(.headline)

                labelledField("Nickname", text: $nickname, editable: store.isEditable)
                labelledField("Username", text: $username, editable: store.isEditable)

                if store.isEditable {
                    Button {
                        Task { await store.save(nickname: nickname, username: username) }
                    } label: {
                        Text("Save changes")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .actionWidth()
                    .disabled(store.isBusy || !hasIdentityChanges(store))
                }

                // Room seats and chat read the JWT, which a profile edit does not reissue.
                Text("Other players see your old name and avatar until you sign in again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func hasIdentityChanges(_ store: ProfileStore) -> Bool {
        guard let profile = store.profile else { return false }
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedNickname != profile.nickname || trimmedUsername != profile.username
    }

    private func labelledField(_ title: LocalizedStringKey, text: Binding<String>, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(!editable)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }

    // MARK: - Password

    private func passwordPanel(_ store: ProfileStore) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label("Password", systemImage: "lock.fill")
                    .font(.headline)

                secureField("New password", text: $newPassword)
                secureField("Repeat password", text: $passwordConfirmation)

                Text("At least 8 characters, with letters and digits.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        await store.setPassword(newPassword, confirmation: passwordConfirmation)
                        newPassword = ""
                        passwordConfirmation = ""
                    }
                } label: {
                    Text("Set password")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .actionWidth()
                .disabled(store.isBusy || newPassword.isEmpty || passwordConfirmation.isEmpty)
            }
        }
    }

    private func secureField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .textContentType(.newPassword)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Passkeys

    private func passkeyPanel(_ store: ProfileStore) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Passkeys", systemImage: "person.badge.key.fill")
                    .font(.headline)

                if store.passkeys.isEmpty {
                    Text("No passkeys yet. Add one to sign in without a password.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(store.passkeys) { passkey in
                    credentialRow(title: passkey.name, subtitle: nil) {
                        Task { await store.deletePasskey(id: passkey.id) }
                    }
                }

                Button {
                    Task {
                        await session.registerPasskey(name: UIDevice.current.name)
                        await store.load()
                    }
                } label: {
                    Label("Add passkey", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(store.isBusy || session.isBusy)
            }
        }
    }

    // MARK: - API keys

    private func apiKeyPanel(_ store: ProfileStore) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("API keys", systemImage: "key.fill")
                    .font(.headline)

                Text("Keys sign in without a password — MCP clients and bots use them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(store.apiKeys) { key in
                    credentialRow(title: key.name, subtitle: key.keyPreview) {
                        Task { await store.deleteApiKey(id: key.id) }
                    }
                }

                if let revealed = store.revealedKey {
                    revealedKeyRow(revealed) { store.revealedKey = nil }
                }

                HStack(spacing: 10) {
                    TextField("New key name", text: $newKeyName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))

                    Button {
                        Task {
                            await store.createApiKey(name: newKeyName)
                            newKeyName = ""
                        }
                    } label: {
                        Label("Create", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.glass)
                    .disabled(store.isBusy || newKeyName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    /// The plaintext key is shown once; copying is the only way to keep it.
    private func revealedKeyRow(_ key: CreatedApiKey, dismiss: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Copy \(key.name) now — it is never shown again", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.orange)
            HStack(spacing: 10) {
                Text(key.key)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = key.key
                    session.showToast(String(localized: "API key copied"), isError: false)
                    dismiss()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(.orange.opacity(0.25)), in: .rect(cornerRadius: 16))
    }

    private func credentialRow(
        title: String, subtitle: String?, delete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Delete \(title)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

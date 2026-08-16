import SwiftUI

/// Picks the AI engine behind a bot. The list is server-filtered by seat count and
/// house rules, so it is fetched when the sheet opens rather than cached in the room.
struct AiEnginePicker: View {
    enum Target: Equatable, Identifiable {
        /// Seat the new bot at a specific index, or let the server choose.
        case add(seatIndex: Int?)
        case change(botId: String)

        var id: String {
            switch self {
            case .add(let seatIndex): return "add-\(seatIndex.map(String.init) ?? "any")"
            case .change(let botId): return "change-\(botId)"
            }
        }

        var intent: AiProviderIntent {
            switch self {
            case .add: return .add
            case .change: return .switch
            }
        }
    }

    let room: RoomStore
    let target: Target

    @Environment(\.dismiss) private var dismiss
    @State private var providers: [AiProvider] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: UnoLayout.columnWidth), spacing: 12)],
                    spacing: 12
                ) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.large)
                            .padding(40)
                    } else if providers.isEmpty {
                        Text("No AI engine fits this room's player count and house rules.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 40)
                    } else {
                        ForEach(providers) { provider in
                            row(provider)
                        }
                    }
                }
                .frame(maxWidth: UnoLayout.contentWidth)
                .screenInsets()
                .frame(maxWidth: .infinity)
            }
            .unoBackdrop()
            .navigationTitle("AI engine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            providers = await room.aiProviders(intent: target.intent)
            isLoading = false
        }
    }

    private func row(_ provider: AiProvider) -> some View {
        Button {
            Task {
                switch target {
                case .add(let seatIndex):
                    await room.addAiBot(providerId: provider.id, seatIndex: seatIndex)
                case .change(let botId):
                    await room.setBotAi(botId: botId, providerId: provider.id)
                }
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "brain")
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(provider.fairness.localizedName)
                        .font(.caption)
                        .foregroundStyle(fairnessColor(provider.fairness))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func fairnessColor(_ fairness: AiProvider.Fairness) -> Color {
        switch fairness {
        case .fair: return .green
        case .privileged: return .yellow
        case .cheat: return .orange
        }
    }
}

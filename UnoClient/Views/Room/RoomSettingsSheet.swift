import SwiftUI

/// Sheet wrapper around `RoomSettingsEditor`: owners edit and save, everyone
/// else gets a read-only view.
struct RoomSettingsSheet: View {
    let room: RoomStore

    @Environment(\.dismiss) private var dismiss
    @State private var settings: RoomSettings

    init(room: RoomStore) {
        self.room = room
        _settings = State(initialValue: room.room?.settings ?? RoomSettings())
    }

    var body: some View {
        NavigationStack {
            RoomSettingsEditor(settings: $settings, isEditable: room.isOwner)
                .safeAreaInset(edge: .bottom) {
                    if !room.isOwner {
                        Text("Only the host can change settings")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .glassChip(horizontal: 14, vertical: 8)
                            .padding(.bottom, 8)
                    }
                }
                .navigationTitle("Room Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                    }
                    if room.isOwner {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Save") {
                                Task {
                                    await room.updateSettings(settings)
                                    dismiss()
                                }
                            }
                            .buttonStyle(.glassProminent)
                        }
                    }
                }
        }
    }
}

import SwiftUI

/// Sheet for composing a new room's settings and creating it.
struct CreateRoomSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var settings = RoomSettings()

    var body: some View {
        NavigationStack {
            RoomSettingsEditor(settings: $settings, isEditable: true)
                .unoBackdrop()
                .navigationTitle("New Room")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            Task {
                                await session.createRoom(settings: settings)
                                dismiss()
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(session.isBusy)
                    }
                }
        }
    }
}

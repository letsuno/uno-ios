import SwiftUI

/// Modal overlays stacked above the table: color picker, swap-target picker
/// and the cheat warning. Thrown items animate in the FX layer.
struct GameOverlays: View {
    let game: GameStore

    var body: some View {
        ZStack {
            if game.showColorPicker || game.pendingColorPick != nil {
                colorPicker
            }
            if !game.swapTargets.isEmpty {
                swapPicker
            }
            if game.room.cheatDetected {
                cheatWarning
            }
        }
        .animation(
            .spring(response: 0.4, dampingFraction: 0.7), value: game.showColorPicker
        )
        .animation(
            .spring(response: 0.4, dampingFraction: 0.7),
            value: game.pendingColorPick != nil
        )
        .animation(
            .spring(response: 0.4, dampingFraction: 0.7), value: game.swapTargets.isEmpty
        )
    }

    // MARK: - Color picker

    private var colorPicker: some View {
        modal {
            VStack(spacing: 20) {
                Text("Choose a color")
                    .font(.headline)
                HStack(spacing: 18) {
                    ForEach(CardColor.allCases, id: \.self) { color in
                        Button {
                            Task {
                                if let pending = game.pendingColorPick {
                                    await game.play(pending, color: color)
                                } else {
                                    await game.chooseColor(color)
                                }
                            }
                        } label: {
                            Circle()
                                .fill(color.tint.gradient)
                                .frame(width: 58, height: 58)
                                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.localizedName)
                    }
                }
                if game.pendingColorPick != nil {
                    Button("Cancel") { game.pendingColorPick = nil }
                        .buttonStyle(.glass)
                }
            }
        }
    }

    // MARK: - Swap target picker

    private var swapPicker: some View {
        modal {
            VStack(spacing: 16) {
                Text("Choose a player to swap hands with")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                ForEach(game.swapTargets) { target in
                    Button {
                        Task { await game.chooseSwapTarget(target.id) }
                    } label: {
                        HStack {
                            Text(target.name)
                            Spacer()
                            Text("^[\(target.handCount) card](inflect: true)")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
            .frame(maxWidth: 300)
        }
    }

    // MARK: - Cheat warning

    private var cheatWarning: some View {
        ZStack {
            Color.red.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 56))
                Text("Cheating detected — room closed")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Button("Leave") {
                    Task { await game.room.leaveRoom() }
                }
                .buttonStyle(.glass)
            }
            .foregroundStyle(.white)
            .padding(32)
        }
    }

    // MARK: - Helpers

    /// Web ColorPicker entrance: scale 0.8 -> 1 spring over a dim backdrop.
    private func modal<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .transition(.opacity)
            content()
                .padding(24)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
                .padding(32)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }
}

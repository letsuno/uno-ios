import SwiftUI

/// Bottom action bar: UNO call, catch buttons, challenge controls, pass and
/// the autopilot toggle. Hidden entirely by GameView for spectators/autopilot.
struct ActionBar: View {
    let game: GameStore

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if game.canCallUno {
                        Button {
                            Task { await game.callUno() }
                        } label: {
                            Text("UNO!")
                                .font(.headline.weight(.black))
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.glassProminent)
                    }
                    ForEach(game.catchTargets) { target in
                        Button("Catch \(target.name)!") {
                            Task { await game.catchUno(target: target) }
                        }
                        .buttonStyle(.glassProminent)
                    }
                    if game.showChallengeControls {
                        Button("Accept +4") {
                            Task { await game.accept() }
                        }
                        .buttonStyle(.glass)
                        if !game.houseRules.noChallengeWildFour {
                            Button("Challenge!") {
                                Task { await game.challenge() }
                            }
                            .buttonStyle(.glassProminent)
                        }
                    }
                    if game.canPass {
                        Button(game.canEndMultiPlay ? "End turn" : "Pass") {
                            Task { await game.pass() }
                        }
                        .buttonStyle(.glass)
                    }
                    autopilotToggle
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .frame(minHeight: 44)
    }

    /// Autopilot state is shown through the filled/outline icon rather than a color tint.
    private var autopilotToggle: some View {
        Button {
            Task { await game.toggleAutopilot() }
        } label: {
            Image(systemName: game.me?.autopilot == true ? "cpu.fill" : "cpu")
        }
        .buttonStyle(.glass)
    }
}

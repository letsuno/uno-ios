import SwiftUI

/// Full room settings form. Used editable in `CreateRoomSheet` and read-only
/// inside the room screen — the `settings` binding + `isEditable` signature is
/// a contract with those callers.
struct RoomSettingsEditor: View {
    @Binding var settings: RoomSettings
    let isEditable: Bool

    var body: some View {
        Form {
            presetSection
            matchSection
            stackingSection
            specialCardsSection
            drawingSection
            unoCallsSection
            paceSection
            endgameSection
        }
        .scrollContentBackground(.hidden)
        .disabled(!isEditable)
    }

    // MARK: - Preset

    private var presetSection: some View {
        Section("Preset") {
            HStack(spacing: 10) {
                presetButton("Classic", rules: .default)
                presetButton("Party", rules: .party)
                presetButton("Crazy", rules: .crazy)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func presetButton(_ title: String, rules: HouseRules) -> some View {
        let isActive = settings.houseRules == rules
        if isActive {
            Button(title) { settings.houseRules = rules }
                .buttonStyle(.glassProminent)
        } else {
            Button(title) { settings.houseRules = rules }
                .buttonStyle(.glass)
        }
    }

    // MARK: - Match

    private var matchSection: some View {
        Section("Match") {
            Picker("Turn time limit", selection: $settings.turnTimeLimit) {
                ForEach(RoomSettings.turnTimeLimitOptions, id: \.self) { seconds in
                    Text("\(seconds)s").tag(seconds)
                }
            }
            Picker("Target score", selection: $settings.targetScore) {
                ForEach(RoomSettings.targetScoreOptions, id: \.self) { score in
                    Text("\(score)").tag(score)
                }
            }
            Toggle("Allow spectators", isOn: $settings.allowSpectators)
            Picker("Spectator view", selection: $settings.spectatorMode) {
                Text("Show hands").tag(SpectatorMode.full)
                Text("Hide hands").tag(SpectatorMode.hidden)
            }
        }
    }

    // MARK: - House rules

    private var stackingSection: some View {
        Section("Stacking & deflection") {
            RuleToggle("Stack +2", isOn: $settings.houseRules.stackDrawTwo)
            RuleToggle("Stack +4", isOn: $settings.houseRules.stackDrawFour)
            RuleToggle(
                "Cross stack",
                detail: "+2 and +4 can stack on each other",
                isOn: $settings.houseRules.crossStack
            )
            RuleToggle(
                "Reverse deflects +2",
                detail: "Play Reverse to bounce a +2 back",
                isOn: $settings.houseRules.reverseDeflectDrawTwo
            )
            RuleToggle(
                "Reverse deflects +4",
                detail: "Play Reverse to bounce a +4 back",
                isOn: $settings.houseRules.reverseDeflectDrawFour
            )
            RuleToggle(
                "Skip deflect",
                detail: "Play Skip to pass a draw stack onward",
                isOn: $settings.houseRules.skipDeflect
            )
            RuleToggle(
                "Revenge mode",
                detail: "Draw victims get a payback opportunity",
                isOn: $settings.houseRules.revengeMode
            )
        }
    }

    private var specialCardsSection: some View {
        Section("Special cards") {
            RuleToggle(
                "Zero rotates hands",
                detail: "Playing a 0 rotates all hands in play direction",
                isOn: $settings.houseRules.zeroRotateHands
            )
            RuleToggle(
                "Seven swaps hands",
                detail: "Playing a 7 swaps hands with a chosen player",
                isOn: $settings.houseRules.sevenSwapHands
            )
            RuleToggle(
                "Jump-in",
                detail: "Play an identical card out of turn",
                isOn: $settings.houseRules.jumpIn
            )
            RuleToggle(
                "Play multiple same numbers",
                detail: "Drop several cards of the same number at once",
                isOn: $settings.houseRules.multiplePlaySameNumber
            )
            RuleToggle(
                "Bomb card",
                detail: "3+ same numbers in a row: everyone else draws 1",
                isOn: $settings.houseRules.bombCard
            )
            RuleToggle(
                "Wild first turn",
                detail: "Wilds may open the game",
                isOn: $settings.houseRules.wildFirstTurn
            )
        }
    }

    private var drawingSection: some View {
        Section("Drawing") {
            RuleToggle(
                "Draw until playable",
                detail: "Keep drawing until you can play",
                isOn: $settings.houseRules.drawUntilPlayable
            )
            RuleToggle(
                "Forced play after draw",
                detail: "A playable drawn card must be played",
                isOn: $settings.houseRules.forcedPlayAfterDraw
            )
            RuleToggle(
                "Forced play",
                detail: "You must play if you hold a playable card",
                isOn: $settings.houseRules.forcedPlay
            )
            RuleToggle(
                "Blind draw",
                detail: "Drawn cards stay hidden until your next turn",
                isOn: $settings.houseRules.blindDraw
            )
            Picker("Hand limit", selection: $settings.houseRules.handLimit) {
                Text("Off").tag(nil as Int?)
                Text("15").tag(15 as Int?)
                Text("20").tag(20 as Int?)
                Text("25").tag(25 as Int?)
            }
        }
    }

    private var unoCallsSection: some View {
        Section("UNO calls") {
            Picker("Missed-UNO penalty", selection: $settings.houseRules.unoPenaltyCount) {
                Text("2 cards").tag(2)
                Text("4 cards").tag(4)
                Text("6 cards").tag(6)
            }
            RuleToggle(
                "Strict UNO call",
                detail: "Must call UNO before the second-to-last card lands",
                isOn: $settings.houseRules.strictUnoCall
            )
            RuleToggle(
                "Silent UNO",
                detail: "UNO calls are not announced to others",
                isOn: $settings.houseRules.silentUno
            )
        }
    }

    private var paceSection: some View {
        Section("Pace") {
            RuleToggle(
                "Fast mode",
                detail: "Shorter animations and snappier turns",
                isOn: $settings.houseRules.fastMode
            )
            RuleToggle(
                "No hints",
                detail: "Playable cards are not highlighted",
                isOn: $settings.houseRules.noHints
            )
            Picker("Blitz time limit", selection: $settings.houseRules.blitzTimeLimit) {
                Text("Off").tag(nil as Int?)
                Text("1 min").tag(60 as Int?)
                Text("2 min").tag(120 as Int?)
                Text("3 min").tag(180 as Int?)
                Text("5 min").tag(300 as Int?)
            }
            RuleToggle(
                "Misplay penalty",
                detail: "Illegal play attempts cost a drawn card",
                isOn: $settings.houseRules.misplayPenalty
            )
        }
    }

    private var endgameSection: some View {
        Section("Endgame & scoring") {
            RuleToggle(
                "Elimination",
                detail: "Players over the score cap drop out",
                isOn: $settings.houseRules.elimination
            )
            RuleToggle(
                "Team mode",
                detail: "Needs an even player count",
                isOn: $settings.houseRules.teamMode
            )
            RuleToggle(
                "No action-card finish",
                detail: "Cannot win on Skip/Reverse/+2",
                isOn: $settings.houseRules.noFunctionCardFinish
            )
            RuleToggle(
                "No wild finish",
                detail: "Cannot win on a Wild card",
                isOn: $settings.houseRules.noWildFinish
            )
            RuleToggle(
                "Double score",
                detail: "Round points count twice",
                isOn: $settings.houseRules.doubleScore
            )
            RuleToggle(
                "No +4 challenges",
                detail: "Wild +4 can always be played, never challenged",
                isOn: $settings.houseRules.noChallengeWildFour
            )
            Picker("Reveal small hands", selection: $settings.houseRules.handRevealThreshold) {
                Text("Off").tag(nil as Int?)
                Text("2 cards").tag(2 as Int?)
                Text("3 cards").tag(3 as Int?)
            }
            RuleToggle(
                "Shuffle seats",
                detail: "Random seating each round",
                isOn: $settings.houseRules.shuffleSeats
            )
        }
    }
}

/// Toggle row with an optional footnote description.
private struct RuleToggle: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

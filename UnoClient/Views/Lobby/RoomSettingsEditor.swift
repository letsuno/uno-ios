import SwiftUI

/// Full room settings. Used editable in `CreateRoomSheet` and read-only inside the room
/// screen — the `settings` binding + `isEditable` signature is a contract with those callers.
///
/// The 35 house rules do not fit a landscape screen as one list, and a `Form` gave every
/// rule the full width with nothing in the middle. Presets and match settings stay pinned;
/// the rules below them are split into sections, one shown at a time in an adaptive grid,
/// so a section fits without scrolling on all but the shortest screens.
struct RoomSettingsEditor: View {
    @Binding var settings: RoomSettings
    let isEditable: Bool

    @State private var section: RuleSection = .stacking

    private let columns = [GridItem(.adaptive(minimum: UnoLayout.columnWidth), spacing: 10)]

    var body: some View {
        VStack(spacing: 10) {
            controlStrip

            Picker("Rules", selection: $section) {
                ForEach(RuleSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    rules(for: section)
                }
                .padding(.bottom, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: UnoLayout.contentWidth)
        .frame(maxWidth: .infinity)
        .screenInsets()
        .disabled(!isEditable)
    }

    // MARK: - Presets and match

    /// One row, not two panels: a landscape sheet is only ~360pt tall, and the match
    /// settings previously ate nearly half of it before a single rule was visible.
    /// Wide choices use menu pickers — a 4-way segmented control truncates "1,000".
    private var controlStrip: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 6) {
                presetButton("Classic", rules: .default)
                presetButton("Party", rules: .party)
                presetButton("Crazy", rules: .crazy)
            }

            Divider().frame(height: 26)

            labelled("Turn time") {
                Picker("Turn time", selection: $settings.turnTimeLimit) {
                    ForEach(RoomSettings.turnTimeLimitOptions, id: \.self) { seconds in
                        Text("\(seconds)s").tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }

            labelled("Target") {
                Picker("Target", selection: $settings.targetScore) {
                    ForEach(RoomSettings.targetScoreOptions, id: \.self) { score in
                        Text("\(score)").tag(score)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            labelled("Spectators") {
                HStack(spacing: 6) {
                    Toggle("Spectators", isOn: $settings.allowSpectators)
                        .labelsHidden()
                    Picker("Spectator view", selection: $settings.spectatorMode) {
                        Text("Show hands").tag(SpectatorMode.full)
                        Text("Hide hands").tag(SpectatorMode.hidden)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(!settings.allowSpectators)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private func presetButton(_ title: LocalizedStringKey, rules: HouseRules) -> some View {
        let isActive = settings.houseRules == rules
        if isActive {
            Button(title) { settings.houseRules = rules }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
        } else {
            Button(title) { settings.houseRules = rules }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
    }

    private func labelled<Control: View>(
        _ title: LocalizedStringKey, @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            control()
        }
    }

    // MARK: - House rules

    private enum RuleSection: String, CaseIterable, Identifiable {
        case stacking, special, drawing, unoCalls, pace, endgame

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .stacking: return "Stacking"
            case .special: return "Cards"
            case .drawing: return "Drawing"
            case .unoCalls: return "UNO"
            case .pace: return "Pace"
            case .endgame: return "Endgame"
            }
        }
    }

    @ViewBuilder
    private func rules(for section: RuleSection) -> some View {
        switch section {
        case .stacking: stackingRules
        case .special: specialCardRules
        case .drawing: drawingRules
        case .unoCalls: unoCallRules
        case .pace: paceRules
        case .endgame: endgameRules
        }
    }

    @ViewBuilder
    private var stackingRules: some View {
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

    @ViewBuilder
    private var specialCardRules: some View {
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

    @ViewBuilder
    private var drawingRules: some View {
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
        RulePicker("Hand limit", selection: $settings.houseRules.handLimit) {
            Text("Off").tag(nil as Int?)
            Text("15").tag(15 as Int?)
            Text("20").tag(20 as Int?)
            Text("25").tag(25 as Int?)
        }
    }

    @ViewBuilder
    private var unoCallRules: some View {
        RulePicker("Missed-UNO penalty", selection: $settings.houseRules.unoPenaltyCount) {
            Text("2").tag(2)
            Text("4").tag(4)
            Text("6").tag(6)
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

    @ViewBuilder
    private var paceRules: some View {
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
        RuleToggle(
            "Misplay penalty",
            detail: "Illegal play attempts cost a drawn card",
            isOn: $settings.houseRules.misplayPenalty
        )
        RulePicker("Blitz limit", selection: $settings.houseRules.blitzTimeLimit) {
            Text("Off").tag(nil as Int?)
            Text("1m").tag(60 as Int?)
            Text("2m").tag(120 as Int?)
            Text("3m").tag(180 as Int?)
            Text("5m").tag(300 as Int?)
        }
    }

    @ViewBuilder
    private var endgameRules: some View {
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
        RuleToggle(
            "Shuffle seats",
            detail: "Random seating each round",
            isOn: $settings.houseRules.shuffleSeats
        )
        RulePicker("Reveal small hands", selection: $settings.houseRules.handRevealThreshold) {
            Text("Off").tag(nil as Int?)
            Text("2").tag(2 as Int?)
            Text("3").tag(3 as Int?)
        }
    }
}

/// One rule as a self-contained card, sized to a grid column instead of a full row.
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
                    .font(.subheadline.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .ruleCard()
    }
}

/// A multiple-choice rule, styled to sit in the same grid as the toggles.
private struct RulePicker<Value: Hashable, Options: View>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    @ViewBuilder let options: () -> Options

    init(
        _ title: LocalizedStringKey,
        selection: Binding<Value>,
        @ViewBuilder options: @escaping () -> Options
    ) {
        self.title = title
        self._selection = selection
        self.options = options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Picker(title, selection: $selection, content: options)
                .pickerStyle(.segmented)
                .labelsHidden()
        }
        .ruleCard()
    }
}

extension View {
    fileprivate func ruleCard() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

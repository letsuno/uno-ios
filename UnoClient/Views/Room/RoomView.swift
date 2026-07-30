import SwiftUI
import UIKit

/// Waiting-room screen: room code hero, seat grid, spectators and lobby controls.
struct RoomView: View {
    let room: RoomStore

    @State private var showSettingsSheet = false
    @State private var showLeaveDialog = false

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 16) {
                    roomCodeHero
                    settingsSummary
                    if room.ownerTransferAt != nil {
                        ownerTransferBanner
                    }
                    if room.isSpectator {
                        spectatingBanner
                    }
                    spectatorsStrip
                    Spacer(minLength: 0)
                    controlBar
                }
                .frame(maxWidth: .infinity)
                ScrollView {
                    SeatGridView(room: room)
                        .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(20)
            // Landscape home-indicator inflates the bottom safe area; extend into
            // it so the visual bottom margin equals the (≈0-inset) top margin.
            .ignoresSafeArea(.container, edges: .bottom)
            .overlay(alignment: .topTrailing) {
                Button {
                    showSettingsSheet = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                }
                .buttonStyle(.glass)
                .padding(.trailing, 20)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettingsSheet) {
                RoomSettingsSheet(room: room)
            }
            .confirmationDialog("Leave this room?", isPresented: $showLeaveDialog, titleVisibility: .visible) {
                Button("Leave", role: .destructive) {
                    Task { await room.leaveRoom() }
                }
                if room.isOwner {
                    Button("Close room", role: .destructive) {
                        Task { await room.dissolveRoom() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "\(room.incomingSwapRequest?.requesterName ?? String(localized: "Someone")) wants to swap seats",
                isPresented: Binding(
                    get: { room.incomingSwapRequest != nil },
                    set: { _ in }
                ),
                presenting: room.incomingSwapRequest
            ) { swap in
                Button("Accept") {
                    Task { await room.respondSwap(requesterId: swap.requesterId, accept: true) }
                }
                Button("Decline", role: .cancel) {
                    Task { await room.respondSwap(requesterId: swap.requesterId, accept: false) }
                }
            }
        }
    }

    // MARK: - Room code hero

    private var roomCodeHero: some View {
        GlassPanel {
            VStack(spacing: 10) {
                Text("Room code")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(room.roomCode)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .kerning(6)
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = room.roomCode
                        room.session.showToast(String(localized: "Room code copied"), isError: false)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.glass)

                    ShareLink(item: shareText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.glass)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var shareText: String {
        let base = room.session.endpoint?.baseURL.absoluteString ?? ""
        return "Join my UNO room \(room.roomCode): \(base)/room/\(room.roomCode)"
    }

    // MARK: - Settings summary

    private var settingsSummary: some View {
        HStack(spacing: 14) {
            if let settings = room.room?.settings {
                Label("\(settings.turnTimeLimit)s turns", systemImage: "timer")
                Label("\(settings.targetScore) pts", systemImage: "flag.checkered")
                Label(
                    "^[\(settings.houseRules.enabledToggleCount) house rule](inflect: true)", systemImage: "list.bullet"
                )
            } else {
                Text("Loading settings…")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .glassChip(horizontal: 14, vertical: 8)
    }

    // MARK: - Banners

    private var ownerTransferBanner: some View {
        Label("Ownership transfers soon…", systemImage: "crown")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.orange)
            .glassChip(horizontal: 14, vertical: 8)
    }

    private var spectatingBanner: some View {
        Label("You are spectating — tap a free seat to join", systemImage: "eye")
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(.blue.opacity(0.4)), in: .capsule)
    }

    // MARK: - Spectators

    private var spectatorNames: [String] {
        room.spectators.map(\.nickname)
    }

    @ViewBuilder
    private var spectatorsStrip: some View {
        let names = spectatorNames
        if !names.isEmpty {
            GlassPanel(cornerRadius: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "eye.fill")
                        .foregroundStyle(.secondary)
                    Text(names.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text("\(names.count)")
                        .font(.caption.weight(.bold))
                        .glassChip(horizontal: 8, vertical: 3)
                }
            }
        }
    }

    // MARK: - Bottom controls

    private var controlBar: some View {
        VStack(spacing: 10) {
            if let seat = room.mySeat {
                HStack(spacing: 10) {
                    readyButton(currentlyReady: seat.ready)
                    Button {
                        Task { await room.leaveSeat() }
                    } label: {
                        barLabel("Stand up", "figure.stand")
                    }
                    .buttonStyle(.glass)
                }
            }
            HStack(spacing: 10) {
                if room.isOwner {
                    Button {
                        Task { await room.startGame() }
                    } label: {
                        barLabel("Start game", "play.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!room.canStartGame)

                    Menu {
                        ForEach(BotDifficulty.allCases, id: \.self) { difficulty in
                            Button(difficulty.localizedName) {
                                Task { await room.addBot(difficulty: difficulty, seatIndex: nil) }
                            }
                        }
                    } label: {
                        barLabel("Add bot", "cpu")
                    }
                    .buttonStyle(.glass)
                }
                Button(role: .destructive) {
                    showLeaveDialog = true
                } label: {
                    barLabel("Leave", "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.bottom, 4)
    }

    /// Uniform control-bar button label: equal width per row, equal height.
    private func barLabel(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    private func readyButton(currentlyReady: Bool) -> some View {
        Button {
            Task { await room.setReady(!currentlyReady) }
        } label: {
            barLabel(
                currentlyReady ? "Ready ✓" : "Ready up",
                currentlyReady ? "checkmark.circle.fill" : "hand.thumbsup"
            )
        }
        .buttonStyle(.glassProminent)
        .tint(currentlyReady ? .green : .orange)
    }
}

// MARK: - House rule counting

extension HouseRules {
    /// Number of enabled Bool house-rule toggles (numeric knobs excluded).
    fileprivate var enabledToggleCount: Int {
        let toggles = [
            stackDrawTwo, stackDrawFour, crossStack,
            reverseDeflectDrawTwo, reverseDeflectDrawFour, skipDeflect,
            zeroRotateHands, sevenSwapHands, jumpIn,
            multiplePlaySameNumber, wildFirstTurn, drawUntilPlayable,
            forcedPlayAfterDraw, forcedPlay, strictUnoCall,
            misplayPenalty, fastMode, noHints,
            elimination, revengeMode, silentUno,
            teamMode, noFunctionCardFinish, noWildFinish,
            doubleScore, noChallengeWildFour, blindDraw,
            bombCard, shuffleSeats,
        ]
        return toggles.filter { $0 }.count
    }
}

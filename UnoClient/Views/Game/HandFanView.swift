import SwiftUI

/// The viewer's hand. Two layouts by fit:
///   - **fanned** (few cards): every card fully separated, the pre-stack spread.
///   - **stacked** (overflow): cards overlap to left-anchored corner slivers;
///     the selected one expands to full width.
/// A selected card can be dragged up out of the band to play it, or dragged
/// sideways to reorder the hand — the other cards slide to fill the gap and a
/// placement hint marks where it will land.
struct HandFanView: View {
    let game: GameStore

    static let cardWidth: CGFloat = 62
    static let cardHeight: CGFloat = 93
    static let bandHeight: CGFloat = 116

    /// Visible sliver of each stacked (unselected) card.
    private static let cornerStride: CGFloat = 26
    /// Gap between cards in the fully-spread fanned layout.
    private static let fanGap: CGFloat = 6
    /// Extra room after the expanded (selected) card in the stacked layout.
    private static let expandGap: CGFloat = 10
    /// How far the selected card lifts above the resting row.
    private static let selectedLift: CGFloat = 34
    /// Upward pull past which a release commits the play.
    private static let playThreshold: CGFloat = 90
    /// Movement before the drag locks into a play (vertical) or reorder (horizontal).
    private static let axisDeadzone: CGFloat = 10

    private static let space = "handband"

    @State private var selectedId: String?
    /// Card index anchoring an in-progress horizontal scrub (nil when idle).
    @State private var scrubAnchor: Int?
    /// Finger position (band space) while the selected card is dragged; nil idle.
    @State private var dragLocation: CGPoint?
    /// Locked drag intent once past the deadzone.
    @State private var dragAxis: Axis?
    /// Target slot for the in-flight reorder (nil unless dragging horizontally).
    @State private var reorderTarget: Int?

    private var interactive: Bool {
        !(game.isSpectator || game.me?.autopilot == true)
    }

    var body: some View {
        GeometryReader { geo in
            let cards = game.myHand
            let width = geo.size.width
            let fanned = Self.fanWidth(cards.count) <= width - 16
            // No selection while autopilot/spectating drives the hand, so a
            // previously-selected card never sticks out under the veil.
            let selectedIndex =
                interactive
                ? selectedId.flatMap { id in cards.firstIndex { $0.id == id } }
                : nil
            let reordering = dragAxis == .horizontal && selectedIndex != nil
            let expandedSlot = reordering ? reorderTarget : selectedIndex
            let xs = Self.centers(
                count: cards.count, expanded: expandedSlot, width: width, fanned: fanned
            )
            let slots = Self.slotForCard(
                count: cards.count,
                dragged: reordering ? selectedIndex : nil,
                target: reorderTarget
            )

            ZStack {
                // Background scrub surface: horizontal drag anywhere browses cards.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(scrubGesture(cards: cards, width: width, fanned: fanned))

                if reordering, let target = reorderTarget {
                    placementHint(x: xs[target], height: geo.size.height)
                }

                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    slot(
                        card,
                        slotX: xs[slots[index]],
                        index: index,
                        selected: index == selectedIndex,
                        playable: game.playableCardIds.contains(card.id),
                        width: width,
                        height: geo.size.height
                    )
                }
            }
            .coordinateSpace(name: Self.space)
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: selectedId)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: cards)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: reorderTarget)
            .animation(.easeOut(duration: 0.16), value: fanned)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: Self.bandHeight)
        .tableAnchor(.myHand)
        .onChange(of: interactive) { _, active in
            if !active {
                selectedId = nil
                scrubAnchor = nil
                dragLocation = nil
                dragAxis = nil
                reorderTarget = nil
            }
        }
    }

    // MARK: - Slots

    @ViewBuilder
    private func slot(
        _ card: UnoCard, slotX: CGFloat, index: Int, selected: Bool, playable: Bool,
        width: CGFloat, height: CGFloat
    ) -> some View {
        let hinted = game.hintedCardIds.contains(card.id)
        let dimmed = game.isMyTurn && !playable && !game.houseRules.noHints
        let hidden = game.fx.hiddenHandCardId == card.id
        let dragged = dragLocation != nil && selected
        let baseY = height - Self.cardHeight / 2 - 6
        let restY = baseY - (selected ? Self.selectedLift : 0)
        let px = dragged ? (dragLocation?.x ?? slotX) : slotX
        let py = dragged ? (dragLocation?.y ?? restY) : restY

        CardView(card: card, width: Self.cardWidth)
            .overlay {
                if hinted || (selected && playable) {
                    RoundedRectangle(cornerRadius: Self.cardWidth * 0.14)
                        .stroke(playable ? UnoPalette.amber : .white.opacity(0.4), lineWidth: 3)
                }
            }
            .overlay(alignment: .top) {
                if game.lastDrawnCard?.id == card.id && !hidden {
                    Text("NEW")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(.blue, in: .capsule)
                        .offset(y: -7)
                }
            }
            .shadow(
                color: dragged
                    ? .black.opacity(0.5)
                    : (selected ? .black.opacity(0.4) : (hinted ? UnoPalette.gold.opacity(0.5) : .clear)),
                radius: dragged ? 16 : (selected ? 12 : (hinted ? 9 : 0)),
                y: dragged ? 8 : (selected ? 6 : 0)
            )
            .saturation(dimmed ? 0.7 : 1)
            .brightness(dimmed ? -0.28 : 0)
            .scaleEffect(selected ? 1.06 : 1, anchor: .bottom)
            .position(x: px, y: py)
            .zIndex(dragged ? 2000 : (selected ? 1000 : Double(index)))
            .opacity(hidden ? 0 : 1)
            // The dragged card must track the finger 1:1 — never spring-lag it.
            .transaction { if dragged { $0.animation = nil } }
            .transition(
                .asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity)
                        .combined(with: .offset(y: 20)),
                    removal: .opacity
                )
            )
            .onTapGesture {
                guard interactive else { return }
                // Re-tapping a selected but unplayable card cancels the choice.
                if selected, !playable {
                    selectedId = nil
                } else {
                    selectedId = card.id
                }
            }
            .highPriorityGesture(
                dragGesture(card: card, playable: playable, count: game.myHand.count, width: width),
                including: selected ? .all : .none
            )
    }

    /// Dashed card-sized outline marking where a reordered card will drop.
    private func placementHint(x: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Self.cardWidth * 0.14)
            .stroke(style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
            .foregroundStyle(UnoPalette.amber.opacity(0.9))
            .background(
                RoundedRectangle(cornerRadius: Self.cardWidth * 0.14)
                    .fill(.white.opacity(0.08))
            )
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            .position(x: x, y: height - Self.cardHeight / 2 - 6 - Self.selectedLift)
    }

    // MARK: - Gestures

    /// Horizontal browse over the deck: step selection by finger travel.
    private func scrubGesture(cards: [UnoCard], width: CGFloat, fanned: Bool) -> some Gesture {
        let stride = fanned ? Self.cardWidth + Self.fanGap : Self.cornerStride
        return DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard interactive, !cards.isEmpty else { return }
                let anchor: Int
                if let existing = scrubAnchor {
                    anchor = existing
                } else {
                    anchor =
                        selectedId.flatMap { id in cards.firstIndex { $0.id == id } }
                        ?? Self.slotIndex(forX: value.startLocation.x, count: cards.count, width: width, fanned: fanned)
                    scrubAnchor = anchor
                }
                let steps = Int((value.translation.width / stride).rounded())
                selectedId = cards[min(max(anchor + steps, 0), cards.count - 1)].id
            }
            .onEnded { _ in scrubAnchor = nil }
    }

    /// Drag the selected card: up past the threshold plays it; sideways reorders.
    private func dragGesture(
        card: UnoCard, playable: Bool, count: Int, width: CGFloat
    ) -> some Gesture {
        let fanned = Self.fanWidth(count) <= width - 16
        return DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard interactive else { return }
                dragLocation = value.location
                if dragAxis == nil,
                    abs(value.translation.width) > Self.axisDeadzone
                        || abs(value.translation.height) > Self.axisDeadzone
                {
                    dragAxis =
                        abs(value.translation.height) > abs(value.translation.width)
                        ? .vertical : .horizontal
                }
                if dragAxis == .horizontal {
                    reorderTarget = Self.slotIndex(
                        forX: value.location.x, count: count, width: width, fanned: fanned
                    )
                }
            }
            .onEnded { value in
                defer {
                    dragLocation = nil
                    dragAxis = nil
                    reorderTarget = nil
                }
                guard interactive else { return }
                switch dragAxis {
                case .vertical:
                    if playable, value.translation.height < -Self.playThreshold {
                        Task { await game.play(card) }
                    }
                case .horizontal:
                    if let target = reorderTarget { game.reorderHand(card.id, to: target) }
                case nil:
                    break
                }
            }
    }

    // MARK: - Layout math

    /// Width the fully-spread fan needs for `count` cards.
    private static func fanWidth(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * cardWidth + CGFloat(count - 1) * fanGap
    }

    /// Center x for every slot. Fanned: uniform full-card stride. Stacked: corner
    /// slivers with the expanded slot claiming a full card. Run is centered.
    private static func centers(count: Int, expanded: Int?, width: CGFloat, fanned: Bool) -> [CGFloat] {
        guard count > 0 else { return [] }
        if fanned {
            let stride = cardWidth + fanGap
            let runWidth = fanWidth(count)
            let startX = max(8, (width - runWidth) / 2)
            return (0..<count).map { startX + CGFloat($0) * stride + cardWidth / 2 }
        }
        var lefts: [CGFloat] = []
        var x: CGFloat = 0
        for index in 0..<count {
            lefts.append(x)
            x += index == expanded ? cardWidth + expandGap : cornerStride
        }
        let runWidth = (lefts.last ?? 0) + cardWidth
        let startX = max(8, (width - runWidth) / 2)
        return lefts.map { startX + $0 + cardWidth / 2 }
    }

    /// Map each card index to the slot it occupies. Identity unless a reorder is
    /// in flight, in which case the dragged card owns slot `target` and the rest
    /// close ranks around it in their existing order.
    private static func slotForCard(count: Int, dragged: Int?, target: Int?) -> [Int] {
        var map = Array(0..<count)
        guard let dragged, let target else { return map }
        var filled = 0
        for index in 0..<count {
            if index == dragged {
                map[index] = target
            } else {
                map[index] = filled < target ? filled : filled + 1
                filled += 1
            }
        }
        return map
    }

    /// Nearest slot to a touch x on the base (unexpanded) grid, so hit-testing
    /// stays stable while a slot expands.
    private static func slotIndex(forX touchX: CGFloat, count: Int, width: CGFloat, fanned: Bool) -> Int {
        guard count > 1 else { return 0 }
        let stride = fanned ? cardWidth + fanGap : cornerStride
        let runWidth = fanned ? fanWidth(count) : cardWidth + cornerStride * CGFloat(count - 1)
        let startX = max(8, (width - runWidth) / 2)
        let firstCenter = startX + cardWidth / 2
        let raw = Int(((touchX - firstCenter) / stride).rounded())
        return min(max(raw, 0), count - 1)
    }
}

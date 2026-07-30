import SwiftUI

/// Anchor registry for in-table animation targets. Seats, the piles and the
/// viewer's hand publish their center anchors; the FX layer resolves them into
/// one shared coordinate space for card flights and thrown items.
enum TableAnchorKind: Hashable {
    case seat(playerId: String)
    case discard
    case deck(DrawSide)
    case myHand
}

struct TableAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [TableAnchorKind: Anchor<CGPoint>] = [:]

    static func reduce(
        value: inout [TableAnchorKind: Anchor<CGPoint>],
        nextValue: () -> [TableAnchorKind: Anchor<CGPoint>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publish this view's center as a named table anchor.
    func tableAnchor(_ kind: TableAnchorKind) -> some View {
        anchorPreference(key: TableAnchorPreferenceKey.self, value: .center) {
            [kind: $0]
        }
    }
}

/// Seat layout mirroring the web client's table mode (usePlayerLayout.ts):
/// all players sit on an ellipse with rx = 0.38 * width, ry = 0.38 * height;
/// the viewer is pinned to the bottom (angle π/2 in y-down coordinates) and
/// the rest follow clockwise in turn order.
enum TableGeometry {
    static func seatPosition(
        playerIndex: Int,
        viewerIndex: Int,
        playerCount: Int,
        in size: CGSize
    ) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radiusX = size.width * 0.38
        let radiusY = size.height * 0.38
        let angle = seatAngle(
            playerIndex: playerIndex, viewerIndex: viewerIndex, playerCount: playerCount
        )
        return CGPoint(
            x: center.x + radiusX * CGFloat(cos(angle)),
            y: center.y + radiusY * CGFloat(sin(angle))
        )
    }

    /// Radians, y-down screen space: π/2 = bottom (viewer), increasing angle
    /// moves clockwise on screen.
    static func seatAngle(playerIndex: Int, viewerIndex: Int, playerCount: Int) -> Double {
        let count = max(1, playerCount)
        let offset = ((playerIndex - viewerIndex) % count + count) % count
        return .pi / 2 + Double(offset) * 2 * .pi / Double(count)
    }
}

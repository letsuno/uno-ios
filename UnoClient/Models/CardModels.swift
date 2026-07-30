import SwiftUI

enum CardColor: String, Codable, CaseIterable, Sendable {
    case red, blue, green, yellow

    /// Display/sort order used by the reference client: red, yellow, blue, green.
    var sortRank: Int {
        switch self {
        case .red: return 0
        case .yellow: return 1
        case .blue: return 2
        case .green: return 3
        }
    }

    var tint: Color {
        switch self {
        case .red: return Color(red: 0.92, green: 0.20, blue: 0.23)
        case .yellow: return Color(red: 0.98, green: 0.75, blue: 0.10)
        case .green: return Color(red: 0.18, green: 0.72, blue: 0.35)
        case .blue: return Color(red: 0.12, green: 0.46, blue: 0.95)
        }
    }

    var localizedName: String {
        switch self {
        case .red: return String(localized: "Red")
        case .yellow: return String(localized: "Yellow")
        case .green: return String(localized: "Green")
        case .blue: return String(localized: "Blue")
        }
    }
}

/// Wire `Card` is a discriminated union on `type`; `value` only exists for numbers,
/// `color` is an explicit null for wilds, `chosenColor` appears after color selection.
struct UnoCard: Codable, Identifiable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case number
        case skip
        case reverse
        case drawTwo = "draw_two"
        case wild
        case wildDrawFour = "wild_draw_four"

        var sortRank: Int {
            switch self {
            case .number: return 0
            case .skip: return 1
            case .reverse: return 2
            case .drawTwo: return 3
            case .wild: return 4
            case .wildDrawFour: return 5
            }
        }
    }

    let id: String
    let type: Kind
    let color: CardColor?
    let value: Int?
    let chosenColor: CardColor?

    init(id: String, type: Kind, color: CardColor? = nil, value: Int? = nil, chosenColor: CardColor? = nil) {
        self.id = id
        self.type = type
        self.color = color
        self.value = value
        self.chosenColor = chosenColor
    }

    var isWild: Bool { type == .wild || type == .wildDrawFour }

    var effectiveColor: CardColor? { isWild ? chosenColor : color }

    var score: Int {
        switch type {
        case .number: return value ?? 0
        case .skip, .reverse, .drawTwo: return 20
        case .wild, .wildDrawFour: return 50
        }
    }

    var symbol: String {
        switch type {
        case .number: return value.map(String.init) ?? "?"
        case .skip: return "⃠"
        case .reverse: return "⇄"
        case .drawTwo: return "+2"
        case .wild: return "★"
        case .wildDrawFour: return "+4"
        }
    }
}

extension [UnoCard] {
    /// Reference-client hand ordering: color (red, yellow, blue, green, wilds last),
    /// then card kind, then face value.
    func sortedForHand() -> [UnoCard] {
        sorted { a, b in
            let colorA = a.color?.sortRank ?? 99
            let colorB = b.color?.sortRank ?? 99
            if colorA != colorB { return colorA < colorB }
            if a.type.sortRank != b.type.sortRank { return a.type.sortRank < b.type.sortRank }
            return (a.value ?? 0) < (b.value ?? 0)
        }
    }
}

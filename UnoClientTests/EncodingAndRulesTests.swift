import Foundation
import Testing

@testable import UnoClient

@Suite("Wire encoding")
struct WireEncodingTests {
    @Test("Base64URL round trips without padding")
    func base64URLRoundTrip() throws {
        let input = Data([0xFB, 0xFF, 0x00, 0x7F])
        let encoded = input.base64URLEncoded

        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
        #expect(Data(base64URLEncoded: encoded) == input)
    }

    @Test("JSON values preserve nested payloads")
    func jsonValueRoundTrip() throws {
        let value: JSONValue = [
            "success": true,
            "players": ["alice", "bob"],
            "score": 42,
            "optional": nil,
        ]

        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
    }
}

@Suite("Card rules")
struct CardRulesTests {
    private let redFive = UnoCard(id: "red-five", type: .number, color: .red, value: 5)
    private let blueFive = UnoCard(id: "blue-five", type: .number, color: .blue, value: 5)
    private let redSkip = UnoCard(id: "red-skip", type: .skip, color: .red)
    private let wild = UnoCard(id: "wild", type: .wild)

    @Test("Cards match by active color, value, or wild status")
    func standardPlayability() {
        #expect(canPlayCard(blueFive, top: redFive, currentColor: .red))
        #expect(canPlayCard(redSkip, top: redFive, currentColor: .red))
        #expect(canPlayCard(wild, top: redFive, currentColor: .red))
        #expect(!canPlayCard(redSkip, top: blueFive, currentColor: .blue))
    }

    @Test("Jump-in requires an exact face match")
    func jumpInMatch() {
        #expect(isExactJumpInMatch(redFive, top: redFive))
        #expect(!isExactJumpInMatch(blueFive, top: redFive))
    }

    @Test("Cross stack accepts draw-two against draw-four")
    func crossStack() {
        var rules = HouseRules()
        rules.crossStack = true
        let drawTwo = UnoCard(id: "draw-two", type: .drawTwo, color: .red)
        let drawFour = UnoCard(id: "draw-four", type: .wildDrawFour)

        #expect(canRespondToDrawStack(drawTwo, top: drawFour, rules: rules))
    }
}

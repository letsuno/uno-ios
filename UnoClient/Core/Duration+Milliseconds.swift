import Foundation

extension Duration {
    /// Whole milliseconds. `components.attoseconds` only carries the sub-second part,
    /// so a round trip past one second has to add the seconds back in.
    var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds * 1000 + attoseconds / 1_000_000_000_000_000)
    }
}

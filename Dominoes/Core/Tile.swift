/// One domino. The two numbers are stored low first, so [6|2] and [2|6] are
/// the same tile.
struct Tile: Hashable, Identifiable, Codable, CustomStringConvertible {
    let low: Int
    let high: Int

    init(_ a: Int, _ b: Int) {
        low = min(a, b)
        high = max(a, b)
    }

    var id: String { "\(low)-\(high)" }
    var isDouble: Bool { low == high }
    var pips: Int { low + high }
    var description: String { "[\(low)|\(high)]" }

    func has(_ value: Int) -> Bool { low == value || high == value }

    /// The number on the other half, once `value` is matched.
    func other(than value: Int) -> Int { low == value ? high : low }

    /// Every tile of a set: 0-0 through max-max (55 tiles for double nine).
    static func fullSet(highest: Int = 9) -> [Tile] {
        var tiles: [Tile] = []
        for low in 0...highest {
            for high in low...highest {
                tiles.append(Tile(low, high))
            }
        }
        return tiles
    }
}

/// The two sides of the table. Seats 0 (you) and 2 (your partner) are Us,
/// seats 1 and 3 are Them.
enum Team: Int, Codable, CaseIterable {
    case us = 0
    case them = 1

    var other: Team { self == .us ? .them : .us }
    var seats: [Int] { self == .us ? [0, 2] : [1, 3] }

    static func of(seat: Int) -> Team { seat % 2 == 0 ? .us : .them }
}

/// A small, fast random number generator that can be seeded, so tests and
/// screenshots get the same deal every time. Games use a random seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    init() {
        var system = SystemRandomNumberGenerator()
        state = system.next()
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

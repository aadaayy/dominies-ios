/// Which open end of the line a tile goes on.
enum End: String, Codable, Hashable {
    case left
    case right
}

/// Which arm of the line a tile belongs to. The first tile is the origin;
/// every later tile is on the left arm or the right arm forever, so the
/// layout never has to guess.
enum Branch: String, Codable, Hashable {
    case origin
    case left
    case right
}

/// A tile on the table. `near` is the number touching the tile before it
/// (for the origin: its left number) and `far` is the number left open.
struct Placement: Hashable, Codable {
    let tile: Tile
    let branch: Branch
    let near: Int
    let far: Int
}

/// The line of tiles: one origin tile and two arms growing outward from it.
struct Board: Hashable, Codable {
    private(set) var origin: Placement?
    /// Outward from the origin, nearest first.
    private(set) var leftArm: [Placement] = []
    private(set) var rightArm: [Placement] = []

    var isEmpty: Bool { origin == nil }
    var count: Int { (origin == nil ? 0 : 1) + leftArm.count + rightArm.count }

    var leftOpen: Int? { leftArm.last?.far ?? origin?.near }
    var rightOpen: Int? { rightArm.last?.far ?? origin?.far }

    func open(_ end: End) -> Int? { end == .left ? leftOpen : rightOpen }

    /// Every tile on the table.
    var tiles: [Tile] {
        var all = leftArm.map(\.tile)
        if let origin { all.append(origin.tile) }
        all += rightArm.map(\.tile)
        return all
    }

    /// The ends a tile can go on. An empty table takes any tile (no end).
    func ends(for tile: Tile) -> [End] {
        guard let leftOpen, let rightOpen else { return [] }
        var ends: [End] = []
        if tile.has(leftOpen) { ends.append(.left) }
        if tile.has(rightOpen) { ends.append(.right) }
        return ends
    }

    func canPlay(_ tile: Tile) -> Bool { isEmpty || !ends(for: tile).isEmpty }

    /// Puts a tile down. Returns false (and changes nothing) when it doesn't fit.
    @discardableResult
    mutating func place(_ tile: Tile, on end: End?) -> Bool {
        guard let origin else {
            self.origin = Placement(tile: tile, branch: .origin, near: tile.low, far: tile.high)
            return true
        }
        _ = origin
        guard let end, let value = open(end), tile.has(value) else { return false }
        let placement = Placement(tile: tile, branch: end == .left ? .left : .right, near: value, far: tile.other(than: value))
        if end == .left { leftArm.append(placement) } else { rightArm.append(placement) }
        return true
    }
}

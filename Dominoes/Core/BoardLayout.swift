/// A rectangle on the table, in tile units: a tile is 2 long and 1 wide.
/// y grows downward, like the screen.
struct TableRect: Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }

    /// True when the two share any area (just touching doesn't count).
    func overlaps(_ other: TableRect, tolerance: Double = 1e-6) -> Bool {
        min(maxX, other.maxX) - max(x, other.x) > tolerance &&
            min(maxY, other.maxY) - max(y, other.y) > tolerance
    }

    /// True when the two touch along an edge (for checking the line connects).
    func touches(_ other: TableRect, tolerance: Double = 1e-6) -> Bool {
        let overlapX = min(maxX, other.maxX) - max(x, other.x)
        let overlapY = min(maxY, other.maxY) - max(y, other.y)
        return (abs(overlapX) <= tolerance && overlapY > tolerance) ||
            (abs(overlapY) <= tolerance && overlapX > tolerance)
    }

    func union(_ other: TableRect) -> TableRect {
        let minX = min(x, other.x), minY = min(y, other.y)
        return TableRect(x: minX, y: minY, width: max(maxX, other.maxX) - minX, height: max(maxY, other.maxY) - minY)
    }
}

/// Where one tile sits on the table and which way it faces.
struct LaidTile: Hashable, Identifiable {
    let tile: Tile
    let branch: Branch
    /// 0 for the origin; 1, 2, 3... outward along its arm.
    let step: Int
    let rect: TableRect
    /// Standing up (taller than wide).
    var isVertical: Bool { rect.height > rect.width }
    /// The number drawn on the left half (lying down) or top half (standing).
    let firstFace: Int
    /// The number drawn on the right half or bottom half.
    let secondFace: Int

    var id: String { tile.id }
}

/// Lays the line of tiles out as a snake that can't overlap itself.
///
/// The origin tile sits in the middle. The right arm runs right to the edge,
/// turns down with two standing tiles, runs back left across the whole table,
/// turns down again, and so on. The left arm does the same going left and up,
/// so the two arms never meet.
///
/// Why it can't overlap (the old web game's bug): every turn column sits
/// completely outside the row it leaves, so a double standing across the row
/// can't poke into it. The first tile after a turn always lies in line, even
/// a double, so it can't poke back into the column. Rows are at least two
/// tile widths apart, which is the most a standing double reaches. Tests lay
/// out thousands of random games at every table width and check that no two
/// tiles share any area and that each tile touches the one before it.
enum BoardLayout {
    /// Smallest half width the layout allows, in tile units (two tile lengths).
    static let minimumHalfWidth = 4.0

    /// - Parameter halfWidth: how far each row may reach from the middle, in
    ///   tile units (a tile is 2 long). The turn columns sit just outside it.
    static func lay(_ board: Board, halfWidth: Double) -> [LaidTile] {
        guard let origin = board.origin else { return [] }
        let reach = max(halfWidth, minimumHalfWidth)
        let originRect = origin.tile.isDouble
            ? TableRect(x: -0.5, y: -1, width: 1, height: 2)
            : TableRect(x: -1, y: -0.5, width: 2, height: 1)
        let originTile = LaidTile(tile: origin.tile, branch: .origin, step: 0, rect: originRect,
                                  firstFace: origin.near, secondFace: origin.far)
        let originHalf = originRect.width / 2
        return [originTile]
            + arm(board.leftArm, branch: .left, start: originHalf, reach: reach)
            + arm(board.rightArm, branch: .right, start: originHalf, reach: reach)
    }

    /// The area all the tiles cover.
    static func bounds(of tiles: [LaidTile]) -> TableRect? {
        guard var box = tiles.first?.rect else { return nil }
        for tile in tiles.dropFirst() { box = box.union(tile.rect) }
        return box
    }

    /// How far the rows may reach for a table this wide, aiming for tiles about
    /// `idealTileLength` long. Kept as whole tile lengths so the snake only
    /// changes when the space changes a lot.
    static func halfWidth(forTableWidth width: Double, idealTileLength: Double) -> Double {
        let units = width / (idealTileLength / 2)
        // One unit of margin each side for the turn columns.
        let half = ((units - 2) / 2 / 2).rounded(.down) * 2
        return max(minimumHalfWidth, half)
    }

    private static func arm(_ placements: [Placement], branch: Branch, start: Double, reach: Double) -> [LaidTile] {
        var laid: [LaidTile] = []
        let outward: Double = branch == .right ? 1 : -1
        // The right arm turns downward, the left arm upward.
        let downward = outward
        var direction = outward
        var cursor = outward * start
        var rowY = 0.0
        var row = 0
        var index = 0
        var startsReturnRow = false

        func faces(_ p: Placement, travelling: Double, vertical: Bool) -> (Int, Int) {
            // The matched number goes on the side touching the tile before.
            if vertical {
                // Travelling down: the near number is on top.
                return travelling > 0 ? (p.near, p.far) : (p.far, p.near)
            }
            return travelling > 0 ? (p.near, p.far) : (p.far, p.near)
        }

        while index < placements.count {
            let placement = placements[index]
            let isDouble = placement.tile.isDouble
            // Doubles stand across the row, except right after a turn.
            let standing = isDouble && !startsReturnRow
            let along: Double = standing ? 1 : 2
            let across: Double = standing ? 2 : 1
            let next = cursor + direction * along
            let fits = row == 0 ? abs(next) <= reach + 1e-9 : (next >= -reach - 1e-9 && next <= reach + 1e-9)

            if fits {
                let rect = TableRect(x: min(cursor, next), y: rowY - across / 2, width: along, height: across)
                let (first, second) = faces(placement, travelling: direction, vertical: false)
                laid.append(LaidTile(tile: placement.tile, branch: branch, step: index + 1, rect: rect,
                                     firstFace: first, secondFace: second))
                cursor = next
                index += 1
                startsReturnRow = false
                continue
            }

            // Turn: two standing tiles in a column just past the end of the row.
            let columnX = direction > 0 ? cursor : cursor - 1
            // The first one's near half sits beside the row's last tile
            // (a double is centred on the row instead).
            let entryCenter = rowY + (isDouble ? 0 : downward * 0.5)
            let (entryFirst, entrySecond) = faces(placement, travelling: downward, vertical: true)
            laid.append(LaidTile(tile: placement.tile, branch: branch, step: index + 1,
                                 rect: TableRect(x: columnX, y: entryCenter - 1, width: 1, height: 2),
                                 firstFace: entryFirst, secondFace: entrySecond))
            index += 1

            var nextRowY = entryCenter + downward * 2.5
            if index < placements.count {
                let exit = placements[index]
                let exitCenter = entryCenter + downward * 2
                let (exitFirst, exitSecond) = faces(exit, travelling: downward, vertical: true)
                laid.append(LaidTile(tile: exit.tile, branch: branch, step: index + 1,
                                     rect: TableRect(x: columnX, y: exitCenter - 1, width: 1, height: 2),
                                     firstFace: exitFirst, secondFace: exitSecond))
                // The next row runs back beside the far half of this tile.
                nextRowY = exitCenter + (exit.tile.isDouble ? 0 : downward * 0.5)
                index += 1
            }

            rowY = nextRowY
            direction = -direction
            row += 1
            startsReturnRow = true
        }
        return laid
    }
}

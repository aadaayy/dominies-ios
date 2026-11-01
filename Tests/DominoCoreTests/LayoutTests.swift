import XCTest
@testable import DominoCore

/// The old web game's biggest bug was tiles overlapping where the line turns.
/// These tests lay out thousands of real games, after every single play, at
/// every table width, and fail if any two tiles share any area.
final class LayoutTests: XCTestCase {
    func testNoTilesEverOverlapAndTheLineAlwaysConnects() throws {
        var rng = SeededGenerator(seed: 2026)
        var layoutsChecked = 0
        for halfWidth in stride(from: 4.0, through: 20.0, by: 1.0) {
            for number in 0..<150 {
                let deal = Game.deal(using: &rng)
                var game = Game(hands: deal.hands, boneyard: deal.boneyard, starter: number % 4)
                let levels: [BotLevel] = [.normal, .easy, .normal, .easy]
                while !game.isOver {
                    try Simulation.playOn(&game, levels: levels, moves: 1, using: &rng)
                    try check(BoardLayout.lay(game.board, halfWidth: halfWidth), board: game.board, halfWidth: halfWidth)
                    layoutsChecked += 1
                }
            }
        }
        print("Checked \(layoutsChecked) layouts")
    }

    /// The worst case for turns: long arms full of doubles, built by hand
    /// (no real game has this many doubles, which makes it a harder test).
    func testArmsFullOfDoublesNeverOverlap() throws {
        for halfWidth in stride(from: 4.0, through: 12.0, by: 1.0) {
            for pattern in 0..<64 {
                let board = makeBoard(length: 30, doubleWhen: { step in (pattern >> (step % 6)) & 1 == 1 })
                try check(BoardLayout.lay(board, halfWidth: halfWidth), board: board, halfWidth: halfWidth)
            }
        }
    }

    func testTheOpeningTileIsInTheMiddle() {
        var board = Board()
        board.place(Tile(9, 9), on: nil)
        let laid = BoardLayout.lay(board, halfWidth: 8)
        XCTAssertEqual(laid.count, 1)
        XCTAssertEqual(laid[0].rect.midX, 0)
        XCTAssertEqual(laid[0].rect.midY, 0)
        XCTAssertTrue(laid[0].isVertical, "A double opens standing across the line")
    }

    func testTheRightArmTurnsDownAndTheLeftArmTurnsUp() throws {
        let board = makeBoard(length: 40, doubleWhen: { _ in false })
        let laid = BoardLayout.lay(board, halfWidth: 6)
        let right = laid.filter { $0.branch == .right }
        let left = laid.filter { $0.branch == .left }
        XCTAssertTrue(right.allSatisfy { $0.rect.minYValue >= -0.5 - 1e-9 })
        XCTAssertTrue(left.allSatisfy { $0.rect.maxY <= 0.5 + 1e-9 })
        XCTAssertGreaterThan(right.map(\.rect.maxY).max() ?? 0, 3, "The right arm should have turned")
    }

    func testHalfWidthGrowsWithTheTable() {
        let phone = BoardLayout.halfWidth(forTableWidth: 390, idealTileLength: 54)
        let open = BoardLayout.halfWidth(forTableWidth: 951, idealTileLength: 54)
        XCTAssertGreaterThanOrEqual(phone, BoardLayout.minimumHalfWidth)
        XCTAssertGreaterThan(open, phone)
    }

    // MARK: - Helpers

    private func check(_ laid: [LaidTile], board: Board, halfWidth: Double, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(laid.count, board.count, "Every tile on the table is laid out", file: file, line: line)
        for i in laid.indices {
            for j in laid.indices where j > i {
                if laid[i].rect.overlaps(laid[j].rect) {
                    XCTFail("\(laid[i].tile) and \(laid[j].tile) overlap at half width \(halfWidth): \(laid[i].rect) / \(laid[j].rect)", file: file, line: line)
                    throw Stop()
                }
            }
        }
        // Each tile touches the tile before it on its arm, and the touching
        // numbers are the same.
        let origin = try XCTUnwrap(laid.first { $0.branch == .origin })
        for branch in [Branch.left, .right] {
            var previous = origin
            for tile in laid.filter({ $0.branch == branch }).sorted(by: { $0.step < $1.step }) {
                if !tile.rect.touches(previous.rect) {
                    XCTFail("\(tile.tile) doesn't touch \(previous.tile) at half width \(halfWidth)", file: file, line: line)
                    throw Stop()
                }
                XCTAssertEqual(touchingNumber(of: tile, toward: previous), touchingNumber(of: previous, toward: tile),
                               "\(tile.tile) and \(previous.tile) don't show the same number where they meet", file: file, line: line)
                previous = tile
            }
        }
    }

    /// The number on the half of `tile` nearest to `other`.
    private func touchingNumber(of tile: LaidTile, toward other: LaidTile) -> Int {
        if tile.tile.isDouble { return tile.firstFace }
        if tile.isVertical {
            return other.rect.midY < tile.rect.midY ? tile.firstFace : tile.secondFace
        }
        return other.rect.midX < tile.rect.midX ? tile.firstFace : tile.secondFace
    }

    /// A board whose arms are `length` tiles each. Every plain tile brings a
    /// new number, so the made-up tiles never repeat.
    private func makeBoard(length: Int, doubleWhen: (Int) -> Bool) -> Board {
        var board = Board()
        board.place(Tile(0, 1), on: nil)
        var fresh = 100
        for end in [End.left, .right] {
            var lastWasDouble = false
            for step in 0..<length {
                let open = board.open(end)!
                let tile: Tile
                if doubleWhen(step) && !lastWasDouble {
                    tile = Tile(open, open)
                    lastWasDouble = true
                } else {
                    fresh += 1
                    tile = Tile(open, fresh)
                    lastWasDouble = false
                }
                board.place(tile, on: end)
            }
        }
        return board
    }

    private struct Stop: Error {}
}

private extension TableRect {
    var minYValue: Double { y }
}

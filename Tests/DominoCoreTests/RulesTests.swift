import XCTest
@testable import DominoCore

final class RulesTests: XCTestCase {
    func testFullSetHas55DifferentTiles() {
        let set = Tile.fullSet()
        XCTAssertEqual(set.count, 55)
        XCTAssertEqual(Set(set).count, 55)
        XCTAssertEqual(set.filter(\.isDouble).count, 10)
    }

    func testDealGivesTenEachAndNeverFiveDoubles() {
        var rng = SeededGenerator(seed: 1)
        for _ in 0..<500 {
            let deal = Game.deal(using: &rng)
            XCTAssertEqual(deal.hands.map(\.count), [10, 10, 10, 10])
            XCTAssertEqual(deal.boneyard.count, 15)
            XCTAssertEqual(Set(deal.hands.flatMap { $0 } + deal.boneyard).count, 55)
            XCTAssertTrue(deal.hands.allSatisfy { $0.filter(\.isDouble).count < 5 })
        }
    }

    func testOpeningTileCanBeAnything() throws {
        var game = Game(hands: [[Tile(3, 5), Tile(1, 1)], [Tile(5, 6)], [Tile(0, 0)], [Tile(2, 2)]], starter: 0)
        XCTAssertEqual(game.legalMoves(for: 0).count, 2)
        try game.play(Tile(3, 5))
        XCTAssertEqual(game.board.leftOpen, 3)
        XCTAssertEqual(game.board.rightOpen, 5)
        XCTAssertEqual(game.current, 1)
    }

    func testTileMustMatchAnOpenEnd() throws {
        var game = Game(hands: [[Tile(3, 5), Tile(9, 9)], [Tile(5, 6), Tile(7, 8)], [Tile(0, 0)], [Tile(2, 2)]], starter: 0)
        try game.play(Tile(3, 5))
        XCTAssertThrowsError(try game.play(Tile(7, 8))) { XCTAssertEqual($0 as? GameError, .doesNotFit) }
        XCTAssertThrowsError(try game.knock()) { XCTAssertEqual($0 as? GameError, .mustPlay) }
        try game.play(Tile(5, 6))
        XCTAssertEqual(game.board.rightOpen, 6)
        XCTAssertEqual(game.board.rightArm.first?.near, 5)
    }

    func testTileThatFitsOneEndGoesThere() throws {
        var game = Game(hands: [[Tile(3, 5), Tile(9, 9)], [Tile(3, 9), Tile(5, 9)], [Tile(0, 0)], [Tile(2, 2)]], starter: 0)
        try game.play(Tile(3, 5))
        // [5|9]... fits only the 5 end, so no choice needed.
        try game.play(Tile(5, 9))
        XCTAssertEqual(game.board.rightOpen, 9)
    }

    func testChoosingAnEnd() throws {
        var game = Game(hands: [[Tile(3, 4), Tile(9, 9)], [Tile(4, 5), Tile(8, 8)], [Tile(3, 5), Tile(0, 0)], [Tile(2, 2)]], starter: 0)
        try game.play(Tile(3, 4))
        try game.play(Tile(4, 5))
        // Ends are 3 and 5, and [3|5] fits both, so seat 2 has to choose.
        XCTAssertEqual(game.legalMoves(for: 2).first?.ends, [.left, .right])
        XCTAssertThrowsError(try game.play(Tile(3, 5))) { XCTAssertEqual($0 as? GameError, .chooseAnEnd) }
        try game.play(Tile(3, 5), on: .left)
        XCTAssertEqual(game.board.leftOpen, 5)
        XCTAssertEqual(game.board.rightOpen, 5)
    }

    func testSameNumberOnBothEndsNeedsNoChoice() throws {
        var game = Game(hands: [[Tile(3, 3), Tile(9, 9)], [Tile(3, 7), Tile(8, 8)], [Tile(0, 0)], [Tile(2, 2)]], starter: 0)
        try game.play(Tile(3, 3))
        try game.play(Tile(3, 7))
        XCTAssertEqual(game.board.count, 2)
        XCTAssertEqual(game.board.leftArm.count + game.board.rightArm.count, 1)
    }

    func testGoingOutScoresTheOpponentsPipsOnly() throws {
        // Seat 0 goes out with its only tile; partner's [9|9] doesn't count.
        var game = Game(hands: [[Tile(4, 4)], [Tile(6, 6), Tile(1, 2)], [Tile(9, 9)], [Tile(0, 5)]], starter: 0)
        try game.play(Tile(4, 4))
        let result = try XCTUnwrap(game.result)
        XCTAssertEqual(result.kind, .domino(seat: 0))
        XCTAssertEqual(result.winner, .us)
        XCTAssertEqual(result.points, 12 + 3 + 5)
        XCTAssertThrowsError(try game.knock()) { XCTAssertEqual($0 as? GameError, .gameOver) }
    }

    func testFourKnocksBlockTheGameAndTheLighterTeamWins() throws {
        var game = Game(hands: [[Tile(1, 1), Tile(9, 8)], [Tile(9, 9)], [Tile(8, 8)], [Tile(7, 7)]], starter: 0)
        try game.play(Tile(1, 1))
        try game.knock()
        try game.knock()
        try game.knock()
        XCTAssertNil(game.result)
        try game.knock()
        let result = try XCTUnwrap(game.result)
        XCTAssertEqual(result.kind, .blocked)
        // Us: [9|8] + [8|8] = 33. Them: [9|9] + [7|7] = 32.
        XCTAssertEqual(result.winner, .them)
        XCTAssertEqual(result.points, 33)
    }

    func testBlockedTieScoresNothingAndTheSecondTeamOpensNext() throws {
        // After [1|1] nobody holds a 1. Us: [9|8] + [7|7] = 31. Them: [9|7] + [8|7] = 31.
        var tie = Game(hands: [[Tile(1, 1), Tile(9, 8)], [Tile(9, 7)], [Tile(7, 7)], [Tile(8, 7)]], starter: 0)
        try tie.play(Tile(1, 1))
        for _ in 0..<4 { try tie.knock() }
        let tied = try XCTUnwrap(tie.result)
        XCTAssertEqual(tied.kind, .tie)
        XCTAssertNil(tied.winner)
        XCTAssertEqual(tied.points, 0)
        var match = Match(target: 100, openingTeam: .us)
        match.record(tie)
        XCTAssertEqual(match.score(of: .us), 0)
        XCTAssertEqual(match.score(of: .them), 0)
        XCTAssertEqual(match.openingTeam, .them)
        XCTAssertEqual(match.gameNumber, 2)
    }

    func testMatchEndsAtTheTarget() throws {
        var match = Match(target: 20, openingTeam: .them)
        var game = Game(hands: [[Tile(4, 4)], [Tile(9, 9), Tile(1, 2)], [Tile(9, 8)], [Tile(0, 5)]], starter: 0)
        try game.play(Tile(4, 4))
        match.record(game)
        XCTAssertEqual(match.score(of: .us), 26)
        XCTAssertEqual(match.winner, .us)
        XCTAssertEqual(match.openingTeam, .us)
    }

    func testRandomGamesFollowTheRules() throws {
        var rng = SeededGenerator(seed: 42)
        for game in 0..<1_000 {
            let level: BotLevel = game.isMultiple(of: 2) ? .easy : .normal
            let played = try Simulation.playOut(starter: game % 4, levels: [level, .normal, .easy, level], using: &rng)
            let result = try XCTUnwrap(played.result)
            let all = played.board.tiles + played.hands.flatMap { $0 } + played.boneyard
            XCTAssertEqual(Set(all).count, 55, "Tiles went missing")
            // Each arm connects: every tile's near number is the open number before it.
            var open = played.board.origin!.far
            for p in played.board.rightArm { XCTAssertEqual(p.near, open); open = p.far }
            open = played.board.origin!.near
            for p in played.board.leftArm { XCTAssertEqual(p.near, open); open = p.far }
            switch result.kind {
            case .domino(let seat): XCTAssertTrue(played.hands[seat].isEmpty)
            case .blocked, .tie:
                XCTAssertTrue(Seat.all.allSatisfy { !played.canPlay($0) })
            }
        }
    }

    func testNormalBotsBeatEasyBots() throws {
        var rng = SeededGenerator(seed: 7)
        var usWins = 0
        let matches = 300
        for number in 0..<matches {
            var match = Match(target: 100, openingTeam: number.isMultiple(of: 2) ? .us : .them)
            while match.winner == nil {
                let starter = Bot.starter(for: match.openingTeam, hands: [[], [], [], []])
                let game = try Simulation.playOut(starter: starter, levels: [.normal, .easy, .normal, .easy], using: &rng)
                match.record(game)
            }
            if match.winner == .us { usWins += 1 }
        }
        let rate = Double(usWins) / Double(matches)
        print("Normal bots won \(usWins) of \(matches) matches against easy bots")
        XCTAssertGreaterThan(rate, 0.55)
    }
}


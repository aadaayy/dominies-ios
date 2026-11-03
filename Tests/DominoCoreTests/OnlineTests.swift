import XCTest
@testable import DominoCore

/// Reading the game server's answers (real ones, saved from a test match in
/// Fixtures) and turning the table so the phone's own player is seat 0.
final class OnlineTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        return try Data(contentsOf: url)
    }

    func testLobbyForTheHost() throws {
        let state = try OnlineState.decode(fixture("lobby_host"))
        XCTAssertEqual(state.phase, .lobby)
        XCTAssertTrue(state.isHost)
        XCTAssertEqual(state.mySeat, 0)
        XCTAssertEqual(state.code.count, 6)
        XCTAssertEqual(state.seats.count, 4)
        XCTAssertEqual(state.people.count, 1)
        XCTAssertEqual(state.names, ["You", "Left", "Partner", "Right"])
        XCTAssertEqual(state.computerSeats, [1, 2, 3])
        XCTAssertTrue(state.myTiles.isEmpty)

        // The live server leaves "you" and "host" empty for computer seats.
        let text = String(decoding: try fixture("lobby_host"), as: UTF8.self)
            .replacingOccurrences(of: "\"you\": false", with: "\"you\": null")
            .replacingOccurrences(of: "\"host\": false", with: "\"host\": null")
        XCTAssertTrue(text.contains("null"))
        let tolerant = try OnlineState.decode(Data(text.utf8))
        XCTAssertEqual(tolerant.seats, state.seats)
    }

    func testLobbyForAGuestOnTheLeft() throws {
        let state = try OnlineState.decode(fixture("lobby_guest"))
        XCTAssertFalse(state.isHost)
        XCTAssertEqual(state.mySeat, 1)
        // From seat 1, the host (seat 0) sits on the right.
        XCTAssertEqual(state.local(0), 3)
        XCTAssertEqual(state.server(3), 0)
        XCTAssertEqual(state.names[3], "Alberto")
        XCTAssertEqual(state.names[0], "You")
        XCTAssertEqual(state.computerSeats, [1, 2])
        XCTAssertEqual(state.hostName, "Alberto Aday")
    }

    func testHome() throws {
        let home = try OnlineHome.decode(fixture("home_host"))
        XCTAssertEqual(home.name, "Alberto Aday")
        XCTAssertEqual(home.friendCode.count, 6)
        XCTAssertEqual(home.games.count, 1)
        XCTAssertEqual(home.games[0].players, ["Sam Lee"])
        XCTAssertEqual(home.games[0].phase, .lobby)
        XCTAssertTrue(home.games[0].isHost)
    }

    /// Mid-game from the guest's side: the board rebuilt from the log, the
    /// guest's own tiles, the others' counts, and every step along the way.
    func testPlayingFromTheGuestsSide() throws {
        let state = try OnlineState.decode(fixture("playing_guest"))
        XCTAssertEqual(state.phase, .playing)
        let game = state.game()
        XCTAssertEqual(game.current, state.local(state.current!))
        XCTAssertEqual(game.current, 0, "It's the guest's turn in this fixture")
        XCTAssertEqual(game.hands[0], Game.sorted(state.myTiles))
        let plays = state.actions.filter { if case .play = $0 { return true } else { return false } }
        XCTAssertEqual(game.board.count, plays.count)
        XCTAssertEqual(game.hands.map(\.count).reduce(0, +) + game.board.count, 40, "No tile goes missing")
        XCTAssertTrue(game.hands[1].allSatisfy(\.isHidden))
        XCTAssertEqual(Set(game.hands[1].map(\.id)).count, game.hands[1].count, "Hidden tiles keep distinct ids")
        // The guest's legal moves come from the real board.
        for move in game.legalMoves(for: 0) {
            XCTAssertTrue(game.board.canPlay(move.tile))
        }
        // Stepping through: each step has one more action, and the next actor's turn.
        for shown in 0...state.log.count {
            let step = state.game(showing: shown)
            XCTAssertEqual(step.log.count, shown)
            XCTAssertEqual(step.hands.map(\.count).reduce(0, +) + step.board.count, 40)
            if shown < state.log.count {
                XCTAssertEqual(step.current, state.local(state.log[shown].s))
            }
        }
        XCTAssertEqual(state.game(showing: 0).hands[0].count, 10, "Before anything was played the guest held ten")
    }

    /// A finished game: the result in Us/Them terms and everyone's tiles shown.
    func testGameOver() throws {
        let state = try OnlineState.decode(fixture("over"))
        let game = state.game()
        let result = try XCTUnwrap(game.result)
        XCTAssertEqual(result, state.gameResult)
        XCTAssertFalse(game.hands.flatMap { $0 }.contains(where: \.isHidden))
        XCTAssertEqual(game.hands.map(\.count).reduce(0, +) + game.board.count, 40)
        let match = state.match
        XCTAssertEqual(match.score(of: .us), state.score[state.mySeat % 2])
        XCTAssertEqual(match.score(of: .them), state.score[1 - state.mySeat % 2])
        XCTAssertEqual(match.gameNumber, state.gameNumber)
        if let winner = result.winner {
            XCTAssertEqual(match.openingTeam, winner, "The winners lead the next game")
        }
        // Not the last step yet: no result, hands still hidden.
        let before = state.game(showing: state.log.count - 1)
        XCTAssertNil(before.result)
        XCTAssertTrue(before.hands[1].allSatisfy(\.isHidden))
    }

    func testTurningTheTableKeepsTeams() throws {
        var state = try OnlineState.decode(fixture("lobby_host"))
        for mine in 0..<4 {
            state.mySeat = mine
            for seat in 0..<4 {
                XCTAssertEqual(state.server(state.local(seat)), seat)
                // Your partner is always on your team, the others never.
                XCTAssertEqual(Team.of(seat: state.local(seat)) == .us, seat % 2 == mine % 2)
            }
            XCTAssertEqual(state.team(mine % 2), .us)
        }
    }

    func testCodesAndNames() {
        XCTAssertEqual(OnlineJSON.cleanCode(" k7q-2mx "), "K7Q2MX")
        XCTAssertEqual(OnlineJSON.cleanCode("abcdefgh"), "ABCDEF")
        XCTAssertEqual(OnlineJSON.firstName("Sam Lee"), "Sam")
        XCTAssertNil(OnlineJSON.nameProblem("Sam"))
        XCTAssertNotNil(OnlineJSON.nameProblem("  "))
        XCTAssertNotNil(OnlineJSON.nameProblem("sam@mail.com"))
        XCTAssertNotNil(OnlineJSON.nameProblem(String(repeating: "a", count: 41)))
        var rng = SeededGenerator(seed: 3)
        let code = OnlineJSON.randomCode(using: &rng)
        XCTAssertEqual(code.count, 6)
        XCTAssertEqual(OnlineJSON.cleanCode(code), code)
    }
}

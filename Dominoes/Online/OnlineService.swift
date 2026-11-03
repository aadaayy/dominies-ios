import Foundation

/// Online games with friends. `SupabaseOnlineService` talks to the real game
/// server (the Dominoes Supabase project); `MockOnlineService` stands in for
/// it in the automatic checks, with pretend friends who join and play.
@MainActor
protocol OnlineService: AnyObject {
    /// Your name and friend code, friends, invites to you and your games.
    func home() async throws -> OnlineHome
    /// The name friends see.
    func setName(_ name: String) async throws
    func addFriend(code: String) async throws -> OnlineFriend
    func removeFriend(id: String) async throws

    func createGame(target: Int, level: BotLevel) async throws -> OnlineState
    func joinGame(code: String) async throws -> OnlineState
    func declineInvite(gameID: String) async throws
    func state(gameID: String) async throws -> OnlineState
    func invite(gameID: String, friendID: String) async throws -> OnlineState
    /// Before the start: move to an empty (computer) seat.
    func moveSeat(gameID: String, seat: Int) async throws -> OnlineState
    func setOptions(gameID: String, target: Int, level: BotLevel) async throws -> OnlineState
    func start(gameID: String) async throws -> OnlineState
    /// The leading team picks who plays first (a server seat).
    func chooseLeader(gameID: String, seat: Int) async throws -> OnlineState
    func play(gameID: String, tile: Tile, end: End?) async throws -> OnlineState
    /// Deals the next game after `gameNumber` ends.
    func nextGame(gameID: String, after gameNumber: Int) async throws -> OnlineState
    /// A player stopped answering on their turn: a computer takes the seat.
    func replaceWithComputer(gameID: String, seat: Int) async throws -> OnlineState
    func leave(gameID: String) async throws
    /// The host ends the room for everyone; the server deletes it.
    func disband(gameID: String) async throws

    /// Fires whenever the game changes on the server (or, for nil, when an
    /// invite to you arrives), while the stream is being read.
    func changes(gameID: String?) -> AsyncStream<Void>
}

enum OnlineError: LocalizedError, Equatable {
    case signedOut
    case needsName
    case noSuchCode
    case thatsYou
    case noSuchGame
    case gameFull
    case alreadyStarted
    case gameClosed
    case notYourTurn
    case doesNotFit
    case stillTheirTurn
    case tooMany
    case offline
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .signedOut: "Sign in to play with friends."
        case .needsName: "Choose the name your friends will see first."
        case .noSuchCode: "No one has that friend code. Check the six letters and try again."
        case .thatsYou: "That's your own code. Send it to a friend so they can add you."
        case .noSuchGame: "There's no game with that code. Check the six letters and try again."
        case .gameFull: "That game already has four players."
        case .alreadyStarted: "That game has already started."
        case .gameClosed: "That game was closed."
        case .notYourTurn: "It isn't your turn yet."
        case .doesNotFit: "That tile doesn't fit there."
        case .stillTheirTurn: "Give them a little longer. After a minute a computer can play for them."
        case .tooMany: "You're in a lot of games already. Finish or leave one first."
        case .offline: "No connection. Check your signal and try again."
        case .failed(let message): message
        }
    }

    /// The server's short error words to a plain message.
    static func from(serverMessage message: String) -> OnlineError {
        switch message {
        case "not_signed_in": .signedOut
        case "needs_name": .needsName
        case "no_such_code": .noSuchCode
        case "thats_you": .thatsYou
        case "no_such_game", "not_in_game": .noSuchGame
        case "game_full", "seat_taken": .gameFull
        case "already_started": .alreadyStarted
        case "game_closed": .gameClosed
        case "not_your_turn", "not_playing": .notYourTurn
        case "does_not_fit", "choose_an_end", "not_in_hand": .doesNotFit
        case "still_their_turn": .stillTheirTurn
        case "too_many_games", "too_many_friends": .tooMany
        case "host_only": .failed("Only the person who made the game can do that.")
        case "not_a_friend": .failed("Add them as a friend first.")
        case "not_your_team": .failed("The other team chooses who leads this game.")
        default: .failed("Something went wrong. Try again.")
        }
    }
}

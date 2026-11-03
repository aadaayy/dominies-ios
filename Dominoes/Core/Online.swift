import Foundation

// Online games, as the server describes them. The server (Supabase, in
// supabase/migrations) runs the rules, keeps the hands hidden and plays the
// computer seats; the phone only shows the table and sends its own moves.
//
// The server numbers seats 0 to 3 around the table, the same for everyone.
// Each phone turns the table so its own player is seat 0 at the bottom, so
// the game screen works exactly as it does against the computer: seat 1 is
// on your left, 2 is your partner and 3 is on your right.

extension Seat {
    /// What each seat is called on this phone: you, and where the others sit.
    static let names = ["You", "Left", "Partner", "Right"]
}

/// One seat at an online table.
struct OnlineSeat: Codable, Equatable, Hashable {
    /// The server's seat number.
    var seat: Int
    /// The player's name; nil for a computer.
    var name: String?
    var picture: URL?
    /// A person (false: a computer).
    var person: Bool
    var you: Bool
    var host: Bool

    var isComputer: Bool { !person }

    init(seat: Int, name: String?, picture: URL? = nil, person: Bool, you: Bool, host: Bool) {
        self.seat = seat
        self.name = name
        self.picture = picture
        self.person = person
        self.you = you
        self.host = host
    }

    // The server leaves "you" and "host" empty (null) for computer seats.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seat = try c.decode(Int.self, forKey: .seat)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        picture = try? c.decodeIfPresent(URL.self, forKey: .picture)
        person = try c.decodeIfPresent(Bool.self, forKey: .person) ?? false
        you = try c.decodeIfPresent(Bool.self, forKey: .you) ?? false
        host = try c.decodeIfPresent(Bool.self, forKey: .host) ?? false
    }
}

/// A play or a knock, as the server logs it.
struct OnlineAction: Codable, Equatable, Hashable {
    /// The server's seat number.
    var s: Int
    /// "play" or "knock".
    var t: String
    var tile: [Int]?
    /// "left", "right", or nil for the first tile.
    var e: String?
    /// A knock: the open numbers at the time.
    var l: Int?
    var r: Int?
}

/// How a game ended, as the server reports it.
struct OnlineResult: Codable, Equatable, Hashable {
    /// "domino", "blocked" or "tie".
    var kind: String
    /// Who went out (server seat).
    var seat: Int?
    /// The winning team (0: seats 0 and 2, 1: seats 1 and 3), nil for a tie.
    var winner: Int?
    var points: Int
    /// Pips left in each team's hands.
    var pips: [Int]
}

/// Everything one player's phone gets for one online game.
struct OnlineState: Codable, Equatable {
    enum Phase: String, Codable {
        /// Waiting for friends; the host starts it.
        case lobby
        /// A team chooses who plays first.
        case choosing
        case playing
        /// A game ended.
        case over
        /// A team reached the target.
        case matchOver = "match_over"
        /// The host closed it, or everyone left.
        case closed
    }

    var id: String
    /// The six letters friends type to join.
    var code: String
    var phase: Phase
    var target: Int
    /// The computer players' level: "easy" or "normal".
    var level: String
    var mySeat: Int
    /// Null from the server when the host has deleted their account.
    var isHostValue: Bool?
    var isHost: Bool {
        get { isHostValue ?? false }
        set { isHostValue = newValue }
    }
    var version: Int
    /// Points for team 0 (seats 0 and 2) and team 1.
    var score: [Int]
    var gameNumber: Int
    var openingTeam: Int?
    var matchWinner: Int?
    var starter: Int?
    var current: Int?
    var log: [OnlineAction]
    var result: OnlineResult?
    /// Everyone's leftover tiles once a game ends, by server seat.
    var revealed: [[[Int]]]?
    /// Seconds since the current turn started.
    var turnSeconds: Int?
    var seats: [OnlineSeat]
    /// Your own tiles (none before the first deal, when the server sends null).
    var hand: [[Int]]?

    enum CodingKeys: String, CodingKey {
        case id, code, phase, target, level, mySeat, version, score, gameNumber, openingTeam, matchWinner
        case starter, current, log, result, revealed, turnSeconds, seats, hand
        case isHostValue = "isHost"
    }

    /// Reads the server's JSON (snake_case keys).
    static func decode(_ data: Data) throws -> OnlineState {
        try OnlineJSON.decoder.decode(OnlineState.self, from: data)
    }

    // MARK: - Turning the table

    /// Server seat to the seat on this phone (0 is you, 1 your left, 2 your partner, 3 your right).
    func local(_ seat: Int) -> Int { (seat - mySeat + 4) % 4 }
    /// Seat on this phone to the server's seat.
    func server(_ local: Int) -> Int { (local + mySeat) % 4 }

    /// The server's team number to Us or Them for this phone.
    func team(_ serverTeam: Int) -> Team { serverTeam == mySeat % 2 ? .us : .them }

    func seat(local: Int) -> OnlineSeat? { seats.first { $0.seat == server(local) } }

    var myTiles: [Tile] { (hand ?? []).compactMap(OnlineJSON.tile) }

    /// Plays and knocks so far this game, with this phone's seat numbers.
    var actions: [Action] { log.compactMap(action) }

    func action(_ entry: OnlineAction) -> Action? {
        let seat = local(entry.s)
        if entry.t == "knock" {
            return .knock(seat: seat, leftOpen: entry.l ?? -1, rightOpen: entry.r ?? -1)
        }
        guard let tile = entry.tile.flatMap(OnlineJSON.tile) else { return nil }
        let end: End? = entry.e.flatMap(End.init(rawValue:))
        return .play(seat: seat, tile: tile, end: end)
    }

    var match: Match {
        Match(target: target,
              usScore: score.indices.contains(mySeat % 2) ? score[mySeat % 2] : 0,
              themScore: score.indices.contains(1 - mySeat % 2) ? score[1 - mySeat % 2] : 0,
              gameNumber: gameNumber,
              openingTeam: openingTeam.map(team) ?? .us,
              winner: matchWinner.map(team))
    }

    /// The table after the first `shown` plays and knocks of this game, so a
    /// phone can show the computers' turns one at a time. With everything
    /// shown, a finished game includes its result and everyone's tiles.
    func game(showing shown: Int? = nil) -> Game {
        let all = actions
        let count = min(max(shown ?? all.count, 0), all.count)
        let done = Array(all.prefix(count))
        let later = all.dropFirst(count)
        let finished = count == all.count && result != nil

        var hands: [[Tile]] = []
        for seat in 0..<4 {
            if finished, let revealed, revealed.indices.contains(server(seat)) {
                hands.append(revealed[server(seat)].compactMap(OnlineJSON.tile))
            } else if seat == 0 {
                // Your tiles now, plus any you played after this point.
                var tiles = myTiles
                for case .play(0, let tile, _) in later { tiles.append(tile) }
                hands.append(tiles)
            } else {
                let played = done.filter { if case .play(seat, _, _) = $0 { return true } else { return false } }.count
                hands.append((0..<max(Game.handSize - played, 0)).map(Tile.hidden))
            }
        }

        let current: Int
        if count < all.count {
            current = all[count].seat
        } else if phase == .playing, let seat = self.current {
            current = local(seat)
        } else {
            current = -1
        }
        return Game(snapshot: hands, log: done,
                    starter: starter.map(local) ?? max(current, 0),
                    current: current,
                    result: finished ? gameResult : nil)
    }

    var gameResult: GameResult? {
        guard let result else { return nil }
        let kind: GameResult.Kind
        switch result.kind {
        case "domino": kind = .domino(seat: local(result.seat ?? mySeat))
        case "tie": kind = .tie
        default: kind = .blocked
        }
        let pips = result.pips.count == 2 ? result.pips : [0, 0]
        return GameResult(kind: kind,
                          winner: result.winner.map(team),
                          points: result.points,
                          usPips: pips[mySeat % 2],
                          themPips: pips[1 - mySeat % 2])
    }

    /// Whether your team picks who leads now.
    var yourTeamChooses: Bool { phase == .choosing && openingTeam == mySeat % 2 }

    /// The names the game screen shows, by this phone's seat: you, then the
    /// others' first names. A computer seat is named after where it sits.
    var names: [String] {
        (0..<4).map { local in
            if local == 0 { return "You" }
            guard let seat = seat(local: local), let name = seat.name, seat.person else {
                // An empty seat is played by a computer once the game starts.
                return "Computer"
            }
            return OnlineJSON.firstName(name)
        }
    }

    /// Seats (this phone's numbers) a computer plays.
    var computerSeats: Set<Int> {
        Set((0..<4).filter { seat(local: $0)?.isComputer ?? true })
    }

    var people: [OnlineSeat] { seats.filter(\.person) }
    var hostName: String? { seats.first(where: \.host)?.name }
}

/// A friend in your list.
struct OnlineFriend: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var picture: URL?
}

/// An invite to someone else's game.
struct OnlineInvite: Codable, Equatable, Hashable, Identifiable {
    var gameId: String
    var code: String
    var from: String
    var fromPicture: URL?
    /// Everyone already in the game, the host included.
    var players: [String]
    var id: String { gameId }
}

/// A game you're in, for the list on the Play with Friends page.
struct OnlineGameSummary: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var code: String
    var phase: OnlineState.Phase
    var gameNumber: Int
    var isHost: Bool
    var yourTurn: Bool
    /// The other people in it (not computers, not you).
    var players: [String]
    /// Friends invited who haven't joined yet (their ids).
    var invited: [String]
    var score: [Int]
    var mySeat: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        code = try c.decode(String.self, forKey: .code)
        phase = try c.decode(OnlineState.Phase.self, forKey: .phase)
        gameNumber = try c.decodeIfPresent(Int.self, forKey: .gameNumber) ?? 0
        isHost = try c.decodeIfPresent(Bool.self, forKey: .isHost) ?? false
        yourTurn = try c.decodeIfPresent(Bool.self, forKey: .yourTurn) ?? false
        players = try c.decodeIfPresent([String].self, forKey: .players) ?? []
        invited = try c.decodeIfPresent([String].self, forKey: .invited) ?? []
        score = try c.decodeIfPresent([Int].self, forKey: .score) ?? [0, 0]
        mySeat = try c.decodeIfPresent(Int.self, forKey: .mySeat) ?? 0
    }

    init(id: String, code: String, phase: OnlineState.Phase, gameNumber: Int, isHost: Bool, yourTurn: Bool,
         players: [String], invited: [String], score: [Int], mySeat: Int) {
        self.id = id
        self.code = code
        self.phase = phase
        self.gameNumber = gameNumber
        self.isHost = isHost
        self.yourTurn = yourTurn
        self.players = players
        self.invited = invited
        self.score = score
        self.mySeat = mySeat
    }

    var usScore: Int { score.indices.contains(mySeat % 2) ? score[mySeat % 2] : 0 }
    var themScore: Int { score.indices.contains(1 - mySeat % 2) ? score[1 - mySeat % 2] : 0 }
}

/// The Play with Friends page: your name and code, friends, invites and games.
struct OnlineHome: Codable, Equatable {
    /// Nil until the player has a name others can see.
    var name: String?
    var friendCode: String
    var friends: [OnlineFriend]
    var invites: [OnlineInvite]
    var games: [OnlineGameSummary]

    static func decode(_ data: Data) throws -> OnlineHome {
        try OnlineJSON.decoder.decode(OnlineHome.self, from: data)
    }

    static let empty = OnlineHome(name: nil, friendCode: "", friends: [], invites: [], games: [])
}

enum OnlineJSON {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    static func tile(_ pair: [Int]) -> Tile? {
        guard pair.count == 2, (0...9).contains(pair[0]), (0...9).contains(pair[1]) else { return nil }
        return Tile(pair[0], pair[1])
    }

    static func pair(_ tile: Tile) -> [Int] { [tile.low, tile.high] }

    /// "Sam Lee" is Sam; "sam.lee@mail.com" stays as it is (never shown to
    /// others: the server asks for a name first).
    static func firstName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    /// Codes are shown and typed as six letters and digits, in capitals.
    static func cleanCode(_ text: String) -> String {
        String(text.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
    }

    /// Letters and digits used in codes, without ones that look alike.
    static let codeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    static func randomCode<R: RandomNumberGenerator>(using rng: inout R) -> String {
        String((0..<6).map { _ in codeAlphabet.randomElement(using: &rng)! })
    }

    /// The longest name the server keeps.
    static let nameLimit = 40

    /// Why a name won't do, or nil when it's fine.
    static func nameProblem(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Type the name your friends know you by." }
        if trimmed.count > nameLimit { return "Use \(nameLimit) characters or fewer." }
        if trimmed.contains("@") { return "Use a name, not an email address, so your email stays private." }
        return nil
    }
}

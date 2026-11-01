/// Seats around the table, in turn order (clockwise, to the left):
/// 0 is you at the bottom, 1 on your left, 2 your partner at the top and
/// 3 on your right. Turns go 0, 1, 2, 3, so they alternate between teams.
enum Seat {
    static let all = [0, 1, 2, 3]
    static func next(after seat: Int) -> Int { (seat + 1) % 4 }
    static func partner(of seat: Int) -> Int { (seat + 2) % 4 }
}

/// Something a player did on their turn.
enum Action: Hashable, Codable {
    case play(seat: Int, tile: Tile, end: End?)
    /// A knock (pass). Remembers which numbers were open, since a player who
    /// knocks has none of them, which the bots keep track of.
    case knock(seat: Int, leftOpen: Int, rightOpen: Int)

    var seat: Int {
        switch self {
        case .play(let seat, _, _), .knock(let seat, _, _): return seat
        }
    }
}

/// A tile that can be played now, and the ends it fits.
/// On an empty table `ends` is empty: the opening tile needs no end.
struct Move: Hashable {
    let tile: Tile
    let ends: [End]
}

/// How a game ended.
struct GameResult: Hashable, Codable {
    enum Kind: Hashable, Codable {
        /// A player went out (played their last tile).
        case domino(seat: Int)
        /// Nobody could play; the lighter team won.
        case blocked
        /// Nobody could play and both teams held the same pips: no points.
        case tie
    }

    let kind: Kind
    /// Nil for a tie.
    let winner: Team?
    let points: Int
    /// Pips left in each team's two hands.
    let usPips: Int
    let themPips: Int
}

enum GameError: Error, Equatable {
    case gameOver
    case notYourTurn
    case notInHand
    case doesNotFit
    case chooseAnEnd
    case mustPlay
}

/// One game (one hand of tiles) of partner Double Nine: four players, ten
/// tiles each, no drawing from the boneyard.
struct Game: Hashable, Codable {
    static let handSize = 10

    private(set) var hands: [[Tile]]
    /// Tiles nobody was dealt. They stay out of play.
    let boneyard: [Tile]
    private(set) var board = Board()
    private(set) var current: Int
    let starter: Int
    private(set) var knocksInARow = 0
    private(set) var log: [Action] = []
    private(set) var result: GameResult?

    var isOver: Bool { result != nil }

    init(hands: [[Tile]], boneyard: [Tile] = [], starter: Int) {
        precondition(hands.count == 4)
        self.hands = hands.map(Game.sorted)
        self.boneyard = boneyard
        self.starter = starter
        current = starter
    }

    /// Shuffles a double-nine set and deals ten tiles each. Deals again
    /// whenever anyone gets five or more doubles.
    static func deal<R: RandomNumberGenerator>(using rng: inout R) -> (hands: [[Tile]], boneyard: [Tile]) {
        while true {
            let shuffled = Tile.fullSet().shuffled(using: &rng)
            let hands = (0..<4).map { seat in Array(shuffled[(seat * handSize)..<((seat + 1) * handSize)]) }
            if hands.allSatisfy({ $0.filter(\.isDouble).count < 5 }) {
                return (hands.map(sorted), Array(shuffled[(4 * handSize)...]))
            }
        }
    }

    /// A hand in a tidy order: by number, doubles after their suit.
    static func sorted(_ hand: [Tile]) -> [Tile] {
        hand.sorted { ($0.high, $0.low) < ($1.high, $1.low) }
    }

    func team(of seat: Int) -> Team { Team.of(seat: seat) }

    func pips(of seat: Int) -> Int { hands[seat].reduce(0) { $0 + $1.pips } }

    func pips(of team: Team) -> Int { team.seats.reduce(0) { $0 + pips(of: $1) } }

    func legalMoves(for seat: Int) -> [Move] {
        if board.isEmpty { return hands[seat].map { Move(tile: $0, ends: []) } }
        return hands[seat].compactMap { tile in
            let ends = board.ends(for: tile)
            return ends.isEmpty ? nil : Move(tile: tile, ends: ends)
        }
    }

    func canPlay(_ seat: Int) -> Bool { !legalMoves(for: seat).isEmpty }

    /// Plays a tile for whoever's turn it is. `end` can be left out when the
    /// tile fits only one end, or both ends show the same number.
    mutating func play(_ tile: Tile, on end: End? = nil) throws {
        guard result == nil else { throw GameError.gameOver }
        let seat = current
        guard let index = hands[seat].firstIndex(of: tile) else { throw GameError.notInHand }

        var chosen: End? = nil
        if !board.isEmpty {
            let ends = board.ends(for: tile)
            guard !ends.isEmpty else { throw GameError.doesNotFit }
            if let end {
                guard ends.contains(end) else { throw GameError.doesNotFit }
                chosen = end
            } else if ends.count == 1 || board.leftOpen == board.rightOpen {
                chosen = ends.count == 1 ? ends[0] : shorterArm
            } else {
                throw GameError.chooseAnEnd
            }
        }

        board.place(tile, on: chosen)
        hands[seat].remove(at: index)
        log.append(.play(seat: seat, tile: tile, end: chosen))
        knocksInARow = 0

        if hands[seat].isEmpty {
            // Going out wins at once for the team; the partner's tiles don't count.
            let losers = team(of: seat).other
            finish(GameResult(kind: .domino(seat: seat), winner: team(of: seat), points: pips(of: losers),
                              usPips: pips(of: .us), themPips: pips(of: .them)))
            return
        }
        current = Seat.next(after: seat)
    }

    /// Knocks (passes) for whoever's turn it is. Only allowed with no tile to play.
    mutating func knock() throws {
        guard result == nil else { throw GameError.gameOver }
        let seat = current
        guard !canPlay(seat) else { throw GameError.mustPlay }
        log.append(.knock(seat: seat, leftOpen: board.leftOpen ?? -1, rightOpen: board.rightOpen ?? -1))
        knocksInARow += 1
        if knocksInARow >= 4 {
            finishBlocked()
            return
        }
        current = Seat.next(after: seat)
    }

    /// When both ends show the same number, a tile goes on the shorter arm.
    private var shorterArm: End { board.leftArm.count <= board.rightArm.count ? .left : .right }

    private mutating func finishBlocked() {
        let us = pips(of: .us)
        let them = pips(of: .them)
        if us == them {
            finish(GameResult(kind: .tie, winner: nil, points: 0, usPips: us, themPips: them))
        } else {
            let winner: Team = us < them ? .us : .them
            finish(GameResult(kind: .blocked, winner: winner, points: max(us, them), usPips: us, themPips: them))
        }
    }

    private mutating func finish(_ result: GameResult) {
        self.result = result
    }
}

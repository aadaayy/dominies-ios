/// How well the computer players play.
enum BotLevel: String, Codable, CaseIterable, Identifiable {
    /// Any legal tile.
    case easy
    /// Thinks about each tile: sheds heavy tiles and doubles, keeps a follow-up,
    /// plays numbers the next opponent has knocked on, and avoids numbers its
    /// partner has knocked on.
    case normal

    var id: String { rawValue }
    var title: String { self == .easy ? "Easy" : "Normal" }
}

/// A computer player. It only uses what a person at the table could know:
/// its own hand, the tiles on the table and who knocked on what.
struct Bot {
    let level: BotLevel

    /// The tile and end to play, or nil to knock.
    func choose<R: RandomNumberGenerator>(in game: Game, using rng: inout R) -> (tile: Tile, end: End?)? {
        let seat = game.current
        let moves = game.legalMoves(for: seat)
        guard !moves.isEmpty else { return nil }

        let options: [(tile: Tile, end: End?)] = moves.flatMap { move -> [(tile: Tile, end: End?)] in
            move.ends.isEmpty ? [(tile: move.tile, end: nil)] : move.ends.map { (tile: move.tile, end: Optional($0)) }
        }

        switch level {
        case .easy:
            return options.randomElement(using: &rng)
        case .normal:
            let knowledge = Knowledge(game: game, seat: seat)
            var best = options[0]
            var bestScore = -Double.infinity
            for option in options {
                let score = knowledge.score(option.tile, on: option.end) + Double.random(in: 0..<0.5, using: &rng)
                if score > bestScore {
                    bestScore = score
                    best = option
                }
            }
            return best
        }
    }

    /// Which teammate leads when this bot's team opens: the one holding
    /// more doubles, since doubles are the hardest tiles to get rid of.
    static func starter(for team: Team, hands: [[Tile]]) -> Int {
        let seats = team.seats
        let doubles = seats.map { seat in hands[seat].filter(\.isDouble).count }
        return doubles[0] >= doubles[1] ? seats[0] : seats[1]
    }
}

/// What a seat can work out from the table.
struct Knowledge {
    let game: Game
    let seat: Int
    /// Numbers each seat is known not to hold, from their knocks.
    let missing: [Set<Int>]

    init(game: Game, seat: Int) {
        self.game = game
        self.seat = seat
        var missing = Array(repeating: Set<Int>(), count: 4)
        for action in game.log {
            if case .knock(let who, let left, let right) = action, left >= 0 {
                missing[who].insert(left)
                missing[who].insert(right)
            }
        }
        self.missing = missing
    }

    /// How many tiles with this number this seat can't see (in other hands
    /// or the boneyard).
    func unseen(_ value: Int) -> Int {
        let seen = game.board.tiles + game.hands[seat]
        return Tile.fullSet().filter { $0.has(value) && !seen.contains($0) }.count
    }

    func score(_ tile: Tile, on end: End?) -> Double {
        let hand = game.hands[seat].filter { $0 != tile }
        var score = Double(tile.pips)
        if tile.isDouble { score += 6 }

        // The opening tile: lead with a heavy double, or the suit we hold most of.
        guard let end else {
            let suitCount = hand.filter { $0.has(tile.low) || $0.has(tile.high) }.count
            return score + Double(suitCount) * 2
        }

        // The two numbers left open after this play.
        let value = game.board.open(end)!
        let newOpen = tile.other(than: value)
        let ends = end == .left ? (newOpen, game.board.rightOpen!) : (game.board.leftOpen!, newOpen)
        let openNumbers = [ends.0, ends.1]

        // Keep tiles we can follow up with.
        let followUps = hand.filter { $0.has(ends.0) || $0.has(ends.1) }.count
        score += Double(min(followUps, 3)) * 2.5
        if followUps == 0 { score -= 6 }

        // Leave numbers the next opponent can't play; don't starve our partner.
        let nextOpponent = Seat.next(after: seat)
        let partner = Seat.partner(of: seat)
        let lastOpponent = Seat.next(after: partner)
        let blocksNext = openNumbers.filter { missing[nextOpponent].contains($0) }.count
        score += blocksNext == 2 ? 25 : Double(blocksNext) * 6
        score += Double(openNumbers.filter { missing[lastOpponent].contains($0) }.count) * 3
        let starvesPartner = openNumbers.filter { missing[partner].contains($0) }.count
        score -= starvesPartner == 2 ? 12 : Double(starvesPartner) * 4

        // A number nobody else can have is ours to control.
        for number in Set(openNumbers) where unseen(number) == 0 && hand.contains(where: { $0.has(number) }) {
            score += 4
        }
        return score
    }
}

/// A match: games played until one team reaches the target score.
struct Match: Hashable, Codable {
    static let targets = [100, 150, 200, 250]

    let target: Int
    private(set) var usScore = 0
    private(set) var themScore = 0
    private(set) var gameNumber = 1
    /// The team that picks who leads the next game.
    private(set) var openingTeam: Team
    private(set) var winner: Team?

    init(target: Int = 100, openingTeam: Team) {
        self.target = target
        self.openingTeam = openingTeam
    }

    /// The first game's opening team comes from a fair draw.
    init<R: RandomNumberGenerator>(target: Int = 100, using rng: inout R) {
        self.init(target: target, openingTeam: Bool.random(using: &rng) ? .us : .them)
    }

    func score(of team: Team) -> Int { team == .us ? usScore : themScore }

    /// Adds a finished game's points and works out who opens the next one:
    /// the winners, or after a tie, the team that went second.
    mutating func record(_ game: Game) {
        guard let result = game.result, winner == nil else { return }
        if let team = result.winner {
            if team == .us { usScore += result.points } else { themScore += result.points }
            openingTeam = team
        } else {
            openingTeam = Team.of(seat: game.starter).other
        }
        if usScore >= target { winner = .us } else if themScore >= target { winner = .them }
        if winner == nil { gameNumber += 1 }
    }
}

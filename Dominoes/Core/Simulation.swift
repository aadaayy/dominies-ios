/// Plays games with bots in every seat, for tests and for the screenshot demo.
enum Simulation {
    /// Deals and plays a whole game with bots in every seat.
    static func playOut<R: RandomNumberGenerator>(starter: Int, levels: [BotLevel], using rng: inout R) throws -> Game {
        let deal = Game.deal(using: &rng)
        var game = Game(hands: deal.hands, boneyard: deal.boneyard, starter: starter)
        try playOn(&game, levels: levels, moves: Int.max, using: &rng)
        return game
    }

    /// Lets bots take up to `moves` turns (stopping when the game ends).
    static func playOn<R: RandomNumberGenerator>(_ game: inout Game, levels: [BotLevel], moves: Int, using rng: inout R) throws {
        var taken = 0
        while !game.isOver && taken < moves {
            let bot = Bot(level: levels[game.current])
            if let choice = bot.choose(in: game, using: &rng) {
                try game.play(choice.tile, on: choice.end)
            } else {
                try game.knock()
            }
            taken += 1
        }
    }
}

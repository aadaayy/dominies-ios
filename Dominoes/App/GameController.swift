import SwiftUI
import Observation

/// Runs a match against three computer players: deals, waits for your
/// moves, lets the bots take their turns, and keeps the score.
@MainActor
@Observable
final class GameController {
    enum Phase: Equatable {
        /// Your team leads: pick who goes first.
        case choosingStarter
        case playing
        /// The game ended; the result card is showing.
        case gameOver
        /// A team reached the target.
        case matchOver
    }

    static let names = ["You", "Left", "Partner", "Right"]

    private(set) var match: Match
    private(set) var game: Game
    private(set) var phase: Phase = .playing
    /// A tile you picked that fits both ends, waiting for you to choose one.
    private(set) var pendingTile: Tile?
    /// Bumped on every play, for the tap feel and the animations.
    private(set) var playCount = 0

    let level: BotLevel
    @ObservationIgnored private let options: LaunchOptions
    @ObservationIgnored private var rng: SeededGenerator
    @ObservationIgnored private var turnTask: Task<Void, Never>?

    init(target: Int, level: BotLevel, options: LaunchOptions = .current) {
        self.level = level
        self.options = options
        var rng = options.seed.map(SeededGenerator.init(seed:)) ?? SeededGenerator()
        var match = Match(target: target, using: &rng)
        if let first = options.firstTeam { match = Match(target: target, openingTeam: first) }
        self.match = match
        let deal = Game.deal(using: &rng)
        self.game = Game(hands: deal.hands, boneyard: deal.boneyard, starter: match.openingTeam.seats[0])
        self.rng = rng
        beginGame(hands: deal.hands, boneyard: deal.boneyard)
    }

    // MARK: - What the screen shows

    var yourHand: [Tile] { game.hands[0] }
    var isYourTurn: Bool { phase == .playing && game.current == 0 && !game.isOver }
    var yourMoves: [Move] { isYourTurn ? game.legalMoves(for: 0) : [] }

    func canPlay(_ tile: Tile) -> Bool { yourMoves.contains { $0.tile == tile } }

    /// The last thing a seat did this game, for the little note by their name.
    func lastAction(of seat: Int) -> Action? { game.log.last { $0.seat == seat } }

    var status: String {
        switch phase {
        case .choosingStarter: return "Your team leads"
        case .gameOver, .matchOver: return ""
        case .playing:
            if game.isOver { return "" }
            if game.current == 0 {
                if game.board.isEmpty { return "You lead. Play any tile." }
                return yourMoves.isEmpty ? "No tile to play" : "Your turn"
            }
            return "\(Self.names[game.current]) is playing"
        }
    }

    // MARK: - Your moves

    /// Your team leads: you, or your partner.
    func lead(withPartner: Bool) {
        guard phase == .choosingStarter else { return }
        game = Game(hands: game.hands, boneyard: game.boneyard, starter: withPartner ? 2 : 0)
        phase = .playing
        nextTurn()
    }

    func tap(_ tile: Tile) {
        guard isYourTurn, let move = yourMoves.first(where: { $0.tile == tile }) else { return }
        if move.ends.count > 1 && game.board.leftOpen != game.board.rightOpen {
            pendingTile = pendingTile == tile ? nil : tile
            return
        }
        commit(tile, on: nil)
    }

    func play(pendingOn end: End) {
        guard let tile = pendingTile else { return }
        commit(tile, on: end)
    }

    func cancelPending() { pendingTile = nil }

    func knock() {
        guard isYourTurn, yourMoves.isEmpty else { return }
        turnTask?.cancel()
        try? game.knock()
        afterAction()
    }

    func nextGame() {
        guard phase == .gameOver else { return }
        let deal = Game.deal(using: &rng)
        beginGame(hands: deal.hands, boneyard: deal.boneyard)
    }

    func stop() { turnTask?.cancel() }

    // MARK: - Turns

    private func beginGame(hands: [[Tile]], boneyard: [Tile]) {
        pendingTile = nil
        if match.openingTeam == .us && options.demoMoves == 0 {
            game = Game(hands: hands, boneyard: boneyard, starter: 0)
            phase = .choosingStarter
            return
        }
        let starter = match.openingTeam == .us ? 0 : Bot.starter(for: .them, hands: hands)
        game = Game(hands: hands, boneyard: boneyard, starter: starter)
        phase = .playing
        if options.demoMoves > 0 && match.gameNumber == 1 {
            let levels = Array(repeating: BotLevel.normal, count: 4)
            try? Simulation.playOn(&game, levels: levels, moves: options.demoMoves, using: &rng)
            playCount += 1
            if game.isOver { finishGame(); return }
        }
        nextTurn()
    }

    private func commit(_ tile: Tile, on end: End?) {
        do {
            try game.play(tile, on: end)
        } catch {
            return
        }
        pendingTile = nil
        afterAction()
    }

    private func afterAction() {
        playCount += 1
        if game.isOver { finishGame() } else { nextTurn() }
    }

    private func finishGame() {
        turnTask?.cancel()
        match.record(game)
        phase = match.winner == nil ? .gameOver : .matchOver
    }

    private func nextTurn() {
        turnTask?.cancel()
        guard phase == .playing, !game.isOver else { return }
        let seat = game.current
        if seat == 0 {
            // With nothing to play, knock for you after a moment.
            guard yourMoves.isEmpty else { return }
            turnTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { return }
                self?.knock()
            }
            return
        }
        let delay = options.botDelay
        turnTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.botTurn()
        }
    }

    private func botTurn() {
        guard phase == .playing, !game.isOver, game.current != 0 else { return }
        let bot = Bot(level: game.current == 2 ? .normal : level)
        if let choice = bot.choose(in: game, using: &rng) {
            try? game.play(choice.tile, on: choice.end)
        } else {
            try? game.knock()
        }
        afterAction()
    }
}

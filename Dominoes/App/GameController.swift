import SwiftUI
import Observation

/// Runs a match on this phone: against three computer players, or online
/// with friends. Offline it deals, waits for your moves, lets the bots take
/// their turns and keeps the score. Online the game server does all that;
/// this shows what the server sends (the others' turns one at a time) and
/// sends your moves. Either way seat 0 is you, so the game screen is the same.
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

    /// Offline seat names, by seat: you, then where the others sit.
    static let names = Seat.names
    static let positionNames = Seat.names

    private(set) var match: Match
    private(set) var game: Game
    private(set) var phase: Phase = .playing
    /// A tile you picked that fits both ends, waiting for you to choose one.
    private(set) var pendingTile: Tile?
    /// Bumped on every play, for the tap feel and the animations.
    private(set) var playCount = 0

    /// What each seat is called: "You", then friends' first names online, or
    /// where a computer sits ("Left", "Partner", "Right").
    private(set) var names: [String] = GameController.names
    /// The seats a computer plays.
    private(set) var computerSeats: Set<Int> = [1, 2, 3]
    let isOnline: Bool

    // Online only.
    /// The latest from the game server.
    private(set) var online: OnlineState?
    /// Something to tell the player: a lost connection or a refused move.
    private(set) var problem: String?
    /// Waiting for the server to take your move.
    private(set) var sending = false
    /// The host disbanded the room (the server deleted it).
    private(set) var vanished = false
    var isClosed: Bool { vanished || online?.phase == .closed }
    var isHost: Bool { online?.isHost ?? false }

    let level: BotLevel
    @ObservationIgnored private let options: LaunchOptions
    @ObservationIgnored private var rng: SeededGenerator
    @ObservationIgnored private var turnTask: Task<Void, Never>?
    @ObservationIgnored private let service: OnlineService?
    /// How many of this game's plays and knocks are on the table so far.
    @ObservationIgnored private var shown = 0
    @ObservationIgnored private var shownGame = -1
    @ObservationIgnored private var stepTask: Task<Void, Never>?
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var receivedAt = Date()

    init(target: Int, level: BotLevel, options: LaunchOptions = .current) {
        self.level = level
        self.options = options
        isOnline = false
        service = nil
        var rng = options.seed.map(SeededGenerator.init(seed:)) ?? SeededGenerator()
        var match = Match(target: target, using: &rng)
        if let first = options.firstTeam { match = Match(target: target, openingTeam: first) }
        self.match = match
        let deal = Game.deal(using: &rng)
        self.game = Game(hands: deal.hands, boneyard: deal.boneyard, starter: match.openingTeam.seats[0])
        self.rng = rng
        beginGame(hands: deal.hands, boneyard: deal.boneyard)
    }

    /// An online game, from the server's latest state.
    init(online state: OnlineState, service: OnlineService, options: LaunchOptions = .current) {
        self.options = options
        self.service = service
        isOnline = true
        level = BotLevel(rawValue: state.level) ?? .normal
        rng = SeededGenerator()
        match = state.match
        game = state.game(showing: 0)
        shownGame = state.gameNumber
        apply(state, fresh: true)
        listen()
    }

    // MARK: - What the screen shows

    var yourHand: [Tile] { game.hands[0] }
    var isYourTurn: Bool { phase == .playing && game.current == 0 && !game.isOver && !sending }
    var yourMoves: [Move] { isYourTurn ? game.legalMoves(for: 0) : [] }

    func canPlay(_ tile: Tile) -> Bool { yourMoves.contains { $0.tile == tile } }

    /// The last thing a seat did this game, for the little note by their name.
    func lastAction(of seat: Int) -> Action? { game.log.last { $0.seat == seat } }

    func isComputer(_ seat: Int) -> Bool { seat != 0 && computerSeats.contains(seat) }

    var status: String {
        if isOnline, let online, caughtUp {
            if isClosed { return "This room was closed" }
            if online.phase == .choosing && !online.yourTeamChooses {
                let choosers = (0..<4).filter { Team.of(seat: $0) == .them && !isComputer($0) }.map { names[$0] }
                return "Waiting for \(choosers.first ?? "them") to choose who leads"
            }
        }
        switch phase {
        case .choosingStarter: return "Your team leads"
        case .gameOver, .matchOver: return ""
        case .playing:
            if game.isOver { return "" }
            if sending { return "Playing…" }
            if game.current == 0 {
                if game.board.isEmpty { return "You lead. Play any tile." }
                return yourMoves.isEmpty ? "No tile to play" : "Your turn"
            }
            guard names.indices.contains(game.current) else { return "" }
            if isOnline && !isComputer(game.current) { return "Waiting for \(names[game.current])" }
            return "\(names[game.current]) is playing"
        }
    }

    /// Online: a friend whose turn has gone on for a minute or more (this
    /// phone's seat number), so a computer can be offered in their place.
    var stalledSeat: Int? {
        guard isOnline, let online, caughtUp, online.phase == .playing, let current = online.current else { return nil }
        let seat = online.local(current)
        guard seat != 0, !isComputer(seat) else { return nil }
        let seconds = (online.turnSeconds ?? 0) + Int(Date().timeIntervalSince(receivedAt))
        return seconds >= 60 ? seat : nil
    }

    // MARK: - Your moves

    /// Your team leads: you, or your partner.
    func lead(withPartner: Bool) {
        guard phase == .choosingStarter else { return }
        if isOnline {
            guard let online else { return }
            send { try await $0.chooseLeader(gameID: online.id, seat: online.server(withPartner ? 2 : 0)) }
            return
        }
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
        // Online, the server knocks for anyone with nothing to play.
        guard !isOnline, isYourTurn, yourMoves.isEmpty else { return }
        turnTask?.cancel()
        try? game.knock()
        afterAction()
    }

    func nextGame() {
        guard phase == .gameOver else { return }
        if isOnline {
            guard let online else { return }
            send { try await $0.nextGame(gameID: online.id, after: online.gameNumber) }
            return
        }
        let deal = Game.deal(using: &rng)
        beginGame(hands: deal.hands, boneyard: deal.boneyard)
    }

    /// Online: let a computer play for a friend who stopped answering.
    func replaceStalledPlayer() {
        guard let seat = stalledSeat, let online else { return }
        send { try await $0.replaceWithComputer(gameID: online.id, seat: online.server(seat)) }
    }

    /// Online: leave the match; a computer takes your tiles.
    func leave() async {
        stop()
        guard let online, let service, !isClosed else { return }
        try? await service.leave(gameID: online.id)
    }

    /// Online, host only: end the room for everyone.
    func disband() async {
        stop()
        guard let online, let service, isHost else { return }
        try? await service.disband(gameID: online.id)
    }

    func dismissProblem() { problem = nil }

    func stop() {
        turnTask?.cancel()
        stepTask?.cancel()
        listenTask?.cancel()
        pollTask?.cancel()
    }

    // MARK: - Offline turns

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
        if isOnline {
            commitOnline(tile, on: end)
            return
        }
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

    // MARK: - Online

    private var caughtUp: Bool { online.map { shown >= $0.log.count } ?? true }

    /// Shows your tile at once, then sends it. If the server refuses, the
    /// table goes back to what it last said.
    private func commitOnline(_ tile: Tile, on end: End?) {
        guard let online, let service, !sending else { return }
        var next = game
        guard (try? next.play(tile, on: end)) != nil else { return }
        game = next
        pendingTile = nil
        shown += 1
        playCount += 1
        sending = true
        Task { [weak self] in
            do {
                let state = try await service.play(gameID: online.id, tile: tile, end: end)
                self?.sending = false
                self?.apply(state, fresh: true)
            } catch {
                guard let self else { return }
                self.sending = false
                self.shown = max(self.shown - 1, 0)
                self.refresh()
                self.failed(error)
            }
        }
    }

    private func send(_ call: @escaping (OnlineService) async throws -> OnlineState) {
        guard let service, !sending else { return }
        sending = true
        Task { [weak self] in
            do {
                let state = try await call(service)
                self?.sending = false
                self?.apply(state, fresh: true)
            } catch {
                self?.sending = false
                self?.failed(error)
            }
        }
    }

    /// Takes the server's latest. `fresh` is an answer to this phone's own
    /// call, which always wins; a fetched state that's older is ignored.
    private func apply(_ state: OnlineState, fresh: Bool = false) {
        if let online, !fresh, state.version < online.version { return }
        receivedAt = Date()
        if state.gameNumber != shownGame {
            shownGame = state.gameNumber
            shown = 0
        }
        shown = min(shown, state.log.count)
        online = state
        names = state.names
        computerSeats = state.computerSeats
        if fresh { problem = nil }
        advance()
    }

    /// Puts the next plays on the table one at a time, your own at once.
    private func advance() {
        stepTask?.cancel()
        guard let online else { return }
        while shown < online.log.count, online.local(online.log[shown].s) == 0 {
            shown += 1
            playCount += 1
        }
        refresh()
        guard shown < online.log.count else { return }
        let delay = options.botDelay
        stepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.shown += 1
            self.playCount += 1
            self.advance()
        }
    }

    /// Rebuilds the table from the server's state and how much of it is shown.
    private func refresh() {
        guard let online else { return }
        game = online.game(showing: shown)
        if pendingTile.map({ !game.hands[0].contains($0) }) == true { pendingTile = nil }
        guard caughtUp else {
            phase = .playing
            return
        }
        match = online.match
        switch online.phase {
        case .choosing: phase = online.yourTeamChooses ? .choosingStarter : .playing
        case .over: phase = .gameOver
        case .matchOver: phase = .matchOver
        case .lobby, .playing, .closed: phase = .playing
        }
    }

    /// Listens for changes on the server, and checks every few seconds too
    /// in case a change was missed (a phone that slept, a weak signal).
    private func listen() {
        guard let service, let id = online?.id else { return }
        listenTask = Task { [weak self] in
            for await _ in service.changes(gameID: id) {
                self?.fetch()
            }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                self?.fetch()
            }
        }
    }

    /// A call was refused: say why, or, when the room is gone, show that.
    private func failed(_ error: Error) {
        if (error as? OnlineError) == .noSuchGame {
            vanished = true
            stop()
        } else {
            problem = error.localizedDescription
            fetch()
        }
    }

    @ObservationIgnored private var fetching = false

    private func fetch() {
        guard let service, let id = online?.id, !fetching, !sending else { return }
        fetching = true
        Task { [weak self] in
            do {
                let state = try await service.state(gameID: id)
                self?.fetching = false
                guard self?.sending == false else { return }
                if self?.problem == OnlineError.offline.localizedDescription { self?.problem = nil }
                self?.apply(state)
            } catch {
                self?.fetching = false
                switch error as? OnlineError {
                case .offline?: self?.problem = error.localizedDescription
                case .noSuchGame?:
                    // The room was deleted: the host disbanded it.
                    self?.vanished = true
                    self?.stop()
                default: break
                }
            }
        }
    }
}

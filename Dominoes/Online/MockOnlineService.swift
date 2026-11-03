#if DEBUG
import Foundation

/// A pretend game server on the phone for the automatic checks, which can't
/// reach Supabase. It plays by the same rules (the app's own Game and Bot),
/// with pretend friends: Sam Lee and Jordan Park are already friends, and
/// Taylor Kim can be added with the code TAYLR4. Invited friends join after
/// a moment and take their turns after a short pause, as people would.
///
/// Launch options: -mockOnline turns it on (with -mockAccount -mockSignedIn),
/// -mockInvite adds an invite from Sam, -mockGameInProgress a game with Sam
/// waiting on your turn, -mockNoName starts without a name (like an email
/// account), -mockStall makes Jordan stop answering on their turn.
@MainActor
final class MockOnlineService: OnlineService {
    struct Person: Hashable {
        let id: String
        let name: String
        let code: String
    }

    static let me = Person(id: "mock-me", name: "Alex Rivera", code: "ALX7KQ")
    static let sam = Person(id: "mock-sam", name: "Sam Lee", code: "SAMLE2")
    static let jordan = Person(id: "mock-jordan", name: "Jordan Park", code: "JRDNP3")
    static let taylor = Person(id: "mock-taylor", name: "Taylor Kim", code: "TAYLR4")
    static let everyone = [me, sam, jordan, taylor]

    /// One game on the pretend server, in the server's seat numbers.
    final class Table {
        let id: String
        let code: String
        var host: String
        /// Person ids by seat; nil is a computer.
        var seats: [String?] = [nil, nil, nil, nil]
        var target = 100
        var level = BotLevel.normal
        var phase = OnlineState.Phase.lobby
        /// Seats 0 and 2 are team 0 ("us" in Match's terms).
        var match = Match(target: 100, openingTeam: .us)
        var game: Game?
        var gameNumber = 0
        var version = 0
        var invited: [String] = []
        var turnStarted = Date()

        init(id: String, code: String, host: String) {
            self.id = id
            self.code = code
            self.host = host
        }
    }

    private var name: String?
    private var friends: [Person]
    private var invites: [(game: String, from: String)] = []
    private var tables: [String: Table] = [:]
    private var rng: SeededGenerator
    private var listeners: [UUID: AsyncStream<Void>.Continuation] = [:]
    private let stall: Bool
    /// Sam ends the game a little after it starts (-mockHostEnds).
    private let hostEnds: Bool
    /// How long pretend friends take: to join, to start, to play.
    private let pause: Duration

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let options = LaunchOptions(arguments: arguments)
        rng = SeededGenerator(seed: options.seed ?? 7)
        name = arguments.contains("-mockNoName") ? nil : Self.me.name
        friends = [Self.sam, Self.jordan]
        stall = arguments.contains("-mockStall")
        hostEnds = arguments.contains("-mockHostEnds")
        pause = .milliseconds(Int(max(options.botDelay, 0.3) * 1500))
        if arguments.contains("-mockInvite") {
            let table = Table(id: "mock-game-sam", code: "Q8M3TZ", host: Self.sam.id)
            table.seats = [Self.sam.id, Self.jordan.id, nil, nil]
            table.invited = [Self.me.id]
            tables[table.id] = table
            invites.append((table.id, Self.sam.id))
        }
        if arguments.contains("-mockGameInProgress") {
            let table = Table(id: "mock-game-playing", code: "HV6WPC", host: Self.me.id)
            table.seats = [Self.me.id, nil, Self.sam.id, Self.jordan.id]
            tables[table.id] = table
            table.match = Match(target: 100, openingTeam: .them)
            deal(table)
        }
    }

    // MARK: - Home and friends

    func home() async throws -> OnlineHome {
        try await Task.sleep(for: .milliseconds(150))
        let games = tables.values
            .filter { $0.seats.contains(Self.me.id) && [.lobby, .choosing, .playing, .over].contains($0.phase) }
            .sorted { $0.id < $1.id }
            .map { table -> OnlineGameSummary in
                let seat = table.seats.firstIndex(of: Self.me.id) ?? 0
                return OnlineGameSummary(
                    id: table.id, code: table.code, phase: table.phase, gameNumber: table.gameNumber,
                    isHost: table.host == Self.me.id,
                    yourTurn: (table.phase == .playing && table.game?.current == seat)
                        || (table.phase == .choosing && table.match.openingTeam.rawValue == seat % 2),
                    players: table.seats.compactMap { $0 }.filter { $0 != Self.me.id }.map(Self.name(of:)),
                    invited: table.invited,
                    score: [table.match.score(of: .us), table.match.score(of: .them)],
                    mySeat: seat)
            }
        let open = invites.compactMap { invite -> OnlineInvite? in
            guard let table = tables[invite.game], table.phase == .lobby, !table.seats.contains(Self.me.id) else { return nil }
            return OnlineInvite(gameId: table.id, code: table.code, from: Self.name(of: invite.from), fromPicture: nil,
                                players: table.seats.compactMap { $0 }.map(Self.name(of:)))
        }
        return OnlineHome(name: name, friendCode: Self.me.code,
                          friends: friends.sorted { $0.name < $1.name }.map { OnlineFriend(id: $0.id, name: $0.name, picture: nil) },
                          invites: open, games: games)
    }

    func setName(_ name: String) async throws {
        try await Task.sleep(for: .milliseconds(150))
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(OnlineJSON.nameLimit))
        changed()
    }

    func addFriend(code: String) async throws -> OnlineFriend {
        try await Task.sleep(for: .milliseconds(200))
        let code = OnlineJSON.cleanCode(code)
        if code == Self.me.code { throw OnlineError.thatsYou }
        guard let person = Self.everyone.first(where: { $0.code == code }) else { throw OnlineError.noSuchCode }
        if !friends.contains(person) { friends.append(person) }
        return OnlineFriend(id: person.id, name: person.name, picture: nil)
    }

    func removeFriend(id: String) async throws {
        friends.removeAll { $0.id == id }
    }

    // MARK: - Games

    func createGame(target: Int, level: BotLevel) async throws -> OnlineState {
        try await Task.sleep(for: .milliseconds(200))
        guard name != nil else { throw OnlineError.needsName }
        let table = Table(id: "mock-game-\(tables.count + 1)", code: OnlineJSON.randomCode(using: &rng), host: Self.me.id)
        table.seats[0] = Self.me.id
        table.match = Match(target: target, using: &rng)
        table.target = target
        table.level = level
        tables[table.id] = table
        return state(of: table)
    }

    func joinGame(code: String) async throws -> OnlineState {
        try await Task.sleep(for: .milliseconds(200))
        guard name != nil else { throw OnlineError.needsName }
        guard let table = tables.values.first(where: { $0.code == OnlineJSON.cleanCode(code) }) else { throw OnlineError.noSuchGame }
        if table.seats.contains(Self.me.id) { return state(of: table) }
        guard table.phase == .lobby else { throw table.phase == .closed ? OnlineError.gameClosed : OnlineError.alreadyStarted }
        guard let seat = [2, 1, 3, 0].first(where: { table.seats[$0] == nil }) else { throw OnlineError.gameFull }
        table.seats[seat] = Self.me.id
        table.invited.removeAll { $0 == Self.me.id }
        invites.removeAll { $0.game == table.id }
        bump(table)
        // The pretend host starts a little later.
        if table.host != Self.me.id {
            later(table, after: pause * 4) { [weak self] table in
                guard let self, table.phase == .lobby else { return }
                self.deal(table)
                if self.hostEnds {
                    self.later(table, after: self.pause * 3) { [weak self] table in
                        self?.tables[table.id] = nil
                        self?.changed()
                    }
                }
            }
        }
        return state(of: table)
    }

    func declineInvite(gameID: String) async throws {
        invites.removeAll { $0.game == gameID }
        changed()
    }

    func state(gameID: String) async throws -> OnlineState {
        state(of: try table(gameID))
    }

    func invite(gameID: String, friendID: String) async throws -> OnlineState {
        let table = try table(gameID)
        guard table.phase == .lobby else { throw OnlineError.alreadyStarted }
        if !table.invited.contains(friendID) { table.invited.append(friendID) }
        bump(table)
        // The friend sees it and joins in a moment.
        later(table, after: pause) { [weak self] table in
            guard table.phase == .lobby, table.invited.contains(friendID), !table.seats.contains(friendID),
                  let seat = [2, 1, 3].first(where: { table.seats[$0] == nil }) else { return }
            table.seats[seat] = friendID
            table.invited.removeAll { $0 == friendID }
            self?.bump(table)
        }
        return state(of: table)
    }

    func moveSeat(gameID: String, seat: Int) async throws -> OnlineState {
        let table = try table(gameID)
        guard table.phase == .lobby else { throw OnlineError.alreadyStarted }
        guard (0..<4).contains(seat), table.seats[seat] == nil else { throw OnlineError.gameFull }
        if let mine = table.seats.firstIndex(of: Self.me.id) { table.seats[mine] = nil }
        table.seats[seat] = Self.me.id
        bump(table)
        return state(of: table)
    }

    func setOptions(gameID: String, target: Int, level: BotLevel) async throws -> OnlineState {
        let table = try table(gameID)
        table.target = target
        table.level = level
        bump(table)
        return state(of: table)
    }

    func start(gameID: String) async throws -> OnlineState {
        try await Task.sleep(for: .milliseconds(200))
        let table = try table(gameID)
        if table.phase == .lobby {
            table.invited = []
            deal(table)
        }
        return state(of: table)
    }

    func chooseLeader(gameID: String, seat: Int) async throws -> OnlineState {
        let table = try table(gameID)
        guard table.phase == .choosing, let game = table.game else { return state(of: table) }
        table.game = Game(hands: game.hands, boneyard: game.boneyard, starter: seat)
        table.phase = .playing
        run(table)
        return state(of: table)
    }

    func play(gameID: String, tile: Tile, end: End?) async throws -> OnlineState {
        try await Task.sleep(for: .milliseconds(120))
        let table = try table(gameID)
        guard table.phase == .playing, var game = table.game, game.current == mySeat(table) else { throw OnlineError.notYourTurn }
        do {
            try game.play(tile, on: end)
        } catch {
            throw OnlineError.doesNotFit
        }
        table.game = game
        run(table)
        return state(of: table)
    }

    func nextGame(gameID: String, after gameNumber: Int) async throws -> OnlineState {
        let table = try table(gameID)
        if table.phase == .over && table.gameNumber == gameNumber { deal(table) }
        return state(of: table)
    }

    func replaceWithComputer(gameID: String, seat: Int) async throws -> OnlineState {
        let table = try table(gameID)
        guard table.phase == .playing, table.game?.current == seat else { throw OnlineError.stillTheirTurn }
        table.seats[seat] = nil
        run(table)
        return state(of: table)
    }

    func leave(gameID: String) async throws {
        let table = try table(gameID)
        if let mine = table.seats.firstIndex(of: Self.me.id) { table.seats[mine] = nil }
        if table.host == Self.me.id && table.phase == .lobby || !table.seats.contains(where: { $0 != nil }) {
            // Like the server: an empty or disbanded room is deleted.
            tables[gameID] = nil
            changed()
            return
        } else if table.phase == .playing {
            run(table)
        }
        bump(table)
    }

    func disband(gameID: String) async throws {
        let table = try table(gameID)
        guard table.host == Self.me.id else { throw OnlineError.failed("Only the person who made the game can do that.") }
        tables[gameID] = nil
        changed()
    }

    func changes(gameID: String?) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let key = UUID()
            listeners[key] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.listeners[key] = nil }
            }
        }
    }

    // MARK: - The pretend server's rules

    private func table(_ id: String) throws -> Table {
        guard let table = tables[id], table.seats.contains(Self.me.id) else { throw OnlineError.noSuchGame }
        return table
    }

    private func mySeat(_ table: Table) -> Int { table.seats.firstIndex(of: Self.me.id) ?? 0 }

    private static func name(of id: String) -> String {
        everyone.first { $0.id == id }?.name ?? "Player"
    }

    private func bump(_ table: Table) {
        table.version += 1
        changed()
    }

    private func changed() {
        for listener in listeners.values { listener.yield(()) }
    }

    private func later(_ table: Table, after delay: Duration, _ work: @escaping @MainActor (Table) -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            work(table)
        }
    }

    private func deal(_ table: Table) {
        if table.gameNumber == 0 {
            table.match = Match(target: table.target, openingTeam: table.match.openingTeam)
        }
        table.gameNumber += 1
        let deal = Game.deal(using: &rng)
        let opening = table.match.openingTeam
        let peopleLead = opening.seats.contains { table.seats[$0] != nil }
        if peopleLead {
            table.game = Game(hands: deal.hands, boneyard: deal.boneyard, starter: opening.seats[0])
            table.phase = .choosing
            // A pretend friend on the leading team (and not you) chooses after a moment.
            if !opening.seats.contains(mySeat(table)) {
                later(table, after: pause) { [weak self] table in
                    guard table.phase == .choosing, let game = table.game else { return }
                    table.game = Game(hands: game.hands, boneyard: game.boneyard, starter: opening.seats[0])
                    table.phase = .playing
                    self?.run(table)
                }
            }
        } else {
            let starter = Bot.starter(for: opening, hands: deal.hands)
            table.game = Game(hands: deal.hands, boneyard: deal.boneyard, starter: starter)
            table.phase = .playing
        }
        run(table)
    }

    /// Computers play, anyone with nothing to play knocks, until a person can
    /// play or the game ends. Pretend friends then play after a pause.
    private func run(_ table: Table) {
        defer { bump(table) }
        guard table.phase == .playing, var game = table.game else { return }
        while !game.isOver {
            let seat = game.current
            if !game.canPlay(seat) {
                try? game.knock()
                continue
            }
            guard table.seats[seat] == nil else { break }
            let bot = Bot(level: table.level)
            guard let choice = bot.choose(in: game, using: &rng) else { break }
            try? game.play(choice.tile, on: choice.end)
        }
        table.game = game
        table.turnStarted = Date()
        if game.isOver {
            table.match.record(game)
            table.phase = table.match.winner == nil ? .over : .matchOver
            return
        }
        let seat = game.current
        if let person = table.seats[seat], person != Self.me.id, !(stall && person == Self.jordan.id) {
            let number = table.gameNumber
            later(table, after: pause) { [weak self] table in
                guard let self, table.phase == .playing, table.gameNumber == number,
                      var game = table.game, game.current == seat else { return }
                if let choice = Bot(level: .normal).choose(in: game, using: &self.rng) {
                    try? game.play(choice.tile, on: choice.end)
                }
                table.game = game
                self.run(table)
            }
        }
    }

    private func state(of table: Table) -> OnlineState {
        let seat = mySeat(table)
        let game = table.game
        let log: [OnlineAction] = (game?.log ?? []).map { action in
            switch action {
            case .play(let seat, let tile, let end):
                return OnlineAction(s: seat, t: "play", tile: OnlineJSON.pair(tile), e: end?.rawValue, l: nil, r: nil)
            case .knock(let seat, let left, let right):
                return OnlineAction(s: seat, t: "knock", tile: nil, e: nil, l: left, r: right)
            }
        }
        let over = table.phase == .over || table.phase == .matchOver
        let result: OnlineResult? = over ? game?.result.map { result in
            let kind: String
            var who: Int?
            switch result.kind {
            case .domino(let seat): kind = "domino"; who = seat
            case .blocked: kind = "blocked"
            case .tie: kind = "tie"
            }
            return OnlineResult(kind: kind, seat: who, winner: result.winner?.rawValue, points: result.points,
                                pips: [result.usPips, result.themPips])
        } : nil
        let stalled = stall && table.phase == .playing && game.map { table.seats[$0.current] == Self.jordan.id } == true
        return OnlineState(
            id: table.id, code: table.code, phase: table.phase, target: table.target, level: table.level.rawValue,
            mySeat: seat, isHostValue: table.host == Self.me.id, version: table.version,
            score: [table.match.score(of: .us), table.match.score(of: .them)],
            gameNumber: table.gameNumber,
            openingTeam: table.gameNumber > 0 ? table.match.openingTeam.rawValue : nil,
            matchWinner: table.match.winner?.rawValue,
            starter: table.phase == .choosing ? nil : game?.starter,
            current: table.phase == .playing ? game?.current : nil,
            log: table.phase == .choosing ? [] : log,
            result: result,
            revealed: over ? game?.hands.map { $0.map(OnlineJSON.pair) } : nil,
            turnSeconds: stalled ? 90 : Int(Date().timeIntervalSince(table.turnStarted)),
            seats: (0..<4).map { index in
                let id = table.seats[index]
                return OnlineSeat(seat: index, name: id.map(Self.name(of:)), picture: nil, person: id != nil,
                                  you: id == Self.me.id, host: id == table.host)
            },
            hand: (game?.hands[seat] ?? []).map(OnlineJSON.pair))
    }
}
#endif

import Foundation
import Observation

/// The Play with Friends page: your friends, invites to you and your games,
/// kept fresh while the page (or the home screen's invite badge) is showing.
@MainActor
@Observable
final class FriendsModel {
    let service: OnlineService
    private(set) var home: OnlineHome?
    private(set) var loading = false
    /// Something that went wrong, in plain words, until the next try.
    var problem: String?
    /// A button's call is running: the page waits for it.
    private(set) var busy = false

    init(service: OnlineService) {
        self.service = service
    }

    var invites: [OnlineInvite] { home?.invites ?? [] }
    var needsName: Bool { home != nil && (home?.name ?? "").isEmpty }

    func load() async {
        loading = home == nil
        defer { loading = false }
        do {
            home = try await service.home()
            if problem == OnlineError.offline.errorDescription { problem = nil }
        } catch is CancellationError {
            // The page went away mid-load: nothing to say.
        } catch {
            if home == nil || (error as? OnlineError) == .offline { problem = error.localizedDescription }
        }
    }

    /// Reloads when an invite arrives, and every few seconds in case one was
    /// missed, until the task that runs it is cancelled.
    func watch() async {
        await load()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for await _ in self.service.changes(gameID: nil) {
                    await self.load()
                }
            }
            group.addTask { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(8))
                    guard !Task.isCancelled else { return }
                    await self.load()
                }
            }
        }
    }

    /// Runs a button's call, shows its problem if it fails, then reloads.
    @discardableResult
    func run<T>(_ call: (OnlineService) async throws -> T) async -> T? {
        guard !busy else { return nil }
        busy = true
        problem = nil
        defer { busy = false }
        do {
            let value = try await call(service)
            await load()
            return value
        } catch is CancellationError {
            return nil
        } catch {
            problem = error.localizedDescription
            return nil
        }
    }
}

/// A game waiting for its players: who's sitting where, the host's options,
/// and invites. Hands over to the game screen once the host starts.
@MainActor
@Observable
final class LobbyModel {
    let service: OnlineService
    private(set) var state: OnlineState
    var problem: String?
    private(set) var busy = false
    /// The room was deleted (the host disbanded it) while you were in it.
    private(set) var closed = false
    /// Friends you invited from this phone.
    private(set) var invited: Set<String> = []
    @ObservationIgnored var onStarted: (OnlineState) -> Void = { _ in }
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    init(state: OnlineState, service: OnlineService) {
        self.state = state
        self.service = service
    }

    var id: String { state.id }

    /// Seats as you see them: 0 you, 1 your left, 2 your partner, 3 your right.
    func seat(_ local: Int) -> OnlineSeat? { state.seat(local: local) }

    func start() {
        stop()
        let changes = Task { @MainActor [weak self] in
            guard let self else { return }
            for await _ in self.service.changes(gameID: self.id) {
                await self.fetch()
            }
        }
        let poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await self?.fetch()
            }
        }
        tasks = [changes, poll]
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    private func fetch() async {
        guard !busy, !closed else { return }
        do {
            apply(try await service.state(gameID: id))
        } catch OnlineError.noSuchGame {
            roomClosed()
        } catch OnlineError.offline {
            problem = OnlineError.offline.errorDescription
        } catch {
            // Try again on the next change or the next few seconds.
        }
    }

    private func apply(_ fresh: OnlineState) {
        guard fresh.version >= state.version || fresh.phase != state.phase else { return }
        state = fresh
        if problem == OnlineError.offline.errorDescription { problem = nil }
        switch fresh.phase {
        case .lobby: break
        case .closed: roomClosed()
        default:
            stop()
            onStarted(fresh)
        }
    }

    private func roomClosed() {
        closed = true
        stop()
    }

    @discardableResult
    private func send(_ call: @escaping (OnlineService) async throws -> OnlineState) -> Bool {
        guard !busy, !closed else { return false }
        busy = true
        problem = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                apply(try await call(service))
            } catch OnlineError.noSuchGame {
                roomClosed()
            } catch is CancellationError {
            } catch {
                problem = error.localizedDescription
            }
        }
        return true
    }

    func invite(_ friend: OnlineFriend) {
        if send({ [id] service in try await service.invite(gameID: id, friendID: friend.id) }) {
            invited.insert(friend.id)
        }
    }
    func sit(atLocal local: Int) {
        let seat = state.server(local)
        send { [id] service in try await service.moveSeat(gameID: id, seat: seat) }
    }
    func setOptions(target: Int, level: BotLevel) {
        send { [id] service in try await service.setOptions(gameID: id, target: target, level: level) }
    }
    func startGame() { send { [id] service in try await service.start(gameID: id) } }

    /// Leaves the room; for the host, before the start, that ends it for everyone.
    func leave() async {
        stop()
        try? await service.leave(gameID: id)
    }

    func disband() async {
        stop()
        try? await service.disband(gameID: id)
    }
}

import Foundation
import Supabase

/// Online games on the Dominoes Supabase project: the functions in
/// supabase/migrations/20261103200000_online_games.sql, called as the signed-in
/// player, plus live updates when a game or an invite changes.
@MainActor
final class SupabaseOnlineService: OnlineService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Calls

    private func call(_ function: String, _ params: [String: AnyJSON] = [:]) async throws -> Data {
        guard client.auth.currentUser != nil else { throw OnlineError.signedOut }
        do {
            return try await client.rpc(function, params: params).execute().data
        } catch let error as PostgrestError {
            throw OnlineError.from(serverMessage: error.message)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw OnlineError.offline
        } catch let error as OnlineError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OnlineError.failed("Something went wrong. Try again.")
        }
    }

    private func state(_ function: String, _ params: [String: AnyJSON]) async throws -> OnlineState {
        let data = try await call(function, params)
        do {
            return try OnlineState.decode(data)
        } catch {
            throw OnlineError.failed("The game didn't load. Try again.")
        }
    }

    func home() async throws -> OnlineHome {
        let data = try await call("home_state")
        do {
            return try OnlineHome.decode(data)
        } catch {
            throw OnlineError.failed("Your games didn't load. Try again.")
        }
    }

    func setName(_ name: String) async throws {
        guard let user = client.auth.currentUser else { throw OnlineError.signedOut }
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(OnlineJSON.nameLimit))
        do {
            try await client.from("profiles")
                .update(["display_name": clean])
                .eq("id", value: user.id.uuidString)
                .execute()
        } catch is URLError {
            throw OnlineError.offline
        } catch {
            throw OnlineError.failed("Your name wasn't saved. Try again.")
        }
    }

    func addFriend(code: String) async throws -> OnlineFriend {
        let data = try await call("add_friend", ["p_code": .string(OnlineJSON.cleanCode(code))])
        do {
            return try OnlineJSON.decoder.decode(OnlineFriend.self, from: data)
        } catch {
            throw OnlineError.failed("Something went wrong. Try again.")
        }
    }

    func removeFriend(id: String) async throws {
        _ = try await call("remove_friend", ["p_friend": .string(id)])
    }

    func createGame(target: Int, level: BotLevel) async throws -> OnlineState {
        try await state("create_game", ["p_target": .integer(target), "p_level": .string(level.rawValue)])
    }

    func joinGame(code: String) async throws -> OnlineState {
        try await state("join_game", ["p_code": .string(OnlineJSON.cleanCode(code))])
    }

    func declineInvite(gameID: String) async throws {
        _ = try await call("decline_invite", ["p_game": .string(gameID)])
    }

    func state(gameID: String) async throws -> OnlineState {
        try await state("game_state", ["p_game": .string(gameID)])
    }

    func invite(gameID: String, friendID: String) async throws -> OnlineState {
        try await state("invite_friend", ["p_game": .string(gameID), "p_friend": .string(friendID)])
    }

    func moveSeat(gameID: String, seat: Int) async throws -> OnlineState {
        try await state("move_seat", ["p_game": .string(gameID), "p_seat": .integer(seat)])
    }

    func setOptions(gameID: String, target: Int, level: BotLevel) async throws -> OnlineState {
        try await state("set_game_options", ["p_game": .string(gameID), "p_target": .integer(target),
                                             "p_level": .string(level.rawValue)])
    }

    func start(gameID: String) async throws -> OnlineState {
        try await state("start_game", ["p_game": .string(gameID)])
    }

    func chooseLeader(gameID: String, seat: Int) async throws -> OnlineState {
        try await state("choose_leader", ["p_game": .string(gameID), "p_seat": .integer(seat)])
    }

    func play(gameID: String, tile: Tile, end: End?) async throws -> OnlineState {
        try await state("play_tile", ["p_game": .string(gameID), "p_low": .integer(tile.low),
                                      "p_high": .integer(tile.high), "p_end": end.map { .string($0.rawValue) } ?? .null])
    }

    func nextGame(gameID: String, after gameNumber: Int) async throws -> OnlineState {
        try await state("next_game", ["p_game": .string(gameID), "p_game_number": .integer(gameNumber)])
    }

    func replaceWithComputer(gameID: String, seat: Int) async throws -> OnlineState {
        try await state("replace_with_computer", ["p_game": .string(gameID), "p_seat": .integer(seat)])
    }

    func leave(gameID: String) async throws {
        _ = try await call("leave_game", ["p_game": .string(gameID)])
    }

    func disband(gameID: String) async throws {
        _ = try await call("disband_game", ["p_game": .string(gameID)])
    }

    // MARK: - Live updates

    func changes(gameID: String?) -> AsyncStream<Void> {
        let client = client
        let userID = client.auth.currentUser?.id.uuidString
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                let channel = client.channel("dominoes-\(gameID ?? "home")-\(UUID().uuidString.prefix(8))")
                let stream: AsyncStream<AnyAction>
                if let gameID {
                    stream = channel.postgresChange(AnyAction.self, schema: "public", table: "games",
                                                    filter: .eq("id", value: gameID))
                } else if let userID {
                    stream = channel.postgresChange(AnyAction.self, schema: "public", table: "game_invites",
                                                    filter: .eq("to_user", value: userID))
                } else {
                    continuation.finish()
                    return
                }
                do {
                    try await channel.subscribeWithError()
                } catch {
                    // The phone checks every few seconds anyway.
                }
                for await _ in stream {
                    continuation.yield(())
                }
                await client.removeChannel(channel)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

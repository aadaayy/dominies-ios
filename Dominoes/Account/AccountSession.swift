import Foundation
import Observation

/// Who's signed in, for the whole app. Signing in is optional: the game plays
/// the same without an account.
@MainActor
@Observable
final class AccountSession {
    /// Nil while Accounts.plist still has its placeholders.
    let service: AccountService?
    /// Games with friends. Nil while Accounts.plist still has its placeholders.
    let online: OnlineService?
    private(set) var player: Player?

    var isSetUp: Bool { service != nil }

    init(service: AccountService?, online: OnlineService? = nil) {
        self.service = service
        self.online = online
        player = service?.currentPlayer()
    }

    /// The real project from Accounts.plist, or the pretend one the checks use.
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> AccountSession {
        #if DEBUG
        if arguments.contains("-mockAccount") || arguments.contains("-mockOnline") {
            let signedIn = arguments.contains("-mockSignedIn") || arguments.contains("-mockOnline")
            return AccountSession(service: MockAccountService(signedIn: signedIn),
                                  online: MockOnlineService(arguments: arguments))
        }
        #endif
        guard let config = AccountConfig.load() else { return AccountSession(service: nil) }
        let service = SupabaseAccountService(config: config)
        return AccountSession(service: service, online: SupabaseOnlineService(client: service.client))
    }

    /// Picks up a name or picture changed since last time.
    func refresh() async {
        guard player != nil, let service else { return }
        if let fresh = await service.refreshProfile() { player = fresh }
    }

    func signInWithGoogle() async throws {
        guard let service else { throw AccountError.notSetUp }
        player = try await service.signInWithGoogle()
    }

    func signUp(email: String, password: String) async throws {
        guard let service else { throw AccountError.notSetUp }
        if let problem = Player.passwordProblem(password) { throw AccountError.weakPassword(problem) }
        player = try await service.signUp(email: Self.clean(email), password: password)
    }

    func signIn(email: String, password: String) async throws {
        guard let service else { throw AccountError.notSetUp }
        player = try await service.signIn(email: Self.clean(email), password: password)
    }

    private static func clean(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespaces).lowercased()
    }

    func signOut() async {
        await service?.signOut()
        player = nil
    }

    func deleteAccount() async throws {
        guard let service else { throw AccountError.notSetUp }
        try await service.deleteAccount()
        player = nil
    }
}

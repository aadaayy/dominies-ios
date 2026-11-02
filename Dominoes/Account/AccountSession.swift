import Foundation
import Observation

/// Who's signed in, for the whole app. Signing in is optional: the game plays
/// the same without an account.
@MainActor
@Observable
final class AccountSession {
    /// Nil while Accounts.plist still has its placeholders.
    let service: AccountService?
    private(set) var player: Player?

    var isSetUp: Bool { service != nil }

    init(service: AccountService?) {
        self.service = service
        player = service?.currentPlayer()
    }

    /// The real project from Accounts.plist, or the pretend one the checks use.
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> AccountSession {
        #if DEBUG
        if arguments.contains("-mockAccount") {
            return AccountSession(service: MockAccountService(signedIn: arguments.contains("-mockSignedIn")))
        }
        #endif
        guard let config = AccountConfig.load() else { return AccountSession(service: nil) }
        return AccountSession(service: SupabaseAccountService(config: config))
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

    func signOut() async {
        await service?.signOut()
        player = nil
    }

    func deleteAccount() async throws {
        guard let service else { throw AccountError.notSetUp }
        try await service.deleteAccount()
        player = nil
    }

    func handle(_ url: URL) {
        service?.handle(url)
    }
}

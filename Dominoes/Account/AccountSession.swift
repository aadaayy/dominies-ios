import Foundation
import Observation
import UIKit

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
            let account = MockAccountService(signedIn: signedIn)
            let online = MockOnlineService(arguments: arguments)
            // One profile, as on the real server: a name or picture changed
            // on either side shows on the other.
            if let me = account.currentPlayer() { online.mirror(me) }
            account.onChange = { [weak online] in online?.mirror($0) }
            online.onNameChange = { [weak account] in account?.nameChangedOnline($0) }
            return AccountSession(service: account, online: online)
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

    // MARK: - Name and picture

    /// The name friends see, everywhere: account, lobbies, games and invites.
    func setName(_ name: String) async throws {
        guard let service else { throw AccountError.notSetUp }
        if let problem = OnlineJSON.nameProblem(name) { throw AccountError.failed(problem) }
        player = try await service.setName(name)
    }

    /// A picture they framed, uploaded as a small square JPEG.
    func setPicture(_ picture: UIImage) async throws {
        guard let service else { throw AccountError.notSetUp }
        guard let jpeg = Pictures.jpeg(picture) else { throw AccountError.failed("That picture didn't work. Try another.") }
        let fresh = try await service.setPicture(jpeg: jpeg)
        // Shows at once, without loading it back.
        if let url = fresh.avatarURL { AvatarCache.store(picture, for: url) }
        player = fresh
    }

    func useGooglePicture() async throws {
        guard let service else { throw AccountError.notSetUp }
        player = try await service.useGooglePicture()
    }

    func removePicture() async throws {
        guard let service else { throw AccountError.notSetUp }
        player = try await service.removePicture()
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

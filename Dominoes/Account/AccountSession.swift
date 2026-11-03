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
    /// True when sign-in emails show a six-digit code; otherwise they carry
    /// a link to tap (Supabase's default emails).
    let emailCodes: Bool
    /// Why the last sign-in link didn't work, if it didn't.
    private(set) var linkProblem: String?
    /// Counts sign-in links handled, so the app can show the account page
    /// when one arrives (the app may have been closed while the player was
    /// in their email).
    private(set) var linksHandled = 0

    var isSetUp: Bool { service != nil }

    init(service: AccountService?, emailCodes: Bool = false) {
        self.service = service
        self.emailCodes = emailCodes
        player = service?.currentPlayer()
    }

    /// The real project from Accounts.plist, or the pretend one the checks use.
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> AccountSession {
        #if DEBUG
        if arguments.contains("-mockAccount") {
            return AccountSession(service: MockAccountService(signedIn: arguments.contains("-mockSignedIn")),
                                  emailCodes: arguments.contains("-mockEmailCodes"))
        }
        #endif
        guard let config = AccountConfig.load() else { return AccountSession(service: nil) }
        return AccountSession(service: SupabaseAccountService(config: config), emailCodes: config.emailCodes)
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

    func sendEmailCode(to email: String) async throws {
        guard let service else { throw AccountError.notSetUp }
        linkProblem = nil
        try await service.sendEmailCode(to: email.trimmingCharacters(in: .whitespaces).lowercased())
    }

    func verifyEmailCode(email: String, code: String) async throws {
        guard let service else { throw AccountError.notSetUp }
        player = try await service.verifyEmailCode(email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                                                   code: Player.cleanCode(code))
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

    /// A sign-in link from the email, opened on this phone.
    func handle(_ url: URL) async {
        guard let service, SignInLink.isSignInLink(url) else { return }
        do {
            if let signedIn = try await service.signIn(from: url) {
                player = signedIn
                linkProblem = nil
            }
        } catch {
            linkProblem = error.localizedDescription
        }
        linksHandled += 1
    }
}

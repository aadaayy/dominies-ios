#if DEBUG
import Foundation

/// A pretend account server on the phone for the automatic checks, which
/// have no Google account. Launched with -mockAccount (and -mockSignedIn to
/// start signed in). Continue with Google signs in as Alex Rivera; email
/// sign-in takes any address, then the code 123456 or any
/// dominoes://login-callback link without an error in it.
@MainActor
final class MockAccountService: AccountService {
    static let me = Player(id: "mock-me", name: "Alex Rivera", email: "alex.rivera@example.com", avatarURL: nil)

    private var player: Player?
    /// Where the last sign-in email went.
    private var emailedTo: String?

    init(signedIn: Bool) {
        player = signedIn ? Self.me : nil
    }

    func currentPlayer() -> Player? { player }

    func signInWithGoogle() async throws -> Player {
        try await Task.sleep(for: .milliseconds(300))
        player = Self.me
        return Self.me
    }

    static let emailCode = "123456"

    func sendEmailCode(to email: String) async throws {
        try await Task.sleep(for: .milliseconds(300))
        emailedTo = email
    }

    func verifyEmailCode(email: String, code: String) async throws -> Player {
        try await Task.sleep(for: .milliseconds(300))
        guard code == Self.emailCode else { throw AccountError.wrongCode }
        let me = Player(id: "mock-email", name: email, email: email, avatarURL: nil, signInMethod: "email")
        player = me
        return me
    }

    func refreshProfile() async -> Player? { player }

    func signOut() async { player = nil }

    func deleteAccount() async throws {
        try await Task.sleep(for: .milliseconds(200))
        player = nil
    }

    func signIn(from url: URL) async throws -> Player? {
        guard SignInLink.isSignInLink(url) else { return nil }
        try await Task.sleep(for: .milliseconds(300))
        guard SignInLink.errorCode(in: url) == nil, let email = emailedTo else { throw AccountError.linkDidntWork }
        let me = Player(id: "mock-email", name: email, email: email, avatarURL: nil, signInMethod: "email")
        player = me
        return me
    }
}
#endif

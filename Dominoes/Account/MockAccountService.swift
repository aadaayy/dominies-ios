#if DEBUG
import Foundation

/// A pretend account server on the phone for the automatic checks, which
/// have no Google account. Launched with -mockAccount (and -mockSignedIn to
/// start signed in). Continue with Google signs in as Alex Rivera. Email
/// accounts live only until the app quits; one is there from the start,
/// jordan@example.com with the password dominoes1, for signing in.
@MainActor
final class MockAccountService: AccountService {
    static let me = Player(id: "mock-me", name: "Alex Rivera", email: "alex.rivera@example.com", avatarURL: nil)
    static let existingEmail = "jordan@example.com"
    static let existingPassword = "dominoes1"

    private var player: Player?
    /// Email accounts made so far: address to password.
    private var accounts = [existingEmail: existingPassword]

    init(signedIn: Bool) {
        player = signedIn ? Self.me : nil
    }

    func currentPlayer() -> Player? { player }

    func signInWithGoogle() async throws -> Player {
        try await Task.sleep(for: .milliseconds(300))
        player = Self.me
        return Self.me
    }

    func signUp(email: String, password: String) async throws -> Player {
        try await Task.sleep(for: .milliseconds(300))
        guard accounts[email] == nil else { throw AccountError.accountExists }
        accounts[email] = password
        return signedIn(as: email)
    }

    func signIn(email: String, password: String) async throws -> Player {
        try await Task.sleep(for: .milliseconds(300))
        guard accounts[email] == password else { throw AccountError.wrongPassword }
        return signedIn(as: email)
    }

    private func signedIn(as email: String) -> Player {
        let me = Player(id: "mock-\(email)", name: email, email: email, avatarURL: nil, signInMethod: "email")
        player = me
        return me
    }

    func refreshProfile() async -> Player? { player }

    func signOut() async { player = nil }

    func deleteAccount() async throws {
        try await Task.sleep(for: .milliseconds(200))
        if let email = player?.email { accounts[email] = nil }
        player = nil
    }
}
#endif

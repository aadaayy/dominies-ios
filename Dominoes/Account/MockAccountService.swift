#if DEBUG
import Foundation

/// A pretend account server on the phone for the automatic checks, which
/// have no Google account. Launched with -mockAccount (and -mockSignedIn to
/// start signed in). Continue with Google signs in as Alex Rivera.
@MainActor
final class MockAccountService: AccountService {
    static let me = Player(id: "mock-me", name: "Alex Rivera", email: "alex.rivera@example.com", avatarURL: nil)

    private var player: Player?

    init(signedIn: Bool) {
        player = signedIn ? Self.me : nil
    }

    func currentPlayer() -> Player? { player }

    func signInWithGoogle() async throws -> Player {
        try await Task.sleep(for: .milliseconds(300))
        player = Self.me
        return Self.me
    }

    func refreshProfile() async -> Player? { player }

    func signOut() async { player = nil }

    func deleteAccount() async throws {
        try await Task.sleep(for: .milliseconds(200))
        player = nil
    }

    func handle(_ url: URL) {}
}
#endif

import Foundation

/// Player accounts. `SupabaseAccountService` talks to the real Dominoes
/// project; `MockAccountService` stands in for it in the automatic checks,
/// which have no Google account.
@MainActor
protocol AccountService: AnyObject {
    /// Whoever is signed in on this phone, if anyone. Works offline.
    func currentPlayer() -> Player?
    /// Google's sign-in page in a sheet, then back to the app.
    func signInWithGoogle() async throws -> Player
    /// Makes a new account with an email and password and signs in. No email
    /// is sent: the project doesn't ask new players to confirm their address.
    func signUp(email: String, password: String) async throws -> Player
    /// Signs in to an account made with an email and password.
    func signIn(email: String, password: String) async throws -> Player
    /// The name and picture saved in the player's profile, if it loads.
    func refreshProfile() async -> Player?
    func signOut() async
    /// Deletes the account and its profile, then signs out.
    func deleteAccount() async throws
}

enum AccountError: LocalizedError, Equatable {
    case notSetUp
    case cancelled
    case wrongPassword
    case accountExists
    case weakPassword(String)
    case badEmail
    case emailSignUpOff
    case confirmEmailOn
    case tooManyTries
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notSetUp: "Sign-in isn't set up in this copy of the app yet."
        case .cancelled: "Sign in was cancelled."
        case .wrongPassword: "That email and password don't match. Check them and try again, or make an account if you're new."
        case .accountExists: "There's already an account with that email. Sign in with its password, or with Google if that's how you made it."
        case .weakPassword(let reason): reason
        case .badEmail: "That email address doesn't look right. Check it and try again."
        case .emailSignUpOff: "Email accounts are turned off right now. Use Google for now."
        case .confirmEmailOn: "Your account is made, but it needs its email confirmed before you can sign in."
        case .tooManyTries: "Too many tries just now. Wait a minute and try again."
        case .failed(let message): message
        }
    }
}

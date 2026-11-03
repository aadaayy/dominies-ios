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
    /// Emails a sign-in link (and a six-digit code, once the project's
    /// emails show one). Makes the account if it's new.
    func sendEmailCode(to email: String) async throws
    /// Signs in with the code from that email.
    func verifyEmailCode(email: String, code: String) async throws -> Player
    /// The name and picture saved in the player's profile, if it loads.
    func refreshProfile() async -> Player?
    func signOut() async
    /// Deletes the account and its profile, then signs out.
    func deleteAccount() async throws
    /// Signs in from the link in a sign-in email, which comes back to the
    /// app as dominoes://login-callback. Nil for any other link.
    func signIn(from url: URL) async throws -> Player?
}

enum AccountError: LocalizedError, Equatable {
    case notSetUp
    case cancelled
    case wrongCode
    case emailNotAllowed
    case tooManyEmails
    case linkDidntWork
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notSetUp: "Sign-in isn't set up in this copy of the app yet."
        case .cancelled: "Sign in was cancelled."
        case .wrongCode: "That code didn't work. Check the newest email, or send a new code."
        case .emailNotAllowed: "Email sign-in isn't open to everyone yet. Use Google for now."
        case .tooManyEmails: "Too many emails were sent just now. Try again later, or use Google."
        case .linkDidntWork: "That link didn't sign you in. It may be old or already used, or from another phone. Send a new one and open it on this phone."
        case .failed(let message): message
        }
    }
}

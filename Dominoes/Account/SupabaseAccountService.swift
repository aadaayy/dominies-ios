import AuthenticationServices
import Foundation
import Supabase

/// Accounts on Supabase Auth, in the Dominoes project (its own players,
/// never the golf app's): Google, or an email and password. Sign in with
/// Apple needs the paid Apple Developer Program.
@MainActor
final class SupabaseAccountService: AccountService {
    /// Where Google sends the player back. It must be in the project's
    /// Redirect URLs (README, Accounts setup).
    static let callbackURL = URL(string: "dominoes://login-callback")!

    private let client: SupabaseClient

    init(config: AccountConfig) {
        client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.key,
            options: SupabaseClientOptions(
                auth: .init(
                    // The session stays in the phone's keychain between launches.
                    storage: KeychainLocalStorage(),
                    redirectToURL: Self.callbackURL,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    func currentPlayer() -> Player? {
        client.auth.currentUser.map(Self.player)
    }

    func signInWithGoogle() async throws -> Player {
        do {
            // A web sheet run by Supabase: Google's own page, then back to the app.
            let session = try await client.auth.signInWithOAuth(provider: .google, redirectTo: Self.callbackURL)
            return await refreshProfile() ?? Self.player(session.user)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw AccountError.cancelled
        } catch {
            throw Self.friendly(error)
        }
    }

    func signUp(email: String, password: String) async throws -> Player {
        let response: AuthResponse
        do {
            response = try await client.auth.signUp(email: email, password: password)
        } catch {
            throw Self.friendly(error, signingUp: true)
        }
        // With Confirm email off in the project, the new player is signed in
        // at once and no email goes out. With it on, there'd be no session.
        guard let session = response.session else { throw AccountError.confirmEmailOn }
        return await refreshProfile() ?? Self.player(session.user)
    }

    func signIn(email: String, password: String) async throws -> Player {
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            return await refreshProfile() ?? Self.player(session.user)
        } catch {
            throw Self.friendly(error, signingUp: false)
        }
    }

    func refreshProfile() async -> Player? {
        guard let user = client.auth.currentUser else { return nil }
        var player = Self.player(user)
        struct Row: Decodable {
            let display_name: String
            let avatar_url: String?
        }
        if let row: Row = try? await client.from("profiles")
            .select("display_name,avatar_url")
            .eq("id", value: user.id.uuidString)
            .single()
            .execute()
            .value {
            if !row.display_name.isEmpty { player.name = row.display_name }
            if let link = row.avatar_url.flatMap(URL.init(string:)) { player.avatarURL = link }
        }
        return player
    }

    func signOut() async {
        try? await client.auth.signOut(scope: .local)
    }

    func deleteAccount() async throws {
        do {
            try await client.rpc("delete_my_account").execute()
        } catch {
            throw Self.friendly(error)
        }
        await signOut()
    }

    private static func player(_ user: User) -> Player {
        let metadata = user.userMetadata
        let name = metadata["full_name"]?.stringValue ?? metadata["name"]?.stringValue ?? user.email ?? "Player"
        let picture = (metadata["avatar_url"]?.stringValue ?? metadata["picture"]?.stringValue).flatMap(URL.init(string:))
        let method = user.appMetadata["provider"]?.stringValue == "email" ? "email" : "google"
        return Player(id: user.id.uuidString, name: name, email: user.email, avatarURL: picture, signInMethod: method)
    }

    private static func friendly(_ error: Error, signingUp: Bool = false) -> Error {
        if let error = error as? AccountError { return error }
        if let error = error as? AuthError {
            switch error.errorCode.rawValue {
            case "invalid_credentials": return AccountError.wrongPassword
            case "user_already_exists", "email_exists": return AccountError.accountExists
            case "weak_password":
                return AccountError.weakPassword("That password is too easy to guess. Try a longer one.")
            case "email_address_invalid": return AccountError.badEmail
            case "signup_disabled", "email_provider_disabled": return AccountError.emailSignUpOff
            case "email_not_confirmed": return AccountError.confirmEmailOn
            case "over_request_rate_limit", "over_email_send_rate_limit": return AccountError.tooManyTries
            default:
                // Older servers say "Invalid login credentials" with no code.
                if !signingUp, error.message.localizedCaseInsensitiveContains("invalid login credentials") {
                    return AccountError.wrongPassword
                }
                return AccountError.failed(error.message)
            }
        }
        if (error as? URLError) != nil {
            return AccountError.failed("No connection. Check your signal and try again.")
        }
        return AccountError.failed(error.localizedDescription)
    }
}

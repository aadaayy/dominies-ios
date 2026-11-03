import AuthenticationServices
import Foundation
import Supabase

/// Accounts on Supabase Auth, in the Dominoes project (its own players,
/// never the golf app's): Google, or email. Sign in with Apple needs the
/// paid Apple Developer Program.
@MainActor
final class SupabaseAccountService: AccountService {
    /// Where Google, and the link in a sign-in email, send the player back.
    /// It must be in the project's Redirect URLs (README, Accounts setup).
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

    func sendEmailCode(to email: String) async throws {
        do {
            // Supabase's Magic Link email (Confirm signup for a new player).
            // Its default carries a link back to the app; once the template
            // shows {{ .Token }} it carries a code too (README, Accounts setup).
            try await client.auth.signInWithOTP(email: email, redirectTo: Self.callbackURL, shouldCreateUser: true)
        } catch {
            throw Self.friendly(error)
        }
    }

    func verifyEmailCode(email: String, code: String) async throws -> Player {
        do {
            let response = try await client.auth.verifyOTP(email: email, token: code, type: .email)
            return await refreshProfile() ?? Self.player(response.user)
        } catch {
            throw Self.friendly(error)
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

    func signIn(from url: URL) async throws -> Player? {
        guard SignInLink.isSignInLink(url) else { return nil }
        if SignInLink.errorCode(in: url) != nil { throw AccountError.linkDidntWork }
        do {
            // Trades the link's one-time code for a session. It only works on
            // the phone that asked for the email, which holds the other half.
            let session = try await client.auth.session(from: url)
            return await refreshProfile() ?? Self.player(session.user)
        } catch let error as URLError {
            throw Self.friendly(error)
        } catch {
            throw AccountError.linkDidntWork
        }
    }

    private static func player(_ user: User) -> Player {
        let metadata = user.userMetadata
        let name = metadata["full_name"]?.stringValue ?? metadata["name"]?.stringValue ?? user.email ?? "Player"
        let picture = (metadata["avatar_url"]?.stringValue ?? metadata["picture"]?.stringValue).flatMap(URL.init(string:))
        let method = user.appMetadata["provider"]?.stringValue == "email" ? "email" : "google"
        return Player(id: user.id.uuidString, name: name, email: user.email, avatarURL: picture, signInMethod: method)
    }

    private static func friendly(_ error: Error) -> Error {
        if let error = error as? AccountError { return error }
        if let error = error as? AuthError {
            switch error.errorCode.rawValue {
            case "otp_expired", "otp_disabled": return AccountError.wrongCode
            case "email_address_not_authorized": return AccountError.emailNotAllowed
            case "over_email_send_rate_limit", "over_request_rate_limit": return AccountError.tooManyEmails
            default: return AccountError.failed(error.message)
            }
        }
        if (error as? URLError) != nil {
            return AccountError.failed("No connection. Check your signal and try again.")
        }
        return AccountError.failed(error.localizedDescription)
    }
}

import AuthenticationServices
import Foundation
import Supabase

/// Accounts on Supabase Auth, in the Dominoes project (its own players,
/// never the golf app's). Google only for now; Sign in with Apple needs the
/// paid Apple Developer Program.
@MainActor
final class SupabaseAccountService: AccountService {
    /// Where Google sends the player back after signing in. It must be in the
    /// project's Redirect URLs (README, Accounts setup).
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

    func handle(_ url: URL) {
        client.auth.handle(url)
    }

    private static func player(_ user: User) -> Player {
        let metadata = user.userMetadata
        let name = metadata["full_name"]?.stringValue ?? metadata["name"]?.stringValue ?? user.email ?? "Player"
        let picture = (metadata["avatar_url"]?.stringValue ?? metadata["picture"]?.stringValue).flatMap(URL.init(string:))
        return Player(id: user.id.uuidString, name: name, email: user.email, avatarURL: picture)
    }

    private static func friendly(_ error: Error) -> Error {
        if let error = error as? AccountError { return error }
        if (error as? URLError) != nil {
            return AccountError.failed("No connection. Check your signal and try again.")
        }
        return AccountError.failed(error.localizedDescription)
    }
}

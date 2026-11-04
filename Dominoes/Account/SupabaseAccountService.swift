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

    /// Shared with the online games, so they run as the signed-in player.
    let client: SupabaseClient

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
            // The profile decides: a chosen picture, the Google photo, or
            // none at all when they removed it.
            player.avatarURL = row.avatar_url.flatMap(URL.init(string:))
        }
        return player
    }

    // MARK: - Name and picture

    /// Pictures live in the public "avatars" bucket, in a folder named after
    /// the account (supabase/migrations/20261104020000_profile_pictures.sql).
    private static let bucket = "avatars"

    /// The player's folder in the bucket. Lowercase, as the database writes ids.
    private func folder() throws -> String {
        guard let user = client.auth.currentUser else { throw AccountError.failed("You're signed out. Sign in and try again.") }
        return user.id.uuidString.lowercased()
    }

    func setName(_ name: String) async throws -> Player {
        let folder = try folder()
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(OnlineJSON.nameLimit))
        do {
            try await client.from("profiles")
                .update(["display_name": clean])
                .eq("id", value: folder)
                .execute()
        } catch {
            throw Self.friendly(error, saving: "Your name wasn't saved. Try again.")
        }
        return try await freshProfile()
    }

    func setPicture(jpeg: Data) async throws -> Player {
        let folder = try folder()
        // A new file name each time, so phones never show an old copy.
        let path = "\(folder)/\(UUID().uuidString.lowercased()).jpg"
        do {
            try await client.storage.from(Self.bucket).upload(
                path, data: jpeg,
                options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg", upsert: false))
            try await client.rpc("set_my_picture", params: ["p_picture": AnyJSON.string(path)]).execute()
        } catch {
            throw Self.friendly(error, saving: "Your picture wasn't saved. Try again.")
        }
        await removePictures(in: folder, keeping: path)
        return try await freshProfile()
    }

    func useGooglePicture() async throws -> Player {
        try await choosePicture("google")
    }

    func removePicture() async throws -> Player {
        try await choosePicture(nil)
    }

    private func choosePicture(_ choice: String?) async throws -> Player {
        let folder = try folder()
        do {
            try await client.rpc("set_my_picture", params: ["p_picture": choice.map(AnyJSON.string) ?? .null]).execute()
        } catch {
            throw Self.friendly(error, saving: "Your picture wasn't changed. Try again.")
        }
        await removePictures(in: folder)
        return try await freshProfile()
    }

    /// Clears out pictures the player no longer uses, so the project's free
    /// storage isn't spent on them. Nothing to say if it fails: they're
    /// tidied up the next time.
    private func removePictures(in folder: String, keeping current: String? = nil) async {
        let bucket = client.storage.from(Self.bucket)
        guard let files = try? await bucket.list(path: folder) else { return }
        let old: [String] = files.map { file -> String in "\(folder)/\(file.name)" }.filter { path in path != current }
        if !old.isEmpty { _ = try? await bucket.remove(paths: old) }
    }

    private func freshProfile() async throws -> Player {
        guard let player = await refreshProfile() else {
            throw AccountError.failed("You're signed out. Sign in and try again.")
        }
        return player
    }

    func signOut() async {
        try? await client.auth.signOut(scope: .local)
    }

    func deleteAccount() async throws {
        // Their pictures go too (the database can't remove stored files itself).
        if let folder = try? folder() { await removePictures(in: folder) }
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
        return Player(id: user.id.uuidString, name: name, email: user.email, avatarURL: picture, signInMethod: method,
                      googlePictureURL: method == "google" ? picture : nil)
    }

    /// A problem saving the name or picture, in plain words.
    private static func friendly(_ error: Error, saving fallback: String) -> Error {
        if let error = error as? AccountError { return error }
        if (error as? URLError) != nil {
            return AccountError.failed("No connection. Check your signal and try again.")
        }
        let text = "\(error)"
        // The bucket or the set_my_picture function isn't there yet: the
        // SQL in supabase/migrations/20261104020000_profile_pictures.sql
        // hasn't been run on the project.
        if text.localizedCaseInsensitiveContains("bucket not found")
            || text.contains("PGRST202") || text.localizedCaseInsensitiveContains("could not find the function") {
            return AccountError.pictureNotSetUp
        }
        if text.contains("no_google_picture") {
            return AccountError.failed("Your Google account has no photo to use.")
        }
        if text.localizedCaseInsensitiveContains("exceeded the maximum allowed size") {
            return AccountError.failed("That picture is too big. Try another.")
        }
        return AccountError.failed(fallback)
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

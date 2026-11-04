#if DEBUG
import Foundation
import UIKit

/// A pretend account server on the phone for the automatic checks, which
/// have no Google account. Launched with -mockAccount (and -mockSignedIn to
/// start signed in). Continue with Google signs in as Alex Rivera. Email
/// accounts live only until the app quits; one is there from the start,
/// jordan@example.com with the password dominoes1, for signing in.
/// Alex starts with a pretend Google photo; a new picture is kept in a file
/// on the phone.
@MainActor
final class MockAccountService: AccountService {
    static let me = Player(id: "mock-me", name: "Alex Rivera", email: "alex.rivera@example.com",
                           avatarURL: MockPictures.googleURL, googlePictureURL: MockPictures.googleURL)

    /// Tells the pretend game server when the name or picture changes, so
    /// lobbies show it like the real server would.
    var onChange: (@MainActor (Player) -> Void)?
    static let existingEmail = "jordan@example.com"
    static let existingPassword = "dominoes1"

    private var player: Player?
    /// Email accounts made so far: address to password.
    private var accounts = [existingEmail: existingPassword]

    init(signedIn: Bool) {
        player = signedIn ? Self.me : nil
        AvatarCache.store(MockPictures.google, for: MockPictures.googleURL)
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

    func setName(_ name: String) async throws -> Player {
        try await Task.sleep(for: .milliseconds(250))
        return try change { $0.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(OnlineJSON.nameLimit)) }
    }

    func setPicture(jpeg: Data) async throws -> Player {
        try await Task.sleep(for: .milliseconds(400))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("picture-\(UUID().uuidString).jpg")
        try jpeg.write(to: file)
        if let image = UIImage(data: jpeg) { AvatarCache.store(image, for: file) }
        return try change { $0.avatarURL = file }
    }

    func useGooglePicture() async throws -> Player {
        try await Task.sleep(for: .milliseconds(250))
        return try change { $0.avatarURL = $0.googlePictureURL }
    }

    func removePicture() async throws -> Player {
        try await Task.sleep(for: .milliseconds(250))
        return try change { $0.avatarURL = nil }
    }

    /// The pretend game server changed the name (Play with Friends asks for one).
    func nameChangedOnline(_ name: String) {
        player?.name = name
    }

    private func change(_ edit: (inout Player) -> Void) throws -> Player {
        guard var me = player else { throw AccountError.failed("You're signed out. Sign in and try again.") }
        edit(&me)
        player = me
        onChange?(me)
        return me
    }

    func signOut() async { player = nil }

    func deleteAccount() async throws {
        try await Task.sleep(for: .milliseconds(200))
        if let email = player?.email { accounts[email] = nil }
        player = nil
    }
}
#endif

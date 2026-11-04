import Foundation

/// A signed-in player, as the app shows them: the name and picture from their
/// Google account (or the name they've changed it to).
struct Player: Equatable {
    var id: String
    var name: String
    var email: String?
    /// The picture others see: one they chose, their Google photo, or none
    /// (initials show instead).
    var avatarURL: URL?
    /// How they signed in: "google" or "email".
    var signInMethod: String = "google"
    /// The photo on their Google account, so they can go back to it after
    /// choosing another. Nil for email accounts.
    var googlePictureURL: URL?

    /// Biggest side, in pixels, of a picture they choose: sharp at the sizes
    /// the app draws it, and only about 15 KB as a JPEG.
    static let pictureSize = 256

    /// False while an email account still goes by its address (no name
    /// chosen yet).
    var hasName: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != email
    }

    /// Up to two letters for the round badge when there's no picture:
    /// "Alex Rivera" is AR, "Prince" is P, "sam.lee@mail.com" is SL.
    var initials: String { Self.initials(for: name) }

    static func initials(for name: String) -> String {
        // An email address: only the part before the @.
        let name = name.split(separator: "@").first.map(String.init) ?? name
        let words = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "_" || $0 == "-" })
            .filter { $0.first?.isLetter == true }
        let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// The first name, for greetings: "Alex Rivera" is Alex.
    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    /// A plain check that text looks like an email address before it's used
    /// to sign in: something@something.something, no spaces.
    static func looksLikeEmail(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.contains(" "), text.count <= 254 else { return false }
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return domain.count >= 2 && domain.allSatisfy { !$0.isEmpty }
    }

    /// Shortest and longest password the app takes. Supabase's own minimum
    /// is 6 by default, so 8 always passes it; 72 is the most it stores.
    static let passwordRange = 8...72

    /// Why a new password won't do, in plain words, or nil when it's fine.
    static func passwordProblem(_ password: String) -> String? {
        if password.count < passwordRange.lowerBound {
            return "Use at least \(passwordRange.lowerBound) characters for your password."
        }
        if password.utf8.count > passwordRange.upperBound {
            return "That password is too long. Use \(passwordRange.upperBound) characters or fewer."
        }
        if password.allSatisfy(\.isWhitespace) {
            return "Your password can't be only spaces."
        }
        return nil
    }
}

/// Where accounts live: the Supabase project in Accounts.plist.
///
/// Only the project URL and its publishable key, both safe inside the app and
/// on GitHub; the database's row level security decides what each player can
/// do. Never the secret (service_role) key.
struct AccountConfig: Equatable {
    var url: URL
    var key: String

    /// The settings from Accounts.plist, or nil while they're placeholders.
    static func load(bundle: Bundle = .main) -> AccountConfig? {
        guard let file = bundle.url(forResource: "Accounts", withExtension: "plist"),
              let data = try? Data(contentsOf: file) else { return nil }
        return load(data: data)
    }

    static func load(data: Data) -> AccountConfig? {
        guard let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return AccountConfig(values: values)
    }

    init?(values: [String: Any]) {
        guard let text = (values["SupabaseURL"] as? String)?.trimmingCharacters(in: .whitespaces),
              let key = (values["SupabaseKey"] as? String)?.trimmingCharacters(in: .whitespaces),
              !text.contains("YOUR-PROJECT"), !key.isEmpty, !key.hasPrefix("YOUR-"),
              // A secret key in the app would let anyone past the database's rules.
              !key.hasPrefix("sb_secret_"),
              let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
        self.init(url: url, key: key)
    }

    init(url: URL, key: String) {
        self.url = url
        self.key = key
    }
}

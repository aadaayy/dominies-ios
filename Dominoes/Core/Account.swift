import Foundation

/// A signed-in player, as the app shows them: the name and picture from their
/// Google account (or the name they've changed it to).
struct Player: Equatable {
    var id: String
    var name: String
    var email: String?
    /// Their Google picture, if they have one. Initials show otherwise.
    var avatarURL: URL?
    /// How they signed in: "google" or "email".
    var signInMethod: String = "google"

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

    /// A plain check that text looks like an email address before a code is
    /// sent to it: something@something.something, no spaces.
    static func looksLikeEmail(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.contains(" "), text.count <= 254 else { return false }
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return domain.count >= 2 && domain.allSatisfy { !$0.isEmpty }
    }

    /// The code from a sign-in email, digits only, as typed or pasted.
    static func cleanCode(_ text: String) -> String {
        String(text.filter(\.isNumber).prefix(10))
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
    /// True once the project's emails show a six-digit code ({{ .Token }}),
    /// which Supabase allows only with your own email sender (SMTP). Until
    /// then its default emails carry a sign-in link instead.
    var emailCodes: Bool = false

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
        self.init(url: url, key: key, emailCodes: values["EmailCodes"] as? Bool ?? false)
    }

    init(url: URL, key: String, emailCodes: Bool = false) {
        self.url = url
        self.key = key
        self.emailCodes = emailCodes
    }
}

/// The link in a sign-in email, once it has been through Supabase and comes
/// back to the app as dominoes://login-callback.
enum SignInLink {
    static let scheme = "dominoes"
    static let host = "login-callback"

    static func isSignInLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host?.lowercased() == host
    }

    /// Supabase's reason when the link didn't work (for example otp_expired
    /// for an old or already used link), or nil. It can be in the query or
    /// after the #.
    static func errorCode(in url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var items = parts.queryItems ?? []
        if let fragment = parts.fragment {
            var inner = URLComponents()
            inner.query = fragment
            items += inner.queryItems ?? []
        }
        let found = items.first { $0.name == "error_code" }?.value ?? items.first { $0.name == "error" }?.value
        return found.flatMap { $0.isEmpty ? nil : $0 }
    }
}

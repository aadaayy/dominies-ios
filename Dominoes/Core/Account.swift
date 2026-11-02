import Foundation

/// A signed-in player, as the app shows them: the name and picture from their
/// Google account (or the name they've changed it to).
struct Player: Equatable {
    var id: String
    var name: String
    var email: String?
    /// Their Google picture, if they have one. Initials show otherwise.
    var avatarURL: URL?

    /// Up to two letters for the round badge when there's no picture:
    /// "Alex Rivera" is AR, "Prince" is P, an email is its first letter.
    var initials: String { Self.initials(for: name) }

    static func initials(for name: String) -> String {
        let words = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "@" || $0 == "." })
            .filter { $0.first?.isLetter == true }
        let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// The first name, for greetings: "Alex Rivera" is Alex.
    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
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

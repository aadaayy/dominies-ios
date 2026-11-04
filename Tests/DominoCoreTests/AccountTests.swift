import Foundation
import XCTest
@testable import DominoCore

final class AccountTests: XCTestCase {
    func testInitials() {
        XCTAssertEqual(Player.initials(for: "Alex Rivera"), "AR")
        XCTAssertEqual(Player.initials(for: "Ana María de la Cruz"), "AC")
        XCTAssertEqual(Player.initials(for: "Prince"), "P")
        XCTAssertEqual(Player.initials(for: "  sam  "), "S")
        XCTAssertEqual(Player.initials(for: "jordan@example.com"), "J")
        XCTAssertEqual(Player.initials(for: "sam.lee@mail.com"), "SL")
        XCTAssertEqual(Player.initials(for: ""), "?")
        XCTAssertEqual(Player.initials(for: "42"), "?")
    }

    func testFirstName() {
        XCTAssertEqual(Player(id: "1", name: "Alex Rivera").firstName, "Alex")
        XCTAssertEqual(Player(id: "1", name: "Prince").firstName, "Prince")
    }

    func testHasName() {
        // An email account goes by its address until a name is chosen.
        XCTAssertFalse(Player(id: "1", name: "sam@mail.com", email: "sam@mail.com").hasName)
        XCTAssertFalse(Player(id: "1", name: "  ", email: "sam@mail.com").hasName)
        XCTAssertTrue(Player(id: "1", name: "Sam Lee", email: "sam@mail.com").hasName)
        XCTAssertTrue(Player(id: "1", name: "Al", email: nil).hasName)
    }

    func testEmailCheck() {
        XCTAssertTrue(Player.looksLikeEmail("sam@mail.com"))
        XCTAssertTrue(Player.looksLikeEmail(" sam.lee@mail.co.uk "))
        XCTAssertFalse(Player.looksLikeEmail("sam@mail"))
        XCTAssertFalse(Player.looksLikeEmail("sam mail.com"))
        XCTAssertFalse(Player.looksLikeEmail("@mail.com"))
        XCTAssertFalse(Player.looksLikeEmail("sam@@mail.com"))
        XCTAssertFalse(Player.looksLikeEmail("sam@mail..com"))
        XCTAssertFalse(Player.looksLikeEmail(""))
    }

    func testPasswordRules() {
        XCTAssertNotNil(Player.passwordProblem(""))
        XCTAssertEqual(Player.passwordProblem("short12"), "Use at least 8 characters for your password.")
        XCTAssertNil(Player.passwordProblem("domino99"))
        XCTAssertNil(Player.passwordProblem("double nine dominoes"))
        XCTAssertNotNil(Player.passwordProblem("        "), "Only spaces won't do")
        XCTAssertNil(Player.passwordProblem(String(repeating: "a", count: 72)))
        XCTAssertNotNil(Player.passwordProblem(String(repeating: "a", count: 73)), "Supabase keeps 72 at most")
    }

    func testConfigNeedsARealProjectAndAPublicKey() {
        let real = AccountConfig(values: ["SupabaseURL": "https://abc.supabase.co", "SupabaseKey": "sb_publishable_x"])
        XCTAssertEqual(real?.url.host, "abc.supabase.co")
        XCTAssertNil(AccountConfig(values: ["SupabaseURL": "https://YOUR-PROJECT.supabase.co", "SupabaseKey": "sb_publishable_x"]))
        XCTAssertNil(AccountConfig(values: ["SupabaseURL": "https://abc.supabase.co", "SupabaseKey": "YOUR-KEY"]))
        XCTAssertNil(AccountConfig(values: ["SupabaseURL": "http://abc.supabase.co", "SupabaseKey": "sb_publishable_x"]))
        XCTAssertNil(AccountConfig(values: ["SupabaseURL": "https://abc.supabase.co", "SupabaseKey": "sb_secret_x"]))
        XCTAssertNil(AccountConfig(values: [:]))
    }

    /// The Accounts.plist that ships in the app points at the Dominoes
    /// project (not the golf app's) with its publishable key.
    func testShippedConfigIsTheDominoesProject() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dominoes/Account/Accounts.plist")
        let config = try XCTUnwrap(AccountConfig.load(data: Data(contentsOf: file)))
        XCTAssertEqual(config.url.host, "chgnvqvkcifbjtgbboqa.supabase.co")
        XCTAssertTrue(config.key.hasPrefix("sb_publishable_"))
    }
}

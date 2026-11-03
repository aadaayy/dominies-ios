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

    func testCleanCode() {
        XCTAssertEqual(Player.cleanCode("123 456"), "123456")
        XCTAssertEqual(Player.cleanCode("Code: 98-76-54"), "987654")
        XCTAssertEqual(Player.cleanCode("12345678901234"), "1234567890")
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

import XCTest

/// Signing in with Google or an emailed code, on a pretend account server
/// (-mockAccount), since the checks have no Google account or inbox. Takes the sign-in screenshots and checks
/// that everything fits on the screen and the game still plays signed out.
final class AccountUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private static var device: String { ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "" }
    private static var isDuo: Bool { device.contains("Duo") }

    /// Home signed out, the sign-in page, signing in, Home with the player's
    /// badge, then signing out again.
    @MainActor
    func testSignInWithGoogle() {
        let app = launch(["-mockAccount"])
        let badge = app.buttons["account"]
        XCTAssertTrue(badge.waitForExistence(timeout: 20), "Home should show the account badge")
        XCTAssertEqual(badge.label, "Sign in")
        assertOnScreen(app, ["account", "play"])
        capture("11-home-signed-out")

        badge.tap()
        let google = app.buttons["sign-in-google"]
        XCTAssertTrue(google.waitForExistence(timeout: 5), "The sign-in page should offer Google")
        sleep(1)
        assertOnScreen(app, ["sign-in-google", "send-code", "not-now", "account-close"])
        capture("12-sign-in")

        google.tap()
        let signOut = app.buttons["sign-out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5), "Signing in should show the account")
        XCTAssertEqual(app.staticTexts["account-name"].label, "Alex Rivera")
        sleep(1)
        assertOnScreen(app, ["sign-out", "delete-account", "account-close"])
        capture("13-signed-in")

        app.buttons["account-close"].tap()
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertEqual(badge.label, "Account, signed in as Alex Rivera")
        sleep(1)
        capture("14-home-signed-in")

        badge.tap()
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.tap()
        XCTAssertTrue(google.waitForExistence(timeout: 5), "Signing out should offer Google again")
    }

    /// Email sign-in for people without Google: the address, a code by
    /// email (a wrong one is refused), then signed in.
    @MainActor
    func testSignInWithEmail() {
        let app = launch(["-mockAccount"])
        let badge = app.buttons["account"]
        XCTAssertTrue(badge.waitForExistence(timeout: 20))
        badge.tap()

        let field = app.textFields["email-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The sign-in page should offer email")
        let send = app.buttons["send-code"]
        XCTAssertFalse(send.isEnabled, "No code without an email address")
        field.tap()
        field.typeText("sam.lee@example.com")
        XCTAssertTrue(send.isEnabled)
        capture("21-email-address")
        send.tap()

        let codeField = app.textFields["code-field"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 5), "After sending, it should ask for the code")
        XCTAssertEqual(app.staticTexts["code-sent-to"].label, "Enter the code sent to sam.lee@example.com.")
        let verify = app.buttons["verify-code"]
        XCTAssertFalse(verify.isEnabled, "No sign-in before six digits")
        codeField.tap()
        codeField.typeText("000000")
        verify.tap()
        XCTAssertTrue(app.staticTexts["account-problem"].waitForExistence(timeout: 5), "A wrong code should be refused")

        app.buttons["resend-code"].tap()
        XCTAssertTrue(app.staticTexts["account-problem"].waitForNonExistence(timeout: 5))
        sleep(1)
        codeField.tap()
        codeField.typeText("123456")
        capture("22-email-code")
        verify.tap()

        XCTAssertTrue(app.buttons["sign-out"].waitForExistence(timeout: 5), "The right code should sign in")
        XCTAssertEqual(app.staticTexts["account-name"].label, "sam.lee@example.com")
        sleep(1)
        capture("23-email-signed-in")
        app.buttons["account-close"].tap()
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertEqual(badge.label, "Account, signed in as sam.lee@example.com")
    }

    /// Delete Account asks first, then signs out.
    @MainActor
    func testDeleteAccount() {
        let app = launch(["-mockAccount", "-mockSignedIn"])
        let badge = app.buttons["account"]
        XCTAssertTrue(badge.waitForExistence(timeout: 20))
        badge.tap()
        let delete = app.buttons["delete-account"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Deleting should ask first")
        capture("15-delete-account")
        alert.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["sign-in-google"].waitForExistence(timeout: 5), "After deleting, the player is signed out")
    }

    /// No account needed to play.
    @MainActor
    func testPlaysWithoutAnAccount() {
        let app = launch(["-mockAccount", "-seed", "11", "-firstTeam", "us"])
        let play = app.buttons["play"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        play.tap()
        XCTAssertTrue(app.buttons["lead-me"].waitForExistence(timeout: 5), "The game should start signed out")
    }

    /// Phones on their side: the sign-in page and the account side by side.
    @MainActor
    func testSidewaysSignIn() throws {
        try XCTSkipIf(Self.isDuo, "The folded Duo plays upright")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch(["-mockAccount"])
        let badge = app.buttons["account"]
        XCTAssertTrue(badge.waitForExistence(timeout: 20))
        sleep(1)
        assertOnScreen(app, ["account", "play"])
        badge.tap()
        let google = app.buttons["sign-in-google"]
        XCTAssertTrue(google.waitForExistence(timeout: 5))
        sleep(1)
        assertOnScreen(app, ["sign-in-google", "send-code", "not-now", "account-close"])
        capture("16-sideways-sign-in")
        google.tap()
        XCTAssertTrue(app.buttons["sign-out"].waitForExistence(timeout: 5))
        sleep(1)
        assertOnScreen(app, ["sign-out", "delete-account", "account-close"])
        capture("17-sideways-signed-in")
        XCUIDevice.shared.orientation = .portrait
    }

    /// The open Duo, drawn at its real size on the Pro Max.
    @MainActor
    func testOpenDuoSignIn() throws {
        try XCTSkipUnless(Self.device.contains("Pro Max"), "These pictures are taken on the Pro Max only")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch(["-openDuoPreview", "-mockAccount"])
        let badge = app.buttons["account"]
        XCTAssertTrue(badge.waitForExistence(timeout: 20))
        badge.tap()
        let google = app.buttons["sign-in-google"]
        XCTAssertTrue(google.waitForExistence(timeout: 5))
        sleep(1)
        capture("18-open-duo-sign-in")

        // The code step, then back to Google.
        let field = app.textFields["email-field"]
        field.tap()
        field.typeText("sam.lee@example.com")
        app.buttons["send-code"].tap()
        XCTAssertTrue(app.textFields["code-field"].waitForExistence(timeout: 5))
        sleep(1)
        capture("18b-open-duo-email-code")
        app.buttons["change-email"].tap()
        XCTAssertTrue(google.waitForExistence(timeout: 5))
        google.tap()
        XCTAssertTrue(app.buttons["sign-out"].waitForExistence(timeout: 5))
        sleep(1)
        capture("19-open-duo-signed-in")
        app.buttons["account-close"].tap()
        XCTAssertTrue(app.buttons["play"].waitForExistence(timeout: 5))
        sleep(1)
        capture("20-open-duo-home-signed-in")
    }

    // MARK: - Helpers

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// Each button is fully on the screen, not cut off at an edge.
    @MainActor
    private func assertOnScreen(_ app: XCUIApplication, _ ids: [String]) {
        let screen = app.windows.firstMatch.frame
        for id in ids {
            let element = app.buttons[id]
            XCTAssertTrue(element.exists, "\(id) is missing")
            XCTAssertTrue(screen.insetBy(dx: -1, dy: -1).contains(element.frame),
                          "\(id) is cut off: \(element.frame) on \(screen)")
            XCTAssertTrue(element.isHittable, "\(id) can't be tapped")
        }
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

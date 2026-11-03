import XCTest

/// Signing in with Google, or with an email and password, on a pretend
/// account server (-mockAccount), since the checks have no Google account.
/// Takes the sign-in screenshots and checks that everything fits on the
/// screen (and above the keyboard) and the game still plays signed out.
final class AccountUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        // Regular iPhones play sideways only; the folded Duo plays upright.
        XCUIDevice.shared.orientation = Self.isDuo ? .portrait : .landscapeLeft
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
        assertOnScreen(app, ["sign-in-google", "email-submit", "not-now", "account-close"])
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

    /// Making an account with an email and password, for people without
    /// Google: a short password is refused with the reason, a good one makes
    /// the account and signs in at once (no email to wait for).
    @MainActor
    func testCreateAccountWithPassword() {
        let app = launch(["-mockAccount"])
        let badge = app.buttons["account"]
        XCTAssertTrue(badge.waitForExistence(timeout: 20))
        badge.tap()

        let field = app.textFields["email-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The sign-in page should offer email")
        let modes = app.segmentedControls.firstMatch
        XCTAssertTrue(modes.buttons["Create Account"].isSelected, "New players make an account first")
        let submit = app.buttons["email-submit"]
        XCTAssertEqual(submit.label, "Create Account")
        XCTAssertEqual(app.secureTextFields["password-field"].placeholderValue, "Password, at least 8 characters",
                       "Creating an account says how long the password must be")
        XCTAssertFalse(submit.isEnabled, "No account without an email and password")

        field.tap()
        field.typeText("sam.lee@example.com")
        let password = app.secureTextFields["password-field"]
        password.tap()
        password.typeText("short")
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
        let problem = app.staticTexts["account-problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 5), "A short password should be refused")
        XCTAssertEqual(problem.label, "Use at least 8 characters for your password.")
        XCTAssertFalse(app.buttons["sign-out"].exists)

        password.tap()
        password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "double99")
        sleep(1)
        assertAboveKeyboard(app, ["email-submit"])
        capture("21-create-account")
        submit.tap()

        XCTAssertTrue(app.buttons["sign-out"].waitForExistence(timeout: 5), "A good password should make the account")
        XCTAssertEqual(app.staticTexts["account-name"].label, "sam.lee@example.com")
        sleep(1)
        assertOnScreen(app, ["sign-out", "delete-account", "account-close"])
        capture("23-email-signed-in")
        app.buttons["account-close"].tap()
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertEqual(badge.label, "Account, signed in as sam.lee@example.com")
    }

    /// Signing in to an account made before: trying to make it again
    /// switches to Sign In, a wrong password is refused, the right one signs
    /// in, and the eye button shows what was typed.
    @MainActor
    func testSignInWithPassword() {
        let app = launch(["-mockAccount"])
        let badge = app.buttons["account"]
        XCTAssertTrue(badge.waitForExistence(timeout: 20))
        badge.tap()

        let field = app.textFields["email-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("jordan@example.com")
        let password = app.secureTextFields["password-field"]
        password.tap()
        password.typeText("wrong-one")
        let submit = app.buttons["email-submit"]
        submit.tap()

        let problem = app.staticTexts["account-problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 5), "An email that has an account can't make another")
        XCTAssertTrue(problem.label.hasPrefix("There's already an account with that email."), problem.label)
        let modes = app.segmentedControls.firstMatch
        XCTAssertTrue(modes.buttons["Sign In"].isSelected, "It should switch to signing in")
        XCTAssertEqual(submit.label, "Sign In")

        submit.tap()
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
        let wrong = NSPredicate(format: "label BEGINSWITH %@", "That email and password don't match.")
        expectation(for: wrong, evaluatedWith: problem)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["sign-out"].exists, "A wrong password shouldn't sign in")
        sleep(1)
        assertOnScreen(app, ["email-submit", "account-close"])
        capture("22-wrong-password")

        password.tap()
        password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "dominoes1")
        app.buttons["show-password"].tap()
        let shown = app.textFields["password-field"]
        XCTAssertTrue(shown.waitForExistence(timeout: 3), "The eye button should show the password")
        XCTAssertEqual(shown.value as? String, "dominoes1")
        sleep(1)
        assertAboveKeyboard(app, ["email-submit"])
        capture("24-sign-in-password")
        submit.tap()

        XCTAssertTrue(app.buttons["sign-out"].waitForExistence(timeout: 5), "The right password should sign in")
        XCTAssertEqual(app.staticTexts["account-name"].label, "jordan@example.com")

        // Signing out leaves a fresh form.
        app.buttons["sign-out"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["email-submit"].label, "Create Account")
        XCTAssertFalse(app.buttons["email-submit"].isEnabled)
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
        assertOnScreen(app, ["sign-in-google", "email-submit", "not-now", "account-close"])
        capture("16-sideways-sign-in")
        google.tap()
        XCTAssertTrue(app.buttons["sign-out"].waitForExistence(timeout: 5))
        sleep(1)
        assertOnScreen(app, ["sign-out", "delete-account", "account-close"])
        capture("17-sideways-signed-in")
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

        // Signing in with an email and password.
        app.segmentedControls.firstMatch.buttons["Sign In"].tap()
        let field = app.textFields["email-field"]
        field.tap()
        field.typeText("jordan@example.com")
        let password = app.secureTextFields["password-field"]
        password.tap()
        password.typeText("dominoes1")
        sleep(1)
        capture("18b-open-duo-email-password")
        password.typeText("\n")
        XCTAssertTrue(app.buttons["sign-out"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["account-name"].label, "jordan@example.com")
        sleep(1)
        capture("19-open-duo-signed-in")
        app.buttons["account-close"].tap()
        XCTAssertTrue(app.buttons["play"].waitForExistence(timeout: 5))
        sleep(1)
        capture("20-open-duo-home-signed-in")
    }

    // MARK: - Helpers

    /// Each button sits above the on-screen keyboard. Skipped when the
    /// simulator types from the Mac's keyboard and shows none.
    @MainActor
    private func assertAboveKeyboard(_ app: XCUIApplication, _ ids: [String]) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 2) else { return }
        for id in ids {
            let element = app.buttons[id]
            XCTAssertLessThanOrEqual(element.frame.maxY, keyboard.frame.minY + 1,
                                     "\(id) is under the keyboard: \(element.frame), keyboard \(keyboard.frame)")
        }
    }

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
        // Sideways pictures get turned the right way up when they're published.
        let sideways = XCUIDevice.shared.orientation.isLandscape && !name.contains("sideways") && !name.contains("open-duo")
        attachment.name = sideways ? name + "-sideways" : name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

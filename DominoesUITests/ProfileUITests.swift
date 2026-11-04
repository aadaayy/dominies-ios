import XCTest

/// Changing your name and picture on the account page, for Google and email
/// accounts alike, on the pretend account server (-mockAccount). A drawn
/// photo stands in for the photo library (-mockLibraryPhoto). Takes the
/// screenshots and checks everything fits.
final class ProfileUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        // Regular iPhones play sideways only; the folded Duo plays upright.
        XCUIDevice.shared.orientation = Self.isDuo ? .portrait : .landscapeLeft
    }

    private static var device: String { ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "" }
    private static var isDuo: Bool { device.contains("Duo") }

    /// A Google account: rename, remove the photo, go back to the Google
    /// photo, then choose a new one from the library and frame it.
    @MainActor
    func testChangeNameAndPicture() {
        let app = launch(["-mockAccount", "-mockSignedIn", "-mockLibraryPhoto"])
        openAccount(app)
        assertOnScreen(app, ["avatar-picture", "change-name", "change-picture", "sign-out", "delete-account", "account-close"])
        capture("50-profile")

        // The name.
        app.buttons["change-name"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Change Name should ask for the name")
        let field = alert.textFields.firstMatch
        XCTAssertEqual(field.value as? String, "Alex Rivera", "It starts with the current name")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Big Al")
        sleep(1)
        capture("51-change-name")
        alert.buttons["Save"].firstMatch.tap()
        let name = app.staticTexts["account-name"]
        expectation(for: NSPredicate(format: "label == %@", "Big Al"), evaluatedWith: name)
        waitForExpectations(timeout: 5)

        // Remove the photo: initials show.
        app.buttons["change-picture"].tap()
        let remove = app.buttons["Remove Photo"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "The picture menu offers Remove Photo")
        XCTAssertTrue(app.buttons["Choose Photo"].exists)
        XCTAssertFalse(app.buttons["Use Google Photo"].exists, "Already the Google photo")
        sleep(1)
        capture("52-picture-menu")
        remove.tap()
        sleep(1)

        // Back to the Google photo.
        app.buttons["change-picture"].tap()
        let google = app.buttons["Use Google Photo"]
        XCTAssertTrue(google.waitForExistence(timeout: 5), "With no picture, the Google photo is offered")
        XCTAssertFalse(app.buttons["Remove Photo"].exists, "Nothing to remove")
        google.tap()
        sleep(1)

        // A new one from the library, framed.
        app.buttons["avatar-picture"].tap()
        let choose = app.buttons["Choose Photo"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5), "Tapping the picture offers the same choices")
        choose.tap()
        let done = app.buttons["crop-choose"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "A photo opens to frame")
        sleep(1)
        assertOnScreen(app, ["crop-cancel", "crop-choose"])
        capture("53-move-and-scale")
        let window = app.windows.firstMatch
        window.pinch(withScale: 1.8, velocity: 1.5)
        let middle = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.press(forDuration: 0.1, thenDragTo: middle.withOffset(CGVector(dx: -40, dy: -30)))
        sleep(1)
        capture("54-move-and-scale-zoomed")
        done.tap()

        XCTAssertTrue(app.buttons["sign-out"].waitForExistence(timeout: 5), "Back on the account page")
        sleep(2)
        assertOnScreen(app, ["avatar-picture", "change-name", "change-picture", "sign-out", "account-close"])
        XCTAssertFalse(app.staticTexts["account-problem"].exists, "The picture should save")
        capture("55-new-picture")

        app.buttons["change-picture"].tap()
        XCTAssertTrue(app.buttons["Use Google Photo"].waitForExistence(timeout: 5), "A chosen picture can go back to Google's")
        // Close the menu without choosing.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.92)).tap()
        sleep(1)

        app.buttons["account-close"].tap()
        let badge = app.buttons["account"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertEqual(badge.label, "Account, signed in as Big Al")
        sleep(1)
        capture("56-home-new-picture")
    }

    /// Cancel on the framing screen keeps the picture as it was.
    @MainActor
    func testCancelFraming() {
        let app = launch(["-mockAccount", "-mockSignedIn", "-mockLibraryPhoto"])
        openAccount(app)
        app.buttons["change-picture"].tap()
        let choose = app.buttons["Choose Photo"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
        XCTAssertTrue(app.buttons["crop-cancel"].waitForExistence(timeout: 5))
        app.buttons["crop-cancel"].tap()
        XCTAssertTrue(app.buttons["sign-out"].waitForExistence(timeout: 5))
        app.buttons["change-picture"].tap()
        XCTAssertTrue(app.buttons["Remove Photo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Use Google Photo"].exists, "Still the Google photo")
    }

    /// An email account starts with no name: Add Your Name, and a name with
    /// an @ is refused so the address stays private.
    @MainActor
    func testEmailAccountAddsName() {
        let app = launch(["-mockAccount", "-mockLibraryPhoto"])
        let badge = app.buttons["account"]
        XCTAssertTrue(badge.waitForExistence(timeout: 20))
        badge.tap()
        app.segmentedControls.firstMatch.buttons["Sign In"].tap()
        let email = app.textFields["email-field"]
        email.tap()
        email.typeText("jordan@example.com")
        let password = app.secureTextFields["password-field"]
        password.tap()
        password.typeText("dominoes1\n")

        let addName = app.buttons["change-name"]
        XCTAssertTrue(addName.waitForExistence(timeout: 5))
        XCTAssertEqual(addName.label, "Add Your Name")
        XCTAssertEqual(app.buttons["change-picture"].label, "Add a Picture", "No picture yet, so no menu")
        sleep(1)
        assertOnScreen(app, ["avatar-picture", "change-name", "change-picture", "sign-out", "delete-account", "account-close"])
        capture("57-email-no-name")

        addName.tap()
        var alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let empty = alert.textFields.firstMatch
        XCTAssertTrue(["", "Name"].contains(empty.value as? String ?? ""), "No name to start from")
        empty.tap()
        empty.typeText("jordan@example.com")
        alert.buttons["Save"].firstMatch.tap()
        let problem = app.staticTexts["account-problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 5), "An email address isn't a name")
        XCTAssertTrue(problem.label.contains("not an email address"), problem.label)

        addName.tap()
        alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.tap()
        alert.textFields.firstMatch.typeText("Jordan Park")
        alert.buttons["Save"].firstMatch.tap()
        expectation(for: NSPredicate(format: "label == %@", "Jordan Park"), evaluatedWith: app.staticTexts["account-name"])
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.buttons["change-name"].label, "Change Name")

        // Straight to the library: there's nothing else to choose.
        app.buttons["change-picture"].tap()
        XCTAssertTrue(app.buttons["crop-choose"].waitForExistence(timeout: 5))
        app.buttons["crop-choose"].tap()
        XCTAssertTrue(app.buttons["sign-out"].waitForExistence(timeout: 5))
        sleep(2)
        capture("58-email-name-and-picture")
    }

    /// The new name and picture are the ones friends see in a game's lobby.
    @MainActor
    func testLobbyShowsNewPicture() {
        let app = launch(["-mockOnline", "-mockLibraryPhoto", "-botDelay", "0.3"])
        openAccount(app)
        app.buttons["change-picture"].tap()
        let choose = app.buttons["Choose Photo"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
        XCTAssertTrue(app.buttons["crop-choose"].waitForExistence(timeout: 5))
        app.buttons["crop-choose"].tap()
        XCTAssertTrue(app.buttons["sign-out"].waitForExistence(timeout: 5))
        sleep(1)
        app.buttons["account-close"].tap()

        let friends = app.buttons["play-friends"]
        XCTAssertTrue(friends.waitForExistence(timeout: 5))
        friends.tap()
        let newGame = app.buttons["new-game"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 10))
        newGame.tap()
        XCTAssertTrue(app.buttons["invite-friends"].waitForExistence(timeout: 5))
        app.buttons["invite-friends"].tap()
        XCTAssertTrue(app.buttons["invite-Sam"].waitForExistence(timeout: 5))
        app.buttons["invite-Sam"].tap()
        sleep(1)
        app.buttons["invite-done"].tap()
        sleep(4)
        capture("59-lobby-with-pictures")
    }

    /// The open Duo, drawn at its real size on the Pro Max.
    @MainActor
    func testOpenDuoProfile() throws {
        try XCTSkipUnless(Self.device.contains("Pro Max"), "These pictures are taken on the Pro Max only")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch(["-openDuoPreview", "-mockAccount", "-mockSignedIn", "-mockLibraryPhoto"])
        openAccount(app)
        capture("60-open-duo-profile")
        app.buttons["change-picture"].tap()
        let choose = app.buttons["Choose Photo"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
        XCTAssertTrue(app.buttons["crop-choose"].waitForExistence(timeout: 5))
        sleep(1)
        capture("61-open-duo-move-and-scale")
        app.buttons["crop-choose"].tap()
        XCTAssertTrue(app.buttons["sign-out"].waitForExistence(timeout: 5))
        sleep(2)
        capture("62-open-duo-new-picture")
    }

    // MARK: - Helpers

    @MainActor
    private func openAccount(_ app: XCUIApplication) {
        let badge = app.buttons["account"]
        XCTAssertTrue(badge.waitForExistence(timeout: 20), "Home should show the account badge")
        badge.tap()
        XCTAssertTrue(app.buttons["change-name"].waitForExistence(timeout: 5), "The account page offers Change Name")
        sleep(1)
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

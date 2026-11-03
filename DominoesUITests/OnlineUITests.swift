import XCTest

/// Playing with friends, against a pretend game server on the phone
/// (-mockOnline) with pretend friends Sam Lee and Jordan Park, who join when
/// invited and play their own turns. Takes the screenshots of every new
/// screen and checks the buttons fit.
final class OnlineUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private static var device: String { ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "" }
    private static var isDuo: Bool { device.contains("Duo") }

    /// Phones play sideways; the folded Duo plays upright.
    private func turn() {
        XCUIDevice.shared.orientation = Self.isDuo ? .portrait : .landscapeLeft
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// Home with an invite waiting, then the Play with Friends page.
    @MainActor
    func testPlayWithFriendsPage() {
        turn()
        let app = launch(["-mockOnline", "-mockInvite", "-mockGameInProgress"])
        let friends = app.buttons["play-friends"]
        XCTAssertTrue(friends.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["invite-count"].waitForExistence(timeout: 10), "Home should count the invite")
        sleep(1)
        assertOnScreen(app, ["play-friends", "play", "account"])
        capture("30-online-home-invite")

        friends.tap()
        XCTAssertTrue(app.buttons["new-game"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["join-Q8M3TZ"].waitForExistence(timeout: 10), "Sam's invite should show")
        XCTAssertTrue(app.buttons["open-HV6WPC"].exists, "The game in progress should show")
        sleep(1)
        assertOnScreen(app, ["back", "new-game", "join", "join-Q8M3TZ"])
        capture("31-online-play-with-friends")

        app.buttons["back"].tap()
        XCTAssertTrue(friends.waitForExistence(timeout: 5))
    }

    /// Signed out, Play with Friends asks you to sign in first.
    @MainActor
    func testSignedOutAsksToSignIn() {
        turn()
        let app = launch(["-mockAccount"])
        let friends = app.buttons["play-friends"]
        XCTAssertTrue(friends.waitForExistence(timeout: 20))
        friends.tap()
        XCTAssertTrue(app.buttons["friends-sign-in"].waitForExistence(timeout: 5))
        sleep(1)
        assertOnScreen(app, ["back", "friends-sign-in"])
        capture("32-online-signed-out")
        app.buttons["friends-sign-in"].tap()
        XCTAssertTrue(app.buttons["sign-in-google"].waitForExistence(timeout: 5))
    }

    /// Choosing the name friends see, then adding a friend by their code.
    @MainActor
    func testNameAndAddFriend() {
        turn()
        let app = launch(["-mockOnline", "-mockNoName", "-openFriends"])
        let field = app.textFields["name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "A player with no name is asked for one")
        XCTAssertFalse(app.buttons["new-game"].isEnabled, "No games until there's a name")
        sleep(1)
        capture("33-online-choose-name")
        field.tap()
        field.typeText("Alex")
        app.buttons["save-name"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))

        let code = app.textFields["friend-code"]
        code.tap()
        code.typeText("taylr4")
        app.buttons["add-friend"].tap()
        XCTAssertTrue(app.staticTexts["Added Taylor Kim."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["friend-Taylor Kim"].exists)
        dismissKeyboard(app)
        sleep(1)
        capture("34-online-friend-added")

        code.tap()
        code.typeText("ZZZZZZ")
        app.buttons["add-friend"].tap()
        XCTAssertTrue(app.staticTexts["friends-problem"].waitForExistence(timeout: 5), "A wrong code says so")
    }

    /// Making a game: the lobby, inviting Sam and Jordan, who join, then
    /// starting and playing a few turns, and leaving to come back later.
    @MainActor
    func testHostAGame() {
        turn()
        let app = launch(["-mockOnline", "-openFriends", "-seed", "3", "-botDelay", "0.3"])
        let newGame = app.buttons["new-game"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 20))
        newGame.tap()
        XCTAssertTrue(app.staticTexts["lobby-code"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sit-left"].exists, "Empty seats can be sat in")
        sleep(1)
        assertOnScreen(app, ["back", "disband-room", "invite-friends", "share-code", "start-game"])
        capture("35-online-lobby")

        app.buttons["invite-friends"].tap()
        let sam = app.buttons["invite-Sam"]
        XCTAssertTrue(sam.waitForExistence(timeout: 5))
        sleep(1)
        capture("36-online-invite-friends")
        sam.tap()
        XCTAssertTrue(app.buttons["invite-Jordan"].waitForExistence(timeout: 5))
        app.buttons["invite-Jordan"].tap()
        sleep(1)
        app.buttons["invite-done"].tap()

        XCTAssertTrue(app.staticTexts["A computer plays the empty seat."].waitForExistence(timeout: 10), "Both friends join")
        sleep(2)
        capture("37-online-lobby-friends-in")

        app.buttons["start-game"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["hand"].waitForExistence(timeout: 10), "The game starts")
        if app.buttons["lead-me"].waitForExistence(timeout: 3) {
            sleep(1)
            capture("38-online-who-leads")
            app.buttons["lead-me"].tap()
        }
        for _ in 0..<3 {
            guard waitForYourTurn(app) else { break }
            let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hand-tile-' AND isEnabled == true")).firstMatch
            guard tile.exists else { break }
            tile.tap()
            if app.descendants(matching: .any)["end-left"].waitForExistence(timeout: 1) {
                app.descendants(matching: .any)["end-left"].tap()
            }
        }
        sleep(2)
        capture("39-online-playing")

        app.buttons["close-game"].tap()
        let later = app.buttons["Come back later"]
        XCTAssertTrue(later.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["End it for everyone"].exists, "The host can end the game")
        sleep(1)
        capture("40-online-leave-game")
        later.tap()
        XCTAssertTrue(app.buttons["new-game"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'open-'")).firstMatch
            .waitForExistence(timeout: 5), "The game waits under Your games")
        sleep(1)
        capture("41-online-your-games")
    }

    /// Ending a room before it starts deletes it.
    @MainActor
    func testEndRoomBeforeStart() {
        turn()
        let app = launch(["-mockOnline", "-openFriends"])
        XCTAssertTrue(app.buttons["new-game"].waitForExistence(timeout: 20))
        app.buttons["new-game"].tap()
        XCTAssertTrue(app.buttons["disband-room"].waitForExistence(timeout: 5))
        app.buttons["disband-room"].tap()
        let end = app.buttons["End game"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        sleep(1)
        capture("42-online-end-room")
        end.tap()
        XCTAssertTrue(app.buttons["new-game"].waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'open-'")).firstMatch.exists,
                       "The ended room is gone")
    }

    /// Joining Sam's game from the invite: waiting for Sam to start, playing,
    /// then Sam ends the game and the table says so.
    @MainActor
    func testJoinAnInvite() {
        turn()
        let app = launch(["-mockOnline", "-mockInvite", "-mockHostEnds", "-openFriends", "-seed", "4", "-botDelay", "0.4"])
        let join = app.buttons["join-Q8M3TZ"]
        XCTAssertTrue(join.waitForExistence(timeout: 20))
        join.tap()
        XCTAssertTrue(app.descendants(matching: .any)["lobby-waiting"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["start-game"].exists, "Only the host starts")
        sleep(1)
        assertOnScreen(app, ["back", "leave-room", "invite-friends"])
        capture("43-online-lobby-guest")

        XCTAssertTrue(app.descendants(matching: .any)["hand"].waitForExistence(timeout: 10), "Sam starts the game")
        sleep(2)
        capture("44-online-guest-game")

        XCTAssertTrue(app.staticTexts["room-closed"].waitForExistence(timeout: 15), "Sam ends the game")
        sleep(1)
        capture("45-online-room-ended")
        app.buttons["room-closed-ok"].tap()
        XCTAssertTrue(app.buttons["new-game"].waitForExistence(timeout: 5))
    }

    /// A friend stops answering on their turn: after a minute anyone can let
    /// a computer play for them.
    @MainActor
    func testFriendStopsAnswering() {
        turn()
        let app = launch(["-mockOnline", "-mockGameInProgress", "-mockStall", "-openFriends", "-seed", "6", "-botDelay", "0.3"])
        let open = app.buttons["open-HV6WPC"]
        XCTAssertTrue(open.waitForExistence(timeout: 20))
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["hand"].waitForExistence(timeout: 10))
        let banner = app.buttons["replace-stalled"]
        let deadline = Date().addingTimeInterval(40)
        while !banner.exists && Date() < deadline {
            if app.buttons["lead-me"].exists { app.buttons["lead-me"].tap() }
            let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hand-tile-' AND isEnabled == true")).firstMatch
            if tile.exists && tile.isHittable {
                tile.tap()
                if app.descendants(matching: .any)["end-left"].waitForExistence(timeout: 1) {
                    app.descendants(matching: .any)["end-left"].tap()
                }
            }
            usleep(500_000)
        }
        XCTAssertTrue(banner.exists, "Jordan's turn should offer a computer")
        sleep(1)
        assertOnScreen(app, ["replace-stalled"])
        capture("46-online-friend-stalled")
        banner.tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 10))
    }

    /// The open Duo, drawn at its real size on the Pro Max.
    @MainActor
    func testOpenDuoOnline() throws {
        try XCTSkipUnless(Self.device.contains("Pro Max"), "These pictures are taken on the Pro Max only")
        XCUIDevice.shared.orientation = .landscapeLeft
        var app = launch(["-openDuoPreview", "-mockOnline", "-mockInvite", "-mockGameInProgress", "-openFriends"])
        XCTAssertTrue(app.buttons["join-Q8M3TZ"].waitForExistence(timeout: 20))
        sleep(1)
        capture("47-open-duo-play-with-friends")
        app.terminate()

        app = launch(["-openDuoPreview", "-mockOnline", "-openFriends", "-botDelay", "0.3"])
        XCTAssertTrue(app.buttons["new-game"].waitForExistence(timeout: 20))
        app.buttons["new-game"].tap()
        XCTAssertTrue(app.buttons["invite-friends"].waitForExistence(timeout: 5))
        app.buttons["invite-friends"].tap()
        XCTAssertTrue(app.buttons["invite-Sam"].waitForExistence(timeout: 5))
        app.buttons["invite-Sam"].tap()
        sleep(1)
        app.buttons["invite-done"].tap()
        sleep(3)
        capture("48-open-duo-lobby")
    }

    // MARK: - Helpers

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    @MainActor
    private func wait(for condition: () -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(250_000)
        }
        return condition()
    }

    @MainActor
    private func waitForYourTurn(_ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        wait(for: {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hand-tile-' AND isEnabled == true")).count > 0
                || app.buttons["next-game"].exists
        }, timeout: timeout) && !app.buttons["next-game"].exists
    }

    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.firstMatch.exists, app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        } else if app.keyboards.firstMatch.exists, app.keyboards.buttons["done"].exists {
            app.keyboards.buttons["done"].tap()
        }
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

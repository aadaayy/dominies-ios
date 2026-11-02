import XCTest

/// Plays through the app on each simulator and saves screenshots. The same
/// seed gives the same deal every run, so the pictures are comparable.
final class WalkthroughUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private static var device: String { ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "" }
    private static var isDuo: Bool { device.contains("Duo") }

    /// Home, choosing who leads (with the whole hand of ten in view), and a
    /// few real turns. Upright: two rows of five on narrow screens.
    @MainActor
    func testPlayingAGame() throws {
        let app = launch(["-seed", "11", "-firstTeam", "us", "-botDelay", "0.3"])
        let play = app.buttons["play"]
        XCTAssertTrue(play.waitForExistence(timeout: 20), "The home screen didn't appear")
        capture("1-home")
        play.tap()

        let leadMe = app.buttons["lead-me"]
        XCTAssertTrue(leadMe.waitForExistence(timeout: 5), "Your team should be asked who leads")
        sleep(1)
        capture("2-who-leads")
        assertWholeHandShows(app)
        leadMe.tap()

        // Take three turns (or knock when there's nothing to play).
        for turn in 1...3 {
            XCTAssertTrue(waitForYourTurn(app), "Turn \(turn) never came")
            let knock = app.buttons["knock"]
            if knock.exists {
                knock.tap()
                continue
            }
            let tile = playableTiles(app).firstMatch
            XCTAssertTrue(tile.exists, "Your turn, but no tile can be played")
            tile.tap()
            let leftEnd = app.buttons["end-left"]
            if leftEnd.waitForExistence(timeout: 1) {
                if turn == 2 { capture("3a-choose-an-end") }
                leftEnd.tap()
            }
        }
        XCTAssertTrue(waitForYourTurn(app) || app.buttons["next-game"].exists)
        XCTAssertGreaterThanOrEqual(tilesOnTable(app).count, 4, "Tiles should be on the table")
        capture("3-playing")
        try assertNoTilesOverlap(app)
    }

    /// A long line with several turns: the old game's overlap bug. Checks the
    /// tiles' real positions on screen as well as taking pictures, pinches in
    /// to zoom, and turns the phone sideways.
    @MainActor
    func testLongLineHasNoOverlaps() throws {
        let app = launch(["-seed", "5", "-startGame", "-firstTeam", "us", "-demoMoves", "30", "-botDelay", "60"])
        let table = app.descendants(matching: .any)["table"]
        XCTAssertTrue(table.waitForExistence(timeout: 20))
        sleep(1)
        XCTAssertGreaterThanOrEqual(tilesOnTable(app).count, 20, "The demo should have put a long line down")
        capture("4-long-line")
        try assertNoTilesOverlap(app)

        // Pinch to zoom in, then tap the button that shows the whole line again.
        let before = tilesOnTable(app).first?.frame.width ?? 0
        table.pinch(withScale: 2, velocity: 1.5)
        let fit = app.buttons["zoom-fit"]
        XCTAssertTrue(fit.waitForExistence(timeout: 3), "Pinching should zoom in")
        sleep(1)
        let after = tilesOnTable(app).first?.frame.width ?? 0
        XCTAssertGreaterThan(after, before * 1.3, "Tiles should look bigger after zooming in")
        capture("4z-zoomed-in")
        try assertNoTilesOverlap(app, zoomedIn: true)
        fit.tap()
        XCTAssertTrue(fit.waitForNonExistence(timeout: 3), "The whole line should show again")
        sleep(2)
        try assertNoTilesOverlap(app)

        // The phones play sideways too; the folded Duo stays upright.
        if !Self.isDuo {
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(2)
            capture("5-sideways-long-line")
            try assertNoTilesOverlap(app)
            XCUIDevice.shared.orientation = .portrait
        }
    }

    /// Sideways, a full hand of ten fits in one row.
    @MainActor
    func testSidewaysWholeHand() throws {
        try XCTSkipIf(Self.isDuo, "The folded Duo plays upright")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch(["-seed", "11", "-startGame", "-firstTeam", "us"])
        XCTAssertTrue(app.buttons["lead-me"].waitForExistence(timeout: 20))
        sleep(1)
        capture("5b-sideways-who-leads")
        assertWholeHandShows(app)
    }

    /// A finished game: the result card with everyone's leftover tiles.
    @MainActor
    func testGameResult() {
        let app = launch(["-seed", "5", "-startGame", "-firstTeam", "us", "-demoMoves", "200"])
        let next = app.buttons["next-game"]
        let done = app.buttons["done"]
        XCTAssertTrue(next.waitForExistence(timeout: 20) || done.exists, "The game should have ended")
        sleep(1)
        capture("6-game-result")
        if next.exists {
            next.tap()
            sleep(1)
            capture("6b-next-game")
        }
    }

    /// The open iPhone Duo and the smallest iPhone on its side, each drawn
    /// at its real size and shrunk to fit a sideways Pro Max, since the Duo
    /// simulator can't be unfolded here.
    @MainActor
    func testOtherScreenSizes() throws {
        try XCTSkipUnless(Self.device.contains("Pro Max"), "These pictures are taken on the Pro Max only")
        XCUIDevice.shared.orientation = .landscapeLeft
        var app = launch(["-openDuoPreview", "-seed", "11"])
        XCTAssertTrue(app.buttons["play"].waitForExistence(timeout: 20))
        sleep(1)
        capture("7-open-duo-home")
        app.terminate()

        app = launch(["-openDuoPreview", "-seed", "11", "-startGame", "-firstTeam", "us"])
        XCTAssertTrue(app.buttons["lead-me"].waitForExistence(timeout: 20))
        sleep(1)
        capture("7b-open-duo-who-leads")
        assertWholeHandShows(app)
        app.terminate()

        app = launch(["-openDuoPreview", "-seed", "5", "-startGame", "-firstTeam", "us", "-demoMoves", "30", "-botDelay", "60"])
        XCTAssertTrue(app.descendants(matching: .any)["table"].waitForExistence(timeout: 20))
        sleep(1)
        capture("8-open-duo-long-line")
        try assertNoTilesOverlap(app)
        app.terminate()

        // iPhone SE (the smallest iPhone that runs the app), on its side.
        app = launch(["-previewSize", "667x375", "-seed", "11", "-startGame", "-firstTeam", "us"])
        XCTAssertTrue(app.buttons["lead-me"].waitForExistence(timeout: 20))
        sleep(1)
        capture("9-small-phone-sideways-who-leads")
        assertWholeHandShows(app)
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
    private func playableTiles(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hand-tile-' AND isEnabled == true"))
    }

    @MainActor
    private func tilesOnTable(_ app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'table-tile-'")).allElementsBoundByIndex
    }

    /// Waits until it's your turn (or the game ended).
    @MainActor
    private func waitForYourTurn(_ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.buttons["next-game"].exists || app.buttons["done"].exists { return false }
            let status = app.staticTexts["status"]
            if status.exists, ["Your turn", "No tile to play", "You lead. Play any tile."].contains(status.label) { return true }
            usleep(200_000)
        }
        return false
    }

    /// All ten tiles of a fresh hand are on screen, none cut off, none
    /// covering another, and big enough to read.
    @MainActor
    private func assertWholeHandShows(_ app: XCUIApplication) {
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hand-tile-'")).allElementsBoundByIndex
        XCTAssertEqual(tiles.count, 10, "A full hand should show ten tiles")
        let screen = app.windows.firstMatch.frame
        let frames = tiles.map(\.frame)
        for frame in frames {
            XCTAssertTrue(screen.insetBy(dx: -1, dy: -1).contains(frame), "A hand tile is cut off: \(frame) on \(screen)")
            XCTAssertGreaterThanOrEqual(min(frame.width, frame.height), 26, "Hand tiles are too small: \(frame)")
        }
        for i in frames.indices {
            for j in frames.indices where j > i {
                let shared = frames[i].intersection(frames[j])
                XCTAssertTrue(shared.isNull || shared.width < 0.5 || shared.height < 0.5,
                              "Two hand tiles overlap: \(frames[i]) and \(frames[j])")
            }
        }
    }

    /// Reads where every tile really is on screen and fails if any two cover
    /// the same spot. (Tiles are drawn with a hairline gap, so touching tiles
    /// don't count.)
    /// Unless you've zoomed in, every tile must also sit fully inside the
    /// table, none cut off at an edge.
    @MainActor
    private func assertNoTilesOverlap(_ app: XCUIApplication, zoomedIn: Bool = false) throws {
        let frames = tilesOnTable(app).map(\.frame)
        if !zoomedIn {
            let table = app.descendants(matching: .any)["table"].frame
            for frame in frames where !table.insetBy(dx: -1, dy: -1).contains(frame) {
                XCTFail("A tile is cut off at the table's edge: \(frame) outside \(table)")
                return
            }
        }
        for i in frames.indices {
            for j in frames.indices where j > i {
                let shared = frames[i].intersection(frames[j])
                if !shared.isNull && shared.width > 0.5 && shared.height > 0.5 {
                    XCTFail("Two tiles overlap on screen: \(frames[i]) and \(frames[j])")
                    return
                }
            }
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

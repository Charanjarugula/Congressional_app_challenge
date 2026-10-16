import XCTest

final class HitStatesTests: XCTestCase {
    func testHitStatesExposeAppropriateActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--hits-ui-checks"]
        app.launch()
        for state in ["Open", "Host", "Pending", "Invited", "Confirmed", "Cancelled", "Played"] {
            let entry = app.buttons[state]
            XCTAssertTrue(entry.waitForExistence(timeout: 10))
            entry.tap()
            XCTAssertTrue(app.staticTexts["Who’s playing"].waitForExistence(timeout: 5))
            if state == "Open" { XCTAssertTrue(app.buttons["Ask to join"].exists) }
            if state == "Host" { XCTAssertTrue(app.buttons["Edit"].exists) }
            if state == "Invited" { XCTAssertTrue(app.buttons["I’m in"].exists) }
            if state == "Pending" { XCTAssertFalse(app.buttons["Ask to join"].exists) }
            if state == "Cancelled" || state == "Played" {
                XCTAssertFalse(app.buttons["Ask to join"].exists)
                XCTAssertFalse(app.buttons["I’m in"].exists)
            }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Hit - " + state
            shot.lifetime = .keepAlways
            add(shot)
            app.navigationBars.buttons.firstMatch.tap()
        }
    }
}

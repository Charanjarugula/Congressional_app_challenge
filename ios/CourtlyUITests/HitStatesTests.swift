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
            if state == "Open" {
                XCTAssertTrue(app.buttons["Ask to join"].exists)
                // Someone who isn't the host can still send the hit to a friend.
                app.buttons["More"].tap()
                XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 5))
                app.buttons["Share"].tap()
                XCTAssertTrue(app.staticTexts["Share"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["Copy link"].exists)
                app.buttons["Done"].tap()
            }
            if state == "Host" {
                // One pinned action; editing and the rest live behind More.
                app.buttons["More"].tap()
                XCTAssertTrue(app.buttons["Edit hit"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["Cancel hit"].exists)
                app.buttons["Edit hit"].tap()
                XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
                app.buttons["Cancel"].firstMatch.tap()
                app.buttons["More"].tap()
                XCTAssertTrue(app.buttons["Invite"].waitForExistence(timeout: 5))
                app.buttons["Invite"].tap()
                XCTAssertTrue(app.buttons["Copy link"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["More"].exists)
                let sheet = XCTAttachment(screenshot: app.screenshot())
                sheet.name = "Hit - Invite sheet"
                sheet.lifetime = .keepAlways
                add(sheet)
                app.buttons["Done"].tap()
            }
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

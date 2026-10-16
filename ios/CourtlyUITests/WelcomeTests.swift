import XCTest

/// Runs without an account on a fresh simulator; never submits credentials or creates server data.
final class WelcomeTests: XCTestCase {
    func testWelcomeEntryPointsAndBackNavigation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["Get started"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        XCTAssertTrue(start.isHittable)
        XCTAssertTrue(app.buttons["I already have an account"].isHittable)
        let welcome = XCTAttachment(screenshot: app.screenshot())
        welcome.name = "Welcome"
        welcome.lifetime = .keepAlways
        add(welcome)

        start.tap()
        XCTAssertTrue(app.staticTexts["Create your account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Email"].exists)
        XCTAssertFalse(app.buttons["Continue"].firstMatch.isEnabled)
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))

        app.buttons["I already have an account"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Email"].exists)
        XCTAssertFalse(app.buttons["Continue"].firstMatch.isEnabled)
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(start.isHittable)
    }
}

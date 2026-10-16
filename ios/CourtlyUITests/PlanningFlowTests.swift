import XCTest

final class PlanningFlowTests: XCTestCase {
    func testPickersCapacityAndCancel() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--planning-ui-checks"]
        app.launch()
        app.buttons["Open plan"].tap()
        XCTAssertTrue(app.staticTexts["Plan a hit"].waitForExistence(timeout: 10))
        let day = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Day'")).firstMatch
        day.tap()
        XCTAssertTrue(app.datePickers.firstMatch.exists)
        day.tap()
        let time = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Time'")).firstMatch
        time.tap()
        XCTAssertTrue(app.buttons["120 min"].waitForExistence(timeout: 5))
        app.buttons["120 min"].tap()
        time.tap()
        XCTAssertTrue(time.label.contains("120 min"))
        app.swipeUp()
        app.buttons["Doubles"].tap()
        XCTAssertTrue(app.staticTexts["3 players"].exists)
        app.buttons["Add a player spot"].tap()
        XCTAssertTrue(app.staticTexts["4 players"].exists)
        app.buttons["Remove a player spot"].tap()
        XCTAssertTrue(app.staticTexts["3 players"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Planning form"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Open plan"].waitForExistence(timeout: 5))
    }
}

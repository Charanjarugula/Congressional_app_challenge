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
        let time = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start time'")).firstMatch
        time.tap()
        XCTAssertTrue(app.datePickers.firstMatch.exists)
        XCTAssertFalse(app.buttons["60 min"].exists)
        XCTAssertFalse(app.buttons["90 min"].exists)
        XCTAssertFalse(app.buttons["120 min"].exists)
        time.tap()
        XCTAssertFalse(time.label.contains("min"))
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

extension PlanningFlowTests {
    func testLiveAddressSearchAndCourtConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--planning-ui-checks"]
        app.launch()
        app.buttons["Open plan"].tap()
        XCTAssertTrue(app.buttons["Choose a court"].waitForExistence(timeout: 10))
        app.buttons["Choose a court"].tap()
        let search = app.textFields["Address, court, or place name"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("1600 Amphitheatre Parkway, Mountain View, CA")
        let review = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Review'")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 25), "Live MapKit address search should return a result")
        review.tap()
        XCTAssertTrue(app.navigationBars["Use this court"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["courtName"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Surface'")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Lights'")).firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Exact address and court details"
        shot.lifetime = .keepAlways
        add(shot)
        // Read-only live search: never add this non-court address to the shared database.
        app.buttons["Back"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        app.buttons["Clear search"].tap()
        XCTAssertTrue(app.staticTexts["Near you"].exists)
        app.buttons["cancelCourtSearch"].tap()
        XCTAssertTrue(app.staticTexts["Plan a hit"].waitForExistence(timeout: 5))
    }
}

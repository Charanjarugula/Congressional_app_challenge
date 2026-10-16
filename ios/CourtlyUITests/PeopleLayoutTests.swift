import XCTest

final class PeopleLayoutTests: XCTestCase {
    func testRequestActionsStayWithEachPlayer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--people-ui-checks"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Ana M."].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "Confirm").count, 2)
        XCTAssertEqual(app.buttons.matching(identifier: "Delete").count, 2)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Friend requests - grouped actions"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

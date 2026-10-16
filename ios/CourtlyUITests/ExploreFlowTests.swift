import XCTest

final class ExploreFlowTests: XCTestCase {
    func testExpandFiltersCancelAndNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--explore-ui-checks"]
        app.launch()
        let discover = app.buttons["Discover"]
        XCTAssertTrue(discover.waitForExistence(timeout: 10))
        discover.tap()
        XCTAssertTrue(discover.isSelected)
        app.buttons["open-filters"].tap()
        let tomorrow = app.buttons["Tomorrow"]
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 5))
        tomorrow.tap()
        XCTAssertTrue(tomorrow.isSelected)
        capture(app, "Filters")
        app.buttons["Cancel"].tap()
        app.buttons["open-filters"].tap()
        XCTAssertTrue(app.buttons["Any day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Any day"].isSelected, "Cancelled filter changes must not persist")
        app.buttons["Cancel"].tap()
        app.buttons["Friends"].tap()
        app.buttons["open-filters"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["Any distance"].isSelected)
        app.buttons["50 mi"].tap()
        app.buttons["Show hits"].tap()
        app.buttons["Discover"].tap()
        app.buttons["open-filters"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["50 mi"].isSelected)
        app.buttons["Reset"].tap()
        app.buttons["Show hits"].tap()
        let hit = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Casual hitting' AND label CONTAINS 'Jordan'")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 5))
        capture(app, "Explore card")
        hit.tap()
        let join = app.buttons["Ask to join"]
        if !join.isHittable { app.swipeUp() }
        XCTAssertTrue(join.isHittable)
        XCTAssertTrue(app.buttons["Open in Maps"].exists)
        capture(app, "Expanded hit")
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Settings"].isSelected)
        app.buttons["Explore"].tap()
        XCTAssertTrue(app.buttons["Explore"].isSelected)
        XCTAssertTrue(discover.isSelected)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

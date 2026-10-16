import XCTest

final class ExploreFlowTests: XCTestCase {
    private let friend = "explore-hit-00000000-0000-0000-0000-000000000101"
    private let stranger = "explore-hit-00000000-0000-0000-0000-000000000102"
    private let far = "explore-hit-00000000-0000-0000-0000-000000000103"

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--explore-ui-checks"]
        app.launchEnvironment["TZ"] = "UTC"
        app.launch()
        XCTAssertTrue(app.buttons["All hits"].waitForExistence(timeout: 10))
        return app
    }

    func testUnifiedInventorySortingScopeAndDetail() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["explore-count"].label.contains("3 hits"), "Duplicate friend listing must appear only once")
        XCTAssertLessThan(app.buttons[friend].frame.minY, app.buttons[stranger].frame.minY)
        XCTAssertFalse(app.buttons["I’m in"].exists, "A joined invitation must not be actionable again")
        capture(app, "Explore All hits")
        app.buttons["Friends"].tap()
        XCTAssertTrue(app.staticTexts["explore-count"].label.contains("1 hit"))
        app.buttons["All hits"].tap()
        app.buttons["explore-sort"].tap()
        app.buttons["Soonest"].tap()
        XCTAssertLessThan(app.buttons[stranger].frame.minY, app.buttons[friend].frame.minY)
        app.buttons[stranger].tap()
        XCTAssertTrue(app.buttons["Ask to join"].waitForExistence(timeout: 8))
        capture(app, "Explore opens hit detail")
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(app.buttons["All hits"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["explore-sort"].label.contains("Soonest"))
        app.buttons["Plan a hit"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        capture(app, "Explore opens planning")
        app.buttons["Cancel"].tap()
    }

    func testFiltersApplyCancelResetAndEmptyRecovery() {
        let app = launch()
        app.buttons["open-filters"].tap()
        XCTAssertTrue(app.buttons["Doubles"].waitForExistence(timeout: 5))
        app.buttons["Doubles"].tap()
        capture(app, "Explore filters")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["explore-count"].label.contains("3 hits"))
        app.buttons["open-filters"].tap()
        XCTAssertFalse(app.buttons["Doubles"].isSelected)
        app.buttons["Doubles"].tap()
        app.buttons["apply-filters"].tap()
        XCTAssertTrue(app.staticTexts["explore-count"].label.contains("1 hit"))
        XCTAssertTrue(app.buttons[far].exists, "No implicit 50-mile cutoff")
        app.buttons["Friends"].tap()
        XCTAssertTrue(app.staticTexts["No matching hits from friends"].waitForExistence(timeout: 5))
        capture(app, "Explore empty search")
        app.buttons["See all hits"].tap()
        XCTAssertTrue(app.buttons[far].exists)
        app.buttons["open-filters"].tap()
        app.buttons["Reset all"].tap()
        app.swipeUp()
        app.buttons["Set a maximum"].tap()
        app.buttons["50 mi"].tap()
        app.buttons["apply-filters"].tap()
        XCTAssertTrue(app.staticTexts["explore-count"].label.contains("2 hits"))
        app.buttons["open-filters"].tap()
        app.buttons["Reset all"].tap()
        app.buttons["apply-filters"].tap()
        XCTAssertTrue(app.staticTexts["explore-count"].label.contains("3 hits"))
    }

    func testTimeSearchCancelApplyAndExactTimes() {
        let app = launch()
        app.buttons["explore-search"].tap()
        XCTAssertTrue(app.buttons["Tomorrow"].waitForExistence(timeout: 5))
        app.buttons["Tomorrow"].tap()
        app.buttons["Cancel"].tap()
        app.buttons["explore-search"].tap()
        XCTAssertTrue(app.buttons["Any day"].isSelected)
        app.buttons["Tomorrow"].tap()
        let afternoon = app.buttons["Afternoon · 12–5"]
        if !afternoon.isHittable { app.swipeUp() }
        afternoon.tap()
        capture(app, "Explore where and when")
        app.buttons["Show hits"].tap()
        XCTAssertTrue(app.staticTexts["explore-count"].label.contains("1 hit"))
        XCTAssertTrue(app.buttons[stranger].exists)
        app.buttons["explore-search"].tap()
        app.swipeUp()
        app.buttons["Choose exact times"].tap()
        XCTAssertTrue(app.datePickers.count >= 2)
        capture(app, "Explore exact time pickers")
        app.buttons["Cancel"].tap()
    }

    func testLargeText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--explore-ui-checks", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        XCTAssertTrue(app.buttons["All hits"].waitForExistence(timeout: 10))
        capture(app, "Explore larger text")
        app.buttons["open-filters"].tap()
        XCTAssertTrue(app.buttons["Singles"].waitForExistence(timeout: 5))
        app.buttons["Singles"].tap()
        app.buttons["apply-filters"].tap()
        XCTAssertTrue(app.staticTexts["explore-count"].label.contains("1 hit"))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

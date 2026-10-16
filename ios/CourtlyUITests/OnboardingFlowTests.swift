import XCTest

/// Real onboarding views with an isolated local draft, never a production account or save.
final class OnboardingFlowTests: XCTestCase {
    private func open(_ name: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--onboarding-ui-checks"]
        app.launch()
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 10))
        app.buttons[name].tap()
        return app
    }

    func testNameValidationAndKeyboard() {
        let app = open("Name")
        let next = app.buttons["Continue"].firstMatch
        XCTAssertFalse(next.isEnabled)
        let field = app.textFields["First name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let keyboardIntro = app.otherElements["UIContinuousPathIntroductionView"].buttons["Continue"]
        if keyboardIntro.exists { keyboardIntro.tap() }
        field.typeText("Sam")
        XCTAssertTrue(next.isEnabled)
        XCTAssertTrue(next.isHittable)
        capture(app, "Name keyboard")
        next.tap()
        XCTAssertTrue(app.staticTexts["Advanced"].waitForExistence(timeout: 5))
    }

    func testSingleAndMultipleSelections() {
        var app = open("Level")
        XCTAssertFalse(app.buttons["Continue"].firstMatch.isEnabled)
        let intermediate = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Intermediate'")).firstMatch
        intermediate.tap()
        XCTAssertTrue(intermediate.isSelected)
        XCTAssertTrue(app.buttons["Continue"].firstMatch.isEnabled)
        capture(app, "Level selected")
        app.buttons["Continue"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Advanced"].waitForExistence(timeout: 5))
        app = open("Formats")
        XCTAssertFalse(app.buttons["Continue"].firstMatch.isEnabled)
        let singles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Singles'")).firstMatch
        singles.tap()
        XCTAssertTrue(app.buttons["Continue"].firstMatch.isEnabled)
        capture(app, "Formats selected")
        singles.tap()
        XCTAssertFalse(app.buttons["Continue"].firstMatch.isEnabled)
    }

    func testAvailabilitySelectionAndCalendarDismissal() {
        let app = open("Availability")
        let cell = app.buttons["Mon Morning"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        XCTAssertTrue(cell.isSelected)
        capture(app, "Availability selected")
        let calendar = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Connect your calendar'")).firstMatch
        if !calendar.isHittable { app.swipeUp() }
        calendar.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Apple Calendar'")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "Apple Calendar sheet")
        app.buttons["Close"].tap()
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertTrue(cell.isSelected)
        app.buttons["Continue"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Advanced"].waitForExistence(timeout: 5))
    }

    func testRemainingScreenLayouts() {
        for screen in ["Birthday", "Location", "Players", "Notifications", "Done"] {
            let app = open(screen)
            let next = app.buttons[screen == "Done" ? "Let’s hit" : screen == "Location" ? "Use my location" : "Continue"]
            XCTAssertTrue(next.waitForExistence(timeout: 15), "Missing primary action on \(screen)")
            XCTAssertTrue(next.isHittable)
            capture(app, screen)
            if screen == "Birthday" { XCTAssertFalse(next.isEnabled) }
            if screen == "Done" {
                next.tap()
                XCTAssertTrue(app.staticTexts["Advanced"].waitForExistence(timeout: 5))
            }
        }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

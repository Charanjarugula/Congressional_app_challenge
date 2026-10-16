import XCTest

final class RemainingFlowsTests: XCTestCase {
    func testLargerTextSettingsAndChat() {
        checkFlows(largerText: true)
    }

    func testSettingsCancellationAndChatComposerStates() {
        checkFlows(largerText: false)
    }

    private func checkFlows(largerText: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--remaining-ui-checks"]
        if largerText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["Settings check"].waitForExistence(timeout: 10))
        app.buttons["Settings check"].tap()
        XCTAssertTrue(app.buttons["Change profile photo"].waitForExistence(timeout: 5))
        capture(app, "Settings")
        let level = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Level")).firstMatch
        XCTAssertTrue(level.exists)
        level.tap()
        let beginner = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Beginner")).firstMatch
        XCTAssertTrue(beginner.waitForExistence(timeout: 5))
        beginner.tap()
        capture(app, "Level - selected blue")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(level.waitForExistence(timeout: 5))
        XCTAssertTrue(level.label.contains("Intermediate"), "Cancelling must retain the original preference")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Chat check"].tap()
        XCTAssertTrue(app.buttons["Request a hit"].waitForExistence(timeout: 5))
        let firstMessage = app.staticTexts["Want to hit tomorrow evening?"]
        XCTAssertTrue(firstMessage.waitForExistence(timeout: 5))
        XCTAssertLessThan(firstMessage.frame.minY, app.frame.height * 0.4, "Short conversations must start near the top")
        capture(app, "Chat")
        let composer = app.textFields["Message"].exists ? app.textFields["Message"] : app.textViews.firstMatch
        composer.tap()
        composer.typeText("Tomorrow works")
        XCTAssertTrue(app.buttons["Send"].exists)
        XCTAssertFalse(app.buttons["Request a hit"].exists)
        capture(app, "Chat - keyboard")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Read-only chat check"].tap()
        XCTAssertTrue(app.staticTexts["You left this chat"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Send"].exists)
        XCTAssertFalse(app.buttons["Request a hit"].exists)
        capture(app, "Chat - read only")
    }

    func testOverviewScreensAndPreferenceSheets() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--remaining-ui-checks"]
        app.launch()
        for entry in ["People check", "My Hits check", "Player check", "Group check"] {
            XCTAssertTrue(app.buttons[entry].waitForExistence(timeout: 10))
            app.buttons[entry].tap()
            if entry == "My Hits check" {
                XCTAssertTrue(app.buttons["Past"].waitForExistence(timeout: 5))
                app.buttons["Past"].tap()
            }
            if entry == "Player check" {
                XCTAssertTrue(app.buttons["Invite to hit"].exists)
                XCTAssertTrue(app.buttons["Message"].isEnabled)
                app.swipeUp()
                XCTAssertTrue(app.buttons["Ask to join"].exists)
            }
            capture(app, entry)
            app.navigationBars.buttons.firstMatch.tap()
        }
        app.buttons["Settings check"].tap()
        for title in ["Name", "Plays", "Area", "Availability"] {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            if !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.exists)
            row.tap()
            XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Save"].isHittable)
            if title == "Area" {
                XCTAssertFalse(app.staticTexts["Show hits within"].exists)
                let field = app.textFields["City, state or ZIP code"]
                XCTAssertTrue(field.exists)
                field.tap()
                field.typeText(" Wellington, FL")
                XCTAssertTrue((field.value as? String ?? "").contains("Wellington"))
                XCTAssertFalse(app.buttons["Save"].isEnabled)
            }
            capture(app, "Settings - " + title)
            app.buttons["Cancel"].tap()
        }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

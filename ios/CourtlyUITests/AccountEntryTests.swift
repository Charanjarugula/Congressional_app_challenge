import XCTest

/// Uses the existing reviewer address's no-send path; never verifies a code or creates an account.
final class AccountEntryTests: XCTestCase {
    func testEmailValidationKeyboardAndCodeRecovery() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 20))
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.staticTexts["Create your account"].waitForExistence(timeout: 5))
        capture(app, "Create account")
        app.buttons["Back"].tap()
        app.buttons["I already have an account"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        capture(app, "Sign in")

        let email = app.textFields["Email"]
        let next = app.buttons["Continue"].firstMatch
        XCTAssertFalse(next.isEnabled)
        email.tap()
        email.typeText("invalid")
        XCTAssertFalse(next.isEnabled)
        email.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
        email.typeText("reviewer@courtly.app")
        XCTAssertTrue(next.isEnabled)
        XCTAssertTrue(next.isHittable, "Continue must stay accessible above the keyboard")
        capture(app, "Email keyboard")
        next.tap()

        XCTAssertTrue(app.staticTexts["Check your email"].waitForExistence(timeout: 5))
        let code = app.textFields["Code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        let resend = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resend code'")).firstMatch
        XCTAssertTrue(resend.exists)
        XCTAssertFalse(resend.isEnabled)
        XCTAssertFalse(next.isEnabled)
        code.tap()
        code.typeText("12345")
        XCTAssertFalse(next.isEnabled)
        code.typeText("6")
        XCTAssertTrue(next.isEnabled)
        XCTAssertTrue(next.isHittable)
        capture(app, "Code keyboard")
        // Six digits only: eight digits would automatically submit the review-account password.
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        XCTAssertEqual(email.value as? String, "reviewer@courtly.app")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 5))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

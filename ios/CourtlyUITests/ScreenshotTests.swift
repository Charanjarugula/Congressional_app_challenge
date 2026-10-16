import XCTest

/// Walks the app as the App Review account and saves one PNG per screen shown in the README.
/// The "README screenshots" workflow runs it on a simulator; without SCREENSHOT_DIR and
/// REVIEWER_PASSWORD in the environment the test is skipped, so a plain ⌘U never signs in.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var directory: URL!
    private var code = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["SCREENSHOT_DIR"], !path.isEmpty,
              let password = environment["REVIEWER_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("Set SCREENSHOT_DIR and REVIEWER_PASSWORD to capture the README screenshots")
        }
        directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        code = password
        app = XCUIApplication()
    }

    func testCaptureReadmeScreens() throws {
        app.launch()

        // Welcome, then sign in with the review account's code.
        let signIn = app.buttons["I already have an account"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 30), "The welcome screen did not appear")
        settle(1.5)
        save("welcome")
        signIn.tap()

        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10), "The email field did not appear")
        email.tap()
        email.typeText("reviewer@courtly.app")
        app.buttons["Continue"].firstMatch.tap()

        let codeField = app.textFields["Code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 15), "The code field did not appear")
        codeField.tap()
        codeField.typeText(code)   // eight digits verify on their own

        // Play is directly usable after sign-in, without first-run tips.
        let myHitsTab = app.buttons["My Hits"]
        XCTAssertTrue(myHitsTab.waitForExistence(timeout: 60), "Signing in did not reach the main tabs")
        settle(5)
        save("play")

        // Plan a hit.
        app.buttons["Plan a hit"].firstMatch.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "The Plan a hit sheet did not open")
        settle(3)
        save("plan")
        cancel.firstMatch.tap()

        // My Hits and one hit's detail.
        myHitsTab.tap()
        settle(3)
        save("my-hits")
        let hitRow = try XCTUnwrap(firstHittable(app.buttons.matching(NSPredicate(format: "label CONTAINS ' · '"))), "No hit row on My Hits")
        hitRow.tap()
        settle(4)
        save("hit")
        goBack()

        // People and one chat.
        app.buttons["People"].firstMatch.tap()
        settle(3)
        save("people")
        let demoNames = ["Ana", "Luis", "Priya", "Marcus"].map { "label CONTAINS '\($0)'" }.joined(separator: " OR ")
        let chats = NSPredicate(format: "(\(demoNames)) AND NOT label CONTAINS 'Friend requests'")
        let chatRow = try XCTUnwrap(firstHittable(app.buttons.matching(chats)), "No chat row on People")
        chatRow.tap()
        settle(4)
        save("chat")
        goBack()

        // You.
        app.buttons["You"].firstMatch.tap()
        settle(3)
        save("you")
    }

    // MARK: - Helpers

    /// The other tabs stay in the hierarchy at zero opacity, so a label match alone can land on a
    /// card that is not on screen; the first one that can be tapped is the one on the visible tab.
    private func firstHittable(_ query: XCUIElementQuery, timeout: TimeInterval = 15) -> XCUIElement? {
        let deadline = Date.now.addingTimeInterval(timeout)
        repeat {
            if let element = query.allElementsBoundByIndex.first(where: \.isHittable) { return element }
            settle(1)
        } while Date.now < deadline
        return nil
    }

    private func goBack() {
        let back = app.buttons["Back"]
        if back.waitForExistence(timeout: 5) {
            back.firstMatch.tap()
        } else {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        settle(1)
    }

    /// Lets animations and network loads finish before a capture.
    private func settle(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [expectation(description: "settle")], timeout: seconds)
    }

    private func save(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let file = directory.appendingPathComponent("\(name).png")
        XCTAssertNoThrow(try screenshot.pngRepresentation.write(to: file), "Could not write \(name).png")
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

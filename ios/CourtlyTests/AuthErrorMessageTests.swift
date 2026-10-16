import AuthenticationServices
import XCTest
@testable import Courtly

final class AuthErrorMessageTests: XCTestCase {
    func testSystemErrorsNeverShowTheirRawText() {
        let apple = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.unknown.rawValue)
        let message = AuthError.message(for: apple)
        XCTAssertFalse(message.contains("AuthorizationError"))
        XCTAssertFalse(message.contains("1000"))
        XCTAssertEqual(message, "Sign-in didn’t finish. Please try again.")
    }

    func testOwnErrorsKeepTheirSentence() {
        XCTAssertEqual(AuthError.message(for: AuthError.appleUnavailable), AuthError.appleUnavailable.errorDescription)
        XCTAssertEqual(AuthError.message(for: AuthError.invalidCode), "That code didn’t work. Check the email and try again.")
    }

    func testConnectionProblemsSaySo() {
        XCTAssertEqual(AuthError.message(for: URLError(.notConnectedToInternet)), "You’re offline. Check your connection and try again.")
        XCTAssertEqual(AuthError.message(for: URLError(.timedOut)), "Couldn’t reach Courtly. Check your connection and try again.")
    }
}

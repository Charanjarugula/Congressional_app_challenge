import XCTest
@testable import Courtly

/// Records the sentences the app shows for the short error codes the database raises.
final class BackendMessagesTests: XCTestCase {
    func testCodesThatShareASentence() {
        XCTAssertEqual(BackendMessages.text(for: "hit_full"), "That spot was just taken.")
        XCTAssertEqual(BackendMessages.text(for: "spot_taken"), "That spot was just taken.")
        XCTAssertEqual(BackendMessages.text(for: "request_not_found"), "This request was already answered.")
        XCTAssertEqual(BackendMessages.text(for: "request_closed"), "This request was already answered.")
    }

    func testProfileCodesAllAskToFinishSettingUp() {
        for code in ["onboarding_incomplete", "missing_birthday", "missing_level", "missing_formats", "missing_location"] {
            XCTAssertEqual(BackendMessages.text(for: code), "Finish setting up your profile first.", code)
        }
    }

    func testSentencesUseTypographicApostrophes() {
        XCTAssertEqual(BackendMessages.text(for: "already_in"), "You’re already in this hit.")
        XCTAssertEqual(BackendMessages.text(for: "hit_closed"), "This hit isn’t open anymore.")
    }

    func testAgeAndAccountCodes() {
        XCTAssertEqual(BackendMessages.text(for: "underage"), "Courtly is for players 18 and older.")
        XCTAssertEqual(BackendMessages.text(for: "account_suspended"), "This account has been suspended.")
        XCTAssertEqual(BackendMessages.text(for: "no_profile"), "We couldn’t find your profile. Sign in again.")
    }

    func testUnknownCodesBecomeCapitalizedWords() {
        XCTAssertEqual(BackendMessages.text(for: "court_closed_for_rain"), "Court Closed For Rain")
        XCTAssertEqual(BackendMessages.text(for: "unknown"), "Unknown")
        XCTAssertEqual(BackendMessages.text(for: ""), "")
    }
}

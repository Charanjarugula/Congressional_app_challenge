import XCTest
@testable import Courtly

/// Records how `DeepLink` reads the `courtly://` links the backend writes into notifications.
final class DeepLinkTests: XCTestCase {
    private let hitID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let playerID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    func testPlayLinkIgnoresAnyPath() {
        XCTAssertEqual(DeepLink(string: "courtly://play"), .play)
        XCTAssertEqual(DeepLink(string: "courtly://play/anything/else"), .play)
    }

    func testLinksThatCarryOneID() {
        XCTAssertEqual(DeepLink(string: "courtly://hit/\(hitID.uuidString)"), .hit(hitID))
        XCTAssertEqual(DeepLink(string: "courtly://request/\(hitID.uuidString)"), .request(hitID))
        XCTAssertEqual(DeepLink(string: "courtly://chat/\(hitID.uuidString)"), .chat(hitID))
    }

    func testLowercaseIDsParseToo() {
        XCTAssertEqual(DeepLink(string: "courtly://hit/\(hitID.uuidString.lowercased())"), .hit(hitID))
    }

    func testCheckLinkNeedsBothIDs() {
        XCTAssertEqual(DeepLink(string: "courtly://check/\(hitID.uuidString)/\(playerID.uuidString)"),
                       .check(hitID: hitID, playerID: playerID))
        XCTAssertNil(DeepLink(string: "courtly://check/\(hitID.uuidString)"))
    }

    func testFriendRequestsLink() {
        XCTAssertEqual(DeepLink(string: "courtly://people/requests"), .friendRequests)
        XCTAssertNil(DeepLink(string: "courtly://people"))
        XCTAssertNil(DeepLink(string: "courtly://people/friends"))
    }

    func testRejectsOtherSchemesUnknownHostsAndBadIDs() {
        XCTAssertNil(DeepLink(string: "https://courtly.app/play"))
        XCTAssertNil(DeepLink(string: "courtly://settings"))
        XCTAssertNil(DeepLink(string: "courtly://hit"))
        XCTAssertNil(DeepLink(string: "courtly://hit/not-a-uuid"))
        XCTAssertNil(DeepLink(string: "courtly://hit/\(hitID.uuidString)/extra"))
        XCTAssertNil(DeepLink(string: ""))
    }

    func testUserInfoPrefersTheDeepLinkString() {
        let userInfo: [AnyHashable: Any] = ["deep_link": "courtly://play", "data": ["chat_id": hitID.uuidString]]
        XCTAssertEqual(DeepLink(userInfo: userInfo), .play)
    }

    func testUserInfoFallsBackToChatThenHit() {
        XCTAssertEqual(DeepLink(userInfo: ["data": ["chat_id": hitID.uuidString]]), .chat(hitID))
        XCTAssertEqual(DeepLink(userInfo: ["data": ["hit_id": hitID.uuidString]]), .hit(hitID))
        XCTAssertEqual(DeepLink(userInfo: ["data": ["chat_id": hitID.uuidString, "hit_id": playerID.uuidString]]), .chat(hitID))
    }

    func testUserInfoWithAnUnreadableDeepLinkStillUsesTheData() {
        XCTAssertEqual(DeepLink(userInfo: ["deep_link": "courtly://nowhere", "data": ["hit_id": hitID.uuidString]]), .hit(hitID))
    }

    func testUserInfoWithNothingUsefulIsNil() {
        XCTAssertNil(DeepLink(userInfo: [:]))
        XCTAssertNil(DeepLink(userInfo: ["data": ["chat_id": "junk"]]))
        XCTAssertNil(DeepLink(userInfo: ["aps": ["alert": "Hello"]]))
    }

    func testChatIDHelperOnlyAnswersForChatLinks() {
        XCTAssertEqual(DeepLinkCenter.chatID(in: ["deep_link": "courtly://chat/\(hitID.uuidString)"]), hitID)
        XCTAssertNil(DeepLinkCenter.chatID(in: ["deep_link": "courtly://hit/\(hitID.uuidString)"]))
    }
}

import XCTest
@testable import Courtly

/// Records how the app reads Postgres timestamps and the auth token response.
final class JSONCodingTests: XCTestCase {
    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int, millis: Int = 0) -> Date {
        var components = DateComponents()
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
        components.nanosecond = millis * 1_000_000
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func assertDate(_ raw: String, is expected: Date, file: StaticString = #filePath, line: UInt = #line) {
        guard let parsed = JSONCoding.parseDate(raw) else { return XCTFail("\(raw) did not parse", file: file, line: line) }
        XCTAssertEqual(parsed.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.0005, raw, file: file, line: line)
    }

    func testPostgresMicrosecondsAreTruncatedToMilliseconds() {
        assertDate("2026-10-16T18:30:00.123456+00:00", is: utc(2026, 10, 16, 18, 30, 0, millis: 123))
    }

    func testTrimmedFractionsArePadded() {
        assertDate("2026-10-16T18:30:00.5+00:00", is: utc(2026, 10, 16, 18, 30, 0, millis: 500))
        assertDate("2026-10-16T18:30:00.25Z", is: utc(2026, 10, 16, 18, 30, 0, millis: 250))
    }

    func testWholeSecondsAndOtherOffsetsParse() {
        assertDate("2026-10-16T18:30:00+00:00", is: utc(2026, 10, 16, 18, 30, 0))
        assertDate("2026-10-16T18:30:00Z", is: utc(2026, 10, 16, 18, 30, 0))
        assertDate("2026-10-16T14:30:00-04:00", is: utc(2026, 10, 16, 18, 30, 0))
    }

    func testTextThatIsNotAnInternetDateIsNil() {
        XCTAssertNil(JSONCoding.parseDate("2026-10-16 18:30:00"))
        XCTAssertNil(JSONCoding.parseDate("2026-10-16"))
        XCTAssertNil(JSONCoding.parseDate("not a date"))
        XCTAssertNil(JSONCoding.parseDate(""))
    }

    func testStringFromDateRoundTrips() {
        let date = utc(2026, 10, 16, 22, 30, 0, millis: 123)
        XCTAssertEqual(JSONCoding.string(from: date), "2026-10-16T22:30:00.123Z")
        assertDate(JSONCoding.string(from: date), is: date)
    }

    private struct Sample: Decodable, Equatable {
        let startsAt: Date
        let spotsOpen: Int
        let chatId: UUID?
    }

    func testDecoderReadsSnakeCaseKeysAndDates() throws {
        let json = Data(#"{"starts_at": "2026-10-16T18:30:00.123456+00:00", "spots_open": 2, "chat_id": null}"#.utf8)
        let sample = try JSONCoding.decoder.decode(Sample.self, from: json)
        XCTAssertEqual(sample.spotsOpen, 2)
        XCTAssertNil(sample.chatId)
        XCTAssertEqual(sample.startsAt.timeIntervalSince1970, utc(2026, 10, 16, 18, 30, 0, millis: 123).timeIntervalSince1970, accuracy: 0.0005)
    }

    func testDecoderRejectsAnUnreadableDate() {
        let json = Data(#"{"starts_at": "tomorrow", "spots_open": 2}"#.utf8)
        XCTAssertThrowsError(try JSONCoding.decoder.decode(Sample.self, from: json))
    }

    func testEncoderWritesSnakeCaseKeysAndMillisecondDates() throws {
        struct Out: Encodable { let startsAt: Date; let spotsOpen: Int }
        let data = try JSONCoding.encoder.encode(Out(startsAt: utc(2026, 10, 16, 18, 30, 0, millis: 5), spotsOpen: 1))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["starts_at"] as? String, "2026-10-16T18:30:00.005Z")
        XCTAssertEqual(object["spots_open"] as? Int, 1)
    }

    func testTokenResponseBecomesASession() throws {
        let userID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let json = Data(#"{"access_token": "access", "refresh_token": "refresh", "expires_in": 3600, "token_type": "bearer", "user": {"id": "\#(userID.uuidString)", "email": "player@example.com"}}"#.utf8)
        let session = try JSONCoding.decoder.decode(TokenResponse.self, from: json).session(provider: "apple")
        XCTAssertEqual(session.accessToken, "access")
        XCTAssertEqual(session.refreshToken, "refresh")
        XCTAssertEqual(session.userID, userID)
        XCTAssertEqual(session.email, "player@example.com")
        XCTAssertEqual(session.provider, "apple")
        XCTAssertEqual(session.expiresAt.timeIntervalSinceNow, 3600, accuracy: 5)
        XCTAssertFalse(session.needsRefresh)
    }

    func testASessionAboutToExpireNeedsARefresh() {
        var session = Session(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSinceNow: 30), userID: UUID(), email: nil, provider: nil)
        XCTAssertTrue(session.needsRefresh)
        session.expiresAt = Date(timeIntervalSinceNow: 61)
        XCTAssertFalse(session.needsRefresh)
    }
}

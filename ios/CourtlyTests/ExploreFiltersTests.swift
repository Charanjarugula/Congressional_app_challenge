import XCTest
@testable import Courtly

final class ExploreFiltersTests: XCTestCase {
    func testDistanceIsUnrestrictedByDefaultIncludingUnknownLocations() {
        let filters = ExploreFilters()
        XCTAssertEqual(filters.activeCount, 0)
        XCTAssertTrue(filters.distance.includes(150))
        XCTAssertTrue(filters.distance.includes(nil))
    }
    func testExplicitDistanceBoundaryAndReset() {
        var filters = ExploreFilters()
        filters.distance = .fifty
        XCTAssertTrue(filters.distance.includes(50))
        XCTAssertFalse(filters.distance.includes(50.1))
        XCTAssertFalse(filters.distance.includes(nil))
        XCTAssertEqual(filters.activeCount, 1)
        filters = ExploreFilters()
        XCTAssertTrue(filters.distance.includes(51))
    }
}

extension ExploreFiltersTests {
    private var now: Date { ISO8601DateFormatter().date(from: "2026-10-16T12:00:00Z")! }
    private func hit(miles: Double? = 1, hours: Double = 1, format: PlayFormat = .casual) -> Hit {
        let host = PlayerCard(id: UUID(), firstName: "Test", lastInitial: "P", photoPath: nil, level: .intermediate,
                              areaLabel: nil, hitsPlayed: 0, formats: [.casual], availabilityMask: nil, busyMaskWeek: nil)
        let court = Court(id: UUID(), name: "Test court", address: nil, city: nil, lat: 26.66, lng: -80.24,
                          surface: nil, lights: nil, timeZone: "America/New_York")
        return Hit(id: UUID(), host: host, court: court, startsAt: now.addingTimeInterval(hours * 3600),
                   durationMin: 60, format: format, spotsTotal: 2, spotsOpen: 2, visibility: .anyone,
                   status: .open, chatId: nil, players: [], miles: miles, pendingRequestCount: 0,
                   unreadMessages: 0, viewer: .init(isHost: false, isPlayer: false))
    }
    private func feed(friends: [Hit], others: [Hit]) -> PlayFeed {
        PlayFeed(needsReply: [], fromFriends: friends, nearYou: others, freeThisWeek: [], myUpcomingCount: 0, badge: 0)
    }

    func testUnionIncludesFriendsDeduplicatesAndScopes() {
        let friend = hit(), other = hit(miles: 75)
        let source = feed(friends: [friend], others: [friend, other])
        XCTAssertEqual(Set(ExploreInventory.hits(source).map(\.id)), [friend.id, other.id])
        XCTAssertEqual(ExploreInventory.hits(source, friendsOnly: true).map(\.id), [friend.id])
        XCTAssertEqual(ExploreInventory.hits(feed(friends: [friend], others: [])).count, 1)
    }

    func testClosestUsesDisplayedDistanceThenFriendThenStart() {
        let friend = hit(miles: 0.74, hours: 3), stranger = hit(miles: 0.71, hours: 1)
        let closer = hit(miles: 0.6, hours: 4), far = hit(miles: 75, hours: 2), unknown = hit(miles: nil)
        let result = ExploreFilters().apply(to: [unknown, far, stranger, friend, closer], friendIDs: [friend.id], now: now)
        XCTAssertEqual(result.map(\.id), [closer.id, friend.id, stranger.id, far.id, unknown.id])
    }

    func testSoonestIsExplicitAndDoesNotPrioritizeLaterFriend() {
        var filters = ExploreFilters(); filters.sort = .soonest
        let friend = hit(miles: 0.1, hours: 3), stranger = hit(miles: 75, hours: 1)
        XCTAssertEqual(filters.apply(to: [friend, stranger], friendIDs: [friend.id], now: now).map(\.id), [stranger.id, friend.id])
    }

    func testFiltersCombineAndKeepPendingRequestsVisible() {
        var filters = ExploreFilters(); filters.formats = [.doubles]; filters.levels = [.intermediate]; filters.distance = .fifty
        var pending = hit(miles: 10, format: .doubles)
        pending.viewer.request = .init(id: UUID(), status: .pending, seen: false)
        let wrongFormat = hit(), tooFar = hit(miles: 51, format: .doubles)
        XCTAssertEqual(filters.apply(to: [wrongFormat, tooFar, pending], now: now).map(\.id), [pending.id])
        filters.levels = [.beginner]
        XCTAssertTrue(filters.apply(to: [pending], now: now).isEmpty)
    }

    func testCancelledExpiredAndPastNeverAppear() {
        var cancelled = hit(); cancelled.status = .cancelled
        var expired = hit(); expired.status = .expired
        let past = hit(hours: -1), future = hit()
        XCTAssertEqual(ExploreFilters().apply(to: [cancelled, expired, past, future], now: now).map(\.id), [future.id])
    }

    func testCourtLocalAfternoonAndEveningBoundaries() {
        var filters = ExploreFilters(); filters.when = .today; filters.times = [.afternoon]
        // Now = 8 AM EDT. Noon included, 5 PM excluded from afternoon.
        let noon = hit(hours: 4), beforeFive = hit(hours: 8.99), five = hit(hours: 9), nextDay = hit(hours: 28)
        XCTAssertEqual(filters.apply(to: [noon, beforeFive, five, nextDay], now: now).map(\.id), [noon.id, beforeFive.id])
        filters.times = [.evening]
        XCTAssertEqual(filters.apply(to: [noon, five], now: now).map(\.id), [five.id])
    }

    func testExactTimeRangeAndTomorrow() {
        var filters = ExploreFilters(); filters.when = .tomorrow; filters.exactTimes = 720..<780
        let noon = hit(hours: 28), one = hit(hours: 29), today = hit(hours: 4)
        XCTAssertEqual(filters.apply(to: [today, noon, one], now: now).map(\.id), [noon.id])
    }

    func testTodayUsesCourtDateAcrossTimezones() {
        var filters = ExploreFilters(); filters.when = .today
        let lateNow = ISO8601DateFormatter().date(from: "2026-10-17T02:00:00Z")! // Oct 16, 10 PM EDT
        var sameCourtDay = hit(); sameCourtDay.startsAt = lateNow.addingTimeInterval(3600)
        var nextCourtDay = hit(); nextCourtDay.startsAt = lateNow.addingTimeInterval(3 * 3600)
        XCTAssertEqual(filters.apply(to: [sameCourtDay, nextCourtDay], now: lateNow).map(\.id), [sameCourtDay.id])
    }

    func testSearchAreaRecomputesDistanceWithoutChangingFeed() {
        let original = hit(miles: 200)
        let source = feed(friends: [], others: [original])
        let area = HomeArea(label: "Court area", latitude: original.court.lat, longitude: original.court.lng)
        XCTAssertEqual(ExploreInventory.hits(source, area: area)[0].miles!, 0, accuracy: 0.001)
        XCTAssertEqual(source.nearYou[0].miles, 200)
    }
}

extension ExploreFiltersTests {
    func testStartOnlyHitHasNoDurationAndOnlyConflictsAtSameStart() {
        var startOnly = hit()
        startOnly.startTimeOnly = true
        XCTAssertNil(startOnly.durationLabel)
        XCTAssertEqual(startOnly.formatLine, startOnly.format.title)
        XCTAssertTrue(startOnly.overlaps(hit()))
        XCTAssertFalse(startOnly.overlaps(hit(hours: 1.5)))
        XCTAssertFalse(hit(hours: 1.5).overlaps(startOnly))
        XCTAssertTrue(hit().overlaps(hit(hours: 1.5)))
        XCTAssertFalse(hit().overlaps(hit(hours: 2)))
    }
    func testStartOnlyFlagSurvivesCodingWhileLegacyHitsKeepDuration() throws {
        var original = hit()
        XCTAssertEqual(original.durationLabel, "60 min")
        original.startTimeOnly = true
        let encoded = try JSONCoding.encoder.encode(original)
        let decoded = try JSONCoding.decoder.decode(Hit.self, from: encoded)
        XCTAssertTrue(decoded.startTimeOnly == true)
        XCTAssertNil(decoded.durationLabel)
    }
}

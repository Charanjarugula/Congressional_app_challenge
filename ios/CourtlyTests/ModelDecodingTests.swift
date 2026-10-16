import XCTest
@testable import Courtly

/// Records how the app decodes the backend's JSON shapes and the labels the models derive from them.
final class ModelDecodingTests: XCTestCase {
    private static let hitJSON = """
    {
      "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "host": {"id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "first_name": "Hannah", "last_initial": "C", "photo_path": null,
               "level": "intermediate", "area_label": "Wellington, FL", "hits_played": 3, "formats": ["casual", "singles"]},
      "court": {"id": "cccccccc-cccc-4ccc-8ccc-cccccccccccc", "name": "Wellington Tennis Center", "address": null, "city": "Wellington",
                "lat": 26.6618, "lng": -80.2414, "surface": "hard", "lights": true, "time_zone": "America/New_York", "miles": 6.4, "played_count": 2},
      "starts_at": "2026-10-16T22:30:00+00:00",
      "duration_min": 90,
      "format": "casual",
      "spots_total": 2,
      "spots_open": 2,
      "visibility": "invite_only",
      "status": "open",
      "chat_id": null,
      "players": [{"id": "dddddddd-dddd-4ddd-8ddd-dddddddddddd", "first_name": "Luis", "last_initial": null, "photo_path": null,
                   "level": null, "area_label": null, "hits_played": 0, "formats": []}],
      "miles": 6.4,
      "pending_request_count": 0,
      "unread_messages": 0,
      "viewer": {"is_host": false, "is_player": false, "request": null, "invite": null},
      "state": "open_requests"
    }
    """

    private func decodeHit() throws -> Hit {
        try JSONCoding.decoder.decode(Hit.self, from: Data(Self.hitJSON.utf8))
    }

    func testHitDecodesEveryField() throws {
        let hit = try decodeHit()
        XCTAssertEqual(hit.host.displayName, "Hannah C.")
        XCTAssertEqual(hit.court.name, "Wellington Tennis Center")
        XCTAssertEqual(hit.durationMin, 90)
        XCTAssertEqual(hit.format, .casual)
        XCTAssertEqual(hit.visibility, .inviteOnly)
        XCTAssertEqual(hit.status, .open)
        XCTAssertNil(hit.chatId)
        XCTAssertEqual(hit.players.count, 1)
        XCTAssertEqual(hit.rowState, .openRequests)
        XCTAssertNil(hit.viewer.attendance)
        XCTAssertEqual(hit.relationship(with: hit.host.id), Relationship.none)
    }

    func testPlayerWithoutARoleIsAPlayer() throws {
        let player = try XCTUnwrap(decodeHit().players.first)
        XCTAssertEqual(player.role, "player")
        XCTAssertFalse(player.isHost)
        XCTAssertEqual(player.card.displayName, "Luis")
        XCTAssertEqual(player.card.initials, "L")
    }

    func testLabelsReadInTheCourtsZone() throws {
        let hit = try decodeHit()
        XCTAssertEqual(hit.zone.identifier, "America/New_York")
        XCTAssertEqual(hit.dateText, "Fri, Oct 16")
        XCTAssertEqual(hit.dayText, "Fri")
        XCTAssertEqual(HitFormatting.string("h:mm a", hit.startsAt, in: hit.zone), "6:30 PM")
        XCTAssertEqual(hit.formatLine, "Casual hitting · 90 min")
        XCTAssertEqual(hit.courtLine, "Wellington Tennis Center · 6 mi")
        XCTAssertEqual(hit.feedTitle, "Hannah C. · Casual")
        XCTAssertEqual(hit.spotsLabel, "2 spots")
        XCTAssertEqual(hit.endsAt, hit.startsAt.addingTimeInterval(90 * 60))
    }

    func testStatusKindForAnOpenHitThatAlreadyStarted() throws {
        // The sample starts on 16 Oct 2026; the status label mutes an open hit once that moment has passed.
        let hit = try decodeHit()
        if hit.startsAt > .now {
            XCTAssertEqual(hit.statusKind, .open("2 spots"))
        } else {
            XCTAssertEqual(hit.statusKind, .muted("Open"))
        }
    }

    func testMilesLabel() {
        XCTAssertEqual(HitFormatting.miles(0.4), "0.4 mi")
        XCTAssertEqual(HitFormatting.miles(1), "1 mi")
        XCTAssertEqual(HitFormatting.miles(6.4), "6 mi")
        XCTAssertEqual(HitFormatting.miles(6.5), "7 mi")
    }

    func testPlayerCardLabels() throws {
        let hit = try decodeHit()
        XCTAssertEqual(hit.host.initials, "HC")
        XCTAssertEqual(hit.host.levelAndArea, "Intermediate · Wellington")
        XCTAssertEqual(try XCTUnwrap(hit.players.first).card.levelAndArea, "")
    }

    func testCourtLabels() throws {
        let court = try decodeHit().court
        XCTAssertEqual(court.shortName, "Wellington")
        XCTAssertEqual(court.detailLine, "Hard · Lights")
        XCTAssertEqual(court.coordinate.latitude, 26.6618, accuracy: 0.00001)
    }

    func testCourtWithoutAZoneUsesTheDevice() throws {
        let json = Data(#"{"id": "cccccccc-cccc-4ccc-8ccc-cccccccccccc", "name": "Park", "address": null, "city": null, "lat": 0, "lng": 0, "surface": null, "lights": false}"#.utf8)
        let court = try JSONCoding.decoder.decode(Court.self, from: json)
        XCTAssertEqual(court.zone, TimeZone.current)
        XCTAssertEqual(court.shortName, "Park")
        XCTAssertEqual(court.detailLine, "No lights")
    }

    func testFriendRowFlattensTheCard() throws {
        let json = Data(#"{"id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "first_name": "Ana", "last_initial": "R", "photo_path": null, "level": "advanced", "area_label": "Boca Raton, FL", "hits_played": 12, "formats": ["singles"], "dm_chat_id": "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}"#.utf8)
        let friend = try JSONCoding.decoder.decode(Friend.self, from: json)
        XCTAssertEqual(friend.card.displayName, "Ana R.")
        XCTAssertEqual(friend.id, friend.card.id)
        XCTAssertEqual(friend.dmChatId?.uuidString, "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE")
    }

    func testSuggestedPlayerFillsInWhatOlderServersOmit() throws {
        let json = Data(#"{"id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "first_name": "Marcus", "last_initial": "T"}"#.utf8)
        let suggested = try JSONCoding.decoder.decode(SuggestedPlayer.self, from: json)
        XCTAssertEqual(suggested.hitsPlayed, 0)
        XCTAssertEqual(suggested.formats, [])
        XCTAssertEqual(suggested.mutualFriends, [])
        XCTAssertNil(suggested.reason)
        XCTAssertEqual(suggested.card.displayName, "Marcus T.")
    }

    func testMutualFriendsLabel() {
        XCTAssertNil([String]().mutualLabel)
        XCTAssertEqual(["Ana"].mutualLabel, "1 mutual friend")
        XCTAssertEqual(["Ana", "Luis"].mutualLabel, "2 mutual friends")
    }
}

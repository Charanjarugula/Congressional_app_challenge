import Foundation

/// Everything the Play tab shows, from one `get_play_feed` call.
struct PlayFeed: Codable {
    var needsReply: [NeedsReplyItem]
    var fromFriends: [Hit]
    var nearYou: [Hit]
    var freeThisWeek: [PlayerCard]
    var myUpcomingCount: Int
    var badge: Int

    var hasHits: Bool { !fromFriends.isEmpty || !nearYou.isEmpty }
}

/// A card at the top of Play: a request to answer, an invite to claim, or an accepted ask to open.
struct NeedsReplyItem: Codable, Identifiable {
    enum Kind: String, Codable {
        case joinRequest = "join_request"
        case invite
        case accepted
    }

    let kind: Kind
    let requestId: UUID?
    let inviteId: UUID?
    let player: PlayerCard?
    let host: PlayerCard?
    var hit: Hit
    let createdAt: Date?

    var id: String {
        "\(kind.rawValue)-\(requestId?.uuidString ?? inviteId?.uuidString ?? hit.id.uuidString)"
    }

    /// Whose face the card shows.
    var person: PlayerCard { player ?? host ?? hit.host }
}

/// The My Hits tab, from `get_my_hits`.
struct MyHits: Codable {
    var upcoming: [Hit]
    var past: [Hit]

    static let empty = MyHits(upcoming: [], past: [])
}

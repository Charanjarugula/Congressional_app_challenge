import Foundation

/// How the signed-in player relates to another one.
enum Relationship: String, Codable {
    case none, friend, requested, blocked
    case requestedMe = "requested_me"

    var isFriend: Bool { self == .friend }
}

enum ReportReason: String, CaseIterable, Identifiable {
    case noShow = "no_show"
    case rudeOrUnsafe = "rude_or_unsafe"
    case fakeProfile = "fake_profile"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .noShow: "Didn’t show up"
        case .rudeOrUnsafe: "Rude or unsafe behavior"
        case .fakeProfile: "Fake profile"
        case .other: "Something else"
        }
    }
}

/// A `search_players` row: the card, who you both know, and where you stand.
struct SearchedPlayer: Codable, Identifiable {
    let card: PlayerCard
    let mutualFriends: [String]
    let relationship: Relationship

    var id: UUID { card.id }

    private enum CodingKeys: String, CodingKey {
        case mutualFriends, relationship
    }

    init(from decoder: Decoder) throws {
        card = try PlayerCard(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mutualFriends = try container.decodeIfPresent([String].self, forKey: .mutualFriends) ?? []
        relationship = try container.decodeIfPresent(Relationship.self, forKey: .relationship) ?? Relationship.none
    }

    func encode(to encoder: Encoder) throws {
        try card.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mutualFriends, forKey: .mutualFriends)
        try container.encode(relationship, forKey: .relationship)
    }
}

/// The player profile screen (`get_player`).
struct PlayerProfile: Codable {
    var card: PlayerCard
    var mutualFriends: [String]
    var mutualCards: [PlayerCard]
    var relationship: Relationship
    var dmChatId: UUID?
    var hitsTogether: Int
    var friendCount: Int
    var openHits: [Hit]

    private enum CodingKeys: String, CodingKey {
        case mutualFriends, mutualCards, relationship, dmChatId, hitsTogether, friendCount, openHits
    }

    init(from decoder: Decoder) throws {
        card = try PlayerCard(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mutualFriends = try container.decodeIfPresent([String].self, forKey: .mutualFriends) ?? []
        mutualCards = try container.decodeIfPresent([PlayerCard].self, forKey: .mutualCards) ?? []
        relationship = try container.decodeIfPresent(Relationship.self, forKey: .relationship) ?? Relationship.none
        dmChatId = try container.decodeIfPresent(UUID.self, forKey: .dmChatId)
        hitsTogether = try container.decodeIfPresent(Int.self, forKey: .hitsTogether) ?? 0
        friendCount = try container.decodeIfPresent(Int.self, forKey: .friendCount) ?? 0
        openHits = try container.decodeIfPresent([Hit].self, forKey: .openHits) ?? []
    }

    func encode(to encoder: Encoder) throws {
        try card.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mutualFriends, forKey: .mutualFriends)
        try container.encode(mutualCards, forKey: .mutualCards)
        try container.encode(relationship, forKey: .relationship)
        try container.encodeIfPresent(dmChatId, forKey: .dmChatId)
        try container.encode(hitsTogether, forKey: .hitsTogether)
        try container.encode(friendCount, forKey: .friendCount)
        try container.encode(openHits, forKey: .openHits)
    }

    /// "Friends with Alex and Sam"
    var mutualLine: String? {
        guard !mutualFriends.isEmpty else { return nil }
        let names = mutualFriends.prefix(2)
        let rest = mutualFriends.count - names.count
        if rest > 0 { return "Friends with \(names.joined(separator: ", ")) and \(rest) more" }
        return "Friends with \(names.joined(separator: " and "))"
    }
}

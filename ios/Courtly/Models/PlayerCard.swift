import Foundation

/// What any player may see of another: first name, last initial, level, area, counts.
struct PlayerCard: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let firstName: String
    let lastInitial: String?
    let photoPath: String?
    let level: PlayerLevel?
    let areaLabel: String?
    let hitsPlayed: Int
    let formats: [PlayFormat]
    let availabilityMask: Int32?
    let busyMaskWeek: Int32?

    var displayName: String {
        guard let initial = lastInitial, !initial.isEmpty else { return firstName }
        return "\(firstName) \(initial)."
    }

    var initials: String {
        let first = firstName.first.map(String.init) ?? ""
        return (first + (lastInitial ?? "")).uppercased()
    }

    /// "Intermediate · Wellington"
    var levelAndArea: String {
        [level?.title, areaLabel?.components(separatedBy: ",").first].compactMap { $0 }.joined(separator: " · ")
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A `match_contacts` row: the hash that matched, and the player it belongs to.
struct ContactMatch: Codable {
    let hash: String
    let player: PlayerCard
    /// Where this person stands with you; missing from older servers, so optional.
    let relationship: Relationship?
}

/// A `get_friend_suggestions` row.
struct SuggestedPlayer: Codable, Identifiable {
    let id: UUID
    let firstName: String
    let lastInitial: String?
    let photoPath: String?
    let level: PlayerLevel?
    let areaLabel: String?
    let hitsPlayed: Int
    let formats: [PlayFormat]
    let reason: String?
    let source: String?
    var mutualFriends: [String] = []

    private enum CodingKeys: String, CodingKey {
        case id, firstName, lastInitial, photoPath, level, areaLabel, hitsPlayed, formats, reason, source, mutualFriends
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        firstName = try c.decode(String.self, forKey: .firstName)
        lastInitial = try c.decodeIfPresent(String.self, forKey: .lastInitial)
        photoPath = try c.decodeIfPresent(String.self, forKey: .photoPath)
        level = try c.decodeIfPresent(PlayerLevel.self, forKey: .level)
        areaLabel = try c.decodeIfPresent(String.self, forKey: .areaLabel)
        hitsPlayed = try c.decodeIfPresent(Int.self, forKey: .hitsPlayed) ?? 0
        formats = try c.decodeIfPresent([PlayFormat].self, forKey: .formats) ?? []
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        mutualFriends = try c.decodeIfPresent([String].self, forKey: .mutualFriends) ?? []
    }

    var card: PlayerCard {
        PlayerCard(id: id, firstName: firstName, lastInitial: lastInitial, photoPath: photoPath, level: level,
                   areaLabel: areaLabel, hitsPlayed: hitsPlayed, formats: formats, availabilityMask: nil, busyMaskWeek: nil)
    }
}

struct FriendshipResult: Codable {
    let relationship: String
    let dmChatId: UUID?
}

/// A `get_friend_requests` row: who asked (or whom you asked), who you both know, and when.
struct FriendRequest: Codable, Identifiable {
    let card: PlayerCard
    let mutualFriends: [String]
    let requestedAt: Date?

    var id: UUID { card.id }

    private enum CodingKeys: String, CodingKey {
        case mutualFriends, requestedAt
    }

    init(from decoder: Decoder) throws {
        card = try PlayerCard(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mutualFriends = try container.decodeIfPresent([String].self, forKey: .mutualFriends) ?? []
        requestedAt = try container.decodeIfPresent(Date.self, forKey: .requestedAt)
    }

    func encode(to encoder: Encoder) throws {
        try card.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mutualFriends, forKey: .mutualFriends)
        try container.encodeIfPresent(requestedAt, forKey: .requestedAt)
    }
}

/// Requests waiting on you, and the ones you sent that haven't been answered.
struct FriendRequests: Codable {
    var incoming: [FriendRequest]
    var outgoing: [FriendRequest]

    static let empty = FriendRequests(incoming: [], outgoing: [])
}

extension Array where Element == String {
    /// "3 mutual friends", "1 mutual friend", or nil.
    var mutualLabel: String? {
        isEmpty ? nil : (count == 1 ? "1 mutual friend" : "\(count) mutual friends")
    }
}

/// What is going on near the player: `get_area_pulse`.
struct AreaPulse: Codable, Equatable {
    let players: Int
    let openHits: Int
    let courts: Int
    let radiusMi: Int
    let areaLabel: String?

    /// "Wellington" from "Wellington, FL".
    var town: String? { areaLabel?.components(separatedBy: ",").first }
}

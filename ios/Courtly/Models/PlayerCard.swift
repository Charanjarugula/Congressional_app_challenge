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
    static func == (lhs: PlayerCard, rhs: PlayerCard) -> Bool { lhs.id == rhs.id }
}

/// A `match_contacts` row: the hash that matched, and the player it belongs to.
struct ContactMatch: Codable {
    let hash: String
    let player: PlayerCard
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

    var card: PlayerCard {
        PlayerCard(id: id, firstName: firstName, lastInitial: lastInitial, photoPath: photoPath, level: level,
                   areaLabel: areaLabel, hitsPlayed: hitsPlayed, formats: formats, availabilityMask: nil, busyMaskWeek: nil)
    }
}

struct FriendshipResult: Codable {
    let relationship: String
    let dmChatId: UUID?
}

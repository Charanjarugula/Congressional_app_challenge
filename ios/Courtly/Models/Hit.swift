import Foundation

enum HitStatus: String, Codable {
    case open, confirmed, cancelled, played, expired
}

enum HitVisibility: String, Codable, CaseIterable, Identifiable {
    case anyone, friends
    case inviteOnly = "invite_only"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anyone: "Anyone"
        case .friends: "Friends only"
        case .inviteOnly: "Invite only"
        }
    }
}

enum RequestStatus: String, Codable {
    case pending, accepted, declined, cancelled, expired
}

enum InviteStatus: String, Codable {
    case open, filled, expired, cancelled
}

/// The coloured label in a hit's corner.
enum HitStatusKind: Equatable {
    case confirmed
    case open(String)
    case muted(String)

    var title: String {
        switch self {
        case .confirmed: "Confirmed"
        case let .open(title), let .muted(title): title
        }
    }
}

/// A player on a hit: their card plus whether they host it. Decoded from `player_card || {role}`.
struct HitPlayer: Codable, Identifiable, Equatable {
    let card: PlayerCard
    let role: String

    var id: UUID { card.id }
    var isHost: Bool { role == "host" }

    private enum CodingKeys: String, CodingKey {
        case role
    }

    init(from decoder: Decoder) throws {
        card = try PlayerCard(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "player"
    }

    func encode(to encoder: Encoder) throws {
        try card.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
    }
}

/// One hit as every screen reads it (`hit_json`), plus the extras the feed and My Hits add.
struct Hit: Codable, Identifiable, Equatable {
    struct Viewer: Codable, Equatable {
        struct Request: Codable, Equatable {
            let id: UUID
            let status: RequestStatus
            let seen: Bool
        }

        struct Invite: Codable, Equatable {
            let id: UUID
            let status: InviteStatus
            let expiresAt: Date
        }

        /// A day-after answer the viewer already gave about someone.
        struct Answer: Codable, Equatable {
            let userId: UUID
            let showedUp: Bool
        }

        /// Where the viewer stands with someone in the hit.
        struct Standing: Codable, Equatable {
            let userId: UUID
            let relationship: Relationship
        }

        var isHost: Bool
        var isPlayer: Bool
        var request: Request?
        var invite: Invite?
        var attendance: [Answer]? = nil
        var relationships: [Standing]? = nil
    }

    /// Row state from `get_my_hits`.
    enum RowState: String {
        case openRequests = "open_requests"
        case openWaiting = "open_waiting"
        case confirmed, pending, invited
        case open, cancelled, played, expired
    }

    let id: UUID
    var host: PlayerCard
    var court: Court
    var startsAt: Date
    var durationMin: Int
    var format: PlayFormat
    var spotsTotal: Int
    var spotsOpen: Int
    var visibility: HitVisibility
    var status: HitStatus
    var chatId: UUID?
    var players: [HitPlayer]
    var miles: Double?
    var pendingRequestCount: Int
    var unreadMessages: Int
    var viewer: Viewer

    // Added by the feed and My Hits.
    var reason: String?
    var state: String?
    var requestId: UUID?
    var inviteId: UUID?
    var needsAttendance: Bool?

    var rowState: RowState? { state.flatMap(RowState.init(rawValue:)) }
    var endsAt: Date { startsAt.addingTimeInterval(TimeInterval(durationMin * 60)) }
    var isLive: Bool { (status == .open || status == .confirmed) && startsAt > .now }
    var isMember: Bool { viewer.isHost || viewer.isPlayer }
    var isFull: Bool { spotsOpen <= 0 }
    var hasPendingRequest: Bool { viewer.request?.status == .pending }
    /// The host already said no; asking again would only fail.
    var wasDeclined: Bool { viewer.request?.status == .declined }

    /// Where the viewer stands with this person, from the server; `.none` when unknown.
    func relationship(with id: UUID) -> Relationship {
        viewer.relationships?.first { $0.userId == id }?.relationship ?? Relationship.none
    }

    var openInvite: Viewer.Invite? {
        guard let invite = viewer.invite, invite.status == .open, invite.expiresAt > .now else { return nil }
        return invite
    }

    /// Host first, then players in the order they joined.
    var everyone: [PlayerCard] { [host] + players.map(\.card) }

    func others(than me: UUID?) -> [PlayerCard] {
        everyone.filter { $0.id != me }
    }

    /// The one other person a row names: the host for a joiner, the first player for the host.
    func counterpart(for me: UUID?) -> PlayerCard? {
        others(than: me).first
    }

    // MARK: Labels

    /// "Thu · 6:30 PM"
    var timeLabel: String {
        "\(HitFormatting.day.string(from: startsAt)) · \(HitFormatting.clock.string(from: startsAt))"
    }

    /// "Thu 6:30 PM"
    var shortTimeLabel: String {
        "\(HitFormatting.day.string(from: startsAt)) \(HitFormatting.clock.string(from: startsAt))"
    }

    /// "Casual hitting · 90 min"
    var formatLine: String { "\(format.title) · \(durationMin) min" }

    var milesLabel: String? { miles.map(HitFormatting.miles) }

    /// "Wellington Tennis Center · 6 mi"
    var courtLine: String { [court.name, milesLabel].compactMap { $0 }.joined(separator: " · ") }

    var spotsLabel: String { spotsOpen == 1 ? "1 spot" : "\(spotsOpen) spots" }

    /// "Hannah C. · Casual"
    var feedTitle: String { "\(host.displayName) · \(format.shortTitle)" }

    /// "Tue 6:00 PM · Wellington · 6 mi"
    var feedSubtitle: String {
        [shortTimeLabel, court.shortName, milesLabel].compactMap { $0 }.joined(separator: " · ")
    }

    var statusKind: HitStatusKind {
        switch status {
        case .open, .confirmed:
            if !isLive { return .muted(status == .confirmed ? "Confirmed" : "Open") }
            if !isMember && spotsOpen > 0 { return .open(spotsLabel) }
            return status == .confirmed ? .confirmed : .open("Open")
        case .played: return .muted("Played")
        case .cancelled: return .muted("Cancelled")
        case .expired: return .muted("Expired")
        }
    }
}

/// Shared date and distance formatting for hit screens. Times show in the device's zone.
enum HitFormatting {
    static let day = formatter("EEE")
    static let clock = formatter("h:mm a")
    static let dayAndDate = formatter("EEE, MMM d")
    static let month = formatter("MMMM")
    static let monthAndYear = formatter("MMMM yyyy")
    static let monthDay = formatter("MMM d")

    /// "6 mi", or "0.4 mi" under a mile.
    static func miles(_ miles: Double) -> String {
        miles < 1 ? String(format: "%.1f mi", miles) : "\(Int(miles.rounded())) mi"
    }

    /// "Today 9:42 AM", "Yesterday 6:30 PM", "Thu, Oct 9 6:30 PM"
    static func conversational(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today \(clock.string(from: date))" }
        if calendar.isDateInYesterday(date) { return "Yesterday \(clock.string(from: date))" }
        return "\(dayAndDate.string(from: date)) \(clock.string(from: date))"
    }

    /// Inbox timestamps: "9:12 AM" today, "Yesterday", "Mon" this week, then "Oct 6".
    static func inboxTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return clock.string(from: date) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 99
        return days < 7 ? day.string(from: date) : monthDay.string(from: date)
    }

    /// "11h left", "45m left", "Closed"
    static func timeLeft(until date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        if seconds <= 0 { return "Closed" }
        let hours = Int(seconds / 3600)
        if hours >= 48 { return "\(hours / 24)d left" }
        if hours >= 1 { return "\(hours)h left" }
        return "\(max(1, Int(seconds / 60)))m left"
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}

import Foundation

enum ChatType: String, Codable {
    case dm, group, hit
}

/// A chat as the inbox and thread screens read it (`chat_json`).
struct Chat: Codable, Identifiable {
    let id: UUID
    let type: ChatType
    let name: String?
    let hitId: UUID?
    let members: [PlayerCard]?
    let memberCount: Int
    let lastMessageAt: Date?
    let preview: String?
    let lastMessageType: MessageType?
    var unreadCount: Int
    let muted: Bool?
    let friendship: String?
    /// Set once the player has left: the thread is theirs to read up to then, not to write.
    let leftAt: Date?
    var hit: Hit?

    var title: String { name ?? "Chat" }

    func others(than me: UUID?) -> [PlayerCard] {
        (members ?? []).filter { $0.id != me }
    }

    /// The small line under the name: member count, level, or the hit's time.
    func subtitle(me: UUID?) -> String {
        switch type {
        case .group: memberCount == 1 ? "1 member" : "\(memberCount) members"
        case .dm: others(than: me).first?.levelAndArea ?? ""
        case .hit: hit.map { "\($0.format.shortTitle) · \($0.shortTimeLabel)" } ?? "Hit chat"
        }
    }
}

enum MessageType: String, Codable {
    case text, system
    case hitInvite = "hit_invite"
}

struct Message: Codable, Identifiable, Equatable {
    let id: UUID
    let chatId: UUID
    let sender: PlayerCard?
    let type: MessageType
    let body: String
    let clientId: UUID?
    let createdAt: Date
    var invite: HitInvite?
}

/// A host's offer of open spots to a chat (`invite_json`). First claim takes the spot.
struct HitInvite: Codable, Identifiable, Equatable {
    let id: UUID
    let hitId: UUID
    let chatId: UUID
    let messageId: UUID?
    let createdBy: PlayerCard
    let targetUserId: UUID?
    let spots: Int
    let claimed: Int
    let expiresAt: Date
    let status: InviteStatus
    var hit: Hit

    var isOpen: Bool { status == .open && expiresAt > .now }
}

struct ChatPage: Codable {
    let chat: Chat
    let messages: [Message]
}

/// A `get_friends` row: the friend's card and the DM the app opened when you became friends.
struct Friend: Codable, Identifiable {
    let card: PlayerCard
    let dmChatId: UUID?

    var id: UUID { card.id }

    private enum CodingKeys: String, CodingKey {
        case dmChatId
    }

    init(from decoder: Decoder) throws {
        card = try PlayerCard(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dmChatId = try container.decodeIfPresent(UUID.self, forKey: .dmChatId)
    }

    func encode(to encoder: Encoder) throws {
        try card.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(dmChatId, forKey: .dmChatId)
    }
}

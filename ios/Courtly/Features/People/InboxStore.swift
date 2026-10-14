import Foundation
import Observation

/// The People tab's chat list, with the last copy kept on disk.
@Observable
final class InboxStore {
    private(set) var chats: [Chat]?
    private(set) var isLoading = false
    private(set) var lastError: String?

    init() {
        chats = SnapshotCache.load([Chat].self, key: "inbox")
    }

    var unreadCount: Int {
        chats?.reduce(0) { $0 + $1.unreadCount } ?? 0
    }

    @MainActor
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await API.Chats.inbox()
            chats = fresh
            lastError = nil
            SnapshotCache.save(fresh, key: "inbox")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Zero a chat's unread count right away; the next load confirms it.
    @MainActor
    func markRead(_ chatID: UUID) {
        guard var list = chats, let index = list.firstIndex(where: { $0.id == chatID }), list[index].unreadCount > 0 else { return }
        list[index] = Chat(
            id: list[index].id, type: list[index].type, name: list[index].name, hitId: list[index].hitId,
            members: list[index].members, memberCount: list[index].memberCount, lastMessageAt: list[index].lastMessageAt,
            preview: list[index].preview, unreadCount: 0, muted: list[index].muted, friendship: list[index].friendship,
            hit: list[index].hit
        )
        chats = list
    }
}

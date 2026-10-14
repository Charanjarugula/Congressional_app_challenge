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

    // Only the newest load may write, so an answer that left before a read mark never puts a dot back.
    private var generation = 0

    @MainActor
    func load() async {
        generation += 1
        let mine = generation
        isLoading = true
        defer { if mine == generation { isLoading = false } }
        let owner = await SupabaseClient.shared.session?.userID
        do {
            let fresh = try await API.Chats.inbox()
            // Newest load, same player (see HitsStore): a sign-out mid-flight must not refill the cache.
            guard mine == generation, await SupabaseClient.shared.session?.userID == owner else { return }
            chats = fresh
            lastError = nil
            SnapshotCache.save(fresh, key: "inbox")
        } catch {
            guard mine == generation, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            lastError = error.localizedDescription
        }
    }

    /// Zero a chat's unread count right away; the next load confirms it.
    @MainActor
    func markRead(_ chatID: UUID) {
        guard var list = chats, let index = list.firstIndex(where: { $0.id == chatID }), list[index].unreadCount > 0 else { return }
        list[index].unreadCount = 0
        chats = list
    }
}

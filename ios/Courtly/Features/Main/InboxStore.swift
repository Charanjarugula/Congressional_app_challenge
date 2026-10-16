import Foundation
import Observation

/// The People tab's chat list, with the last copy kept on disk.
@Observable
final class InboxStore {
    private(set) var chats: [Chat]?
    /// Friend requests waiting on the player and the ones they sent. Loaded with the chats.
    private(set) var requests: FriendRequests?
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var requestsError: String?

    /// Paints from the signed-in player's own snapshot; nothing of another account's is ever read.
    init(account: UUID?) {
        guard let account else { return }
        chats = SnapshotCache.load([Chat].self, key: "inbox", account: account)
        requests = SnapshotCache.load(FriendRequests.self, key: "friend_requests", account: account)
    }

    #if DEBUG && targetEnvironment(simulator)
    init(previewRequests: FriendRequests, previewChats: [Chat] = []) {
        chats = previewChats
        requests = previewRequests
    }
    #endif

    var requestCount: Int { requests?.incoming.count ?? 0 }

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
            async let requestsCall = API.People.friendRequests()
            let fresh = try await API.Chats.inbox()
            let freshRequests: FriendRequests?
            var requestFailure: String?
            do { freshRequests = try await requestsCall }
            catch { freshRequests = nil; requestFailure = error.localizedDescription }
            // Same player (a sign-out mid-flight must not refill the list), then, with no await in
            // between, still the newest load; the file goes under the account that fetched it.
            let samePlayer = await SupabaseClient.shared.session?.userID == owner
            guard samePlayer, mine == generation, let owner else { return }
            chats = fresh
            requestsError = requestFailure
            lastError = nil
            SnapshotCache.save(fresh, key: "inbox", account: owner)
            if let freshRequests {
                requests = freshRequests
                SnapshotCache.save(freshRequests, key: "friend_requests", account: owner)
            }
        } catch {
            guard mine == generation, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            lastError = error.localizedDescription
        }
    }

    /// Drop a request from the list right away; the next load confirms it.
    @MainActor
    func removeRequest(from userID: UUID) {
        guard var current = requests else { return }
        current.incoming.removeAll { $0.id == userID }
        current.outgoing.removeAll { $0.id == userID }
        requests = current
    }

    /// Zero a chat's unread count right away; the next load confirms it.
    @MainActor
    func markRead(_ chatID: UUID) {
        guard var list = chats, let index = list.firstIndex(where: { $0.id == chatID }), list[index].unreadCount > 0 else { return }
        list[index].unreadCount = 0
        chats = list
    }
}

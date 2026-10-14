import Foundation
import Observation

/// Everything the Play and My Hits tabs show. Actions update the lists right away and then
/// refresh from the backend, so every screen sees the same hit.
@Observable
final class HitsStore {
    private(set) var feed: PlayFeed?
    private(set) var myHits: MyHits?
    private(set) var isLoadingFeed = false
    private(set) var isLoadingMyHits = false
    private(set) var lastError: String?

    /// Paints from the signed-in player's own snapshots; nothing of another account's is ever read.
    init(account: UUID?) {
        guard let account else { return }
        feed = SnapshotCache.load(PlayFeed.self, key: "play_feed", account: account)
        myHits = SnapshotCache.load(MyHits.self, key: "my_hits", account: account)
    }

    // MARK: - Loading

    @MainActor
    func loadFeed() async {
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        let owner = await SupabaseClient.shared.session?.userID
        do {
            let fresh = try await API.Hits.feed()
            // Still the same player: after a sign-out or a switch the answer belongs to someone else and
            // must not reach the lists. The file goes under the account that fetched it, so even a write
            // that slipped through could not be read by the next player.
            let samePlayer = await SupabaseClient.shared.session?.userID == owner
            guard samePlayer, let owner else { return }
            feed = fresh
            lastError = nil
            SnapshotCache.save(fresh, key: "play_feed", account: owner)
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    func loadMyHits() async {
        isLoadingMyHits = true
        defer { isLoadingMyHits = false }
        let owner = await SupabaseClient.shared.session?.userID
        do {
            let fresh = try await API.Hits.mine()
            let samePlayer = await SupabaseClient.shared.session?.userID == owner
            guard samePlayer, let owner else { return }
            myHits = fresh
            SnapshotCache.save(fresh, key: "my_hits", account: owner)
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    func refreshAll() async {
        async let feedLoad: () = loadFeed()
        async let mineLoad: () = loadMyHits()
        _ = await (feedLoad, mineLoad)
    }

    // MARK: - Lookups

    func cachedHit(_ id: UUID) -> Hit? {
        if let hit = myHits?.upcoming.first(where: { $0.id == id }) ?? myHits?.past.first(where: { $0.id == id }) {
            return hit
        }
        if let hit = feed?.fromFriends.first(where: { $0.id == id }) ?? feed?.nearYou.first(where: { $0.id == id }) {
            return hit
        }
        return feed?.needsReply.first(where: { $0.hit.id == id })?.hit
    }

    func needsReplyItem(requestID: UUID) -> NeedsReplyItem? {
        feed?.needsReply.first { $0.requestId == requestID }
    }

    var needsReplyCount: Int { feed?.needsReply.count ?? 0 }

    // MARK: - Actions

    @MainActor
    func create(courtID: UUID, startsAt: Date, durationMin: Int, format: PlayFormat, spots: Int, visibility: HitVisibility,
                inviteChatID: UUID? = nil, inviteExpiresAt: Date? = nil) async throws -> Hit {
        var hit = try await API.Hits.create(courtID: courtID, startsAt: startsAt, durationMin: durationMin, format: format, spots: spots,
                                            visibility: visibility, inviteChatID: inviteChatID, inviteExpiresAt: inviteExpiresAt)
        hit.state = Hit.RowState.openWaiting.rawValue
        var mine = myHits ?? .empty
        mine.upcoming.append(hit)
        mine.upcoming.sort { $0.startsAt < $1.startsAt }
        myHits = mine
        feed?.myUpcomingCount += 1
        refreshSoon()
        return hit
    }

    @MainActor
    func requestToJoin(_ hitID: UUID) async throws -> Hit {
        let hit = try await API.Hits.requestToJoin(hitID)
        feed?.fromFriends.removeAll { $0.id == hitID }
        feed?.nearYou.removeAll { $0.id == hitID }
        replace(hit)
        refreshSoon()
        return hit
    }

    @MainActor
    func cancelRequest(_ requestID: UUID, hitID: UUID) async throws {
        try await API.Hits.cancelRequest(requestID)
        myHits?.upcoming.removeAll { $0.id == hitID && $0.rowState == .pending }
        refreshSoon()
    }

    @MainActor
    func respond(requestID: UUID, accept: Bool) async throws -> Hit {
        let hit = try await API.Hits.respond(requestID: requestID, accept: accept)
        feed?.needsReply.removeAll { $0.requestId == requestID }
        replace(hit)
        refreshSoon()
        return hit
    }

    /// The "accepted" banner was opened: drop it and tell the backend so it stays gone.
    @MainActor
    func dismissAccepted(_ item: NeedsReplyItem) {
        feed?.needsReply.removeAll { $0.id == item.id }
        if let requestID = item.requestId {
            Task { try? await API.Hits.markRequestSeen(requestID) }
        }
    }

    @MainActor
    func claimInvite(_ inviteID: UUID) async throws -> Hit {
        let hit = try await API.Hits.claimInvite(inviteID)
        feed?.needsReply.removeAll { $0.inviteId == inviteID }
        replace(hit)
        refreshSoon()
        return hit
    }

    @MainActor
    func declineInvite(_ inviteID: UUID) async throws {
        try await API.Hits.declineInvite(inviteID)
        feed?.needsReply.removeAll { $0.inviteId == inviteID }
        myHits?.upcoming.removeAll { $0.inviteId == inviteID }
        refreshSoon()
    }

    @MainActor
    func leave(_ hitID: UUID) async throws -> Hit {
        let hit = try await API.Hits.leave(hitID)
        myHits?.upcoming.removeAll { $0.id == hitID }
        feed?.myUpcomingCount = max(0, (feed?.myUpcomingCount ?? 1) - 1)
        refreshSoon()
        return hit
    }

    @MainActor
    func cancel(_ hitID: UUID) async throws -> Hit {
        let hit = try await API.Hits.cancel(hitID)
        myHits?.upcoming.removeAll { $0.id == hitID }
        feed?.myUpcomingCount = max(0, (feed?.myUpcomingCount ?? 1) - 1)
        refreshSoon()
        return hit
    }

    @MainActor
    func submitAttendance(hitID: UUID, about playerID: UUID, showedUp: Bool, addFriend: Bool) async throws {
        try await API.Hits.submitAttendance(hitID: hitID, about: playerID, showedUp: showedUp, addFriend: addFriend)
        refreshSoon()
    }

    // MARK: - Private

    /// Swaps a fresh copy of a hit into every list that holds it, keeping each list's own extras.
    @MainActor
    private func replace(_ hit: Hit) {
        func swap(in list: inout [Hit]) {
            guard let index = list.firstIndex(where: { $0.id == hit.id }) else { return }
            var updated = hit
            updated.state = list[index].state
            updated.reason = list[index].reason
            updated.requestId = list[index].requestId
            updated.inviteId = list[index].inviteId
            updated.needsAttendance = list[index].needsAttendance
            list[index] = updated
        }
        if var current = feed {
            swap(in: &current.fromFriends)
            swap(in: &current.nearYou)
            for index in current.needsReply.indices where current.needsReply[index].hit.id == hit.id {
                current.needsReply[index].hit = hit
            }
            feed = current
        }
        if var current = myHits {
            swap(in: &current.upcoming)
            swap(in: &current.past)
            myHits = current
        }
    }

    private func refreshSoon() {
        Task { @MainActor in await refreshAll() }
    }
}

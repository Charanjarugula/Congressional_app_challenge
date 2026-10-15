import Foundation
import Observation
import UserNotifications

/// Everything the Play and My Hits tabs show. Actions update the lists right away and then
/// refresh from the backend, so every screen sees the same hit.
@Observable
final class HitsStore {
    private(set) var feed: PlayFeed?
    private(set) var myHits: MyHits?
    private(set) var isLoadingFeed = false
    private(set) var isLoadingMyHits = false
    /// Why the last feed load failed, if it did; nil once one succeeds.
    private(set) var feedError: String?
    /// Why the last My Hits load failed, if it did.
    private(set) var myHitsError: String?
    /// The feed's error, which the Play tab shows.
    var lastError: String? { feedError }
    /// Bumped after every successful load so open screens can re-fetch their own copy.
    private(set) var lastRefreshedAt: Date?

    // Loads that overlap: only the newest one may write, so an answer that left before an action
    // never puts the list back the way it was.
    private var feedGeneration = 0
    private var myHitsGeneration = 0
    private var refreshTask: Task<Void, Never>?
    private var refreshQueued = false

    /// Paints from the signed-in player's own snapshots; nothing of another account's is ever read.
    init(account: UUID?) {
        guard let account else { return }
        feed = SnapshotCache.load(PlayFeed.self, key: "play_feed", account: account)
        myHits = SnapshotCache.load(MyHits.self, key: "my_hits", account: account)
    }

    // MARK: - Loading

    @MainActor
    /// Hits the player asked to join on this screen. A background reload keeps them in place, marked
    /// Requested, so the ask can be taken back; a pull to refresh lets them go.
    private var held: [Hit] = []

    @MainActor
    func loadFeed(userInitiated: Bool = false) async {
        if userInitiated { held = [] }
        feedGeneration += 1
        let generation = feedGeneration
        isLoadingFeed = true
        defer { if generation == feedGeneration { isLoadingFeed = false } }
        let owner = await SupabaseClient.shared.session?.userID
        do {
            let fresh = try await API.Hits.feed()
            // Still the same player (after a sign-out or a switch the answer belongs to someone else and
            // must not reach the lists), and, checked last with no await in between, still the newest
            // load. The file goes under the account that fetched it, so even a write that slipped
            // through could not be read by the next player.
            let samePlayer = await SupabaseClient.shared.session?.userID == owner
            guard samePlayer, generation == feedGeneration, let owner else { return }
            var merged = fresh
            for hit in held where !merged.fromFriends.contains(where: { $0.id == hit.id }) && !merged.nearYou.contains(where: { $0.id == hit.id }) {
                if let index = (feed?.fromFriends ?? []).firstIndex(where: { $0.id == hit.id }) {
                    merged.fromFriends.insert(hit, at: min(index, merged.fromFriends.count))
                } else {
                    let index = (feed?.nearYou ?? []).firstIndex(where: { $0.id == hit.id }) ?? merged.nearYou.count
                    merged.nearYou.insert(hit, at: min(index, merged.nearYou.count))
                }
            }
            feed = merged
            feedError = nil
            SnapshotCache.save(fresh, key: "play_feed", account: owner)
            try? await UNUserNotificationCenter.current().setBadgeCount(fresh.badge)
        } catch {
            guard generation == feedGeneration, !Self.isCancellation(error) else { return }
            feedError = error.localizedDescription
        }
    }

    @MainActor
    func loadMyHits() async {
        myHitsGeneration += 1
        let generation = myHitsGeneration
        isLoadingMyHits = true
        defer { if generation == myHitsGeneration { isLoadingMyHits = false } }
        let owner = await SupabaseClient.shared.session?.userID
        do {
            let fresh = try await API.Hits.mine()
            let samePlayer = await SupabaseClient.shared.session?.userID == owner
            guard samePlayer, generation == myHitsGeneration, let owner else { return }
            myHits = fresh
            myHitsError = nil
            SnapshotCache.save(fresh, key: "my_hits", account: owner)
        } catch {
            guard generation == myHitsGeneration, !Self.isCancellation(error) else { return }
            myHitsError = error.localizedDescription
        }
    }

    /// Both lists. The loads run in their own task, so a caller that goes away (a cancelled
    /// debounce, a screen popped) never cuts them short. A refresh asked for while one runs makes
    /// it run once more afterwards, so a change that landed in between is not missed, and every
    /// caller waits for that final round.
    @MainActor
    func refreshAll() async {
        if let refreshTask {
            refreshQueued = true
            await refreshTask.value
            return
        }
        let task = Task { @MainActor in
            repeat {
                refreshQueued = false
                async let feedLoad: () = loadFeed()
                async let mineLoad: () = loadMyHits()
                _ = await (feedLoad, mineLoad)
            } while refreshQueued
            lastRefreshedAt = .now
            refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    /// A load that was cut short by its caller going away is not a failure worth showing.
    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
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
    func update(_ hitID: UUID, courtID: UUID, startsAt: Date, durationMin: Int, format: PlayFormat, spots: Int,
                visibility: HitVisibility) async throws -> Hit {
        let hit = try await API.Hits.update(hitID, courtID: courtID, startsAt: startsAt, durationMin: durationMin,
                                            format: format, spots: spots, visibility: visibility)
        replace(hit)
        myHits?.upcoming.sort { $0.startsAt < $1.startsAt }
        refreshSoon()
        return hit
    }

    @MainActor
    func requestToJoin(_ hitID: UUID) async throws -> Hit {
        let hit = try await API.Hits.requestToJoin(hitID)
        replace(hit)
        if let kept = feed?.fromFriends.first(where: { $0.id == hitID }) ?? feed?.nearYou.first(where: { $0.id == hitID }) {
            held.removeAll { $0.id == hitID }
            held.append(kept)
        }
        refreshSoon()
        return hit
    }

    @MainActor
    func cancelRequest(_ requestID: UUID, hitID: UUID) async throws {
        try await API.Hits.cancelRequest(requestID)
        held.removeAll { $0.id == hitID }
        myHits?.upcoming.removeAll { $0.id == hitID && $0.rowState == .pending }
        if var current = feed {
            for index in current.fromFriends.indices where current.fromFriends[index].id == hitID { current.fromFriends[index].viewer.request = nil }
            for index in current.nearYou.indices where current.nearYou[index].id == hitID { current.nearYou[index].viewer.request = nil }
            feed = current
        }
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
        // Read before writing: reading `feed` inside its own modify access trips the exclusivity check.
        if var current = feed {
            current.myUpcomingCount = max(0, current.myUpcomingCount - 1)
            feed = current
        }
        refreshSoon()
        return hit
    }

    @MainActor
    func cancel(_ hitID: UUID) async throws -> Hit {
        let hit = try await API.Hits.cancel(hitID)
        myHits?.upcoming.removeAll { $0.id == hitID }
        // Read before writing: reading `feed` inside its own modify access trips the exclusivity check.
        if var current = feed {
            current.myUpcomingCount = max(0, current.myUpcomingCount - 1)
            feed = current
        }
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

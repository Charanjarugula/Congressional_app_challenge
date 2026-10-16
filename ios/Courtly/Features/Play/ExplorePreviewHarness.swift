#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Exercises the production Explore view. Only the data and navigation destinations are fixtures.
struct ExplorePreviewHarness: View {
    @State private var selected = MainTab.play
    @State private var paths: [AppRoute] = []
    @State private var planning = false
    @State private var session = AppSession(previewProfile: RemainingFlowsHarness.profile)
    @State private var hits = HitsStore(previewFeed: Self.feed)

    var body: some View {
        NavigationStack(path: $paths) {
            PlayView(onPlan: { planning = true })
                .contentMargins(.bottom, 76, for: .scrollContent)
                .navigationDestination(for: AppRoute.self) { route in
                    if case .hit(let id) = route,
                       let hit = ExploreInventory.hits(Self.feed).first(where: { $0.id == id }) {
                        HitDetailView(preview: hit)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if paths.isEmpty {
                        PlusButton(label: "Plan a hit") { planning = true }
                            .padding(.trailing, 20).padding(.bottom, 16)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if paths.isEmpty { GlassTabBar(selected: $selected, dots: []) }
                }
                .sheet(isPresented: $planning) { PlanHitView { _ in planning = false }.preferredColorScheme(.light) }
        }
        .environment(session).environment(hits)
        .environment(\.navigate, NavigateAction(push: { paths.append($0) }, pop: { if !paths.isEmpty { paths.removeLast() } }))
        .preferredColorScheme(paths.isEmpty ? .dark : .light)
        .environment(\.colorScheme, .light)
    }

    static let friendID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static let strangerID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    static let farID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
    static var feed: PlayFeed {
        let base = Calendar.current.startOfDay(for: Date.now).addingTimeInterval(86400)
        func make(_ id: UUID, miles: Double, hour: Double, format: PlayFormat) -> Hit {
            let source = exampleHit
            return Hit(id: id, host: source.host, court: source.court, startsAt: base.addingTimeInterval(hour * 3600),
                       durationMin: 90, format: format, spotsTotal: 2, spotsOpen: 2, visibility: .anyone,
                       status: .open, chatId: nil, players: [], miles: miles, pendingRequestCount: 0,
                       unreadMessages: 0, viewer: .init(isHost: false, isPlayer: false))
        }
        let friend = make(friendID, miles: 0.74, hour: 17.5, format: .casual)
        let stranger = make(strangerID, miles: 0.71, hour: 12, format: .singles)
        let far = make(farID, miles: 52.4, hour: 18, format: .doubles)
        var joined = friend
        joined.viewer.isPlayer = true
        let stale = NeedsReplyItem(kind: .invite, requestId: nil, inviteId: UUID(), player: nil, host: friend.host, hit: joined, createdAt: .now)
        return PlayFeed(needsReply: [stale], fromFriends: [friend], nearYou: [stranger, friend, far], freeThisWeek: [], myUpcomingCount: 0, badge: 0)
    }

    static var exampleHit: Hit {
        let host = PlayerCard(id: UUID(), firstName: "Jordan", lastInitial: "R", photoPath: nil,
                              level: .intermediate, areaLabel: "Wellington, FL", hitsPlayed: 4,
                              formats: [.casual], availabilityMask: nil, busyMaskWeek: nil)
        let court = Court(id: UUID(), name: "Wellington Tennis Center", address: "3100 Lyons Road",
                          city: "Wellington", lat: 26.66, lng: -80.24, surface: "hard", lights: true,
                          timeZone: "America/New_York", miles: nil, playedCount: nil)
        return Hit(id: UUID(), host: host, court: court, startsAt: Date.now.addingTimeInterval(86400),
                   durationMin: 90, format: .casual, spotsTotal: 1, spotsOpen: 1, visibility: .anyone,
                   status: .open, chatId: nil, players: [], miles: nil, pendingRequestCount: 0,
                   unreadMessages: 0, viewer: .init(isHost: false, isPlayer: false))
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Isolated visual and interaction checks. No fixtures or entry point are compiled into TestFlight.
struct ExplorePreviewHarness: View {
    @State private var expanded = false
    @State private var filters = ExploreFilters()
    @State private var showsFilters = false
    @State private var selected = MainTab.play
    @State private var segment = 0
    @State private var hits = HitsStore(account: nil)
    private let hit = Self.exampleHit

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SegmentedControl(options: ["Friends", "Discover"], selectedIndex: $segment, courtside: true)
                    Button("Filters") { showsFilters = true }
                        .accessibilityIdentifier("open-filters")
                    HitFeedRow(hit: hit, isExpanded: expanded) { expanded.toggle() }
                }
                .padding(24)
            }
            .navigationTitle(selected.title)
            .background(CourtlyColor.surface)
            .safeAreaInset(edge: .bottom) { GlassTabBar(selected: $selected, dots: [.people]) }
            .sheet(isPresented: $showsFilters) { ExploreFiltersSheet(filters: $filters, radius: .ten) }
        }
        .environment(hits)
        .preferredColorScheme(.light)
    }

    private static var exampleHit: Hit {
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

import SwiftUI

/// The four tabs behind a floating glass tab bar. Each tab keeps its own navigation stack,
/// and the bar hides while a tab has a screen pushed.
struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var hits: HitsStore
    @State private var inbox: InboxStore
    @State private var selected: MainTab = .play
    @State private var paths: [MainTab: [AppRoute]] = [:]
    @State private var isPlanning = false

    /// The stores read and write only the signed-in player's own snapshots.
    init(account: UUID?) {
        _hits = State(initialValue: HitsStore(account: account))
        _inbox = State(initialValue: InboxStore(account: account))
    }

    private var isAtRoot: Bool { (paths[selected] ?? []).isEmpty }

    var body: some View {
        ZStack {
            ForEach(MainTab.allCases) { tab in
                stack(for: tab)
                    .opacity(selected == tab ? 1 : 0)
                    .allowsHitTesting(selected == tab)
                    .accessibilityHidden(selected != tab)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isAtRoot {
                GlassTabBar(selected: $selected, dots: dots)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isAtRoot && selected == .play && showsPlanPill {
                PlanHitPill { isPlanning = true }
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $isPlanning) {
            PlanHitView { hit in
                selected = .myHits
                paths[.myHits] = [.hit(hit.id)]
            }
        }
        .tint(CourtlyColor.blue)
        .preferredColorScheme(.light)
        .environment(hits)
        .environment(inbox)
        .task {
            Task { await inbox.load() }   // the People dot is right from the start, not from the first visit
            await hits.refreshAll()
            await NotificationPermission.registerIfAuthorized()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await hits.refreshAll() }
                Task { await inbox.load() }
                Task { await API.Devices.retryPending() }   // a push token the server didn't take yet
            }
        }
    }

    /// The empty-state card on Play has its own button, so the pill steps aside.
    private var showsPlanPill: Bool {
        (hits.feed?.myUpcomingCount ?? 1) > 0
    }

    private var dots: Set<MainTab> {
        var tabs = Set<MainTab>()
        if hits.needsReplyCount > 0 { tabs.insert(.play) }
        if inbox.unreadCount > 0 { tabs.insert(.people) }
        return tabs
    }

    private func stack(for tab: MainTab) -> some View {
        NavigationStack(path: path(for: tab)) {
            root(for: tab)
                .toolbar(.hidden, for: .tabBar)
                .navigationDestination(for: AppRoute.self) { route in
                    destination(route)
                }
        }
        .environment(\.navigate, NavigateAction(
            push: { route in paths[tab, default: []].append(route) },
            replaceTop: { route in
                var current = paths[tab] ?? []
                if !current.isEmpty { current.removeLast() }
                current.append(route)
                paths[tab] = current
            },
            pop: {
                if !(paths[tab] ?? []).isEmpty { paths[tab]?.removeLast() }
            }
        ))
    }

    private func path(for tab: MainTab) -> Binding<[AppRoute]> {
        Binding(get: { paths[tab] ?? [] }, set: { paths[tab] = $0 })
    }

    @ViewBuilder
    private func root(for tab: MainTab) -> some View {
        switch tab {
        case .play: PlayView(onPlan: { isPlanning = true })
        case .myHits: MyHitsView(onPlan: { isPlanning = true })
        case .people: PeopleView(isActive: selected == .people)
        case .you: YouView()
        }
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case let .hit(id): HitDetailView(hitID: id)
        case let .request(id): JoinRequestView(requestID: id)
        case let .chat(id): ChatThreadView(chatID: id)
        case let .player(id): PlayerProfileView(playerID: id)
        case .addFriends: AddFriendsView()
        case .newGroup: NewGroupView()
        case .account: AccountView()
        case .blockedPlayers: BlockedPlayersView()
        }
    }
}

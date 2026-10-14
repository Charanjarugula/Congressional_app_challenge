import SwiftUI

/// The four tabs behind a floating glass tab bar. Each tab keeps its own navigation stack,
/// and the bar hides while a tab has a screen pushed.
struct MainTabView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var hits = HitsStore()
    @State private var inbox = InboxStore()
    @State private var deepLinks = DeepLinkCenter.shared
    @State private var selected: MainTab = .play
    @State private var paths: [MainTab: [AppRoute]] = [:]
    @State private var isPlanning = false
    @State private var coachStep: Int?
    @State private var liveUpdates: [RealtimeHub.Subscription] = []
    @State private var refreshDebounce: Task<Void, Never>?
    @State private var inboxDebounce: Task<Void, Never>?

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
        // Placed before the inset so the pill floats above the tab bar instead of over it.
        .overlay(alignment: .bottomTrailing) {
            if isAtRoot && selected == .play && (showsPlanPill || coachStep == 3) {
                PlanHitPill { isPlanning = true }
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.35), lineWidth: 4)
                            .opacity(coachStep == 3 ? 1 : 0)
                    )
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isAtRoot {
                GlassTabBar(selected: $selected, dots: dots)
            }
        }
        .overlay {
            if let coachStep {
                CoachMarksOverlay(step: coachStep, onNext: advanceCoachMarks)
                    .zIndex(1)
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
            if let link = deepLinks.pending {
                await open(link)   // loads what the screen needs; the lists refresh behind it
            } else {
                await hits.refreshAll()
                startCoachMarksIfNeeded()
            }
            await NotificationPermission.registerIfAuthorized()
            startLiveUpdates()
        }
        .onDisappear { stopLiveUpdates() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await hits.refreshAll() }
                Task { await inbox.load() }
                startLiveUpdates()
            case .background:
                stopLiveUpdates()
            default:
                break
            }
        }
        .onChange(of: deepLinks.pending) { _, link in
            if let link { Task { await open(link) } }
        }
        .onChange(of: deepLinks.lastPush) { _, arrival in
            // Refresh only what the push is about; Realtime covers the rest.
            guard let kind = arrival?.kind else { scheduleHitsRefresh(); scheduleInboxRefresh(); return }
            if kind == "message" || kind == "hit_invite" { scheduleInboxRefresh() }
            if kind != "message" { scheduleHitsRefresh() }
        }
    }

    // MARK: - Live updates

    /// Hits, requests and messages change on other phones. Refresh when they do instead of waiting
    /// for a poll; row-level security means each player only hears about rows they can see.
    private func startLiveUpdates() {
        guard liveUpdates.isEmpty else { return }   // launch fires both the task and the active phase
        let hub = RealtimeHub.shared
        liveUpdates = [
            hub.subscribe(table: "hits", events: "*") { scheduleHitsRefresh() },
            hub.subscribe(table: "join_requests", events: "*") { scheduleHitsRefresh() },
            hub.subscribe(table: "messages") { scheduleInboxRefresh() },
        ]
    }

    private func stopLiveUpdates() {
        liveUpdates.forEach { RealtimeHub.shared.unsubscribe($0) }
        liveUpdates = []
    }

    /// Several rows often change in one action (a request, the hit, the chat); refresh once.
    private func scheduleHitsRefresh() {
        refreshDebounce?.cancel()
        refreshDebounce = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await hits.refreshAll()   // coalesces with one already running
        }
    }

    private func scheduleInboxRefresh() {
        inboxDebounce?.cancel()
        inboxDebounce = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await inbox.load()
        }
    }

    // MARK: - Deep links

    /// Lands on the screen a notification points at, with the data behind it loaded first.
    @MainActor
    private func open(_ link: DeepLink) async {
        deepLinks.pending = nil
        isPlanning = false
        coachStep = nil
        switch link {
        case .play:
            selected = .play
            paths[.play] = []
            await hits.refreshAll()
        case let .hit(id), let .check(id, _):
            selected = .myHits
            paths[.myHits] = [.hit(id)]
            Task { await hits.refreshAll() }
        case let .request(id):
            if hits.needsReplyItem(requestID: id) == nil { await hits.loadFeed() }
            selected = .play
            paths[.play] = [.request(id)]
            Task { await hits.loadMyHits() }
        case let .chat(id):
            selected = .people
            paths[.people] = [.chat(id)]
            Task { await hits.refreshAll() }
        }
    }

    // MARK: - Coach marks

    /// Only over the Play root: a pushed screen or another tab is not where the tips point.
    private func startCoachMarksIfNeeded() {
        guard let profile = session.profile, !profile.coachMarksDone, coachStep == nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard coachStep == nil, session.profile?.coachMarksDone == false, isAtRoot, selected == .play, deepLinks.pending == nil else { return }
            withAnimation(.easeInOut(duration: 0.25)) { coachStep = 1 }
        }
    }

    private func advanceCoachMarks() {
        guard let step = coachStep else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            switch step {
            case 1:
                selected = .people
                coachStep = 2
            case 2:
                selected = .play
                coachStep = 3
            default:
                coachStep = nil
            }
        }
        if step >= 3 {
            Task { try? await session.updateProfile(["coach_marks_done": true]) }
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
        case let .groupInfo(id): GroupInfoView(chatID: id)
        case let .player(id, hitID): PlayerProfileView(playerID: id, hitID: hitID)
        case .addFriends: AddFriendsView()
        case .newGroup: NewGroupView()
        case .account: AccountView()
        case .blockedPlayers: BlockedPlayersView()
        }
    }
}

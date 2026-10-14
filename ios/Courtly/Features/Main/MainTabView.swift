import SwiftUI

/// The four tabs behind a floating glass tab bar. Each tab keeps its own navigation stack,
/// and the bar hides while a tab has a screen pushed.
struct MainTabView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var hits: HitsStore
    @State private var inbox: InboxStore
    @State private var deepLinks = DeepLinkCenter.shared
    @State private var selected: MainTab = .play
    @State private var paths: [MainTab: [AppRoute]] = [:]
    @State private var isPlanning = false
    @State private var coachStep: Int?
    @State private var openGeneration = 0   // the newest deep link is the one that lands

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
            Task { await inbox.load() }   // the People dot is right from the start, not from the first visit
            await hits.refreshAll()
            await NotificationPermission.registerIfAuthorized()
            if let link = deepLinks.pending { await open(link) }
            startCoachMarksIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await hits.refreshAll() }
                Task { await inbox.load() }
                Task { await API.Devices.retryPending() }   // a push token the server didn't take yet
            }
        }
        .onChange(of: deepLinks.pending) { _, link in
            if let link { Task { await open(link) } }
        }
        .onChange(of: deepLinks.lastPushReceivedAt) { _, _ in
            Task { await hits.refreshAll() }
            Task { await inbox.load() }
        }
    }

    // MARK: - Deep links

    /// Lands on the screen a notification points at, with the data behind it loaded first.
    @MainActor
    private func open(_ link: DeepLink) async {
        deepLinks.pending = nil
        isPlanning = false
        coachStep = nil
        openGeneration += 1
        let generation = openGeneration
        switch link {
        case .play:
            await hits.loadFeed()
            guard generation == openGeneration else { return }   // a later tap landed while the feed loaded
            selected = .play
            paths[.play] = []
        case let .hit(id), let .check(id, _):
            selected = .myHits
            paths[.myHits] = [.hit(id)]
        case let .request(id):
            await hits.loadFeed()
            guard generation == openGeneration else { return }   // a later tap landed while the feed loaded
            selected = .play
            paths[.play] = [.request(id)]
        case let .chat(id):
            selected = .people
            paths[.people] = [.chat(id)]
        }
    }

    // MARK: - Coach marks

    /// Remembered on the device as well, so tips finished offline stay finished; the server hears next time.
    static let coachMarksDoneKey = "coach_marks_done_local"

    private func startCoachMarksIfNeeded() {
        guard let profile = session.profile, !profile.coachMarksDone, coachStep == nil, deepLinks.pending == nil else { return }
        if UserDefaults.standard.bool(forKey: Self.coachMarksDoneKey) {
            Task { try? await session.updateProfile(["coach_marks_done": true]) }   // finished before; the save hadn't landed
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard coachStep == nil, session.profile?.coachMarksDone == false else { return }
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
            UserDefaults.standard.set(true, forKey: Self.coachMarksDoneKey)
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
        case let .player(id): PlayerProfileView(playerID: id)
        case .addFriends: AddFriendsView()
        case .newGroup: NewGroupView()
        case .account: AccountView()
        case .blockedPlayers: BlockedPlayersView()
        }
    }
}

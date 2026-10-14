import SwiftUI

/// The four tabs behind a floating glass tab bar. Each tab keeps its own navigation stack,
/// and the bar hides while a tab has a screen pushed.
struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var hits = HitsStore()
    @State private var selected: MainTab = .play
    @State private var paths: [MainTab: [AppRoute]] = [:]
    @State private var isPlanning = false

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
        .task {
            await hits.refreshAll()
            await NotificationPermission.registerIfAuthorized()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await hits.refreshAll() }
                Task { await API.Devices.retryPending() }   // a push token the server didn't take yet
            }
        }
    }

    /// The empty-state card on Play has its own button, so the pill steps aside.
    private var showsPlanPill: Bool {
        (hits.feed?.myUpcomingCount ?? 1) > 0
    }

    private var dots: Set<MainTab> {
        hits.needsReplyCount > 0 ? [.play] : []
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
        case .people: PeoplePlaceholderView()
        case .you: YouSummaryView()
        }
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case let .hit(id): HitDetailView(hitID: id)
        case let .request(id): JoinRequestView(requestID: id)
        case let .chat(id): ChatThreadView(chatID: id)
        }
    }
}

/// Stands in until the People tab lands.
private struct PeoplePlaceholderView: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("No chats yet")
                .font(CourtlyFont.sectionHeader)
                .foregroundStyle(CourtlyColor.ink)
            Text("Friends and hits you join show up here.")
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .navigationTitle("People")
    }
}

/// Shows the saved profile so it can be checked on device, plus a way to sign out.
private struct YouSummaryView: View {
    @Environment(AppSession.self) private var session
    @State private var isSigningOut = false

    var body: some View {
        List {
            if let profile = session.profile {
                Section("Profile") {
                    LabeledContent("Name", value: profile.displayName)
                    LabeledContent("Shown to others as", value: profile.publicName)
                    LabeledContent("Birthday", value: profile.birthday ?? "—")
                    LabeledContent("Gender", value: profile.gender?.title ?? "—")
                    LabeledContent("Level", value: profile.level?.title ?? "—")
                    LabeledContent("What you play", value: profile.formats.map(\.shortTitle).joined(separator: ", "))
                    LabeledContent("Area", value: areaText(profile))
                    LabeledContent("Availability", value: profile.availability.shortDescription)
                    LabeledContent("Calendar", value: profile.calendarProvider == .none ? "Not connected" : profile.calendarProvider.rawValue.capitalized)
                    LabeledContent("Hits played", value: String(profile.hitsPlayed))
                }
            }
            Section {
                Button(isSigningOut ? "Signing out…" : "Sign out", role: .destructive) {
                    isSigningOut = true
                    Task { @MainActor in
                        await session.signOut()
                        isSigningOut = false
                    }
                }
                .disabled(isSigningOut)
            }
        }
        .navigationTitle("You")
        .refreshable { await session.refreshProfile() }
    }

    private func areaText(_ profile: Profile) -> String {
        guard let label = profile.areaLabel else { return "Not set" }
        return "\(label) · \(profile.radius.title)"
    }
}

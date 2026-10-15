import SwiftUI

/// Hits you can join. Whatever waits on your answer comes first; under it, two lists: hits your friends
/// are hosting, and everything open near you with a couple of filters.
struct PlayView: View {
    @Environment(HitsStore.self) private var hits
    @Environment(AppSession.self) private var session
    @Environment(\.navigate) private var navigate
    let onPlan: () -> Void

    @State private var tab = 0
    @State private var expanded: UUID?
    @State private var filters = ExploreFilters()
    @State private var showsFilters = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let feed = hits.feed {
                    content(feed)
                } else if let error = hits.lastError, !hits.isLoadingFeed {
                    QuietCard(title: "Couldn’t load hits", detail: error)
                        .padding(.top, 22)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(.horizontal, CourtlyMetrics.screenPadding)
            .padding(.top, 4)
            .padding(.bottom, 96)
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { TabHeader(title: "Play") }
        .refreshable { await hits.loadFeed() }
    }

    @ViewBuilder
    private func content(_ feed: PlayFeed) -> some View {
        if !feed.needsReply.isEmpty {
            SectionHeader(title: "Needs your reply")
            VStack(spacing: 10) {
                ForEach(feed.needsReply) { item in
                    NeedsReplyCard(item: item)
                }
            }
        }

        SegmentedControl(options: ["Friends", "Explore"], selectedIndex: $tab)
            .padding(.top, feed.needsReply.isEmpty ? 4 : 22)

        if tab == 0 {
            friends(feed.fromFriends)
        } else {
            explore(feed.nearYou)
        }
    }

    // MARK: - Friends

    @ViewBuilder
    private func friends(_ hitsFromFriends: [Hit]) -> some View {
        if hitsFromFriends.isEmpty {
            VStack(spacing: 8) {
                Text("Nothing from friends yet")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(CourtlyColor.ink)
                Text("When a friend posts a hit, it shows up here first.")
                    .font(CourtlyFont.secondary)
                    .foregroundStyle(CourtlyColor.secondary)
                    .multilineTextAlignment(.center)
                Button("Add friends") { navigate(.addFriends) }
                    .font(CourtlyFont.secondarySemibold)
                    .foregroundStyle(CourtlyColor.blue)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 56)
        } else {
            rows(hitsFromFriends)
                .padding(.top, 12)
        }
    }

    // MARK: - Explore

    @ViewBuilder
    private func explore(_ nearby: [Hit]) -> some View {
        HStack(spacing: 10) {
            Button { showsFilters = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 13, weight: .semibold))
                    Text(filters.activeCount == 0 ? "Filters" : "Filters · \(filters.activeCount)")
                        .font(CourtlyFont.captionSemibold)
                }
                .foregroundStyle(filters.activeCount == 0 ? CourtlyColor.ink : .white)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(filters.activeCount == 0 ? CourtlyColor.card : CourtlyColor.ink))
            }
            .buttonStyle(.plain)
            Text("Within \(session.profile?.radius.title ?? "") of \(session.profile?.areaLabel?.components(separatedBy: ",").first ?? "you")")
                .font(CourtlyFont.caption)
                .foregroundStyle(CourtlyColor.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .sheet(isPresented: $showsFilters) {
            ExploreFiltersSheet(filters: $filters, radius: session.profile?.radius ?? .ten)
        }
        let shown = filters.apply(to: nearby)
        if nearby.isEmpty {
            QuietCard(title: "No open hits near you", detail: "Widen the distance in Filters, or plan one and players nearby can ask to join.")
        } else if shown.isEmpty {
            QuietCard(title: "Nothing matches", detail: "Loosen a filter to see more.")
        } else {
            rows(shown)
        }
    }

    private func rows(_ list: [Hit]) -> some View {
        CardRows(items: list) { hit in
            HitFeedRow(hit: hit, isExpanded: expanded == hit.id) {
                withAnimation(.easeInOut(duration: 0.22)) {
                    expanded = expanded == hit.id ? nil : hit.id
                }
            }
        }
    }
}

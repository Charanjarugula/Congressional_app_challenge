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
    @State private var format: PlayFormat?
    @State private var myLevelOnly = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Play")
                    .font(CourtlyFont.largeTitle)
                    .tracking(-0.8)
                    .foregroundStyle(CourtlyColor.ink)
                    .frame(height: 52)

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
            .padding(.bottom, 96)
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("Any format") { format = nil }
                    ForEach(PlayFormat.allCases) { option in
                        Button(option.shortTitle) { format = option }
                    }
                } label: {
                    chip(format?.shortTitle ?? "Any format", on: format != nil, menu: true)
                }
                Button { myLevelOnly.toggle() } label: {
                    chip("My level", on: myLevelOnly)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
        }
        let shown = nearby.filter { hit in
            (format == nil || hit.format == format) && (!myLevelOnly || hit.host.level == session.profile?.level)
        }
        if nearby.isEmpty {
            QuietCard(title: "No open hits near you", detail: "Within \(session.profile?.radius.title ?? "your radius") of \(session.profile?.areaLabel?.components(separatedBy: ",").first ?? "you"). Plan one and players nearby can ask to join.")
        } else if shown.isEmpty {
            QuietCard(title: "Nothing matches", detail: "Try another format or turn off the level filter.")
        } else {
            rows(shown)
        }
    }

    private func chip(_ title: String, on: Bool, menu: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(title)
            if menu {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .font(CourtlyFont.captionSemibold)
        .foregroundStyle(on ? .white : CourtlyColor.ink)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Capsule().fill(on ? CourtlyColor.ink : CourtlyColor.card))
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

import SwiftUI

/// Hits you can join: anything waiting on your answer, then the open hits (friends' first, then the closest).
struct PlayView: View {
    @Environment(HitsStore.self) private var hits
    let onPlan: () -> Void

    @State private var expanded: UUID?

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

        let open = feed.fromFriends + feed.nearYou.filter { near in !feed.fromFriends.contains { $0.id == near.id } }
        if open.isEmpty {
            QuietCard(title: "No open hits yet", detail: "Plan one and players nearby can ask to join.")
                .padding(.top, 22)
        } else {
            SectionHeader(title: "Open hits")
            CardRows(items: open) { hit in
                HitFeedRow(hit: hit, isExpanded: expanded == hit.id) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        expanded = expanded == hit.id ? nil : hit.id
                    }
                }
            }
        }
    }
}

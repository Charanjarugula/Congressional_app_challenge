import SwiftUI

/// Hits you can join: requests waiting on you, then friends' hits, then the closest open ones.
struct PlayView: View {
    @Environment(HitsStore.self) private var hits
    let onPlan: () -> Void

    @State private var showsAllNearby = false

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
                } else if hits.isLoadingFeed {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    QuietCard(title: "Couldn’t load hits", detail: hits.lastError ?? "Pull down to try again.")
                        .padding(.top, 22)
                }
            }
            .padding(.horizontal, CourtlyMetrics.screenPadding)
            .padding(.bottom, 24)
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

        if feed.myUpcomingCount == 0 {
            NoHitsCard(onPlan: onPlan)
                .padding(.top, feed.needsReply.isEmpty ? 4 : 22)
        }

        if !feed.freeThisWeek.isEmpty {
            FreeThisWeekCard(players: feed.freeThisWeek, onPlan: onPlan)
                .padding(.top, 22)
        }

        if !feed.fromFriends.isEmpty {
            SectionHeader(title: "From friends")
            CardRows(items: feed.fromFriends) { hit in
                HitFeedRow(hit: hit)
            }
        }

        if !feed.nearYou.isEmpty {
            SectionHeader(
                title: "Near you",
                actionTitle: feed.nearYou.count > 5 ? (showsAllNearby ? "Show less" : "See all") : nil,
                action: { withAnimation { showsAllNearby.toggle() } }
            )
            CardRows(items: showsAllNearby ? feed.nearYou : Array(feed.nearYou.prefix(5))) { hit in
                HitFeedRow(hit: hit)
            }
        }

        if !feed.hasHits {
            QuietCard(
                title: "No open hits near you yet",
                detail: "Post one and players within your radius can ask to join."
            )
            .padding(.top, 22)
        }
    }
}

/// Blue card shown while you have nothing planned.
private struct NoHitsCard: View {
    let onPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("No hits planned")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                Text("Pick a time and a court. Players nearby can ask to join.")
                    .font(CourtlyFont.secondary)
                    .lineSpacing(3)
                    .opacity(0.92)
                    .frame(maxWidth: 260, alignment: .leading)
            }
            Button(action: onPlan) {
                Text("Plan a hit")
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(CourtlyColor.blue))
    }
}

/// Friends whose availability still has open blocks this week.
private struct FreeThisWeekCard: View {
    let players: [PlayerCard]
    let onPlan: () -> Void

    var body: some View {
        Button(action: onPlan) {
            HStack(spacing: 14) {
                AvatarStack(cards: players, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(names)
                        .font(CourtlyFont.bodySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                        .lineLimit(1)
                    Text("Free this week · plan something")
                        .font(CourtlyFont.caption)
                        .foregroundStyle(CourtlyColor.secondary)
                }
                Spacer(minLength: 8)
                ChevronMark()
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: CourtlyMetrics.cardRadius, style: .continuous).fill(CourtlyColor.card))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var names: String {
        let first = players.prefix(2).map(\.firstName)
        let rest = players.count - first.count
        switch (first.count, rest) {
        case (1, _): return first[0]
        case (2, 0): return "\(first[0]) and \(first[1])"
        default: return "\(first.joined(separator: ", ")) and \(rest) more"
        }
    }
}

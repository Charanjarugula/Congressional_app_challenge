import SwiftUI

/// Your commitments: upcoming hits grouped by week, then everything you've played.
struct MyHitsView: View {
    @Environment(HitsStore.self) private var hits
    @Environment(AppSession.self) private var session
    @Environment(\.navigate) private var navigate
    let onPlan: () -> Void

    @State private var segment = 0

    private var me: UUID? { session.profile?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("My Hits")
                    .font(CourtlyFont.largeTitle)
                    .tracking(-0.8)
                    .foregroundStyle(CourtlyColor.ink)
                    .frame(height: 52)
                SegmentedControl(options: ["Upcoming", "Past"], selectedIndex: $segment)
                content
            }
            .padding(.horizontal, CourtlyMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await hits.loadMyHits() }
    }

    @ViewBuilder
    private var content: some View {
        let list = segment == 0 ? (hits.myHits?.upcoming ?? []) : (hits.myHits?.past ?? [])
        if list.isEmpty {
            if hits.myHits == nil, let error = hits.myHitsError, !hits.isLoadingMyHits {
                QuietCard(title: "Couldn’t load your hits", detail: error)
            } else if hits.myHits == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            } else if segment == 0 {
                emptyUpcoming
            } else {
                emptyPast
            }
        } else {
            let groups = segment == 0 ? Self.groupUpcoming(list) : Self.groupPast(list)
            ForEach(groups) { group in
                SectionHeader(title: group.title, top: 24)
                CardRows(items: group.hits) { hit in
                    row(hit)
                }
            }
        }
    }

    private var emptyUpcoming: some View {
        VStack(spacing: 8) {
            Text("Nothing planned")
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(CourtlyColor.ink)
            Text("Join a hit on Play or post your own.")
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.secondary)
                .multilineTextAlignment(.center)
            Button(action: onPlan) {
                Text("Plan a hit")
                    .font(CourtlyFont.secondarySemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CourtlyColor.blue))
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 72)
    }

    private var emptyPast: some View {
        VStack(spacing: 4) {
            Text("No hits yet")
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(CourtlyColor.ink)
            Text("Hits you’ve played show up here the day after.")
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 72)
    }

    private func row(_ hit: Hit) -> some View {
        let status = statusLine(hit)
        return Button {
            navigate(.hit(hit.id))
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(HitFormatting.day.string(from: hit.startsAt))
                    Text(HitFormatting.clock.string(from: hit.startsAt))
                }
                .font(CourtlyFont.rounded(17))
                .foregroundStyle(CourtlyColor.ink)
                .frame(width: 76, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(hit.counterpart(for: me)?.displayName ?? "Your hit") · \(hit.format.shortTitle)")
                        .font(CourtlyFont.bodySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                        .lineLimit(1)
                    Text(status.text)
                        .font(CourtlyFont.captionSemibold)
                        .foregroundStyle(status.color)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if hit.rowState == .openWaiting {
                    Text("Invite")
                        .font(CourtlyFont.secondarySemibold)
                        .foregroundStyle(CourtlyColor.blue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(CourtlyColor.blueTint))
                } else {
                    ChevronMark()
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusLine(_ hit: Hit) -> (text: String, color: Color) {
        let place = hit.court.shortName
        switch hit.rowState {
        case .openRequests:
            let count = hit.pendingRequestCount
            return ("\(count) \(count == 1 ? "request" : "requests") · \(place)", CourtlyColor.blue)
        case .openWaiting: return ("Open · \(hit.spotsLabel) · \(place)", CourtlyColor.blue)
        case .confirmed: return ("Confirmed · \(place)", CourtlyColor.green)
        case .pending: return ("Pending · \(place)", CourtlyColor.secondary)
        case .invited: return ("Invited · \(place)", CourtlyColor.blue)
        case .played:
            return hit.needsAttendance == true
                ? ("Did they show up? · \(place)", CourtlyColor.blue)
                : ("Played · \(place)", CourtlyColor.secondary)
        case .cancelled: return ("Cancelled · \(place)", CourtlyColor.red)
        case .expired: return ("Expired · \(place)", CourtlyColor.secondary)
        case .open, nil: return (place, CourtlyColor.secondary)
        }
    }

    // MARK: - Grouping

    private struct HitGroup: Identifiable {
        let title: String
        var hits: [Hit]
        var id: String { title }
    }

    private static func groupUpcoming(_ list: [Hit]) -> [HitGroup] {
        let calendar = Calendar.current
        let thisWeekEnd = calendar.dateInterval(of: .weekOfYear, for: .now)?.end ?? .now
        let nextWeekEnd = calendar.date(byAdding: .day, value: 7, to: thisWeekEnd) ?? thisWeekEnd
        var groups: [HitGroup] = []
        for hit in list {
            let title = hit.startsAt < thisWeekEnd ? "This week" : (hit.startsAt < nextWeekEnd ? "Next week" : "Later")
            if let index = groups.firstIndex(where: { $0.title == title }) {
                groups[index].hits.append(hit)
            } else {
                groups.append(HitGroup(title: title, hits: [hit]))
            }
        }
        return groups
    }

    private static func groupPast(_ list: [Hit]) -> [HitGroup] {
        let calendar = Calendar.current
        let thisYear = calendar.component(.year, from: .now)
        var groups: [HitGroup] = []
        for hit in list {
            let formatter = calendar.component(.year, from: hit.startsAt) == thisYear ? HitFormatting.month : HitFormatting.monthAndYear
            let title = formatter.string(from: hit.startsAt)
            if let index = groups.firstIndex(where: { $0.title == title }) {
                groups[index].hits.append(hit)
            } else {
                groups.append(HitGroup(title: title, hits: [hit]))
            }
        }
        return groups
    }
}

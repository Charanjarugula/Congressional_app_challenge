import SwiftUI

/// One searchable inventory. Friends narrows the same list rather than competing with Discover.
struct PlayView: View {
    @Environment(HitsStore.self) private var hits
    @Environment(AppSession.self) private var session
    @Environment(\.navigate) private var navigate
    let onPlan: () -> Void

    @State private var friendsOnly = false
    @State private var filters = ExploreFilters()
    @State private var searchArea: HomeArea?
    @State private var showsFilters = false
    @State private var showsSearch = false
    @State private var showsReplies = false

    private var areaLabel: String { searchArea?.label ?? session.profile?.areaLabel ?? "Choose an area" }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    scopeControls
                    if let feed = hits.feed {
                        content(feed)
                    } else if let error = hits.lastError, !hits.isLoadingFeed {
                        errorView(error)
                    } else {
                        ProgressView("Finding hits…")
                            .frame(maxWidth: .infinity).padding(.vertical, 48)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .refreshable { await hits.loadFeed(userInitiated: true) }
        }
        .background(CourtlyColor.card.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsFilters) {
            ExploreFiltersSheet(filters: $filters, inventory: inventory, friendIDs: friendIDs)
        }
        .sheet(isPresented: $showsSearch) {
            ExploreSearchSheet(filters: $filters, area: $searchArea, homeArea: session.profile?.homeArea)
        }
    }

    private var inventory: [Hit] {
        guard let feed = hits.feed else { return [] }
        return ExploreInventory.hits(feed, friendsOnly: friendsOnly, area: searchArea)
    }
    private var friendIDs: Set<UUID> { Set(hits.feed?.fromFriends.map(\.id) ?? []) }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Explore").font(.largeTitle.bold()).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Button { showsSearch = true } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Label { Text(areaLabel) } icon: { Image(systemName: "mappin.and.ellipse").foregroundStyle(CourtlyColor.blue) }
                        .font(.body.weight(.semibold)).foregroundStyle(CourtlyColor.ink)
                    HStack(spacing: 10) {
                        Image(systemName: "clock").foregroundStyle(CourtlyColor.secondary)
                        Text(filters.timeSummary).foregroundStyle(CourtlyColor.secondary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").foregroundStyle(CourtlyColor.blue)
                    }
                    .font(.subheadline)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(CourtlyColor.card, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("explore-search")
            .accessibilityHint("Change city, day or start time")
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CourtlyColor.blue.ignoresSafeArea(edges: .top))
    }

    private var scopeControls: some View {
        HStack(spacing: 26) {
            scope("All hits", selected: !friendsOnly) { friendsOnly = false }
            scope("Friends", selected: friendsOnly) { friendsOnly = true }
            Spacer(minLength: 0)
            Button { showsFilters = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3).foregroundStyle(CourtlyColor.ink)
                    .frame(width: 46, height: 44)
                    .background(CourtlyColor.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .topTrailing) {
                        if filters.activeCount > 0 {
                            Text("\(filters.activeCount)").font(.caption2.bold())
                                .foregroundStyle(.white).padding(4)
                                .background(CourtlyColor.blue, in: Circle())
                        }
                    }
            }
            .accessibilityLabel("Filters")
            .accessibilityValue("\(filters.activeCount) active")
            .accessibilityIdentifier("open-filters")
        }
        .padding(.top, 16).padding(.bottom, 8)
    }

    private func scope(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.body.weight(.semibold))
                .foregroundStyle(selected ? CourtlyColor.blue : CourtlyColor.secondary)
                .frame(minHeight: 44)
                .overlay(alignment: .bottomLeading) {
                    Capsule().fill(selected ? CourtlyColor.blue : .clear).frame(width: 28, height: 3)
                }
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder private func content(_ feed: PlayFeed) -> some View {
        let replies = feed.needsReply.filter { $0.kind != .invite || (!$0.hit.isMember && $0.hit.openInvite != nil) }
        if !replies.isEmpty {
            DisclosureGroup(isExpanded: $showsReplies) {
                VStack(spacing: 10) { ForEach(replies) { NeedsReplyCard(item: $0) } }
                    .padding(.vertical, 12)
            } label: {
                Text("Needs your reply (\(replies.count))").font(.subheadline.weight(.semibold))
            }
            .tint(CourtlyColor.blue).padding(.vertical, 12)
        }
        if let error = hits.lastError { errorView(error) }
        let shown = filters.apply(to: inventory, friendIDs: friendIDs)
        HStack {
            Text("\(shown.count) \(shown.count == 1 ? "hit" : "hits") · \(filters.distance == .any ? "All distances" : filters.distance.title)")
                .font(.caption).foregroundStyle(CourtlyColor.secondary)
                .accessibilityIdentifier("explore-count")
            Spacer()
            Menu {
                Picker("Sort by", selection: $filters.sort) {
                    ForEach(ExploreFilters.Sort.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                HStack(spacing: 4) { Text(filters.sort.title); Image(systemName: "chevron.down") }
                    .font(.footnote.weight(.semibold)).foregroundStyle(CourtlyColor.blue).frame(minHeight: 44)
            }
            .accessibilityIdentifier("explore-sort")
        }
        if shown.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(friendsOnly ? "No matching hits from friends" : "No hits for this search")
                    .font(.title2.bold())
                Text("Try another time or fewer filters. Or post a hit for others to join.")
                    .font(.subheadline).foregroundStyle(CourtlyColor.secondary)
                Button("Clear filters") { filters = ExploreFilters() }
                    .frame(minHeight: 44).foregroundStyle(CourtlyColor.blue)
                if friendsOnly {
                    Button("See all hits") { friendsOnly = false }
                        .frame(minHeight: 44).foregroundStyle(CourtlyColor.blue)
                }
                PrimaryButton(title: "Plan a hit", style: .lime, compact: true, action: onPlan)
            }
            .padding(.vertical, 32).foregroundStyle(CourtlyColor.ink)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(shown) { hit in
                    Button { navigate(.hit(hit.id)) } label: {
                        ExploreSessionRow(hit: hit, isFriend: friendIDs.contains(hit.id) || hit.relationship(with: hit.host.id) == .friend)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("explore-hit-\(hit.id)")
                    .accessibilityHint("Open hit details and joining options")
                    Rectangle().fill(CourtlyColor.line).frame(height: 1).accessibilityHidden(true)
                }
            }
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn’t refresh hits").font(.headline)
            Text(error).font(.footnote).foregroundStyle(CourtlyColor.secondary)
            Button("Try again") { Task { await hits.loadFeed(userInitiated: true) } }
                .frame(minHeight: 44).disabled(hits.isLoadingFeed)
        }.padding(.vertical, 16)
    }
}

private struct ExploreSessionRow: View {
    let hit: Hit
    let isFriend: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { time; details }
            } else {
                HStack(alignment: .top, spacing: 18) { time.frame(width: 74, alignment: .leading); details }
            }
        }
        .padding(.vertical, 16)
        .foregroundStyle(CourtlyColor.ink)
        .accessibilityElement(children: .combine)
    }

    private var time: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hit.calendar.isDateInToday(hit.startsAt) ? "TODAY" : HitFormatting.string("EEE, MMM d", hit.startsAt, in: hit.zone).uppercased())
                .font(.caption2.weight(.semibold)).foregroundStyle(CourtlyColor.blue)
            Text(HitFormatting.string("h:mm", hit.startsAt, in: hit.zone))
                .font(.title2.bold()).fixedSize()
            Text(HitFormatting.string("a", hit.startsAt, in: hit.zone) + (hit.isInAnotherZone ? " \(hit.zone.abbreviation(for: hit.startsAt) ?? "")" : ""))
                .font(.caption).foregroundStyle(CourtlyColor.secondary)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(hit.format.shortTitle).font(.title3.weight(.semibold))
                Spacer(minLength: 4)
                if let miles = hit.miles {
                    Text(String(format: "%.1f mi", miles)).font(.footnote).foregroundStyle(CourtlyColor.blue).fixedSize()
                }
            }
            Text(hit.court.name).font(.footnote).foregroundStyle(CourtlyColor.secondary)
            Text([hit.host.level?.title, hit.durationLabel].compactMap { $0 }.joined(separator: " · "))
                .font(.footnote).foregroundStyle(CourtlyColor.secondary)
            HStack(spacing: 7) {
                PlayerAvatar(card: hit.host, size: 24).accessibilityHidden(true)
                Text(hit.host.displayName).font(.footnote.weight(.medium))
                if isFriend {
                    Text("Friend").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 3)
                        .background(CourtlyColor.lime, in: RoundedRectangle(cornerRadius: 5))
                }
            }
            Text(hit.isMember ? "You’re in" : hit.hasPendingRequest ? "Requested" : hit.isFull ? "Full" : "\(hit.spotsLabel) open")
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

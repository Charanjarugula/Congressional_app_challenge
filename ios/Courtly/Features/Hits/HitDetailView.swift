import SwiftUI

/// One hit: when, who, where, and the one thing to do next. Every fact has a single home:
/// time, format and who can join in the summary; host, players and open spots in "Who's playing";
/// the court in its own card. One pinned action per state; the rest sits in the ••• menu.
struct HitDetailView: View {
    let hitID: UUID

    init(hitID: UUID) { self.hitID = hitID }

    #if DEBUG && targetEnvironment(simulator)
    init(preview hit: Hit) {
        hitID = hit.id
        _hit = State(initialValue: hit)
    }
    #endif

    @Environment(HitsStore.self) private var hits
    @Environment(AppSession.self) private var session
    @Environment(\.navigate) private var navigate
    @State private var hit: Hit?
    @State private var hitVersion = 0   // bumped by every reload and action; only the latest may write
    @State private var loadFailed = false
    @State private var isWorking = false
    @State private var showsCancelAlert = false
    @State private var showsLeaveAlert = false
    @State private var showsCalendar = false
    @State private var showsInvite = false
    @State private var showsEdit = false
    @State private var attendance: [UUID: Bool] = [:]
    @State private var standings: [UUID: Relationship] = [:]   // friend adds made on this screen
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .title) private var timeSize = 30
    @State private var answering: UUID?   // the join request being accepted or declined

    private var me: UUID? { session.profile?.id }

    var body: some View {
        ScrollView {
            if let hit {
                VStack(alignment: .leading, spacing: 16) {
                    banner(hit)
                    if hit.status == .played && hit.isMember && hit.needsAttendance != false {
                        attendanceSections(hit)
                    }
                    summaryCard(hit)
                    if hit.viewer.isHost && hit.isLive { requestsSection(hit) }
                    playersSection(hit)
                    courtCard(hit)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 24)
            } else if loadFailed {
                QuietCard(title: "This hit isn’t available", detail: "It may have been cancelled, or it has filled up.")
                    .padding(24)
            } else {
                ProgressView()
                    .padding(.top, 80)
            }
        }
        .background(CourtlyColor.surface.ignoresSafeArea())
        .plainBackButton()
        .navigationTitle(hit?.viewer.isHost == true ? "Your hit" : "Hit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let hit, hit.viewer.isHost, hit.isLive {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showsEdit = true }
                        .font(CourtlyFont.body)
                        .foregroundStyle(CourtlyColor.blue)
                }
            }
            if let hit, hit.isMember, hit.isLive {
                ToolbarItem(placement: .topBarTrailing) { moreMenu(hit) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let hit { bottomAction(hit) }
        }
        .task(id: hitID) {
            if hit == nil { hit = hits.cachedHit(hitID) }
            await reload()
        }
        .onChange(of: hits.lastRefreshedAt) { _, _ in
            // Something changed on another phone (a request, a claim, a cancel): show it here too.
            Task { await reload() }
        }
        .alert("Cancel this hit?", isPresented: $showsCancelAlert) {
            Button("Cancel hit", role: .destructive) {
                Task { await perform { try await hits.cancel(hitID) } }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Everyone who joined will be told it’s off.")
        }
        .alert("Leave this hit?", isPresented: $showsLeaveAlert) {
            Button("Leave", role: .destructive) {
                Task {
                    if await perform({ try await hits.leave(hitID) }) {
                        navigate.pop()
                    }
                }
            }
            Button("Stay", role: .cancel) {}
        } message: {
            if let hit, hit.viewer.isHost, let next = hit.players.first {
                Text("\(next.card.firstName) takes over as host. The hit goes on without you.")
            } else {
                Text("Your spot opens back up and the host is told.")
            }
        }
        .sheet(isPresented: $showsCalendar) {
            if let hit {
                CalendarEventEditor(hit: hit, me: me)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showsInvite) {
            if let hit { InviteSheet(hit: hit) }
        }
        .sheet(isPresented: $showsEdit) {
            if let hit {
                PlanHitView(editing: hit) { saved in
                    hitVersion += 1
                    self.hit = saved
                }
            }
        }
        .errorAlert($errorMessage)
    }

    // MARK: - Sections

    /// What changed for the viewer, said once at the top.
    @ViewBuilder
    private func banner(_ hit: Hit) -> some View {
        if hit.status == .cancelled {
            QuietCard(title: "This hit was cancelled", detail: "It’s off. Other open hits are on Explore.")
        } else if hit.status == .expired {
            QuietCard(title: "This hit has expired", detail: "It didn’t fill before the start time.")
        } else if hit.isLive && !hit.isMember {
            if hit.hasPendingRequest {
                QuietCard(title: "You’ve asked to join", detail: "\(hit.host.firstName) can accept until the hit starts.")
            } else if hit.openInvite != nil {
                QuietCard(title: "\(hit.host.firstName) invited you", detail: "First to accept takes the spot.")
            } else if hit.wasDeclined {
                QuietCard(title: "\(hit.host.firstName) passed on this one", detail: "Other open hits are on Explore.")
            }
        }
    }

    /// When and what. Players, spots and the court each have their own card below.
    private func summaryCard(_ hit: Hit) -> some View {
        Card(padding: 18, radius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.dateText.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(CourtlyColor.blue)
                        Text(hit.clockText)
                            .font(.system(size: timeSize, weight: .bold))
                            .foregroundStyle(CourtlyColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                    StatusPill(kind: pill(hit))
                }
                Text(hit.status == .played ? headline(hit) : hit.format.title)
                    .font(.headline)
                    .foregroundStyle(CourtlyColor.ink)
                Text([hit.durationLabel, hit.isLive ? whoCanJoin(hit) : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(CourtlyColor.secondary)
                if let note = hit.yourTimeNote {
                    Text(note).font(.footnote).foregroundStyle(CourtlyColor.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The pill says only the state; how many spots are open is in "Who's playing".
    private func pill(_ hit: Hit) -> HitStatusKind {
        if case .open = hit.statusKind { return .open(hit.isFull ? "Full" : "Open") }
        return hit.statusKind
    }

    private func whoCanJoin(_ hit: Hit) -> String {
        switch hit.visibility {
        case .anyone: "Anyone can join"
        case .friends: "Friends only"
        case .inviteOnly: "Invite only"
        }
    }

    private func headline(_ hit: Hit) -> String {
        let others = hit.others(than: me).map(\.displayName)
        return others.isEmpty ? hit.format.title : "\(hit.format.title) with \(others.joined(separator: ", "))"
    }

    /// The host answers join requests right here, without going back to Explore.
    @ViewBuilder
    private func requestsSection(_ hit: Hit) -> some View {
        let requests = (hits.feed?.needsReply ?? []).filter { $0.kind == .joinRequest && $0.hit.id == hit.id && $0.requestId != nil }
        if !requests.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Asked to join", trailing: "\(requests.count)")
                ForEach(requests) { item in
                    Card(padding: 14, radius: 22) {
                        VStack(spacing: 12) {
                            Button {
                                if let id = item.requestId { navigate(.request(id)) }
                            } label: {
                                HStack(spacing: 10) {
                                    PlayerAvatar(card: item.person, size: 44)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.person.displayName).font(.body.weight(.semibold)).foregroundStyle(CourtlyColor.ink)
                                        Text(playerDetail(item.person)).font(.caption).foregroundStyle(CourtlyColor.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    ChevronMark()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            HStack(spacing: 8) {
                                ActionButton(title: "Accept", style: .blue, height: 44, radius: 14, isLoading: answering == item.requestId) {
                                    respond(item, accept: true)
                                }
                                ActionButton(title: "Decline", style: .quiet, height: 44, radius: 14) { respond(item, accept: false) }
                            }
                            .disabled(answering != nil)
                        }
                    }
                }
            }
        } else if hit.pendingRequestCount > 0 {
            QuietCard(
                title: hit.pendingRequestCount == 1 ? "1 player asked to join" : "\(hit.pendingRequestCount) players asked to join",
                detail: "Answer from Explore, under Needs your reply."
            )
        }
    }

    private func playerDetail(_ card: PlayerCard) -> String {
        let played = card.hitsPlayed == 1 ? "1 hit played" : "\(card.hitsPlayed) hits played"
        return [card.level?.title, played].compactMap { $0 }.joined(separator: " · ")
    }

    private func playersSection(_ hit: Hit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Who’s playing", trailing: hit.isLive ? "\(hit.everyone.count) of \(hit.everyone.count + max(hit.spotsOpen, 0))" : nil)
            HitPlayerRows(hit: hit, me: me, onInvite: hit.viewer.isHost && hit.isLive ? { showsInvite = true } : nil)
        }
    }

    private func sectionTitle(_ title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline).foregroundStyle(CourtlyColor.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.subheadline).foregroundStyle(CourtlyColor.secondary)
                    .accessibilityLabel(title == "Who’s playing" ? "\(trailing) spots filled" : "\(trailing) waiting")
            }
        }
        .padding(.top, 4)
    }

    /// The only place the court appears: map, name, address, surface. Distance is for people deciding to come.
    private func courtCard(_ hit: Hit) -> some View {
        Card(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                CourtMap(court: hit.court, height: 126)
                VStack(alignment: .leading, spacing: 3) {
                    Text(hit.court.name).font(.headline).foregroundStyle(CourtlyColor.ink)
                    if let address = hit.court.address, !address.isEmpty {
                        Text(address).font(.subheadline).foregroundStyle(CourtlyColor.secondary)
                            .textSelection(.enabled)
                    }
                    let extras = [hit.court.detailLine, hit.isMember ? nil : hit.milesLabel.map { "\($0) away" }].compactMap { $0 }
                    if !extras.isEmpty {
                        Text(extras.joined(separator: " · ")).font(.footnote).foregroundStyle(CourtlyColor.secondary)
                    }
                }
            }
        }
    }

    /// Everything that isn't the one main action: calendar, sharing, and the ways out.
    private func moreMenu(_ hit: Hit) -> some View {
        Menu {
            if hit.startTimeOnly != true {
                Button("Add to calendar", systemImage: "calendar.badge.plus") { showsCalendar = true }
            }
            ShareLink(item: hit.shareText) { Label("Share hit", systemImage: "square.and.arrow.up") }
            if hit.viewer.isPlayer || (hit.viewer.isHost && !hit.players.isEmpty) {
                Button("Leave hit", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { showsLeaveAlert = true }
            }
            if hit.viewer.isHost {
                Button("Cancel hit", systemImage: "xmark.circle", role: .destructive) { showsCancelAlert = true }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CourtlyColor.blue)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }

    /// Day-after check: one "Did X show up?" per other player.
    private func attendanceSections(_ hit: Hit) -> some View {
        ForEach(hit.others(than: me)) { player in
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Did \(player.firstName) show up?", top: 0)
                HStack(spacing: 8) {
                    ActionButton(title: "No", style: attendance[player.id] == false ? .blue : .grouped) {
                        answer(player, showedUp: false, hit: hit)
                    }
                    ActionButton(title: "Yes", style: attendance[player.id] == true ? .blue : .grouped) {
                        answer(player, showedUp: true, hit: hit)
                    }
                }
                if attendance[player.id] == true {
                    switch standings[player.id] ?? hit.relationship(with: player.id) {
                    case .none:
                        ActionButton(title: "Add \(player.firstName) as a friend", style: .grouped) {
                            addFriend(player)
                        }
                    case .requested:
                        Text("Friend request sent")
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.secondary)
                    case .requestedMe:
                        ActionButton(title: "Confirm \(player.firstName)’s friend request", style: .grouped) {
                            addFriend(player)   // adding someone who asked you is accepting
                        }
                    case .friend, .blocked:
                        EmptyView()
                    }
                }
            }
        }
    }

    /// One pinned action per state. Lime is the single thing to do next; anything else is quieter.
    @ViewBuilder
    private func bottomAction(_ hit: Hit) -> some View {
        let chatOpen = hit.chatId != nil && hit.status != .cancelled && hit.status != .expired
        Group {
            if hit.isMember, let chatID = hit.chatId, chatOpen {
                let chatTitle = hit.unreadMessages > 0 ? "Chat · \(hit.unreadMessages)" : "Chat"
                HStack(spacing: 8) {
                    if hit.viewer.isHost && hit.isLive && hit.spotsOpen > 0 {
                        ActionButton(title: "Invite", style: .quiet, height: 48, radius: 16) { showsInvite = true }
                            .frame(maxWidth: 120)
                    }
                    PrimaryButton(title: chatTitle, style: hit.isLive ? .lime : .blue, compact: true) { navigate(.chat(chatID)) }
                        .accessibilityLabel(hit.unreadMessages > 0 ? "Chat, \(hit.unreadMessages) unread" : "Chat")
                }
            } else if hit.viewer.isHost && hit.isLive && hit.spotsOpen > 0 {
                PrimaryButton(title: "Invite", style: .lime, compact: true) { showsInvite = true }
            } else if hit.isLive && !hit.isMember {
                if let invite = hit.openInvite {
                    PrimaryButton(title: "I’m in", style: .lime, compact: true, isLoading: isWorking) {
                        Task { await perform { try await hits.claimInvite(invite.id) } }
                    }
                } else if hit.hasPendingRequest, let request = hit.viewer.request {
                    DestructiveTextButton(title: "Cancel request") { Task { await cancelRequest(request.id) } }
                } else if !hit.wasDeclined {
                    PrimaryButton(title: hit.isFull ? "Full" : "Ask to join", style: .lime, compact: true, isEnabled: !hit.isFull, isLoading: isWorking) {
                        Task { await perform { try await hits.requestToJoin(hit.id) } }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(CourtlyColor.surface)
    }

    // MARK: - Actions

    private func reload() async {
        hitVersion += 1
        let version = hitVersion
        do {
            var fresh = try await API.Hits.get(hitID)
            guard version == hitVersion else { return }   // an action or a newer reload answered meanwhile
            // `get_hit` carries no My Hits extras; keep the ones the list told us about.
            let known = hit ?? hits.cachedHit(hitID)
            fresh.needsAttendance = fresh.needsAttendance ?? known?.needsAttendance
            hit = fresh
            // Answers already given come back from the server, so leaving and returning keeps them.
            for answer in fresh.viewer.attendance ?? [] where attendance[answer.userId] == nil {
                attendance[answer.userId] = answer.showedUp
            }
            loadFailed = false
        } catch {
            if hit == nil { loadFailed = true }
        }
    }

    /// Runs an action that returns the updated hit. Returns false when it failed (the alert shows why).
    @MainActor
    @discardableResult
    private func perform(_ work: () async throws -> Hit) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let updated = try await work()
            hitVersion += 1   // a reload fetched before this action must not put the old state back
            hit = updated
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Accept or decline from the hit itself; the hit updates in place.
    private func respond(_ item: NeedsReplyItem, accept: Bool) {
        guard let requestID = item.requestId, answering == nil else { return }
        answering = requestID
        Task { @MainActor in
            await perform { try await hits.respond(requestID: requestID, accept: accept) }
            answering = nil
        }
    }

    @MainActor
    private func cancelRequest(_ requestID: UUID) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await hits.cancelRequest(requestID, hitID: hitID)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func answer(_ player: PlayerCard, showedUp: Bool, hit: Hit) {
        attendance[player.id] = showedUp
        Task { @MainActor in
            do {
                try await hits.submitAttendance(hitID: hit.id, about: player.id, showedUp: showedUp, addFriend: false)
            } catch {
                attendance[player.id] = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addFriend(_ player: PlayerCard) {
        let before = standings[player.id]
        standings[player.id] = .requested
        Task { @MainActor in
            do {
                let result = try await API.People.addFriend(player.id)
                standings[player.id] = Relationship(rawValue: result.relationship) ?? .requested
            } catch {
                standings[player.id] = before
                errorMessage = error.localizedDescription
            }
        }
    }
}

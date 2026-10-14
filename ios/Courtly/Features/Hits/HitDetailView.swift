import SwiftUI

/// One hit: time, status, who's in, where, and what you can do about it.
/// Members see Chat, Add to calendar and the details; everyone else sees the host and Ask to join.
struct HitDetailView: View {
    let hitID: UUID

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
    @State private var attendance: [UUID: Bool] = [:]
    @State private var friendsAdded: Set<UUID> = []
    @State private var errorMessage: String?

    private var me: UUID? { session.profile?.id }

    var body: some View {
        ScrollView {
            if let hit {
                VStack(alignment: .leading, spacing: 0) {
                    summaryCard(hit)
                    if hit.status == .played && hit.isMember && hit.needsAttendance != false {
                        attendanceSections(hit)
                    }
                    if hit.isMember {
                        detailsSection(hit)
                    } else {
                        hostSection(hit)
                    }
                    footer(hit)
                }
                .padding(.horizontal, CourtlyMetrics.screenPadding)
                .padding(.bottom, 24)
            } else if loadFailed {
                QuietCard(title: "This hit isn’t available", detail: "It may have been cancelled, or it has filled up.")
                    .padding(CourtlyMetrics.screenPadding)
            } else {
                ProgressView()
                    .padding(.top, 80)
            }
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .navigationTitle(hit?.format.shortTitle ?? "Hit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
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
            Text("Your spot opens back up and the host is told.")
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
        .errorAlert($errorMessage)
    }

    // MARK: - Sections

    private func summaryCard(_ hit: Hit) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(hit.timeLabel)
                    .font(CourtlyFont.rounded(28))
                    .tracking(-0.5)
                    .foregroundStyle(CourtlyColor.ink)
                Spacer()
                StatusPill(kind: hit.statusKind)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(headline(hit))
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                Text(hit.courtLine)
                    .font(CourtlyFont.secondary)
                    .foregroundStyle(CourtlyColor.secondary)
            }
            PlayerTiles(hit: hit, me: me)
            CourtMap(court: hit.court)
            // The chat outlives the start time (running late, a thank-you after); inviting and the calendar don't.
            let chatStaysOpen = hit.chatId != nil && hit.status != .cancelled && hit.status != .expired
            if hit.isMember && (hit.isLive || chatStaysOpen) {
                HStack(spacing: 8) {
                    if let chatID = hit.chatId {
                        ActionButton(title: hit.unreadMessages > 0 ? "Chat · \(hit.unreadMessages)" : "Chat") {
                            navigate(.chat(chatID))
                        }
                    } else if hit.isLive {
                        ActionButton(title: "Invite") { showsInvite = true }
                    }
                    if hit.isLive {
                        ActionButton(title: "Add to calendar", style: .grouped) { showsCalendar = true }
                    }
                }
                if hit.isLive && hit.viewer.isHost && hit.chatId != nil && hit.spotsOpen > 0 {
                    ActionButton(title: "Invite more players", style: .grouped) { showsInvite = true }
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: CourtlyMetrics.cardRadius, style: .continuous).fill(CourtlyColor.card))
    }

    private func headline(_ hit: Hit) -> String {
        let others = hit.others(than: me).map(\.displayName)
        if hit.status == .played, !others.isEmpty {
            return "\(hit.format.title) with \(others.joined(separator: ", "))"
        }
        return hit.formatLine
    }

    private func detailsSection(_ hit: Hit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Details", top: 24)
            Card {
                VStack(spacing: 0) {
                    DetailRow(title: "Court", value: hit.court.detailLine ?? hit.court.name)
                    HairlineSeparator()
                    DetailRow(title: "Address", value: hit.court.address ?? hit.court.shortName)
                    HairlineSeparator()
                    DetailRow(title: "Who can join", value: hit.visibility.title)
                }
            }
        }
    }

    private func hostSection(_ hit: Hit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Host", top: 24)
            Card {
                Button {
                    navigate(.player(hit.host.id, hitID: hit.id))
                } label: {
                    HStack(spacing: 14) {
                        PlayerAvatar(card: hit.host, size: 48)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(hit.host.displayName)
                                .font(CourtlyFont.bodySemibold)
                                .foregroundStyle(CourtlyColor.ink)
                            Text(hostDetail(hit.host))
                                .font(CourtlyFont.secondary)
                                .foregroundStyle(CourtlyColor.secondary)
                        }
                        Spacer(minLength: 8)
                        ChevronMark()
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func hostDetail(_ host: PlayerCard) -> String {
        let played = host.hitsPlayed == 1 ? "1 hit played" : "\(host.hitsPlayed) hits played"
        return [host.level?.title, played].compactMap { $0 }.joined(separator: " · ")
    }

    /// Day-after check: one "Did X show up?" per other player.
    private func attendanceSections(_ hit: Hit) -> some View {
        ForEach(hit.others(than: me)) { player in
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Did \(player.firstName) show up?", top: 24)
                HStack(spacing: 8) {
                    ActionButton(title: "No", style: attendance[player.id] == false ? .blue : .grouped) {
                        answer(player, showedUp: false, hit: hit)
                    }
                    ActionButton(title: "Yes", style: attendance[player.id] == true ? .blue : .grouped) {
                        answer(player, showedUp: true, hit: hit)
                    }
                }
                if attendance[player.id] == true && !friendsAdded.contains(player.id) {
                    ActionButton(title: "Add \(player.firstName) as a friend", style: .grouped) {
                        addFriend(player)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func footer(_ hit: Hit) -> some View {
        if hit.isLive {
            if hit.viewer.isHost {
                DestructiveTextButton(title: "Cancel hit") { showsCancelAlert = true }
                    .padding(.top, 8)
            } else if hit.viewer.isPlayer {
                DestructiveTextButton(title: "Leave hit") { showsLeaveAlert = true }
                    .padding(.top, 8)
            } else if hit.hasPendingRequest, let request = hit.viewer.request {
                VStack(spacing: 4) {
                    Text("You asked to join. \(hit.host.firstName) will get back to you.")
                        .font(CourtlyFont.secondary)
                        .foregroundStyle(CourtlyColor.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                    DestructiveTextButton(title: "Cancel request") {
                        Task { await cancelRequest(request.id) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bottomAction(_ hit: Hit) -> some View {
        if hit.isLive && !hit.isMember && !hit.hasPendingRequest {
            Group {
                if let invite = hit.openInvite {
                    PrimaryButton(title: "I’m in", isLoading: isWorking) {
                        Task { await perform { try await hits.claimInvite(invite.id) } }
                    }
                } else {
                    PrimaryButton(title: hit.isFull ? "Full" : "Ask to join", isEnabled: !hit.isFull, isLoading: isWorking) {
                        Task { await perform { try await hits.requestToJoin(hit.id) } }
                    }
                }
            }
            .padding(.horizontal, CourtlyMetrics.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .background(CourtlyColor.groupedBackground)
        }
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
        friendsAdded.insert(player.id)
        Task { @MainActor in
            do {
                _ = try await API.People.addFriend(player.id)
            } catch {
                friendsAdded.remove(player.id)
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// "Court — Hard · Lights" style row, 50pt tall.
private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(CourtlyFont.body)
                .foregroundStyle(CourtlyColor.ink)
            Spacer(minLength: 12)
            Text(value)
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }
}

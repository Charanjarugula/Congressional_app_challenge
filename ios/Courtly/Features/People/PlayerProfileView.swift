import SwiftUI

/// Another player: who they are, what they play, their open hits, and the safety actions.
struct PlayerProfileView: View {
    let playerID: UUID
    /// The hit this player was opened from, so a report can name it.
    var hitID: UUID? = nil

    @Environment(HitsStore.self) private var hits
    @Environment(InboxStore.self) private var inbox
    @Environment(\.navigate) private var navigate
    @State private var profile: PlayerProfile?
    @State private var loadFailed = false
    @State private var isWorking = false
    @State private var showsActions = false
    @State private var showsBlockAlert = false
    @State private var showsReport = false
    @State private var showsInviteToHit = false
    @State private var showsCancelRequest = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            if let profile {
                VStack(alignment: .leading, spacing: 0) {
                    heading(profile)
                    actions(profile)
                        .padding(.top, 18)
                    SectionHeader(title: "Plays", top: 24)
                    Card {
                        VStack(spacing: 0) {
                            InfoRow(title: "What", value: profile.card.formats.isEmpty ? "Not set" : profile.card.formats.map(\.shortTitle).joined(separator: ", "))
                            HairlineSeparator()
                            InfoRow(title: "Usually free", value: AvailabilityMask(rawValue: profile.card.availabilityMask ?? 0).shortDescription)
                        }
                    }
                    if !profile.mutualCards.isEmpty {
                        SectionHeader(title: profile.mutualCards.count == 1 ? "1 mutual friend" : "\(profile.mutualCards.count) mutual friends", top: 24)
                        CardRows(items: profile.mutualCards) { friend in
                            Button {
                                navigate(.player(friend.id))
                            } label: {
                                HStack(spacing: 14) {
                                    PlayerAvatar(card: friend, size: 40)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(friend.displayName)
                                            .font(CourtlyFont.bodySemibold)
                                            .foregroundStyle(CourtlyColor.ink)
                                        Text(friend.levelAndArea)
                                            .font(CourtlyFont.caption)
                                            .foregroundStyle(CourtlyColor.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(CourtlyColor.placeholder)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !profile.openHits.isEmpty {
                        SectionHeader(title: "Open hits", top: 24)
                        CardRows(items: profile.openHits) { hit in
                            OpenHitRow(hit: hit)
                        }
                    }
                }
                .padding(.horizontal, CourtlyMetrics.screenPadding)
                .padding(.bottom, 24)
            } else if loadFailed {
                QuietCard(title: "This player isn’t available", detail: "They may have left Courtly.")
                    .padding(CourtlyMetrics.screenPadding)
            } else {
                ProgressView()
                    .padding(.top, 80)
            }
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .navigationTitle(profile?.card.firstName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if profile != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsActions = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .confirmationDialog("", isPresented: $showsActions) {
            if profile?.relationship.isFriend == true {
                Button("Remove friend") { removeFriend() }
            }
            Button("Block", role: .destructive) { showsBlockAlert = true }
            Button("Report", role: .destructive) { showsReport = true }
        }
        .confirmationDialog("Cancel your friend request?", isPresented: $showsCancelRequest, titleVisibility: .visible) {
            Button("Cancel request", role: .destructive) { cancelRequest() }
            Button("Keep it", role: .cancel) {}
        }
        .alert("Block \(profile?.card.firstName ?? "this player")?", isPresented: $showsBlockAlert) {
            Button("Block", role: .destructive) { block() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won’t see each other’s hits or messages. They aren’t told.")
        }
        .sheet(isPresented: $showsReport) {
            if let card = profile?.card {
                ReportView(player: card, hitID: hitID) { blocked in
                    showsReport = false
                    if blocked { Task { await afterBlock() } }
                }
            }
        }
        .sheet(isPresented: $showsInviteToHit) {
            if let profile {
                InviteToHitSheet(player: profile.card, dmChatID: profile.dmChatId)
            }
        }
        .task(id: playerID) { await load() }
        .errorAlert($errorMessage)
    }

    // MARK: - Sections

    private func heading(_ profile: PlayerProfile) -> some View {
        VStack(spacing: 6) {
            PlayerAvatar(card: profile.card, size: 96)
                .padding(.bottom, 6)
            Text(profile.card.displayName)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(CourtlyColor.ink)
            Text(summary(profile))
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.secondary)
                .multilineTextAlignment(.center)
            if let mutual = profile.mutualLine {
                Text(mutual)
                    .font(CourtlyFont.caption)
                    .foregroundStyle(CourtlyColor.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func summary(_ profile: PlayerProfile) -> String {
        let card = profile.card
        let played = card.hitsPlayed == 1 ? "1 hit played" : "\(card.hitsPlayed) hits played"
        var parts = [card.level?.title, card.areaLabel?.components(separatedBy: ",").first, played].compactMap { $0 }
        if profile.hitsTogether > 0 {
            parts.append(profile.hitsTogether == 1 ? "1 hit together" : "\(profile.hitsTogether) hits together")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func actions(_ profile: PlayerProfile) -> some View {
        HStack(spacing: 8) {
            switch profile.relationship {
            case .friend:
                ActionButton(title: "Invite to hit") { showsInviteToHit = true }
                ActionButton(title: "Message", style: .grouped, isEnabled: profile.dmChatId != nil) {
                    if let chatID = profile.dmChatId { navigate(.chat(chatID)) }
                }
            case .requested:
                ActionButton(title: "Requested", style: .grouped, isLoading: isWorking) { showsCancelRequest = true }
                ActionButton(title: "Message", style: .grouped, isEnabled: false) {}
            case .requestedMe:
                ActionButton(title: "Confirm", isLoading: isWorking) { respond(accept: true) }
                ActionButton(title: "Delete", style: .grouped, isLoading: isWorking) { respond(accept: false) }
            case .none, .blocked:
                ActionButton(title: "Add friend", isLoading: isWorking) { addFriend() }
                ActionButton(title: "Message", style: .grouped, isEnabled: false) {}
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        do {
            profile = try await API.People.player(playerID)
            loadFailed = false
        } catch {
            if profile == nil { loadFailed = true }
        }
    }

    private func addFriend() {
        isWorking = true
        Task { @MainActor in
            do {
                _ = try await API.People.addFriend(playerID)
                await load()
                await inbox.load()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func respond(accept: Bool) {
        isWorking = true
        Task { @MainActor in
            do {
                _ = try await API.People.respondFriendRequest(playerID, accept: accept)
                inbox.removeRequest(from: playerID)
                await load()
                await inbox.load()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func cancelRequest() {
        isWorking = true
        Task { @MainActor in
            do {
                _ = try await API.People.cancelFriendRequest(playerID)
                inbox.removeRequest(from: playerID)
                await load()
                await inbox.load()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func removeFriend() {
        Task { @MainActor in
            do {
                try await API.People.removeFriend(playerID)
                await load()
                await inbox.load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func block() {
        Task { @MainActor in
            do {
                try await API.People.block(playerID)
                await afterBlock()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// A block hides the player from chats and hits alike, so both refresh before this screen goes.
    @MainActor
    private func afterBlock() async {
        await inbox.load()
        await hits.refreshAll()
        navigate.pop()
    }
}

/// "What — Casual, Singles" style row, 50pt tall.
private struct InfoRow: View {
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
                .truncationMode(.tail)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }
}

/// One of a player's open hits, with a Join pill.
private struct OpenHitRow: View {
    let hit: Hit

    @Environment(HitsStore.self) private var hits
    @Environment(\.navigate) private var navigate
    @State private var isJoining = false
    @State private var asked = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 14) {
            Button {
                navigate(.hit(hit.id))
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(HitFormatting.day.string(from: hit.startsAt))
                        Text(HitFormatting.clock.string(from: hit.startsAt))
                    }
                    .font(CourtlyFont.rounded(17))
                    .foregroundStyle(CourtlyColor.ink)
                    .frame(width: 76, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hit.format.title)
                            .font(CourtlyFont.bodySemibold)
                            .foregroundStyle(CourtlyColor.ink)
                        Text([hit.court.shortName, hit.milesLabel].compactMap { $0 }.joined(separator: " · "))
                            .font(CourtlyFont.secondary)
                            .foregroundStyle(CourtlyColor.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if asked || hit.hasPendingRequest {
                Text("Asked")
                    .font(CourtlyFont.secondarySemibold)
                    .foregroundStyle(CourtlyColor.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(CourtlyColor.groupedBackground))
            } else {
                PillButton(title: isJoining ? "Asking…" : "Join", style: .tint) { join() }
                    .disabled(isJoining)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .errorAlert($errorMessage, title: "Couldn’t ask to join")
    }

    private func join() {
        isJoining = true
        Task { @MainActor in
            do {
                _ = try await hits.requestToJoin(hit.id)
                asked = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isJoining = false
        }
    }
}

/// Pick one of your open hits to invite this player to.
private struct InviteToHitSheet: View {
    let player: PlayerCard
    let dmChatID: UUID?

    @Environment(HitsStore.self) private var hits
    @Environment(\.dismiss) private var dismiss
    @State private var sent: Set<UUID> = []
    @State private var sending: UUID?
    @State private var errorMessage: String?

    private var openHits: [Hit] {
        (hits.myHits?.upcoming ?? []).filter { $0.viewer.isHost && $0.isLive && $0.spotsOpen > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(CourtlyColor.placeholder)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 18)
            Text("Invite \(player.firstName)")
                .font(CourtlyFont.sheetTitle)
                .tracking(-0.4)
                .foregroundStyle(CourtlyColor.ink)
            Text("Pick one of your hits with an open spot.")
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.top, 4)
            ScrollView {
                VStack(spacing: 0) {
                    if openHits.isEmpty {
                        QuietCard(title: "No open hits", detail: "Plan a hit from Play, then invite \(player.firstName) from here.")
                    } else {
                        CardRows(items: openHits) { hit in
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(HitFormatting.day.string(from: hit.startsAt))
                                    Text(HitFormatting.clock.string(from: hit.startsAt))
                                }
                                .font(CourtlyFont.rounded(17))
                                .foregroundStyle(CourtlyColor.ink)
                                .frame(width: 76, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(hit.format.shortTitle) · \(hit.spotsLabel)")
                                        .font(CourtlyFont.bodySemibold)
                                        .foregroundStyle(CourtlyColor.ink)
                                    Text(hit.court.shortName)
                                        .font(CourtlyFont.caption)
                                        .foregroundStyle(CourtlyColor.secondary)
                                }
                                Spacer(minLength: 8)
                                PillButton(
                                    title: sent.contains(hit.id) ? "Sent" : (sending == hit.id ? "Sending…" : "Send"),
                                    style: sent.contains(hit.id) ? .tint : .filled,
                                    showsCheck: sent.contains(hit.id)
                                ) {
                                    send(hit)
                                }
                                .disabled(sent.contains(hit.id) || sending != nil)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.top, 16)
            }
            TextActionButton(title: "Done") { dismiss() }
        }
        .padding(.horizontal, CourtlyMetrics.screenPadding)
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
        .errorAlert($errorMessage, title: "Couldn’t send the invite")
    }

    private func send(_ hit: Hit) {
        guard let dmChatID else {
            errorMessage = "Add \(player.firstName) as a friend first."
            return
        }
        sending = hit.id
        Task { @MainActor in
            do {
                _ = try await API.Hits.sendInvite(hitID: hit.id, chatID: dmChatID, targetUserID: player.id)
                sent.insert(hit.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            sending = nil
        }
    }
}

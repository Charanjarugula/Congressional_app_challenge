import SwiftUI

/// Another player: who they are, what they play, their open hits, and the safety actions.
struct PlayerProfileView: View {
    let playerID: UUID
    /// The hit this player was opened from, so a report can name it.
    var hitID: UUID? = nil

    @Environment(HitsStore.self) private var hits
    @Environment(InboxStore.self) private var inbox
    @Environment(AppSession.self) private var session
    @Environment(\.navigate) private var navigate
    @State private var profile: PlayerProfile?
    @State private var showsRemoveFriend = false
    @State private var loadFailed = false
    @State private var isWorking = false
    @State private var showsActions = false
    @State private var showsBlockAlert = false
    @State private var showsReport = false
    @State private var showsInviteToHit = false
    @State private var pendingRequest: PendingFriendRequest?
    @State private var showsMutuals = false
    @State private var errorMessage: String?

    init(playerID: UUID, hitID: UUID? = nil) {
        self.playerID = playerID
        self.hitID = hitID
    }

    #if DEBUG && targetEnvironment(simulator)
    init(preview: PlayerProfile) {
        playerID = preview.card.id
        _profile = State(initialValue: preview)
    }
    #endif

    var body: some View {
        ScrollView {
            if let profile {
                VStack(alignment: .leading, spacing: 0) {
                    heading(profile)
                    if !profile.openHits.isEmpty {
                        SectionHeader(title: "Open hits", top: 24)
                        VStack(spacing: 16) {
                            ForEach(profile.openHits) { hit in
                                Card(padding: 18, radius: 22) { OpenHitRow(hit: hit) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            } else if loadFailed {
                QuietCard(title: "This player isn’t available", detail: "They may have left Courtly.")
                    .padding(24)
            } else {
                ProgressView()
                    .padding(.top, 80)
            }
        }
        .background(CourtlyColor.surface.ignoresSafeArea())
        .plainBackButton()
        .navigationTitle(profile?.card.firstName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if profile != nil {
                PlainToolbarItem(placement: .topBarTrailing) {
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
                Button("Remove friend") { showsRemoveFriend = true }
            }
            Button("Block", role: .destructive) { showsBlockAlert = true }
            Button("Report", role: .destructive) { showsReport = true }
        }
        .confirmationDialog("Remove \(profile?.card.firstName ?? "this player") as a friend?", isPresented: $showsRemoveFriend, titleVisibility: .visible) {
            Button("Remove friend", role: .destructive) { removeFriend() }
            Button("Keep", role: .cancel) {}
        }
        .takeBackRequestDialog($pendingRequest) { _ in cancelRequest() }
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
        .sheet(isPresented: $showsMutuals) {
            if let profile {
                PlayersSheet(title: "Friends with \(profile.card.firstName)", players: profile.mutualCards) { id in
                    showsMutuals = false
                    navigate(.player(id))
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                PlayerAvatar(card: profile.card, size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.card.displayName)
                        .font(.system(size: 22, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(CourtlyColor.ink)
                    if let level = profile.card.level?.title {
                        Text(level)
                            .font(CourtlyFont.secondary)
                            .foregroundStyle(CourtlyColor.secondary)
                    }
                    if let area = profile.card.areaLabel {
                        Text(area).font(.footnote).foregroundStyle(CourtlyColor.secondary)
                    }
                }
                .padding(.top, 6)
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            HStack(spacing: 10) {
                statistic(profile.card.hitsPlayed, label: "hits")
                statistic(profile.friendCount, label: "friends")
                statistic(profile.hitsTogether, label: "together")
            }
            if !profile.mutualCards.isEmpty {
                Button {
                    showsMutuals = true
                } label: {
                    HStack(spacing: 10) {
                        HStack(spacing: -9) {
                            ForEach(profile.mutualCards.prefix(3)) { friend in
                                PlayerAvatar(card: friend, size: 26)
                                    .overlay(Circle().stroke(CourtlyColor.surface, lineWidth: 2))
                            }
                        }
                        Text(mutualLine(profile))
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            actions(profile)
        }
        .padding(.top, 4)
    }

    private func statistic(_ value: Int, label: String) -> some View {
        Card(padding: 14, radius: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text(value.formatted()).font(.title.bold()).foregroundStyle(CourtlyColor.blue)
                Text(label).font(.caption).foregroundStyle(CourtlyColor.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Friends with Ana, Luis + 3 more", the names in bold.
    private func mutualLine(_ profile: PlayerProfile) -> AttributedString {
        let names = profile.mutualCards.prefix(2).map(\.firstName)
        let rest = profile.mutualCards.count - names.count
        var line = AttributedString("Friends with ")
        var bold = AttributedString(names.joined(separator: ", "))
        bold.font = .system(size: 13, weight: .semibold)
        line += bold
        if rest > 0 { line += AttributedString(" + \(rest) more") }
        return line
    }

    @ViewBuilder
    private func actions(_ profile: PlayerProfile) -> some View {
        HStack(spacing: 8) {
            switch profile.relationship {
            case .friend:
                ActionButton(title: "Invite to hit", style: .lime, height: 48, radius: 16) { showsInviteToHit = true }
                ActionButton(title: "Message", style: .card, isEnabled: profile.dmChatId != nil) {
                    if let chatID = profile.dmChatId { navigate(.chat(chatID)) }
                }
            case .requested:
                ActionButton(title: "Requested", style: .card, isLoading: isWorking) {
                    pendingRequest = PendingFriendRequest(id: playerID, firstName: profile.card.firstName)
                }
                ActionButton(title: "Message", style: .card, isEnabled: false) {}
            case .requestedMe:
                ActionButton(title: "Confirm", style: .lime, isLoading: isWorking) { respond(accept: true) }
                ActionButton(title: "Delete", style: .card, isLoading: isWorking) { respond(accept: false) }
            case .none, .blocked:
                ActionButton(title: "Add friend", style: .lime, isLoading: isWorking) { addFriend() }
                ActionButton(title: "Message", style: .card, isEnabled: false) {}
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
        await session.refreshProfile()   // the Blocked players count on You
        navigate.pop()
    }
}

/// One of a player's open hits, with a Join pill.
private struct OpenHitRow: View {
    let hit: Hit

    @Environment(HitsStore.self) private var hits
    @Environment(\.navigate) private var navigate
    @State private var isJoining = false
    @State private var requestID: UUID?   // set once asked here
    @State private var cancelledHere = false   // taken back here: the hit's own copy is now stale
    @State private var errorMessage: String?

    private var pendingRequestID: UUID? {
        requestID ?? (!cancelledHere && hit.hasPendingRequest ? hit.viewer.request?.id : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { navigate(.hit(hit.id)) } label: {
                HitSummary(hit: hit, showsHost: false)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Same words and behavior as the feed: Ask to join, then Requested (tap to take it back).
            if let pending = pendingRequestID {
                PillButton(title: isJoining ? "…" : "Requested", style: .tint) { cancel(pending) }
                    .disabled(isJoining)
            } else if hit.wasDeclined {
                Text("Passed")
                    .font(CourtlyFont.secondarySemibold)
                    .foregroundStyle(CourtlyColor.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(CourtlyColor.surface))
            } else {
                PillButton(title: isJoining ? "Asking…" : "Ask to join", style: .filled) { join() }
                    .disabled(isJoining)
            }
        }
        .errorAlert($errorMessage, title: "Couldn’t ask to join")
    }

    private func join() {
        isJoining = true
        Task { @MainActor in
            do {
                let updated = try await hits.requestToJoin(hit.id)
                requestID = updated.viewer.request?.id
                cancelledHere = false
            } catch {
                errorMessage = error.localizedDescription
            }
            isJoining = false
        }
    }

    private func cancel(_ requestID: UUID) {
        isJoining = true
        Task { @MainActor in
            do {
                try await hits.cancelRequest(requestID, hitID: hit.id)
                self.requestID = nil
                cancelledHere = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isJoining = false
        }
    }
}

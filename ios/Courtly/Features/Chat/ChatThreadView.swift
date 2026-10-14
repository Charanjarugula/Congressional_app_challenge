import SwiftUI

/// One conversation: the hit pinned on top for hit chats, messages, and a composer.
/// New messages arrive over Realtime while the screen is open, with polling as the fallback.
struct ChatThreadView: View {
    let chatID: UUID

    @Environment(AppSession.self) private var session
    @Environment(InboxStore.self) private var inbox
    @Environment(\.navigate) private var navigate
    @State private var chat: Chat?
    @State private var subscription: RealtimeHub.Subscription?
    @State private var showsRequestHit = false
    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var loadFailed = false
    @State private var hasEarlier = false
    @State private var isLoadingEarlier = false
    @State private var errorMessage: String?
    @FocusState private var composerFocused: Bool

    private var me: UUID? { session.profile?.id }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        VStack(spacing: 0) {
            if let hit = chat?.hit {
                PinnedHitBar(hit: hit) { navigate(.hit(hit.id)) }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if loadFailed && messages.isEmpty {
                            QuietCard(title: "Couldn’t open this chat", detail: "Check your connection and try again.")
                        }
                        if hasEarlier {
                            Button(isLoadingEarlier ? "Loading…" : "Load earlier messages") { loadEarlier() }
                                .font(CourtlyFont.secondarySemibold)
                                .foregroundStyle(CourtlyColor.blue)
                                .disabled(isLoadingEarlier)
                                .padding(.bottom, 6)
                        }
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            if showsTimestamp(at: index) {
                                Text(HitFormatting.conversational(message.createdAt))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CourtlyColor.secondary)
                                    .padding(.top, index == 0 ? 0 : 6)
                            }
                            MessageRow(message: message, isMine: message.sender?.id == me, showsAvatar: chat?.type != .dm)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.last?.id) { _, _ in   // a page loaded above leaves the reader where they are
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            composer
        }
        .background(Color.white.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .principal) { header }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: chatID) {
            DeepLinkCenter.shared.visibleChatID = chatID
            await load()
            guard !Task.isCancelled else { return }
            if let subscription { RealtimeHub.shared.unsubscribe(subscription) }
            subscription = RealtimeHub.shared.subscribe(table: "messages", filter: "chat_id=eq.\(chatID.uuidString.lowercased())") {
                Task { await refresh() }
            }
            // Polling is the fallback: quick until this chat's channel is delivering, slow after.
            while !Task.isCancelled {
                let live = subscription.map { RealtimeHub.shared.isDelivering($0) } ?? false
                try? await Task.sleep(for: .seconds(live ? 20 : 5))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
        .onDisappear {
            if DeepLinkCenter.shared.visibleChatID == chatID { DeepLinkCenter.shared.visibleChatID = nil }
            if let subscription { RealtimeHub.shared.unsubscribe(subscription) }
            subscription = nil
            inbox.markRead(chatID)
            Task { await inbox.load() }
        }
        .sheet(isPresented: $showsRequestHit) {
            if let chat {
                PlanHitView(inviteTo: chat) { _ in
                    Task { await refresh() }
                }
            }
        }
        .errorAlert($errorMessage)
    }

    /// Hit chats already are about a hit; DMs and groups can ask for one.
    private var canRequestHit: Bool {
        guard let chat else { return false }
        return chat.type != .hit && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Pieces

    /// DMs open the other player's profile, groups open the member list, hit chats open the hit.
    private var header: some View {
        Button {
            guard let chat else { return }
            switch chat.type {
            case .dm:
                if let other = chat.others(than: me).first { navigate(.player(other.id)) }
            case .group:
                navigate(.groupInfo(chat.id))
            case .hit:
                if let hit = chat.hit { navigate(.hit(hit.id)) }
            }
        } label: {
            headerContent
        }
        .buttonStyle(.plain)
        .disabled(chat == nil)
    }

    private var headerContent: some View {
        HStack(spacing: 10) {
            if let chat {
                if chat.type == .group {
                    InitialsAvatar(initials: String(chat.title.prefix(2)).uppercased(), size: 32, style: .muted)
                } else if let other = chat.others(than: me).first {
                    PlayerAvatar(card: other, size: 32)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(chat.title)
                        .font(CourtlyFont.bodySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                        .lineLimit(1)
                    let subtitle = chat.subtitle(me: me)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("Chat")
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            HairlineSeparator()
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(CourtlyFont.body)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(CourtlyColor.separator, lineWidth: 1)
                    )
                if canRequestHit {
                    Button {
                        showsRequestHit = true
                    } label: {
                        Text("Request a hit")
                            .font(CourtlyFont.secondarySemibold)
                            .foregroundStyle(CourtlyColor.blue)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(Capsule().fill(CourtlyColor.blueTint))
                    }
                    .buttonStyle(PressableButtonStyle())
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(canSend ? CourtlyColor.blue : CourtlyColor.placeholder)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .padding(.bottom, 2)
                    .accessibilityLabel("Send")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.white)
    }

    /// A time label before the first message and whenever more than 30 minutes pass.
    private func showsTimestamp(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return messages[index].createdAt.timeIntervalSince(messages[index - 1].createdAt) > 30 * 60
    }

    // MARK: - Data

    private func load() async {
        do {
            let page = try await API.Chats.page(chatID: chatID)
            chat = page.chat
            messages = page.messages
            hasEarlier = page.messages.count >= Self.pageSize
            loadFailed = false
            try? await API.Chats.markRead(chatID)
        } catch {
            loadFailed = true
        }
    }

    private func refresh() async {
        guard let page = try? await API.Chats.page(chatID: chatID) else { return }
        chat = page.chat
        // Keep what the page doesn't have yet: messages still on their way, and ones sent moments ago
        // that a page fetched before the insert committed would otherwise wipe out.
        let newest = page.messages.last?.createdAt ?? .distantPast
        let pending = messages.filter { local in
            !page.messages.contains { $0.id == local.id || ($0.clientId != nil && $0.clientId == local.clientId) }
                && (local.clientId == local.id || local.createdAt > newest)
        }
        let earlier = messages.filter { local in
            // Pages loaded with "Load earlier" sit before the latest page.
            local.createdAt < (page.messages.first?.createdAt ?? .distantPast) && !page.messages.contains { $0.id == local.id }
        }
        let latest = earlier + page.messages + pending
        let hasNew = latest.count != messages.count || latest.last?.id != messages.last?.id
        if latest != messages {
            messages = latest   // also picks up invite cards whose spots or status changed
        }
        if hasNew {
            try? await API.Chats.markRead(chatID)
        }
    }

    private static let pageSize = 50

    private func loadEarlier() {
        guard let first = messages.first, !isLoadingEarlier else { return }
        isLoadingEarlier = true
        Task { @MainActor in
            defer { isLoadingEarlier = false }
            guard let page = try? await API.Chats.page(chatID: chatID, before: first, limit: Self.pageSize) else { return }
            let known = Set(messages.map(\.id))
            messages = page.messages.filter { !known.contains($0.id) } + messages
            hasEarlier = page.messages.count >= Self.pageSize
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        isSending = true
        let clientID = UUID()
        if let card = session.profile?.card {
            messages.append(Message(id: clientID, chatId: chatID, sender: card, type: .text, body: text, clientId: clientID, createdAt: .now, invite: nil))
        }
        Task { @MainActor in
            do {
                let sent = try await API.Chats.send(chatID: chatID, clientID: clientID, body: text)
                if let index = messages.firstIndex(where: { $0.id == clientID }) {
                    messages[index] = sent
                } else {
                    messages.append(sent)
                }
            } catch {
                messages.removeAll { $0.id == clientID }
                draft = text
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}

/// The hit a hit chat is about, pinned under the header.
private struct PinnedHitBar: View {
    let hit: Hit
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(HitFormatting.day.string(from: hit.startsAt))
                    Text(HitFormatting.clock.string(from: hit.startsAt))
                }
                .font(CourtlyFont.rounded(15))
                .foregroundStyle(CourtlyColor.ink)
                .frame(width: 62, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(hit.format.shortTitle) · \(hit.court.shortName)")
                        .font(CourtlyFont.secondarySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                        .lineLimit(1)
                    Text(hit.statusKind.title)
                        .font(CourtlyFont.captionSemibold)
                        .foregroundStyle(hit.statusKind == .confirmed ? CourtlyColor.green : CourtlyColor.secondary)
                }
                Spacer(minLength: 8)
                ChevronMark()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CourtlyColor.groupedBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

/// A text bubble, a system line, or a hit request card.
private struct MessageRow: View {
    let message: Message
    let isMine: Bool
    let showsAvatar: Bool

    var body: some View {
        switch message.type {
        case .system:
            Text(message.body)
                .font(CourtlyFont.caption)
                .foregroundStyle(CourtlyColor.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        case .hitInvite:
            HStack {
                if isMine { Spacer(minLength: 40) }
                if let invite = message.invite {
                    HitInviteCard(invite: invite)
                } else {
                    bubble
                }
                if !isMine { Spacer(minLength: 40) }
            }
        case .text:
            HStack(alignment: .bottom, spacing: 8) {
                if isMine {
                    Spacer(minLength: 60)
                } else if showsAvatar, let sender = message.sender {
                    PlayerAvatar(card: sender, size: 28)
                }
                bubble
                if !isMine { Spacer(minLength: 60) }
            }
        }
    }

    private var bubble: some View {
        Text(message.body)
            .font(CourtlyFont.body)
            .foregroundStyle(isMine ? .white : CourtlyColor.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isMine ? CourtlyColor.blue : CourtlyColor.groupedBackground)
            )
            .frame(maxWidth: 260, alignment: isMine ? .trailing : .leading)
    }
}
